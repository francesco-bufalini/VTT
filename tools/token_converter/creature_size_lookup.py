#!/usr/bin/env python3
"""Shared 5eTools creature-size lookup helpers for token conversion."""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path
from typing import Any

SIZE_CODE_TO_NAME = {
    "T": "Tiny",
    "S": "Small",
    "M": "Medium",
    "L": "Large",
    "H": "Huge",
    "G": "Gargantuan",
}
SIZE_TO_FOOTPRINT = {
    "Tiny": 0.5,
    "Small": 1.0,
    "Medium": 1.0,
    "Large": 2.0,
    "Huge": 3.0,
    "Gargantuan": 4.0,
}

# 2014-era sources are deliberately preferred over the revised Monster Manual.
DEFAULT_SOURCE_PRIORITY = [
    "MM", "VGM", "MTF", "MPMM", "ToA", "CoS", "SKT", "WDH", "WDMM",
    "BGDIA", "IDRotF", "WBtW", "FTD", "BAM", "PaBTSO", "XMM",
]
MODEL_SUFFIXES = {
    "updated", "update", "final", "posed", "pose", "rigged", "merged",
    "complete", "completed", "assembled", "sculpted", "supported",
    "presupported", "pre", "supported",
}


def normalize_creature_name(value: str) -> str:
    text = unicodedata.normalize("NFKD", value or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"\.\d+$", "", text.strip())
    text = re.sub(r"[\[\(].*?[\]\)]", " ", text)
    text = text.replace("_", " ").replace("-", " ")
    text = re.sub(r"[^a-zA-Z0-9' ]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip().lower()
    return text


def controlled_name_variants(value: str) -> list[str]:
    base = normalize_creature_name(value)
    if not base:
        return []
    out = [base]
    parts = base.split()
    while parts and parts[-1] in MODEL_SUFFIXES:
        parts = parts[:-1]
        candidate = " ".join(parts)
        if candidate and candidate not in out:
            out.append(candidate)
    return out


def _source_rank(source: str, preferred_sources: list[str]) -> int:
    try:
        return preferred_sources.index(source)
    except ValueError:
        return len(preferred_sources) + 100


def _edition_rank(edition: str) -> int:
    return 0 if edition == "2014" else (1 if edition == "unknown" else 2)


def _record_sort_key(record: dict[str, Any], preferred_sources: list[str]) -> tuple:
    return (
        _edition_rank(str(record.get("edition", "unknown"))),
        _source_rank(str(record.get("source", "")), preferred_sources),
        str(record.get("source", "")),
        str(record.get("name", "")),
    )


def load_creature_index(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    records = data.get("creatures", []) if isinstance(data, dict) else []
    return [r for r in records if isinstance(r, dict)]


def lookup_5etools_size(
    creature_name: str,
    records: list[dict[str, Any]],
    *,
    aliases: dict[str, str] | None = None,
    preferred_sources: list[str] | None = None,
) -> dict[str, Any] | None:
    preferred_sources = preferred_sources or DEFAULT_SOURCE_PRIORITY
    aliases = aliases or {}

    by_name: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        normalized = normalize_creature_name(str(record.get("name", "")))
        if normalized:
            by_name.setdefault(normalized, []).append(record)

    variants = controlled_name_variants(creature_name)
    alias_target = aliases.get(normalize_creature_name(creature_name))
    if alias_target:
        variants.insert(0, normalize_creature_name(alias_target))

    match_kind = "exact_normalized"
    matched_key = None
    candidates: list[dict[str, Any]] = []
    for idx, variant in enumerate(variants):
        if variant in by_name:
            matched_key = variant
            candidates = by_name[variant]
            match_kind = "exact_normalized" if idx == 0 else "controlled_suffix"
            break

    if not candidates:
        return None

    ranked = sorted(candidates, key=lambda r: _record_sort_key(r, preferred_sources))
    best = ranked[0]
    best_key = _record_sort_key(best, preferred_sources)

    # Never guess when equally preferred variants disagree on size.
    tied = [r for r in ranked if _record_sort_key(r, preferred_sources)[:2] == best_key[:2]]
    tied_sizes = {str(r.get("size_name", "")) for r in tied}
    if len(tied_sizes) > 1:
        return {
            "ambiguous": True,
            "query": creature_name,
            "match_key": matched_key,
            "candidates": tied,
        }

    return {
        "ambiguous": False,
        "query": creature_name,
        "match_kind": match_kind,
        "match_key": matched_key,
        "name": best.get("name", ""),
        "size_name": best.get("size_name", ""),
        "footprint": float(best.get("footprint", 1.0)),
        "source": best.get("source", ""),
        "edition": best.get("edition", "unknown"),
    }
