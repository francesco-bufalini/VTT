"""Fetch/cache 5eTools conditionsdiseases and normalize reproducibly. Never edit output.
Raw cache is ignored. --offline rebuilds without network; --refresh updates cache.
"""
import argparse, hashlib, json, re, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = "https://5e.tools/data/conditionsdiseases.json"
MIRROR = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-src/main/data/conditionsdiseases.json"

def normalize(data):
    rows = []
    legacy = {"blinded", "charmed", "deafened", "exhaustion", "frightened", "grappled", "incapacitated", "invisible", "paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious"}
    from urllib.parse import quote
    for key, category in [("condition", "conditions"), ("disease", "diseases"), ("status", "effects")]:
        for raw in data.get(key, []):
            name, source = raw["name"], raw["source"]
            row = {"id": f"5etools:{category}:{source.lower()}:{quote(name.lower(), safe='')}", "name": name, "source": source, "category": category, "origin": "5etools", "page": raw.get("page", 0), "edition": "2024" if source in ("XPHB", "XDMG") else "2014", "entries": raw.get("entries", [])}
            if key == "condition" and name.lower() in legacy:
                row["legacy_id"] = name.lower()
            rows.append(row)
    return sorted(rows, key=lambda row: row["id"])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".5etools-cache/conditionsdiseases.json")
    parser.add_argument("--output", type=Path, default=ROOT / "vtt/data/effects_5etools.json")
    args = parser.parse_args()
    if args.refresh or not args.cache.exists():
        if args.offline:
            parser.error("Offline cache missing")
        error = None
        for url in (URL, MIRROR):
            try:
                with urllib.request.urlopen(url, timeout=30) as response:
                    payload = response.read()
                parsed = json.loads(payload)
                if not isinstance(parsed.get("condition"), list) or not parsed["condition"]:
                    raise ValueError("Invalid condition response")
                args.cache.parent.mkdir(parents=True, exist_ok=True)
                args.cache.write_bytes(payload)
                break
            except Exception as exc:
                error = exc
        else:
            raise RuntimeError(f"Cannot refresh cache: {error}")
    payload = args.cache.read_bytes()
    rows = normalize(json.loads(payload))
    output = {"schema_version": 1, "source_url": URL, "sha256": hashlib.sha256(payload).hexdigest(), "entries": rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(rows)} effects; SHA256 {output['sha256']}")

if __name__ == "__main__":
    main()
