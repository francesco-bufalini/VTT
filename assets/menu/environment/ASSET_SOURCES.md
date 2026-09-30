# Main-menu environment asset sources

The menu is designed to work without these files by using procedural fallbacks,
but the downloaded assets provide the intended final look.

## Castle

- Asset: `assets/menu/castle/Castle.glb`
- Source: the castle GLB supplied by the project owner.
- The repository does not automatically download or relicense this file.

## Sky

- Asset: `assets/menu/environment/sky/kloppenheim_06_puresky_1k.hdr`
- Work: **Kloppenheim 06 (Pure Sky)**.
- Authors: Greg Zaal (original), Jarod Guest (sky edits).
- Source: https://polyhaven.com/a/kloppenheim_06_puresky
- Download used by the helper:
  https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloppenheim_06_puresky_1k.hdr
- License: **CC0 1.0**. Attribution is not required.

The HDRI is used only for the sky/background and environment lighting. The
mountain geometry remains separate, so mountains still sit visibly in front of
the sky.

## Mountains, river-bank rocks and pine trees

- Pack: **Kenney Nature Kit**.
- Official source: https://kenney.nl/assets/nature-kit
- License: **CC0 1.0**. Attribution is not required.
- The helper downloads a small curated subset from the pinned public mirror
  `shorepine/kenney`, commit:
  `3694c6879e487c108f55677be7dd2ca75b07cc3b`.

Files:

- `rock_tallA.glb`
- `rock_tallB.glb`
- `rock_tallH.glb` — enlarged and darkened as distant mountain formations.
- `rock_largeA.glb`, `rock_largeB.glb`
- `stone_largeA.glb`, `stone_largeB.glb` — river-bank rocks.
- `tree_pineTallA.glb`, `tree_pineTallB.glb` — sparse river-bank vegetation.

Kenney's original Nature Kit is deliberately low-poly. That is useful in this
menu because the distant silhouettes remain inexpensive to render.

## River

The river does **not** require a third-party texture. It uses the project's own
animated Godot shader so there is no large tiling texture dependency. The
external Kenney rocks and trees are used around the banks.

## Download

From the repository root:

```bash
python tools/download_menu_environment_assets.py
```

Use `--force` to replace existing copies.

All third-party environment files downloaded by this helper are CC0. This file
keeps provenance even though attribution is optional.
