"""Update character release and unified catalogs from recalibrated pack bytes."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def update_catalogs(pack_dir, source_catalog, spec_path, unified_path, additions_path=None):
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
    if additions_path is not None:
        additions = read_json(additions_path)
        assert additions["release_tag"] == spec["release_tag"]
        for profile in additions["tokens"]:
            token_id = profile["id"]
            assert token_id not in profiles, f"Duplicate calibrated/imported character: {token_id}"
            pack = pack_dir / (token_id + ".pck")
            with pack.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            entry = {key: profile[key] for key in ("id", "name", "size_name", "footprint", "version", "source_collection")}
            entry.update({
                "pck": pack.name,
                "scene": f"res://remote_tokens/{token_id}/{token_id}_token.tscn",
                "sha256": digest,
                "bytes": pack.stat().st_size,
            })
            release["tokens"].append(entry)
            existing = next((p for p in unified["tokens"] if p["id"] == token_id), None)
            if existing is not None:
                assert existing["release_tag"] == spec["release_tag"]
                assert int(existing["version"]) <= int(entry["version"]), f"Newer imported character exists: {token_id}"
                existing.update(entry)
            else:
                unified["tokens"].append({**entry, "release_tag": spec["release_tag"]})
    release["generated_at"] = datetime.now(timezone.utc).isoformat()
    # Character artwork is a 2D token as well as a portable PWA portrait.
    # Generate the same metadata in the release and bundled unified catalogs.
    for entry in release["tokens"]:
        image = ROOT / "pwa/miniature-images" / (entry["id"] + ".webp")
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        artwork = {
            "token_image_url": f"https://github.com/francesco-bufalini/VTT/releases/download/characters/{image.name}?v={digest[:12]}",
            "token_image_path": f"res://pwa/miniature-images/{image.name}",
            "token_image_sha256": digest,
            "token_image_bytes": image.stat().st_size,
        }
        entry.update(artwork)
        next(p for p in unified["tokens"] if p["id"] == entry["id"]).update(artwork)
    (pack_dir / "token_catalog.json").write_text(json.dumps(release, indent=2) + "\n", encoding="utf-8", newline="\n")
    unified_path.write_text(json.dumps(unified, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(release['tokens'])} character entries in both catalogs")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-dir", type=Path, required=True)
    parser.add_argument("--source-catalog", type=Path, required=True)
    parser.add_argument("--spec", type=Path, default=ROOT / "scripts/data/character_miniature_heights.json")
    parser.add_argument("--unified-catalog", type=Path, default=ROOT / "vtt/data/token_catalog_offline.json")
    parser.add_argument("--additions", type=Path, help="Curated new character imports to include in both catalogs")
    args = parser.parse_args()
    update_catalogs(args.pack_dir, args.source_catalog, args.spec, args.unified_catalog, args.additions)
