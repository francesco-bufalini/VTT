"""Generate miniature-to-5etools bestiary portraits from checked release associations."""
import argparse
import json
import pathlib
import unicodedata
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--associations", type=pathlib.Path, default=ROOT / "scripts/data/miniature_5etools_associations.json")
parser.add_argument("--release-additions", type=pathlib.Path, default=ROOT / "scripts/data/miniature_5etools_release_additions.json")
parser.add_argument("--bestiary-2014", type=pathlib.Path, required=True)
parser.add_argument("--bestiary-2024", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, default=ROOT / "vtt/data/miniature_bestiary.json")
args = parser.parse_args()

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

monsters = {
    edition: {(m["name"], m["source"]): m for m in read_json(path)["monster"]}
    for edition, path in (("2014", args.bestiary_2014), ("2024", args.bestiary_2024))
}

SIZE_CODE_TO_NAME = {
    "T": "Tiny", "S": "Small", "M": "Medium",
    "L": "Large", "H": "Huge", "G": "Gargantuan",
}
SIZE_TO_FOOTPRINT = {
    "Tiny": 0.5, "Small": 1, "Medium": 1,
    "Large": 2, "Huge": 3, "Gargantuan": 4,
}


def unambiguous_size_name(raw):
    values = raw if isinstance(raw, list) else [raw]
    sizes = {
        SIZE_CODE_TO_NAME.get(
            value if isinstance(value, str)
            else value.get("size") if isinstance(value, dict) else None
        )
        for value in values
    }
    # A variable/unknown size must not be silently reduced to one shape.
    return next(iter(sizes)) if len(sizes) == 1 and None not in sizes else None


def enrich_reference(selected, edition):
    value = dict(selected)
    m = monsters[edition].get((value["name"], value["source"]))
    if m is None:
        # References from older supplements (e.g. FTD/RoT) are stored
        # explicitly. Do not manufacture a token URL for a missing creature.
        if not value.get("url") or not value.get("token_url"):
            raise ValueError(f"Unresolved 5etools creature: {edition} {selected!r}")
        return value
    value.setdefault("page", m.get("page"))
    value.setdefault(
        "url", "https://5e.tools/bestiary.html#"
        + urllib.parse.quote(m["name"].lower(), safe="")
        + "_" + urllib.parse.quote(m["source"].lower(), safe="")
    )
    token = m.get("token", m)
    url = m.get("tokenUrl", "")
    href = m.get("tokenHref", {})
    if href:
        url = href.get("url", "") if href.get("type") == "external" else "https://5e.tools/img/" + href.get("path", "")
    if not url and (m.get("hasToken") or m.get("token")):
        name = unicodedata.normalize("NFKD", token["name"]).encode("ascii", "ignore").decode().replace('"', "")
        url = ("https://5e.tools/img/bestiary/tokens/"
               + urllib.parse.quote(token["source"], safe="")
               + "/" + urllib.parse.quote(name, safe="") + ".webp")
    value["token_url"] = url
    if not url:
        raise ValueError(f"5etools creature has no token art: {edition} {selected!r}")
    size_name = unambiguous_size_name(m.get("size"))
    if size_name:
        value["size_name"] = size_name
        value["footprint"] = SIZE_TO_FOOTPRINT[size_name]
    return value

entries = {}
def add(asset_name, miniature_key, editions):
    if not asset_name.endswith(".pck"):
        raise ValueError(f"Not a PCK: {asset_name}")
    token_id = asset_name[:-4]
    if token_id in entries:
        raise ValueError(f"Conflicting miniature identity: {token_id}")
    entries[token_id] = {
        "miniature_key": miniature_key,
        "editions": {
            edition: enrich_reference(selected, edition)
            for edition, selected in editions.items() if selected
        },
    }

original = read_json(args.associations)
for row in original["miniatures"]:
    add(row["asset_name"], row["miniature_key"],
        {edition: value.get("selected") for edition, value in row["editions"].items()})

if args.release_additions.is_file():
    additions = read_json(args.release_additions)
    for group in additions["groups"]:
        for asset in group["assets"]:
            add(asset, group["release_tag"] + "/" + asset, group["editions"])
    for row in additions["unassociated"]:
        add(row["asset_name"], row["release_tag"] + "/" + row["asset_name"], {})

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(
    json.dumps({"schema_version": 1, "entries": entries}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print(f"Generated {len(entries)} miniature entries ({sum(bool(x['editions']) for x in entries.values())} associated)")
