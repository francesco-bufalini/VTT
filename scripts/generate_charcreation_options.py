#!/usr/bin/env python3
"""Bundle 5etools Character Creation Options as selectable VTT feats.

Usage: python scripts/generate_charcreation_options.py /path/to/5etools-src

Keep structured source fields and descriptive entries verbatim. Do not deduce
bonuses or spell grants from ordinary prose. Only the explicit italic
"<level>-level <name> trait" marker is normalized as a display-level gate.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "vtt/data/charcreation_options_5etools.json"
TYPE_NAMES = {
    "SG": "Supernatural Gift",
    "DG": "Dark Gift",
    "CS": "Character Secret",
    "RF:B": "Background Feature",
}
LEVEL_MARKER = re.compile(r"^\{@i\s+(\d+)(?:st|nd|rd|th)-level\s+[^}]+trait\}", re.I)


def slug(value: str) -> str:
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9]+", "_", value.lower()))


def feature_sections(entries: object) -> list[dict]:
    sections: list[dict] = []

    def visit(raw: object) -> None:
        if isinstance(raw, list):
            for child in raw:
                visit(child)
        elif isinstance(raw, dict):
            if isinstance(raw.get("name"), str) and isinstance(raw.get("entries"), list):
                texts = [v for v in raw["entries"] if isinstance(v, str)]
                match = LEVEL_MARKER.match(texts[0]) if texts else None
                sections.append({
                    "name": raw["name"],
                    "source_section": True,
                    "min_level": int(match.group(1)) if match else 1,
                    "entries": raw["entries"],
                    "page": raw.get("page"),
                })
            else:
                for key in ("entries", "items"):
                    if key in raw:
                        visit(raw[key])

    visit(entries)
    return sections


def generate(src_root: Path) -> dict:
    source = src_root / "data/charcreationoptions.json"
    values = json.loads(source.read_text(encoding="utf-8"))["charoption"]
    output: list[dict] = []
    ids: set[str] = set()
    for original in values:
        row = original.copy()
        row["id"] = f"charoption:{slug(row['source'])}:{slug(row['name'])}"
        if row["id"] in ids:
            raise ValueError(f"Duplicate character option: {row['id']}")
        ids.add(row["id"])
        row["category"] = "feats"
        row["option_group"] = "Character Creation Option"
        row["feature_type"] = ", ".join(TYPE_NAMES.get(t, t) for t in row["optionType"])
        row["feature_sections"] = feature_sections(row["entries"])
        row["edition"] = "2014"
        row["origin"] = "5etools"
        output.append(row)
    return {"schema_version": 1, "provenance": "5etools-src/data/charcreationoptions.json", "feats": output}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    data = generate(Path(sys.argv[1]))
    OUTPUT.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"Exported {len(data['feats'])} 5etools Character Creation Options")


if __name__ == "__main__":
    main()
