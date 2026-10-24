#!/usr/bin/env python3
"""Regenerate structured proficiency grants from 5etools-src JSON.

Usage:
    python scripts/generate_proficiency_grants.py /path/to/5etools-src

No prose parsing is performed. Class features and subclass features currently
lack structured proficiency fields in upstream data and are not inferred.
"""
import json
import sys
from pathlib import Path

FIELDS = (
    "skillProficiencies",
    "weaponProficiencies",
    "armorProficiencies",
    "toolProficiencies",
    "languageProficiencies",
    "expertise",
)
IGNORED_SOURCES = {"XDMG", "EFA"}

# Typed fallback definitions for feats whose choice mechanics are omitted by
# upstream 5etools proficiency fields. Shared pick groups use a *single* pool.
FEAT_PROFICIENCY_OVERRIDES = {
    ("Skilled", "PHB"): {"proficiencyChoices": [
        {"choose": {"fromKinds": ["skill", "tool"], "count": 3}}]},
    ("Skilled", "XPHB"): {"proficiencyChoices": [
        {"choose": {"fromKinds": ["skill", "tool"], "count": 3}}]},
    ("Crafter", "XPHB"): {"toolProficiencies": [
        {"choose": {"from": [
            "carpenter's tools", "leatherworker's tools", "mason's tools",
            "potter's tools", "smith's tools", "tinker's tools",
            "weaver's tools", "woodcarver's tools"], "count": 3}}]},
    ("Musician", "XPHB"): {"toolProficiencies": [
        {"anyMusicalInstrument": 3}]},
}



def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def convert(kind: str, records: list[dict]) -> list[dict]:
    output = []
    for record in records:
        if not record.get("name") or not record.get("source"):
            continue
        if (record.get("edition") == "one" and record["source"] != "XPHB") or record["source"] in IGNORED_SOURCES:
            continue
        row = {"name": record["name"], "source": record["source"]}
        if kind == "subrace":
            row["raceName"] = record.get("raceName", "")
            row["raceSource"] = record.get("raceSource", "")
        # Some subraces have mutually exclusive _versions. A null field in
        # one version explicitly removes the parent grant for that choice;
        # the unspecialized parent row must not grant it to every variant.
        alternative_fields = {
            field for version in record.get("_versions", [])
            for field in FIELDS if field in version and version[field] is None
        } if kind == "subrace" else set()
        for field in FIELDS:
            if field in record and field not in alternative_fields:
                row[field] = record[field]
        if kind == "feat":
            # Preserve upstream structured values when present.
            for key, value in FEAT_PROFICIENCY_OVERRIDES.get((record["name"], record["source"]), {}).items():
                row.setdefault(key, value)
        # Some 5etools-src mirrors omit the MPMM Languages trait entirely,
        # although the structured full race data grants Common + one language
        # agreed with the DM. Retain this rule across index regenerations.
        # Never replace the structured field when the upstream supplies it.
        if kind == "race" and record["source"] == "MPMM" and "languageProficiencies" not in row:
            row["languageProficiencies"] = [{"common": True, "anyStandard": 1}]
        if kind == "class":
            if "proficiency" in record:
                row["savingThrows"] = record["proficiency"]
            if "startingProficiencies" in record:
                row["startingProficiencies"] = record["startingProficiencies"]
            multiclass = record.get("multiclassing", {})
            if "proficienciesGained" in multiclass:
                row["multiclassProficiencies"] = multiclass["proficienciesGained"]
            hit_dice = record.get("hd", {})
            equipment = record.get("startingEquipment", {})
            row["startingMeta"] = {
                "hitDice": f"1d{hit_dice['faces']}" if hit_dice.get("faces") else "",
                "hitPointsAtFirst": hit_dice.get("faces"),
                "equipment": equipment.get("default", []),
                "multiclass": multiclass.get("requirements", {}),
                "gold": equipment.get("goldAlternative", ""),
            }
        if any(key in row for key in FIELDS + (
            "savingThrows", "startingProficiencies", "multiclassProficiencies", "proficiencyChoices"
        )):
            output.append(row)
    return output


def generate_language_catalog(root: Path, release: str) -> tuple[Path, int]:
    """Build the compact typed-language list from the same 5etools release."""
    source = root / "data/languages.json"
    if not source.is_file():
        raise FileNotFoundError(f"Latest 5etools language list is missing: {source}")
    data = read_json(source)
    by_name: dict[str, list[dict]] = {}
    for language in data.get("language", []):
        name = str(language.get("name", "")).strip()
        if name:
            by_name.setdefault(name.lower(), []).append(language)
    languages = []
    for key, candidates in by_name.items():
        types = sorted({row.get("type", "other") for row in candidates})
        chosen = next(
            (row for row in candidates if row.get("source") == "PHB" and row.get("type")),
            None,
        ) or next(
            (row for row in candidates if row.get("source") == "XPHB" and row.get("type")),
            None,
        ) or next(
            (row for row in candidates if row.get("type")),
            None,
        ) or next(
            (row for row in candidates if row.get("source") == "PHB"), None
        ) or candidates[0]
        is_secret = "secret" in types or key in {"druidic", "thieves' cant"}
        languages.append({
            "key": key,
            "label": chosen["name"],
            "source": chosen["source"],
            "group": "secret" if is_secret else chosen.get("type", "other"),
            "types": types,
        })
    languages.sort(key=lambda entry: entry["label"].casefold())
    dest = Path(__file__).resolve().parent.parent / "vtt/data/languages_5etools.json"
    document = {
        "meta": {
            "source": "https://github.com/5etools-mirror-3/5etools-src",
            "release": release,
            "sourceFile": "data/languages.json",
        },
        "languages": languages,
    }
    dest.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")),
                    encoding="utf-8")
    return dest, len(languages)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_proficiency_grants.py /path/to/5etools-src")
    root = Path(sys.argv[1])
    package = read_json(root / "package.json")
    release = "v" + str(package.get("version", "unknown")).lstrip("v")
    index = read_json(root / "data/class/index.json")
    sources = {
        "class": [],
        "race": [],
        "subrace": [],
        "background": [],
        "feat": [],
    }
    for file in index.values():
        data = read_json(root / "data/class" / file)
        sources["class"].extend(data.get("class", []))
    for filename in ["races.json", "backgrounds.json", "feats.json"]:
        data = read_json(root / "data" / filename)
        for category in ["race", "subrace", "background", "feat"]:
            sources[category].extend(data.get(category, []))
    out = {
        "meta": {
            "source": "5etools-mirror-3/5etools-src",
            "snapshot": release,
            "note": "Structured proficiencies; MPMM Common + one language fallback where omitted by mirror",
        }
    }
    for category, entries in sources.items():
        out[category] = convert(category, entries)
    for (name, source), fields in FEAT_PROFICIENCY_OVERRIDES.items():
        if not any(row["name"] == name and row["source"] == source for row in out["feat"]):
            out["feat"].append({"name": name, "source": source, **fields})
    out["feat"].sort(key=lambda row: (row["name"].casefold(), row["source"]))
    destination = Path(__file__).resolve().parent.parent / "vtt/data/proficiency_grants_5etools.json"
    destination.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {destination}: " + ", ".join(f"{k}: {len(out[k])}" for k in sources))
    languages_path, languages_count = generate_language_catalog(root, release)
    print(f"Wrote {languages_path}: {languages_count} typed languages from {release}")


if __name__ == "__main__":
    main()
