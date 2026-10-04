#!/usr/bin/env python3
"""Extract text from a PDF for the VTT stat-block importer.

The importer prefers normal PDF libraries when they are installed, but it also
contains a dependency-free extractor for browser-generated/Tetra-Cube stat
blocks. The native extractor reads embedded ToUnicode CMaps, so custom subset
fonts do not turn into mojibake when PyMuPDF/pypdf are unavailable.
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


def _pdf_objects(data: bytes) -> dict[int, bytes]:
    starts = list(
        re.finditer(rb"(?m)^(\d+)\s+(\d+)\s+obj\b", data)
    )
    result: dict[int, bytes] = {}
    for index, match in enumerate(starts):
        object_number = int(match.group(1))
        end = (
            starts[index + 1].start()
            if index + 1 < len(starts)
            else len(data)
        )
        chunk = data[match.end() : end]
        marker = chunk.rfind(b"endobj")
        if marker >= 0:
            chunk = chunk[:marker]
        result[object_number] = chunk
    return result


def _object_stream(obj: bytes) -> bytes:
    stream_match = re.search(rb"\bstream\r?\n", obj)
    if not stream_match:
        return b""

    start = stream_match.end()
    header = obj[: stream_match.start()]
    length_match = re.search(rb"/Length\s+(\d+)\b", header)

    if length_match:
        length = int(length_match.group(1))
        raw = obj[start : start + length]
    else:
        end = obj.find(b"endstream", start)
        if end < 0:
            return b""
        raw = obj[start:end].rstrip(b"\r\n")

    if b"/FlateDecode" in header:
        try:
            return zlib.decompress(raw)
        except Exception:
            return b""
    return raw


def _decode_utf16_hex(raw_hex: bytes) -> str:
    try:
        raw = bytes.fromhex(raw_hex.decode("ascii"))
    except Exception:
        return ""
    try:
        return raw.decode("utf-16-be")
    except Exception:
        return raw.decode("latin-1", errors="replace")


def _parse_tounicode(stream: bytes) -> dict[bytes, str]:
    mapping: dict[bytes, str] = {}

    for section in re.finditer(
        rb"beginbfchar(.*?)endbfchar",
        stream,
        flags=re.S,
    ):
        for source, target in re.findall(
            rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>",
            section.group(1),
        ):
            try:
                key = bytes.fromhex(source.decode("ascii"))
            except Exception:
                continue
            mapping[key] = _decode_utf16_hex(target)

    for section in re.finditer(
        rb"beginbfrange(.*?)endbfrange",
        stream,
        flags=re.S,
    ):
        body = section.group(1)

        for source_start, source_end, target_start in re.findall(
            rb"<([0-9A-Fa-f]+)>\s*"
            rb"<([0-9A-Fa-f]+)>\s*"
            rb"<([0-9A-Fa-f]+)>",
            body,
        ):
            start = int(source_start, 16)
            end = int(source_end, 16)
            target = int(target_start, 16)
            source_width = len(bytes.fromhex(source_start.decode("ascii")))
            target_width = len(bytes.fromhex(target_start.decode("ascii")))
            for offset, code in enumerate(range(start, end + 1)):
                key = code.to_bytes(source_width, "big")
                target_bytes = (target + offset).to_bytes(
                    target_width,
                    "big",
                )
                try:
                    mapping[key] = target_bytes.decode("utf-16-be")
                except Exception:
                    mapping[key] = target_bytes.decode(
                        "latin-1",
                        errors="replace",
                    )

        for source_start, source_end, target_array in re.findall(
            rb"<([0-9A-Fa-f]+)>\s*"
            rb"<([0-9A-Fa-f]+)>\s*"
            rb"\[(.*?)\]",
            body,
            flags=re.S,
        ):
            start = int(source_start, 16)
            end = int(source_end, 16)
            source_width = len(bytes.fromhex(source_start.decode("ascii")))
            targets = re.findall(
                rb"<([0-9A-Fa-f]+)>",
                target_array,
            )
            for offset, code in enumerate(range(start, end + 1)):
                if offset >= len(targets):
                    break
                key = code.to_bytes(source_width, "big")
                mapping[key] = _decode_utf16_hex(targets[offset])

    return mapping


def _decode_pdf_literal_bytes(raw: bytes) -> bytes:
    result = bytearray()
    index = 0
    while index < len(raw):
        value = raw[index]
        if value != 0x5C:
            result.append(value)
            index += 1
            continue

        index += 1
        if index >= len(raw):
            break

        escaped = raw[index]
        replacements = {
            ord("n"): 0x0A,
            ord("r"): 0x0D,
            ord("t"): 0x09,
            ord("b"): 0x08,
            ord("f"): 0x0C,
            ord("("): ord("("),
            ord(")"): ord(")"),
            ord("\\"): ord("\\"),
        }
        if escaped in replacements:
            result.append(replacements[escaped])
            index += 1
            continue

        if 48 <= escaped <= 55:
            digits = bytes([escaped])
            index += 1
            for _ in range(2):
                if index < len(raw) and 48 <= raw[index] <= 55:
                    digits += bytes([raw[index]])
                    index += 1
                else:
                    break
            try:
                result.append(int(digits, 8))
            except ValueError:
                pass
            continue

        if escaped in (0x0A, 0x0D):
            index += 1
            if (
                escaped == 0x0D
                and index < len(raw)
                and raw[index] == 0x0A
            ):
                index += 1
            continue

        result.append(escaped)
        index += 1

    return bytes(result)


def decode_pdf_literal(raw: bytes) -> str:
    data = _decode_pdf_literal_bytes(raw)
    for encoding in ("utf-8", "cp1252", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("latin-1", errors="replace")


def _decode_font_bytes(
    raw: bytes,
    cmap: dict[bytes, str],
) -> str:
    if not raw:
        return ""

    if not cmap:
        if len(raw) % 2 == 0 and raw.count(b"\x00") > len(raw) // 4:
            try:
                return raw.decode("utf-16-be")
            except Exception:
                pass
        return raw.decode("latin-1", errors="replace")

    widths = sorted({len(key) for key in cmap}, reverse=True)
    result: list[str] = []
    index = 0

    while index < len(raw):
        matched = False
        for width in widths:
            key = raw[index : index + width]
            if len(key) == width and key in cmap:
                result.append(cmap[key])
                index += width
                matched = True
                break
        if matched:
            continue

        # Identity-H fonts in Chromium PDFs normally use two-byte codes.
        if 2 in widths and index + 2 <= len(raw):
            index += 2
        else:
            result.append(chr(raw[index]))
            index += 1

    return "".join(result)


_TEXT_TOKEN = re.compile(
    rb"/([A-Za-z0-9]+)\s+[-+]?\d*\.?\d+\s+Tf"
    rb"|/ActualText\s*\(((?:\\.|[^\\)])*)\)\s*>>?\s*BDC"
    rb"|\bEMC\b"
    rb"|<([0-9A-Fa-f]+)>\s*Tj"
    rb"|\(((?:\\.|[^\\)])*)\)\s*Tj"
    rb"|\[(.*?)\]\s*TJ",
    flags=re.S,
)


def _decode_text_block(
    block: bytes,
    current_font: str,
    fonts: dict[str, dict[bytes, str]],
) -> tuple[str, str]:
    parts: list[str] = []
    actual_text_stack: list[str | None] = []

    def append_text(raw: bytes) -> None:
        nonlocal actual_text_stack
        if actual_text_stack:
            if actual_text_stack[-1] is not None:
                parts.append(actual_text_stack[-1] or "")
                actual_text_stack[-1] = None
            return
        parts.append(
            _decode_font_bytes(raw, fonts.get(current_font, {}))
        )

    for token in _TEXT_TOKEN.finditer(block):
        if token.group(1) is not None:
            current_font = token.group(1).decode(
                "ascii",
                errors="ignore",
            )
            continue

        if token.group(2) is not None:
            actual_text_stack.append(
                decode_pdf_literal(token.group(2))
            )
            continue

        if token.group(0) == b"EMC":
            if actual_text_stack:
                actual_text_stack.pop()
            continue

        if token.group(3) is not None:
            try:
                append_text(
                    bytes.fromhex(token.group(3).decode("ascii"))
                )
            except Exception:
                pass
            continue

        if token.group(4) is not None:
            append_text(_decode_pdf_literal_bytes(token.group(4)))
            continue

        if token.group(5) is not None:
            for item in re.finditer(
                rb"<([0-9A-Fa-f]+)>"
                rb"|\(((?:\\.|[^\\)])*)\)",
                token.group(5),
                flags=re.S,
            ):
                if item.group(1) is not None:
                    try:
                        append_text(
                            bytes.fromhex(
                                item.group(1).decode("ascii")
                            )
                        )
                    except Exception:
                        pass
                elif item.group(2) is not None:
                    append_text(
                        _decode_pdf_literal_bytes(item.group(2))
                    )

    return "".join(parts).strip(), current_font


def _page_font_maps(
    page: bytes,
    objects: dict[int, bytes],
    font_cmaps: dict[int, dict[bytes, str]],
) -> dict[str, dict[bytes, str]]:
    result: dict[str, dict[bytes, str]] = {}
    font_dictionary = re.search(
        rb"/Font\s*<<(.*?)>>",
        page,
        flags=re.S,
    )
    if not font_dictionary:
        return result

    for name, object_number in re.findall(
        rb"/([A-Za-z0-9]+)\s+(\d+)\s+\d+\s+R",
        font_dictionary.group(1),
    ):
        result[name.decode("ascii", errors="ignore")] = font_cmaps.get(
            int(object_number),
            {},
        )
    return result


def _page_content_refs(page: bytes) -> list[int]:
    single = re.search(
        rb"/Contents\s+(\d+)\s+\d+\s+R",
        page,
    )
    if single:
        return [int(single.group(1))]

    array = re.search(
        rb"/Contents\s*\[(.*?)\]",
        page,
        flags=re.S,
    )
    if not array:
        return []
    return [
        int(value)
        for value in re.findall(
            rb"(\d+)\s+\d+\s+R",
            array.group(1),
        )
    ]


def _merge_same_visual_line(previous: str, current: str) -> str:
    if not previous:
        return current
    if not current:
        return previous

    # Tetra-Cube headings use a decorative initial in a separate text
    # object: "A" + "ctions", "L" + "egendary" etc.
    previous_word = previous.rsplit(" ", 1)[-1]
    if (
        current[0] in ",.;:!?)]}"
        or (
            len(previous_word) == 1
            and previous_word.isupper()
            and current[0].islower()
        )
    ):
        return previous + current
    return previous + " " + current


def _clean_browser_footer(lines: list[str]) -> list[str]:
    result: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if re.match(
            r"^\d{1,2}/\d{1,2}/\d{2,4},\s*\d{1,2}:\d{2}\b",
            stripped,
        ):
            continue
        if stripped.lower().startswith("about:blank"):
            continue
        if re.fullmatch(r"\d+\s*/\s*\d+", stripped):
            continue
        result.append(stripped)
    return result


def extract_browser_pdf_native(path: str) -> str:
    """Dependency-free extraction for Chromium/Tetra-Cube PDFs.

    The stream order in these PDFs is already semantic column order. We keep
    that order and only merge immediately adjacent text objects that share the
    same visual Y coordinate. Sorting the whole page by Y would incorrectly
    interleave the two stat-block columns.
    """

    data = Path(path).read_bytes()
    objects = _pdf_objects(data)
    if not objects:
        return ""

    font_cmaps: dict[int, dict[bytes, str]] = {}
    for object_number, obj in objects.items():
        if b"/Type /Font" not in obj or b"/ToUnicode" not in obj:
            continue
        unicode_ref = re.search(
            rb"/ToUnicode\s+(\d+)\s+\d+\s+R",
            obj,
        )
        if not unicode_ref:
            continue
        cmap_object = objects.get(int(unicode_ref.group(1)), b"")
        font_cmaps[object_number] = _parse_tounicode(
            _object_stream(cmap_object)
        )

    pages = [
        obj
        for obj in objects.values()
        if re.search(rb"/Type\s*/Page\b", obj)
    ]
    all_lines: list[str] = []

    for page in pages:
        fonts = _page_font_maps(page, objects, font_cmaps)
        page_items: list[tuple[float, float, str]] = []
        current_font = ""

        for content_ref in _page_content_refs(page):
            content = _object_stream(
                objects.get(content_ref, b"")
            )
            if not content:
                continue

            for order, match in enumerate(
                re.finditer(
                    rb"BT(.*?)ET",
                    content,
                    flags=re.S,
                )
            ):
                block = match.group(1)
                text, current_font = _decode_text_block(
                    block,
                    current_font,
                    fonts,
                )
                if not text:
                    continue

                matrix = re.search(
                    rb"([-+]?\d*\.?\d+)\s+"
                    rb"([-+]?\d*\.?\d+)\s+"
                    rb"([-+]?\d*\.?\d+)\s+"
                    rb"([-+]?\d*\.?\d+)\s+"
                    rb"([-+]?\d*\.?\d+)\s+"
                    rb"([-+]?\d*\.?\d+)\s+Tm",
                    block,
                )
                if matrix:
                    x = float(matrix.group(5))
                    y = float(matrix.group(6))
                else:
                    x = 0.0
                    y = float(order) * 1000.0

                page_items.append((x, y, text))

        page_lines: list[str] = []
        previous_y: float | None = None

        for _x, y, text in page_items:
            if (
                page_lines
                and previous_y is not None
                and abs(y - previous_y) <= 0.75
            ):
                page_lines[-1] = _merge_same_visual_line(
                    page_lines[-1],
                    text,
                )
            else:
                page_lines.append(text)
            previous_y = y

        all_lines.extend(_clean_browser_footer(page_lines))

    text = "\n".join(all_lines)
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


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
                [
                    tesseract,
                    str(image_path),
                    "stdout",
                    "-l",
                    "eng+ita",
                    "--psm",
                    "6",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode == 0:
                parts.append(
                    result.stdout.decode(
                        "utf-8",
                        errors="replace",
                    )
                )
        return "\n".join(parts)


def extract_basic(path: str) -> str:
    """Last-resort literal stream extraction.

    This is intentionally after the ToUnicode-aware native extractor. It is
    only useful for very simple PDFs whose font bytes are already Unicode.
    """

    data = Path(path).read_bytes()
    objects = _pdf_objects(data)
    parts: list[str] = []

    for obj in objects.values():
        decoded = _object_stream(obj)
        if b"BT" not in decoded or b"ET" not in decoded:
            continue
        for block in re.findall(
            rb"BT(.*?)ET",
            decoded,
            flags=re.S,
        ):
            block_parts: list[str] = []
            for match in re.finditer(
                rb"\((?:\\.|[^\\)])*\)\s*Tj",
                block,
                flags=re.S,
            ):
                token = match.group(0)
                raw = token[1 : token.rfind(b")")]
                block_parts.append(decode_pdf_literal(raw))
            if block_parts:
                parts.append("".join(block_parts))

    return "\n".join(parts)


def main() -> int:
    if len(sys.argv) != 2:
        emit(
            {
                "ok": False,
                "message": "Uso: pdf_statblock_extract.py <file.pdf>",
            }
        )
        return 2

    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path):
        emit({"ok": False, "message": "PDF non trovato."})
        return 2

    methods = [
        ("PyMuPDF", extract_pymupdf),
        ("pypdf", extract_pypdf),
        ("pdftotext", extract_pdftotext),
        ("PDF Tetra-Cube/Browser", extract_browser_pdf_native),
        ("OCR Tesseract", extract_ocr),
        ("PDF basic", extract_basic),
    ]
    errors: list[str] = []

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
                        else (
                            "Estrazione PDF di compatibilità: "
                            "controlla la scheda importata."
                        )
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
