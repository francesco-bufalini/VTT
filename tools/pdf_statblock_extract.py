#!/usr/bin/env python3
"""Extract text from a PDF for the VTT stat-block importer.

Preferred backends are optional and used when available:
PyMuPDF -> pypdf/PyPDF2 -> pdftotext -> Tesseract OCR -> basic PDF streams.
The script always prints one JSON object to stdout.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


def emit(payload: dict) -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    print(json.dumps(payload, ensure_ascii=False))


def enough(text: str) -> bool:
    compact = re.sub(r"\s+", "", text or "")
    return len(compact) >= 40


def extract_pymupdf(path: str) -> str:
    import fitz  # type: ignore

    document = fitz.open(path)
    parts = []
    try:
        for page in document:
            parts.append(page.get_text("text"))
    finally:
        document.close()
    return "\n".join(parts)


def extract_pypdf(path: str) -> str:
    try:
        from pypdf import PdfReader  # type: ignore
    except Exception:
        from PyPDF2 import PdfReader  # type: ignore

    reader = PdfReader(path)
    return "\n".join((page.extract_text() or "") for page in reader.pages)


def extract_pdftotext(path: str) -> str:
    executable = shutil.which("pdftotext")
    if not executable:
        return ""
    result = subprocess.run(
        [executable, "-layout", path, "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout.decode("utf-8", errors="replace")


def extract_ocr(path: str) -> str:
    pdftoppm = shutil.which("pdftoppm")
    tesseract = shutil.which("tesseract")
    if not pdftoppm or not tesseract:
        return ""

    with tempfile.TemporaryDirectory(prefix="vtt_statblock_") as folder:
        prefix = str(Path(folder) / "page")
        raster = subprocess.run(
            [pdftoppm, "-png", "-r", "180", path, prefix],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if raster.returncode != 0:
            return ""

        parts = []
        for image_path in sorted(Path(folder).glob("page-*.png")):
            result = subprocess.run(
                [tesseract, str(image_path), "stdout", "-l", "eng+ita", "--psm", "6"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode == 0:
                parts.append(result.stdout.decode("utf-8", errors="replace"))
        return "\n".join(parts)


def decode_pdf_literal(raw: bytes) -> str:
    result = bytearray()
    i = 0
    while i < len(raw):
        byte = raw[i]
        if byte != 0x5C:  # backslash
            result.append(byte)
            i += 1
            continue

        i += 1
        if i >= len(raw):
            break
        esc = raw[i]
        mapping = {
            ord("n"): 0x0A,
            ord("r"): 0x0D,
            ord("t"): 0x09,
            ord("b"): 0x08,
            ord("f"): 0x0C,
            ord("("): ord("("),
            ord(")"): ord(")"),
            ord("\\"): ord("\\"),
        }
        if esc in mapping:
            result.append(mapping[esc])
            i += 1
            continue

        if 48 <= esc <= 55:
            digits = bytes([esc])
            i += 1
            for _ in range(2):
                if i < len(raw) and 48 <= raw[i] <= 55:
                    digits += bytes([raw[i]])
                    i += 1
                else:
                    break
            try:
                result.append(int(digits, 8))
            except ValueError:
                pass
            continue

        if esc in (0x0A, 0x0D):
            i += 1
            if esc == 0x0D and i < len(raw) and raw[i] == 0x0A:
                i += 1
            continue

        result.append(esc)
        i += 1

    data = bytes(result)
    for encoding in ("utf-8", "cp1252", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("latin-1", errors="replace")


def decode_hex_pdf(raw: bytes) -> str:
    compact = re.sub(rb"\s+", b"", raw)
    if len(compact) % 2:
        compact += b"0"
    try:
        data = bytes.fromhex(compact.decode("ascii"))
    except Exception:
        return ""
    if data.startswith((b"\xfe\xff", b"\xff\xfe")):
        try:
            return data.decode("utf-16")
        except Exception:
            pass
    if data.count(b"\x00") > len(data) // 4:
        try:
            return data.decode("utf-16-be")
        except Exception:
            pass
    return data.decode("latin-1", errors="replace")


def text_from_content_stream(stream: bytes) -> str:
    pieces = []

    for block in re.findall(rb"BT(.*?)ET", stream, flags=re.S):
        # Literal-string Tj operators.
        for match in re.finditer(rb"\((?:\\.|[^\\)])*\)\s*Tj", block, flags=re.S):
            token = match.group(0)
            raw = token[1 : token.rfind(b")")]
            pieces.append(decode_pdf_literal(raw))

        # Hex-string Tj operators.
        for match in re.finditer(rb"<([0-9A-Fa-f\s]+)>\s*Tj", block):
            pieces.append(decode_hex_pdf(match.group(1)))

        # TJ arrays, preserving each text token in order.
        for match in re.finditer(rb"\[(.*?)\]\s*TJ", block, flags=re.S):
            array = match.group(1)
            for token in re.finditer(
                rb"\((?:\\.|[^\\)])*\)|<([0-9A-Fa-f\s]+)>",
                array,
                flags=re.S,
            ):
                raw_token = token.group(0)
                if raw_token.startswith(b"("):
                    pieces.append(decode_pdf_literal(raw_token[1:-1]))
                else:
                    pieces.append(decode_hex_pdf(raw_token[1:-1]))

        pieces.append("\n")

    text = " ".join(piece for piece in pieces if piece)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s*\n\s*", "\n", text)
    return text


def extract_basic(path: str) -> str:
    data = Path(path).read_bytes()
    parts = []

    for match in re.finditer(rb"stream\r?\n(.*?)\r?\nendstream", data, flags=re.S):
        stream = match.group(1)
        dictionary_start = data.rfind(b"<<", max(0, match.start() - 2048), match.start())
        dictionary = (
            data[dictionary_start : match.start()]
            if dictionary_start >= 0
            else b""
        )
        decoded = stream
        if b"/FlateDecode" in dictionary:
            try:
                decoded = zlib.decompress(stream)
            except Exception:
                continue
        if b"BT" not in decoded or b"ET" not in decoded:
            continue
        text = text_from_content_stream(decoded)
        if text.strip():
            parts.append(text)

    return "\n".join(parts)


def main() -> int:
    if len(sys.argv) != 2:
        emit({"ok": False, "message": "Uso: pdf_statblock_extract.py <file.pdf>"})
        return 2

    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path):
        emit({"ok": False, "message": "PDF non trovato."})
        return 2

    methods = [
        ("PyMuPDF", extract_pymupdf),
        ("pypdf", extract_pypdf),
        ("pdftotext", extract_pdftotext),
        ("OCR Tesseract", extract_ocr),
        ("PDF basic", extract_basic),
    ]
    errors = []

    for name, extractor in methods:
        try:
            text = extractor(path)
        except Exception as exc:
            errors.append(f"{name}: {exc}")
            continue

        if enough(text):
            emit(
                {
                    "ok": True,
                    "text": text,
                    "method": name,
                    "warning": (
                        ""
                        if name != "PDF basic"
                        else "Estrazione PDF di compatibilità: controlla la scheda importata."
                    ),
                }
            )
            return 0

    message = (
        "Il PDF non contiene testo estraibile. "
        "Per PDF scannerizzati installa Tesseract e Poppler, "
        "oppure usa un PDF con testo selezionabile."
    )
    if errors:
        message += " Dettagli: " + " | ".join(errors[:3])
    emit({"ok": False, "message": message})
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
