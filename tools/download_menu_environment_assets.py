#!/usr/bin/env python3
"""Download the CC0 environment assets used by the VTT main menu.

The castle itself is user-provided and is not downloaded by this script.
Everything downloaded here is CC0; see assets/menu/environment/ASSET_SOURCES.md.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KENNEY_COMMIT = "3694c6879e487c108f55677be7dd2ca75b07cc3b"

ASSETS = [
    (
        "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/"
        "kloppenheim_06_puresky_1k.hdr",
        ROOT / "assets/menu/environment/sky/kloppenheim_06_puresky_1k.hdr",
    ),
    *[
        (
            "https://raw.githubusercontent.com/shorepine/kenney/"
            f"{KENNEY_COMMIT}/3d/nature/{name}",
            ROOT / "assets/menu/environment/kenney" / name,
        )
        for name in (
            "rock_tallA.glb",
            "rock_tallB.glb",
            "rock_tallH.glb",
            "rock_largeA.glb",
            "rock_largeB.glb",
            "stone_largeA.glb",
            "stone_largeB.glb",
            "tree_pineTallA.glb",
            "tree_pineTallB.glb",
        )
    ],
]


def download(url: str, destination: Path, force: bool) -> None:
    if destination.exists() and destination.stat().st_size > 0 and not force:
        print(f"skip  {destination.relative_to(ROOT)}")
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Virtual-Table-Story-Teller-menu-assets/1.0",
        },
    )

    print(f"fetch {destination.relative_to(ROOT)}")
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            with temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
        temporary.replace(destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-download assets that already exist",
    )
    args = parser.parse_args()

    failures: list[str] = []
    for url, destination in ASSETS:
        try:
            download(url, destination, args.force)
        except Exception as exc:
            failures.append(f"{destination.name}: {exc}")
            print(f"ERROR {destination}: {exc}", file=sys.stderr)

    if failures:
        print("\nSome assets could not be downloaded:", file=sys.stderr)
        for failure in failures:
            print(f" - {failure}", file=sys.stderr)
        return 1

    print("\nMain-menu environment assets are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
