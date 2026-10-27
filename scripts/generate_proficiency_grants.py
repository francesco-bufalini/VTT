#!/usr/bin/env python3
"""Regenerate structured proficiency grants from 5etools-src JSON.

Usage:
    python scripts/generate_proficiency_grants.py /path/to/5etools-src

Class and subclass features retain source-qualified identities and level gates.
Missing upstream fields use reviewed typed supplements, never runtime prose parsing.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
from urllib.parse import quote

FIELDS = (
    "skillProficiencies",
    "weaponProficiencies",
    "armorProficiencies",
    "toolProficiencies",
    "languageProficiencies",
    "expertise",
)
IGNORED_SOURCES = {"XDMG", "EFA"}

# Reviewed language overrides for 2014-era player races/subraces. Some 5etools
# "other" fields stand for *named* racial languages (e.g. Quori), not picks.
# Keep this supplement in the generator so regenerated native/PWA catalogs agree.
LANGUAGE_OVERRIDES = {
    (entry["kind"], entry["name"].casefold(), entry["source"].casefold(),
     entry.get("raceName", "").casefold(), entry.get("raceSource", "").casefold()): entry
    for entry in json.loads((Path(__file__).resolve().parent / "data/race_language_grants_2014.json")
                            .read_text(encoding="utf-8"))["entries"]
}

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



FEATURE_GROUPS = ("classFeature", "subclassFeature")
FEATURE_FIELDS = FIELDS + ("saveProficiencies", "proficiencyChoices", "proficiencyReplacements")
FEATURE_ID_FIELDS = {
    "classFeature": ("className", "classSource", "level", "source", "name"),
    "subclassFeature": ("className", "classSource", "subclassShortName", "subclassSource", "level", "source", "name"),
}
FEATURE_METADATA = {"className": "class_name", "classSource": "class_source",
                    "subclassShortName": "subclass_short_name", "subclassSource": "subclass_source"}


def feature_identity(kind: str, record: dict) -> str:
    if kind == "classFeature":
        # Match generate_creature_references.py; never change persisted trait IDs.
        return ("5etools:class_features:" + str(record.get("source", "")).lower() + ":" +
                quote(str(record.get("name", "")).lower(), safe="") + ":" +
                str(record.get("className", "")).lower() + ":" + str(record.get("level", "")))
    namespace = "subclass_features"
    value = "|".join(str(record.get(key, "")) for key in FEATURE_ID_FIELDS[kind]).lower()
    return "5etools:" + namespace + ":" + quote(value, safe="-_.!~*'()")


def convert_features(kind: str, records: list[dict], supplements: list[dict]) -> list[dict]:
    """Only explicit typed grants; a matching supplement fills missing fields."""
    def key(record):
        return tuple(str(record.get(field, "")).casefold() for field in FEATURE_ID_FIELDS[kind])

    rules = {key(rule): rule for rule in supplements if rule["kind"] == kind}
    output = {}
    for record in records:
        if not record.get("name") or not record.get("source") or not record.get("className"):
            continue
        if record["source"].startswith("UA") or record["source"] == "XDMG":
            continue
        if not record.get("classSource") or int(record.get("level", 0)) < 1:
            continue
        if kind == "subclassFeature" and not (record.get("subclassShortName") and record.get("subclassSource")):
            continue
        sid = feature_identity(kind, record)
        fields = {field: deepcopy(record[field]) for field in FEATURE_FIELDS if field in record}
        for field in FEATURE_FIELDS:
            if field in rules.get(key(record), {}):
                fields.setdefault(field, deepcopy(rules[key(record)][field]))
        if not fields:
            continue
        output[key(record)] = {"id": sid, "name": record["name"], "source": record["source"],
                       **{target: record[key] for key, target in FEATURE_METADATA.items() if key in record},
                       "level": int(record["level"]), **fields}
    return sorted(output.values(), key=lambda row: (row["class_name"].casefold(), row["class_source"],
                  row.get("subclass_short_name", "").casefold(), row.get("subclass_source", ""), row["level"], row["id"]))


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
        if kind in ("race", "subrace"):
            key = (kind, str(record["name"]).casefold(), str(record["source"]).casefold(),
                   str(record.get("raceName", "")).casefold(),
                   str(record.get("raceSource", "")).casefold())
            override = LANGUAGE_OVERRIDES.get(key)
            if override is not None:
                row["languageProficiencies"] = deepcopy(override["languageProficiencies"])
                if override.get("replaces_parent_languages"):
                    row["replaces_parent_languages"] = True
            # An unknown 5etools "other" is ambiguous: never silently turn it
            # into a literal language, or guess that it means a free choice.
            if any(isinstance(grant, dict) and (
                    "other" in grant or
                    isinstance(grant.get("choose"), dict) and
                    "other" in grant["choose"].get("from", [])
                    ) for grant in row.get("languageProficiencies", [])):
                raise ValueError(f"Unaudited race language 'other': {kind} {row['name']} {row['source']}")
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--features-only", action="store_true",
                        help="Refresh feature sections without changing existing origin catalogs or languages")
    args = parser.parse_args()
    root = args.root
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
    feature_records = {kind: [] for kind in FEATURE_GROUPS}
    for file in sorted(set(index.values())):
        data = read_json(root / "data/class" / file)
        sources["class"].extend(data.get("class", []))
        for kind in FEATURE_GROUPS:
            feature_records[kind].extend(data.get(kind, []))
    supplements_path = Path(__file__).resolve().parent / "data/feature_proficiency_grants.json"
    supplements = read_json(supplements_path)["entries"]
    feature_output = {kind: convert_features(kind, rows, supplements)
                      for kind, rows in feature_records.items()}
    destination = Path(__file__).resolve().parent.parent / "vtt/data/proficiency_grants_5etools.json"
    if args.features_only:
        out = read_json(destination)
        out.update(feature_output)
        out["meta"]["featureSnapshot"] = release
        destination.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print("Updated " + ", ".join(f"{kind}: {len(rows)}" for kind, rows in feature_output.items()))
        return
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
    # Retain reviewed races absent from the upstream proficiency index.
    # These are real source-qualified species records, not fabricated grants.
    for (kind, name, book, race_name, race_book), override in LANGUAGE_OVERRIDES.items():
        rows = out[kind]
        if any((str(row.get("name", "")).casefold(), str(row.get("source", "")).casefold(),
                str(row.get("raceName", "")).casefold(), str(row.get("raceSource", "")).casefold())
               == (name, book, race_name, race_book) for row in rows):
            continue
        created = {"name": override["name"], "source": override["source"],
                   "languageProficiencies": deepcopy(override["languageProficiencies"])}
        if kind == "subrace":
            created.update({"raceName": override["raceName"], "raceSource": override["raceSource"]})
        if override.get("replaces_parent_languages"):
            created["replaces_parent_languages"] = True
        rows.append(created)
    out.update(feature_output)
    out["meta"]["featureSnapshot"] = release
    for (name, source), fields in FEAT_PROFICIENCY_OVERRIDES.items():
        if not any(row["name"] == name and row["source"] == source for row in out["feat"]):
            out["feat"].append({"name": name, "source": source, **fields})
    out["feat"].sort(key=lambda row: (row["name"].casefold(), row["source"]))
    # Persist audited trait ownership across upstream index regeneration.
    # This manifest never grants new proficiencies; it only identifies which
    # named 5etools trait owns existing structured grants/choices.
    ownership_path = Path(__file__).resolve().parent.parent / "vtt/data/proficiency_feature_ownership.json"
    if ownership_path.exists():
        ownership = read_json(ownership_path).get("entries", [])
        for rule in ownership:
            group = rule.get("kind", "")
            for row in out.get(group, []):
                if row["name"].casefold() != rule["name"].casefold() or row["source"].casefold() != rule["source"].casefold():
                    continue
                if rule.get("fixed"):
                    row["trait_proficiencies"] = rule["fixed"]
                if rule.get("choice"):
                    row["trait_proficiency_choices"] = rule["choice"]
                break
    destination = Path(__file__).resolve().parent.parent / "vtt/data/proficiency_grants_5etools.json"
    destination.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {destination}: " + ", ".join(f"{k}: {len(out[k])}" for k in sources))
    languages_path, languages_count = generate_language_catalog(root, release)
    print(f"Wrote {languages_path}: {languages_count} typed languages from {release}")


if __name__ == "__main__":
    main()
