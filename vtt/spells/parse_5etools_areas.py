#!/usr/bin/env python3
"""
Deterministic 5e.tools area-geometry parser.

Usage:
    python vtt/spells/parse_5etools_areas.py <path-to-data/spells>
    python vtt/spells/parse_5etools_areas.py <normalized-candidates.json>

The parser:
- only reacts to spells that have geometry-relevant areaTags;
- ignores ST/MT target tags and W (walls) for now;
- finds a sentence containing the word associated with the tag;
- extracts regular dimensional phrases with regexes;
- writes a deterministic supplemental catalog to
  assets/spell_area_geometry.json by default.

No neural/LLM component is used.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterable


OUTPUT_DEFAULT = Path("assets/spell_area_geometry.json")

# Walls are deliberately excluded for now.
GEOMETRY_TAGS = {
    "E": ("emanation",),
    "S": ("sphere", "emanation", "aura", "radius"),
    "L": ("line",),
    "Q": ("square", "squares"),
    "N": ("cone",),
    "C": ("cube", "cubes"),
    "Y": ("cylinder",),
    "R": ("circle", "radius"),
    "H": ("hemisphere", "dome"),
}
IGNORED_AREA_TAGS = {"ST", "MT", "W"}

TAG_RE = re.compile(r"\{@([^\s{}]+)\s+([^{}]+)\}")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n+")


def _number(value: str | float) -> int | float:
    parsed = float(value)
    return int(parsed) if parsed.is_integer() else parsed


def _strip_5etools_tags(text: str) -> str:
    current = text
    for _ in range(6):
        previous = current

        def replace(match: re.Match[str]) -> str:
            payload = match.group(2)
            parts = [part.strip() for part in payload.split("|")]
            if len(parts) >= 3 and parts[2] and not parts[2].isdigit():
                return parts[2]
            return parts[0] if parts else ""

        current = TAG_RE.sub(replace, current)
        if current == previous:
            break
    return re.sub(r"\s+", " ", current).strip()


def _flatten_entries(value: Any) -> list[str]:
    result: list[str] = []
    if isinstance(value, str):
        result.append(value)
    elif isinstance(value, list):
        for item in value:
            result.extend(_flatten_entries(item))
    elif isinstance(value, dict):
        # Geometry descriptions live in prose/list entries. Avoid flattening
        # metadata such as source/type fields, which can create false matches.
        for key in ("entry", "entries", "items", "rows"):
            if key in value:
                result.extend(_flatten_entries(value[key]))
    return result


def _spell_text(spell: dict[str, Any]) -> str:
    normalized = spell.get("text")
    if isinstance(normalized, str):
        return normalized

    parts: list[str] = []
    parts.extend(_flatten_entries(spell.get("entries", [])))
    parts.extend(_flatten_entries(spell.get("entriesHigherLevel", [])))
    return "\n".join(parts)


def _sentences(text: str) -> list[str]:
    cleaned = _strip_5etools_tags(text)
    return [
        sentence.strip()
        for sentence in SENTENCE_SPLIT_RE.split(cleaned)
        if sentence.strip()
    ]


def _contains_other_shape(text: str, allowed: set[str]) -> bool:
    shape_words = {
        "sphere",
        "emanation",
        "aura",
        "line",
        "square",
        "cube",
        "cone",
        "cylinder",
        "circle",
        "hemisphere",
        "dome",
        "wall",
    }
    return any(
        re.search(rf"\b{re.escape(word)}s?\b", text)
        for word in shape_words - allowed
    )


def _parse_sphere(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")

    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot-radius\b[^.]{0,100}?\bsphere\b",
        text,
    )
    if match:
        return {"shape": "sphere", "radius_feet": _number(match.group(1))}

    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot-diameter\b[^.]{0,100}?\bsphere\b",
        text,
    )
    if match:
        diameter = float(match.group(1))
        return {
            "shape": "sphere",
            "diameter_feet": _number(diameter),
            "radius_feet": _number(diameter / 2.0),
        }

    match = re.search(
        r"\bsphere\b[^.]{0,140}?\bradius\s+of\s+(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\b",
        text,
    )
    if match:
        return {"shape": "sphere", "radius_feet": _number(match.group(1))}

    match = re.search(
        r"\bsphere\b[^.]{0,140}?\bwith\s+(?:a\s+)?"
        r"(\d+(?:\.\d+)?)\s*-\s*foot\s+radius\b",
        text,
    )
    if match:
        return {"shape": "sphere", "radius_feet": _number(match.group(1))}

    # 2024 data frequently has areaTags=["S"] while the rules text explicitly
    # calls the volume an Emanation. Trust the textual geometry.
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,45}?\bemanation\b",
        text,
    )
    if match:
        return {
            "shape": "emanation",
            "radius_feet": _number(match.group(1)),
        }

    match = re.search(
        r"\baura\b[^.]{0,100}?\b(?:with|in)\s+(?:a\s+)?"
        r"(\d+(?:\.\d+)?)\s*-?\s*foot\s+radius\b",
        text,
    )
    if match:
        return {"shape": "sphere", "radius_feet": _number(match.group(1))}

    # Older text often describes an S-tagged effect only as "a 30-foot
    # radius around you." Do not use this fallback when the same sentence
    # clearly describes another geometric primitive such as a cylinder.
    if not _contains_other_shape(
        text,
        {"sphere", "emanation", "aura", "circle"},
    ):
        match = re.search(
            r"(\d+(?:\.\d+)?)\s*-\s*foot\s+radius\b",
            text,
        )
        if match:
            return {"shape": "sphere", "radius_feet": _number(match.group(1))}

        match = re.search(
            r"\bwithin\s+(\d+(?:\.\d+)?)\s+feet\s+of\b",
            text,
        )
        if match:
            return {"shape": "sphere", "radius_feet": _number(match.group(1))}

    return None


def _parse_emanation(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,45}?\bemanation\b",
        text,
    )
    if match:
        return {
            "shape": "emanation",
            "radius_feet": _number(match.group(1)),
        }
    return None


def _parse_cone(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,45}?\bcone\b",
        text,
    )
    if match:
        return {"shape": "cone", "length_feet": _number(match.group(1))}
    match = re.search(
        r"\bcone\b[^.]{0,90}?(\d+(?:\.\d+)?)\s+feet\b",
        text,
    )
    if match:
        return {"shape": "cone", "length_feet": _number(match.group(1))}
    return None


def _parse_cube(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")

    matches = re.findall(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,24}?\bcubes?\b",
        text,
    )
    if matches:
        distinct = sorted({_number(value) for value in matches}, key=float)
        if len(distinct) == 1:
            return {"shape": "cube", "side_feet": distinct[0]}
        return {
            "shape": "cube",
            "variants": [{"side_feet": value} for value in distinct],
        }

    side_matches = re.findall(
        r"(?:cube|cage|box)\b[^.]{0,120}?(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\s+on\s+(?:each|a)\s+side\b",
        text,
    )
    if side_matches:
        distinct = sorted({_number(value) for value in side_matches}, key=float)
        if len(distinct) == 1:
            return {"shape": "cube", "side_feet": distinct[0]}
        return {
            "shape": "cube",
            "variants": [{"side_feet": value} for value in distinct],
        }

    match = re.search(
        r"\bcube\b[^.]{0,100}?(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\s+on\s+(?:each|a)\s+side\b",
        text,
    )
    if match:
        return {"shape": "cube", "side_feet": _number(match.group(1))}
    return None


def _parse_square(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,30}?\bsquares?\b",
        text,
    )
    if match:
        return {"shape": "square", "side_feet": _number(match.group(1))}
    match = re.search(
        r"(\d+(?:\.\d+)?)\s+feet\s+square\b",
        text,
    )
    if match:
        return {"shape": "square", "side_feet": _number(match.group(1))}
    return None


def _parse_line(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    length = None
    width = None

    match = re.search(r"(\d+(?:\.\d+)?)\s*-\s*foot-long\b", text)
    if match:
        length = _number(match.group(1))
    match = re.search(r"(\d+(?:\.\d+)?)\s*-\s*foot-wide\b", text)
    if match:
        width = _number(match.group(1))

    if length is None:
        match = re.search(
            r"\bline\b[^.]{0,120}?(\d+(?:\.\d+)?)\s+feet\s+long\b",
            text,
        )
        if match:
            length = _number(match.group(1))
    if width is None:
        match = re.search(
            r"\bline\b[^.]{0,180}?(\d+(?:\.\d+)?)\s+feet\s+wide\b",
            text,
        )
        if match:
            width = _number(match.group(1))

    pair = re.search(
        r"(\d+(?:\.\d+)?)\s+feet\s+long\b[^.]{0,80}?"
        r"(\d+(?:\.\d+)?)\s+feet\s+wide\b",
        text,
    )
    if pair:
        length = _number(pair.group(1))
        width = _number(pair.group(2))

    if length is None and width is None:
        return None

    result: dict[str, Any] = {"shape": "line"}
    if length is not None:
        result["length_feet"] = length
    if width is not None:
        result["width_feet"] = width
    return result


def _parse_cylinder(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    radius = None
    height = None

    match = re.search(r"(\d+(?:\.\d+)?)\s*-\s*foot-radius\b", text)
    if match:
        radius = _number(match.group(1))
    match = re.search(r"(\d+(?:\.\d+)?)\s*-\s*foot-high\b", text)
    if match:
        height = _number(match.group(1))

    if height is None:
        match = re.search(
            r"\bcylinder\b[^.]{0,150}?(\d+(?:\.\d+)?)\s+feet\s+tall\b",
            text,
        )
        if match:
            height = _number(match.group(1))
    if radius is None:
        match = re.search(
            r"\bcylinder\b[^.]{0,180}?(\d+(?:\.\d+)?)"
            r"\s*-\s*foot\s+radius\b",
            text,
        )
        if match:
            radius = _number(match.group(1))
    if radius is None:
        match = re.search(
            r"\bcylinder\b[^.]{0,180}?\bradius\s+of\s+"
            r"(\d+(?:\.\d+)?)\s+feet\b",
            text,
        )
        if match:
            radius = _number(match.group(1))

    if radius is None and height is None:
        return None

    result: dict[str, Any] = {"shape": "cylinder"}
    if radius is not None:
        result["radius_feet"] = radius
    if height is not None:
        result["height_feet"] = height
    return result


def _parse_circle(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot-radius\b[^.]{0,90}?\bcircle\b",
        text,
    )
    if match:
        return {"shape": "circle", "radius_feet": _number(match.group(1))}
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\s+radius\b",
        text,
    )
    if match:
        return {"shape": "circle", "radius_feet": _number(match.group(1))}
    match = re.search(
        r"(\d+(?:\.\d+)?)\s+feet\s+in\s+radius\b",
        text,
    )
    if match:
        return {"shape": "circle", "radius_feet": _number(match.group(1))}
    return None


def _parse_hemisphere(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot-radius\b"
        r"[^.]{0,80}?\b(?:hemisphere|dome)\b",
        text,
    )
    if match:
        return {
            "shape": "hemisphere",
            "radius_feet": _number(match.group(1)),
        }
    match = re.search(
        r"\b(?:hemisphere|dome)\b[^.]{0,120}?\bradius\s+"
        r"(?:of\s+)?(?:up\s+to\s+)?(\d+(?:\.\d+)?)\s+feet\b",
        text,
    )
    if match:
        return {
            "shape": "hemisphere",
            "radius_feet": _number(match.group(1)),
        }
    return None


PARSERS = {
    "E": _parse_emanation,
    "S": _parse_sphere,
    "L": _parse_line,
    "Q": _parse_square,
    "N": _parse_cone,
    "C": _parse_cube,
    "Y": _parse_cylinder,
    "R": _parse_circle,
    "H": _parse_hemisphere,
}


def _parse_tag(
    tag: str,
    sentences: Iterable[str],
) -> dict[str, Any] | None:
    keywords = GEOMETRY_TAGS[tag]
    parser = PARSERS[tag]

    for sentence in sentences:
        lowered = sentence.lower()
        if not any(
            re.search(rf"\b{re.escape(keyword)}s?\b", lowered)
            for keyword in keywords
        ):
            continue

        geometry = parser(sentence)
        if geometry is not None:
            geometry["area_tag"] = tag
            geometry["dimension_source"] = "text"
            return geometry
    return None


def _extract_spell_geometry(
    spell: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[str]]:
    area_tags = spell.get("areaTags", [])
    if not isinstance(area_tags, list):
        return [], []

    text = _spell_text(spell)
    sentences = _sentences(text)
    geometries: list[dict[str, Any]] = []
    unresolved: list[str] = []

    for raw_tag in area_tags:
        tag = str(raw_tag)
        if tag in IGNORED_AREA_TAGS or tag not in GEOMETRY_TAGS:
            continue

        geometry = _parse_tag(tag, sentences)
        if geometry is None:
            unresolved.append(tag)
        else:
            geometries.append(geometry)

    return geometries, unresolved


def _load_spells_from_json(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))

    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        spells = data.get("spell")
        if isinstance(spells, list):
            return [item for item in spells if isinstance(item, dict)]
    return []


def _load_spell_directory(directory: Path) -> list[dict[str, Any]]:
    index_path = directory / "index.json"
    files: list[Path] = []

    if index_path.exists():
        index_data = json.loads(index_path.read_text(encoding="utf-8"))
        if isinstance(index_data, dict):
            for value in index_data.values():
                if isinstance(value, str):
                    candidate = directory / value
                    if candidate.exists():
                        files.append(candidate)

    if not files:
        files = sorted(directory.glob("spells-*.json"))

    unique_files = sorted(set(files))
    spells: list[dict[str, Any]] = []
    for path in unique_files:
        spells.extend(_load_spells_from_json(path))
    return spells


def _load_spells(input_path: Path) -> list[dict[str, Any]]:
    if input_path.is_dir():
        return _load_spell_directory(input_path)
    return _load_spells_from_json(input_path)


def build_output(spells: list[dict[str, Any]]) -> dict[str, Any]:
    parsed: dict[str, Any] = {}
    unresolved: list[dict[str, str]] = []

    ordered_spells = sorted(
        spells,
        key=lambda spell: (
            str(spell.get("source", "")),
            str(spell.get("name", "")),
        ),
    )

    for spell in ordered_spells:
        name = str(spell.get("name", "")).strip()
        source = str(spell.get("source", "")).strip()
        if not name or not source:
            continue

        geometries, missing_tags = _extract_spell_geometry(spell)
        key = f"{source}::{name}"

        if geometries:
            parsed[key] = {
                "name": name,
                "source": source,
                "areas": geometries,
            }

        for tag in missing_tags:
            unresolved.append(
                {
                    "name": name,
                    "source": source,
                    "area_tag": tag,
                    "reason": "no regular dimension pattern found in matching sentence",
                }
            )

    unresolved.sort(
        key=lambda item: (
            item["source"],
            item["name"],
            item["area_tag"],
        )
    )

    return {
        "format_version": 1,
        "generated_by": "vtt/spells/parse_5etools_areas.py",
        "walls_ignored": True,
        "spells": parsed,
        "unresolved": unresolved,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "input",
        type=Path,
        help="5e.tools data/spells directory or a JSON file containing spells",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=OUTPUT_DEFAULT,
        help=f"output JSON path (default: {OUTPUT_DEFAULT})",
    )
    args = parser.parse_args()

    spells = _load_spells(args.input)
    if not spells:
        raise SystemExit(f"No spells found in {args.input}")

    output = build_output(spells)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            output,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(
        "Parsed area geometry for "
        f"{len(output['spells'])} spells; "
        f"{len(output['unresolved'])} unresolved geometry tags. "
        f"Wrote {args.output}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
