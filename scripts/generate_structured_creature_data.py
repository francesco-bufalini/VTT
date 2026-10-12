#!/usr/bin/env python3
"""Regenerate creature-side structured catalogs together from one 5etools checkout.

Usage: python scripts/generate_structured_creature_data.py /path/to/5etools-src
This intentionally does not interpret privilege prose or regenerate spell data.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_structured_creature_data.py /path/to/5etools-src")
    source = Path(sys.argv[1]).resolve()
    for script in (
        "generate_proficiency_grants.py",
        "generate_structured_ability_grants.py",
        "generate_class_mechanics.py",
    ):
        subprocess.run([sys.executable, str(ROOT / script), str(source)], check=True)


if __name__ == "__main__":
    main()
