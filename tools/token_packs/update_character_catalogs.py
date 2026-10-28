"""Update character release and unified catalogs from recalibrated pack bytes."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def update_catalogs(pack_dir, source_catalog, spec_path, unified_path):
    spec = read_json(spec_path)
    release = read_json(source_catalog)
    unified = read_json(unified_path)
    profiles = {p["id"]: p for p in spec["characters"]}
    release_entries = {p["id"]: p for p in release["tokens"]}
    assert set(release_entries) == set(profiles), "Release characters changed; review the calibration spec first"
    updates = {}
    for token_id, profile in profiles.items():
        old = release_entries[token_id]
        assert old["sha256"] == profile["source_sha256"], f"Unexpected original catalog hash: {token_id}"
        pack = pack_dir / old["pck"]
        with pack.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        updates[token_id] = {
            "sha256": digest,
            "bytes": pack.stat().st_size,
            "version": int(old.get("version", 1)) + 1,
        }
        assert updates[token_id]["sha256"] != old["sha256"], f"Pack was not recalibrated: {token_id}"
        old.update(updates[token_id])
    seen = set()
    for entry in unified["tokens"]:
        token_id = entry["id"]
        if token_id in updates:
            assert entry["release_tag"] == spec["release_tag"]
            assert int(entry.get("version", 1)) <= updates[token_id]["version"], f"A newer unified entry exists: {token_id}"
            entry.update(updates[token_id])
            seen.add(token_id)
    assert seen == set(profiles), "A character is missing from the unified catalog"
    release["generated_at"] = datetime.now(timezone.utc).isoformat()
    (pack_dir / "token_catalog.json").write_text(json.dumps(release, indent=2) + "\n", encoding="utf-8")
    unified_path.write_text(json.dumps(unified, indent=2) + "\n", encoding="utf-8")
    print(f"Updated {len(updates)} character packs in both catalogs")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-dir", type=Path, required=True)
    parser.add_argument("--source-catalog", type=Path, required=True)
    parser.add_argument("--spec", type=Path, default=ROOT / "scripts/data/character_miniature_heights.json")
    parser.add_argument("--unified-catalog", type=Path, default=ROOT / "vtt/data/token_catalog_offline.json")
    args = parser.parse_args()
    update_catalogs(args.pack_dir, args.source_catalog, args.spec, args.unified_catalog)
