#!/usr/bin/env python3
"""
Build the runtime spell-map catalogue used by the VTT.

The parser is deterministic: it uses 5e.tools structured fields plus regular
expressions over the spell prose. No neural/LLM component is involved.

Input:
    python vtt/spells/parse_5etools_areas.py <5etools data/spells directory>
    python vtt/spells/parse_5etools_areas.py <normalized spell JSON>

Output:
    assets/spell_area_geometry.json

The asset intentionally contains only information consumed to target and draw
spell effects on the map: range, targeting, geometry, persistence, damage
families, and map-relevant visual tags. Parser diagnostics are written to
outputs/spell_area_parser_report.json instead.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Callable, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DEFAULT = PROJECT_ROOT / "assets/spell_area_geometry.json"
REPORT_DEFAULT = PROJECT_ROOT / "outputs/spell_area_parser_report.json"

TAG_RE = re.compile(r"\{@([^\s{}]+)\s+([^{}]+)\}")
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n+")

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
    "W": ("wall",),
}
TARGET_ONLY_AREA_TAGS = {"ST", "MT"}


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
        for key in ("entry", "entries", "items", "rows"):
            if key in value:
                result.extend(_flatten_entries(value[key]))
    return result


def _spell_text(spell: dict[str, Any]) -> str:
    if isinstance(spell.get("text"), str):
        return str(spell["text"])

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
        "sphere", "emanation", "aura", "line", "square", "cube", "cone",
        "cylinder", "circle", "hemisphere", "dome", "wall",
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

    # 2024 entries sometimes retain areaTags=["S"] while calling the actual
    # volume an Emanation. The prose wins.
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,45}?\bemanation\b",
        text,
    )
    if match:
        return {"shape": "emanation", "radius_feet": _number(match.group(1))}

    match = re.search(
        r"\baura\b[^.]{0,100}?\b(?:with|in)\s+(?:a\s+)?"
        r"(\d+(?:\.\d+)?)\s*-?\s*foot\s+radius\b",
        text,
    )
    if match:
        return {"shape": "sphere", "radius_feet": _number(match.group(1))}

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
    if not match:
        return None
    return {"shape": "emanation", "radius_feet": _number(match.group(1))}


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

    matches = re.findall(
        r"(?:cube|cage|box)\b[^.]{0,120}?(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\s+on\s+(?:each|a)\s+side\b",
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
    return None


def _parse_square(sentence: str) -> dict[str, Any] | None:
    text = sentence.lower().replace("–", "-").replace("—", "-")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*-\s*foot\b[^.]{0,30}?\bsquares?\b",
        text,
    )
    if match:
        return {"shape": "square", "side_feet": _number(match.group(1))}
    match = re.search(r"(\d+(?:\.\d+)?)\s+feet\s+square\b", text)
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
    for pattern in (
        r"(\d+(?:\.\d+)?)\s*-\s*foot-radius\b[^.]{0,90}?\bcircle\b",
        r"(\d+(?:\.\d+)?)\s*-\s*foot\s+radius\b",
        r"(\d+(?:\.\d+)?)\s+feet\s+in\s+radius\b",
    ):
        match = re.search(pattern, text)
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
    if not match:
        match = re.search(
            r"\b(?:hemisphere|dome)\b[^.]{0,120}?\bradius\s+"
            r"(?:of\s+)?(?:up\s+to\s+)?(\d+(?:\.\d+)?)\s+feet\b",
            text,
        )
    if not match:
        return None
    return {"shape": "hemisphere", "radius_feet": _number(match.group(1))}


def _feet_from_inches(value: float) -> int | float:
    return _number(value / 12.0)


def _parse_length_feet(text: str) -> int | float | None:
    fraction = re.search(r"(\d+)\s*/\s*(\d+)\s+inch(?:es)?\s+thick", text)
    if fraction and int(fraction.group(2)) != 0:
        inches = float(fraction.group(1)) / float(fraction.group(2))
        return _feet_from_inches(inches)

    inches = re.search(
        r"(\d+(?:\.\d+)?)\s+inch(?:es)?\s+thick",
        text,
    )
    if inches:
        return _feet_from_inches(float(inches.group(1)))

    feet = re.search(
        r"(\d+(?:\.\d+)?)\s+(?:feet|foot)\s+thick",
        text,
    )
    if feet:
        return _number(feet.group(1))
    return None


def _parse_wall(text_value: str) -> dict[str, Any] | None:
    # Walls are parsed from the complete spell text, not a single sentence:
    # the dimensions of alternate forms (ring/globe/panels) are commonly
    # described in following sentences.
    text = _strip_5etools_tags(text_value).lower()
    text = text.replace("–", "-").replace("—", "-")
    if "wall" not in text:
        return None

    variants: list[dict[str, Any]] = []

    # Straight/path wall.
    path_match = re.search(
        r"(?:wall[^.]{0,160}?)?(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\s+long\b"
        r"[^.]{0,100}?(\d+(?:\.\d+)?)\s+feet\s+high\b"
        r"[^.]{0,100}?(?:(\d+(?:\.\d+)?)\s+(?:feet|foot)\s+thick"
        r"|(\d+(?:\.\d+)?)\s+inch(?:es)?\s+thick)",
        text,
    )
    if path_match:
        thickness = (
            _number(path_match.group(3))
            if path_match.group(3)
            else _feet_from_inches(float(path_match.group(4)))
        )
        variants.append({
            "type": "path",
            "max_length_feet": _number(path_match.group(1)),
            "height_feet": _number(path_match.group(2)),
            "thickness_feet": thickness,
        })

    # Ring/circle wall, accepting both "20-foot diameter" and
    # "20 feet in diameter" wording.
    circle_patterns = (
        r"(?:ringed\s+wall|circle)[^.]{0,100}?"
        r"(?:up\s+to\s+)?(?:a\s+)?(\d+(?:\.\d+)?)\s*-\s*foot\s+diameter\b"
        r"[^.]{0,100}?(?:up\s+to\s+)?(\d+(?:\.\d+)?)\s+feet\s+high\b"
        r"[^.]{0,100}?(\d+(?:\.\d+)?)\s+(?:feet|foot)\s+thick\b",
        r"(?:ringed\s+wall|circle)[^.]{0,100}?"
        r"(?:up\s+to\s+)?(?:a\s+)?(\d+(?:\.\d+)?)\s+feet\s+in\s+diameter\b"
        r"[^.]{0,100}?(?:up\s+to\s+)?(\d+(?:\.\d+)?)\s+feet\s+high\b"
        r"[^.]{0,100}?(\d+(?:\.\d+)?)\s+(?:feet|foot)\s+thick\b",
    )
    for pattern in circle_patterns:
        match = re.search(pattern, text)
        if match:
            variants.append({
                "type": "circle",
                "radius_feet": _number(float(match.group(1)) / 2.0),
                "height_feet": _number(match.group(2)),
                "thickness_feet": _number(match.group(3)),
            })
            break

    # Globe/sphere. The dome alternative often shares this same radius.
    globe_radius: int | float | None = None
    match = re.search(
        r"(?:sphere|globe)\b[^.]{0,120}?\bradius\s+of\s+(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\b",
        text,
    )
    if match:
        globe_radius = _number(match.group(1))
    else:
        match = re.search(
            r"(?:sphere|globe)\b[^.]{0,120}?(?:up\s+to\s+)?"
            r"(\d+(?:\.\d+)?)\s+feet\s+in\s+diameter\b",
            text,
        )
        if match:
            globe_radius = _number(float(match.group(1)) / 2.0)
    if globe_radius is not None:
        variants.append({"type": "globe", "radius_feet": globe_radius})

    dome_radius: int | float | None = None
    match = re.search(
        r"hemispherical\s+dome\b[^.]{0,140}?"
        r"(?:radius\s+of\s+)?(?:up\s+to\s+)?"
        r"(\d+(?:\.\d+)?)\s+feet\b",
        text,
    )
    if match:
        dome_radius = _number(match.group(1))
    elif "hemispherical dome" in text and globe_radius is not None:
        dome_radius = globe_radius
    if dome_radius is not None:
        variants.append({"type": "dome", "radius_feet": dome_radius})

    # Panels. Keep exact panel metadata even though the current UI maps them
    # to the polyline editor.
    words = {
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    }
    panel_match = re.search(
        r"\b(one|two|three|four|five|six|seven|eight|nine|ten|\d+)"
        r"\s+(\d+(?:\.\d+)?)\s*-\s*foot(?:-by-"
        r"(\d+(?:\.\d+)?)\s*-\s*foot|-square)\s+panels?\b",
        text,
    )
    if panel_match:
        raw_count = panel_match.group(1)
        count = int(raw_count) if raw_count.isdigit() else words.get(raw_count, 1)
        width = float(panel_match.group(2))
        height = (
            float(panel_match.group(3))
            if panel_match.group(3)
            else width
        )
        thickness = _parse_length_feet(text)
        if thickness is None:
            thickness = 0.5

        variants.append({
            "type": "panels",
            "max_panels": count,
            "panel_width_feet": _number(width),
            "panel_height_feet": _number(height),
            "thickness_feet": thickness,
        })

    if not variants:
        return None

    # Remove exact duplicates while retaining the prose order.
    unique: list[dict[str, Any]] = []
    for variant in variants:
        if variant not in unique:
            unique.append(variant)
    return {"shape": "wall", "variants": unique}


PARSERS: dict[str, Callable[[str], dict[str, Any] | None]] = {
    "E": _parse_emanation,
    "S": _parse_sphere,
    "L": _parse_line,
    "Q": _parse_square,
    "N": _parse_cone,
    "C": _parse_cube,
    "Y": _parse_cylinder,
    "R": _parse_circle,
    "H": _parse_hemisphere,
    "W": _parse_wall,
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
            return geometry
    return None


def _extract_geometries(
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
        if tag in TARGET_ONLY_AREA_TAGS or tag not in GEOMETRY_TAGS:
            continue
        geometry = (
            _parse_wall(text)
            if tag == "W"
            else _parse_tag(tag, sentences)
        )
        if geometry is None:
            unresolved.append(tag)
            continue
        if geometry not in geometries:
            geometries.append(geometry)

    return geometries, unresolved


def _range_spec(spell: dict[str, Any]) -> dict[str, Any]:
    value = spell.get("range", {})
    if not isinstance(value, dict):
        return {}

    range_type = str(value.get("type", "point"))
    distance = value.get("distance", {})
    result: dict[str, Any] = {"type": range_type}

    if isinstance(distance, dict):
        distance_type = str(distance.get("type", ""))
        amount = distance.get("amount")
        if distance_type == "feet" and isinstance(amount, (int, float)):
            result["feet"] = _number(float(amount))
        elif distance_type == "miles" and isinstance(amount, (int, float)):
            result["feet"] = _number(float(amount) * 5280.0)
        elif distance_type:
            result["distance_type"] = distance_type
    return result


def _is_persistent(spell: dict[str, Any]) -> bool:
    duration = spell.get("duration", [])
    if not isinstance(duration, list) or not duration:
        return False
    for item in duration:
        if isinstance(item, dict) and str(item.get("type", "")) != "instant":
            return True
    return False


def _requires_ground(text: str) -> bool:
    cleaned = _strip_5etools_tags(text).lower()
    return bool(re.search(
        r"\b(?:point|area)\s+on\s+the\s+ground\b"
        r"|\bon\s+(?:the\s+)?ground\b",
        cleaned,
    ))


def _wall_requires_ground(text: str) -> bool:
    cleaned = _strip_5etools_tags(text).lower()
    if "free floating" in cleaned:
        return False
    return bool(re.search(
        r"\bwall\b[^.]{0,120}?\b(?:on|along)\s+"
        r"(?:the\s+)?(?:ground|a\s+solid\s+surface|solid\s+surface)\b"
        r"|\bwall\b[^.]{0,80}?\brises\s+from\s+the\s+ground\b",
        cleaned,
    ))


def _wall_choose_damage_side(text: str) -> bool:
    cleaned = _strip_5etools_tags(text).lower()
    return bool(
        re.search(
            r"\bone\s+side\s+of\s+the\s+wall\b[^.]{0,120}?\bdeals?\b",
            cleaned,
        )
        or (
            "one side of the wall" in cleaned
            and "other side of the wall" in cleaned
            and "damage" in cleaned
        )
    )


NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
}


def _count_token(value: str) -> int | None:
    lowered = value.lower()
    if lowered.isdigit():
        return int(lowered)
    return NUMBER_WORDS.get(lowered)


def _multi_target_count_spec(spell: dict[str, Any]) -> dict[str, Any]:
    text = _strip_5etools_tags(_spell_text(spell)).lower()
    higher = _strip_5etools_tags(
        "\n".join(_flatten_entries(spell.get("entriesHigherLevel", [])))
    ).lower()
    number = r"(one|two|three|four|five|six|seven|eight|nine|ten|\d+)"
    result: dict[str, Any] = {}

    base_patterns = [
        rf"\b(?:create|creates|fire|fires|launch|launches|shoot|shoots)\s+"
        rf"{number}\b[^.]{0,90}\b(?:dart|darts|ray|rays|missile|missiles|"
        rf"bolt|bolts|beam|beams)\b",
        rf"\bup\s+to\s+{number}\s+(?:willing\s+)?(?:creatures?|targets?)\b",
        rf"\b{number}\s+(?:willing\s+)?(?:creatures?|targets?)\s+of\s+"
        rf"(?:your|the caster's)\s+choice\b",
    ]
    for pattern in base_patterns:
        match = re.search(pattern, text)
        if match:
            count = _count_token(match.group(1))
            if count is not None and count > 0:
                result["base_target_clicks"] = count
                break

    scaling_patterns = [
        rf"\b(?:create|creates|add|adds|gain|gains)\s+{number}\s+"
        rf"(?:additional\s+|more\s+)?(?:dart|darts|ray|rays|missile|missiles|"
        rf"bolt|bolts|beam|beams|creature|creatures|target|targets)\b"
        rf"[^.]{0,120}\bfor\s+each\s+spell\s+slot\s+level\s+above\b",
        rf"\btarget\s+{number}\s+additional\s+(?:creatures?|targets?)\b"
        rf"[^.]{0,120}\bfor\s+each\s+spell\s+slot\s+level\s+above\b",
    ]
    for pattern in scaling_patterns:
        match = re.search(pattern, higher)
        if match:
            count = _count_token(match.group(1))
            if count is not None and count > 0:
                result["target_clicks_per_slot_above_base"] = count
                break

    if (
        "one creature or several" in text
        or "same creature" in text
        or "same target" in text
    ):
        result["allow_repeat_targets"] = True

    return result


def _targeting_spec(
    spell: dict[str, Any],
    range_spec: dict[str, Any],
    geometries: list[dict[str, Any]],
    text: str,
) -> dict[str, Any]:
    if any(geometry.get("shape") == "wall" for geometry in geometries):
        result: dict[str, Any] = {"type": "wall"}
        if _wall_requires_ground(text):
            result["requires_ground"] = True
        if _wall_choose_damage_side(text):
            result["choose_damage_side"] = True
        return result

    primary = geometries[0] if geometries else {}
    shape = str(primary.get("shape", ""))
    range_type = str(range_spec.get("type", "point"))
    distance_type = str(range_spec.get("distance_type", ""))

    self_like = (
        range_type in {"self", "radius", "emanation"}
        or distance_type == "self"
    )
    area_tags_value = spell.get("areaTags", [])
    area_tags = (
        {str(tag) for tag in area_tags_value}
        if isinstance(area_tags_value, list)
        else set()
    )

    if "MT" in area_tags and not self_like:
        result = {"type": "multi_token"}
        result.update(_multi_target_count_spec(spell))
        if not geometries:
            result["projectile"] = True
        return result

    if "ST" in area_tags and not self_like:
        result = {"type": "token"}
        if not geometries:
            result["projectile"] = True
        return result

    result = {}
    if self_like and shape in {"cone", "line", "cube"}:
        result["type"] = "caster_direction"
        result["allow_pitch"] = True
    elif self_like:
        result["type"] = "caster"
    else:
        result["type"] = "point"

    if _requires_ground(text):
        result["requires_ground"] = True
    return result


def _damage_types(spell: dict[str, Any]) -> list[str]:
    value = spell.get("damageInflict", [])
    if not isinstance(value, list):
        return []
    return sorted({str(item).lower() for item in value if str(item)})


def _build_effect(
    spell: dict[str, Any],
    geometries: list[dict[str, Any]],
) -> dict[str, Any]:
    effect: dict[str, Any] = {}
    if geometries:
        effect["geometry"] = geometries[0]

    damage_types = _damage_types(spell)
    if damage_types:
        effect["damage_types"] = damage_types

    if effect:
        effect["persistence"] = (
            "persistent" if _is_persistent(spell) else "instant"
        )
    return effect


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

    spells: list[dict[str, Any]] = []
    for path in sorted(set(files)):
        spells.extend(_load_spells_from_json(path))
    return spells


def _load_spells(input_path: Path) -> list[dict[str, Any]]:
    if input_path.is_dir():
        return _load_spell_directory(input_path)
    return _load_spells_from_json(input_path)


def build_output(
    spells: list[dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any]]:
    runtime: dict[str, Any] = {}
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

        geometries, missing_tags = _extract_geometries(spell)
        area_tags_value = spell.get("areaTags", [])
        area_tags = (
            {str(tag) for tag in area_tags_value}
            if isinstance(area_tags_value, list)
            else set()
        )
        target_only = bool(area_tags & TARGET_ONLY_AREA_TAGS)
        if not geometries and not target_only:
            for tag in missing_tags:
                unresolved.append({
                    "name": name,
                    "source": source,
                    "area_tag": tag,
                })
            continue

        range_spec = _range_spec(spell)
        targeting = _targeting_spec(
            spell,
            range_spec,
            geometries,
            _spell_text(spell),
        )
        if not targeting:
            continue

        effect = _build_effect(spell, geometries)
        entry: dict[str, Any] = {
            "range": range_spec,
            "targeting": targeting,
        }
        if effect:
            entry["effect"] = effect
        runtime[f"{source}::{name}"] = entry

        for tag in missing_tags:
            unresolved.append({
                "name": name,
                "source": source,
                "area_tag": tag,
            })

    report = {
        "spell_records": len(runtime),
        "unresolved": sorted(
            unresolved,
            key=lambda item: (
                item["source"],
                item["name"],
                item["area_tag"],
            ),
        ),
    }
    return runtime, report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "input",
        type=Path,
        help="5e.tools data/spells directory or normalized spell JSON",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=OUTPUT_DEFAULT,
        help="runtime map catalogue output path",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=REPORT_DEFAULT,
        help="parser diagnostics output path",
    )
    args = parser.parse_args()

    spells = _load_spells(args.input)
    if not spells:
        raise SystemExit(f"No spells found in {args.input}")

    runtime, report = build_output(spells)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(runtime, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(
        f"Wrote {len(runtime)} runtime spell-map records to {args.output}; "
        f"{len(report['unresolved'])} unresolved tags are listed in {args.report}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
