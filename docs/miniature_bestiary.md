# Miniature bestiary references and 2D token hats

The context menu offers Bestiario 2024 and 2014 when all selected tokens use the same miniature identity and that identity has a reference. Links open in the system browser. Display names, instance token IDs and party membership do not determine the reference.

In 2D a horizontal image sits above the miniature, sized to the footprint. The miniature, physics, height, selection markers and gameplay state are retained. In 3D only the image is hidden. New tokens inherit their board view; visual transformations refresh the image and ignore stale download callbacks.

Images prefer the revised 2024 catalog (XMM, published 2025), then 2014 when metadata has no revised image. They are downloaded on demand and cached in user://token_cache/bestiary. Missing images or network failures leave the miniature visible. No token artwork is bundled in the repository.

## Data

vtt/data/miniature_bestiary.json contains the 144 original release entries reviewed on 2026-10-09 (136 mapped, 8 custom characters without a matching creature), plus 126 PCKs published in MM-Dragons, MM-H, MM-M and MM-W and inventoried on 2026-10-13. Of those 126 new PCKs, 120 are associated with a 5etools token and six intentionally remain unassociated, so there are 270 entries in total. Art-specific associations only determine the 2D portrait/reference; they do not change creature rules. Visual variants confirmed by the user map to the selected base creature; this is a reference association, not a modification of creature mechanics.

Regenerate with scripts/generate_miniature_bestiary.py --associations PATH --bestiary-2014 PATH --bestiary-2024 PATH. The first input defaults to the confirmed scripts/data/miniature_5etools_associations.json. The optional --release-additions input defaults to scripts/data/miniature_5etools_release_additions.json (new PCK IDs grouped by common creature identity). Bestiary inputs are bestiary-mm.json and bestiary-xmm.json from https://github.com/5etools-mirror-3/5etools-src/tree/main/data/bestiary. Only exact names and explicitly curated variants are included. The six unassociated new entries are listed with reasons in the additions file; older supplement references (Bahamut/FTD, Tiamat/RoT) include explicit verified page and token URL fields. XMM renames such as Modron Duodrone and Hobgoblin Warrior are handled by edition, and colored half-dragons share the generic XMM Half-Dragon portrait. If a 2024 identity has no equivalent, the runtime falls back to 2014. Link hashes and token paths follow js/utils.js, js/render.js and js/parser.js in the same upstream repository.

Both export presets explicitly include vtt/data/*.json. The generated metadata is local and works without fetching the catalogs at runtime; artwork needs either internet access or a previously cached image.

## Validation

res://tests/test_bestiary_token_hat.gd covers homogeneous and mixed selection, both editions, original aliases, new release variants, 2024 renamed creatures, intentionally unassociated accessories, custom characters, footprint scaling, restoration to 3D, stale callbacks and tokens created on a board already in 2D.
