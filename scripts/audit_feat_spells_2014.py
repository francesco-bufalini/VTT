#!/usr/bin/env python3
"""Check every legacy feat spell grant against the reviewed normalization rules.

Usage: python scripts/audit_feat_spells_2014.py /path/to/5etools-src
The report contains identities and structural findings, never inferred grants.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "scripts/data/feat_spell_grants_2014.json"
OUTPUT = ROOT / "docs/feat-spell-audit-2014.json"


def audit(feats: list, manifest: dict) -> dict:
    sources = set(manifest["meta"]["sources"])
    latest = [row for row in feats if row["source"] in sources and not any(
        str(ref).split("|")[-1] in sources for ref in row.get("reprintedAs", []))]
    grants = {(row["name"], row["source"]): row for row in latest if row.get("additionalSpells")}
    reviewed = {(row["name"], row["source"]): row for row in manifest["entries"]}
    missing = sorted(set(grants) - set(reviewed))
    stale = sorted(set(reviewed) - set(grants))
    if missing or stale:
        raise ValueError(f"Feat spell audit incomplete: missing={missing}; stale={stale}")
    return {"meta": {"edition": "2014", "scope": "latest printing within the selected legacy sources",
                     "source_snapshot": manifest["meta"]["feat_source_snapshot"],
                     "rules": str(RULES.relative_to(ROOT)), "sources": sorted(sources)},
            "latest_feats_checked": len(latest), "spell_grant_feats": len(grants),
            "official_spell_grant_feats": sum(source != "PSK" for _, source in grants),
            "optional_plane_shift_spell_grant_feats": sum(source == "PSK" for _, source in grants),
            "missing": [], "stale": [],
            "entries": [{"name": name, "source": source,
                "optional_plane_shift": source == "PSK",
                "upstream_blocks": len(grants[(name, source)]["additionalSpells"]),
                "corrections": sorted(key for key in reviewed[(name, source)] if key not in ("kind", "name", "source"))}
                for name, source in sorted(grants)]}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    path = Path(sys.argv[1]) / "data/feats.json"
    manifest = json.loads(RULES.read_text(encoding="utf-8"))
    report = audit(json.loads(path.read_text(encoding="utf-8"))["feat"], manifest)
    report["meta"]["feats_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Checked {report['latest_feats_checked']} latest legacy feats: "
          f"{report['spell_grant_feats']} spell-grant feats, no missing or stale bindings")
