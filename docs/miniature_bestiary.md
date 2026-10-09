# Miniature bestiary references and 2D token hats

The context menu offers Bestiario 2024 and 2014 when all selected tokens use the same miniature identity and that identity has a reference. Links open in the system browser. Display names, instance token IDs and party membership do not determine the reference.

In 2D a horizontal image sits above the miniature, sized to the footprint. The miniature, physics, height, selection markers and gameplay state are retained. In 3D only the image is hidden. New tokens inherit their board view; visual transformations refresh the image and ignore stale download callbacks.

Images prefer the revised 2024 catalog (XMM, published 2025), then 2014 when metadata has no revised image. They are downloaded on demand and cached in user://token_cache/bestiary. Missing images or network failures leave the miniature visible. No token artwork is bundled in the repository.

## Data

vtt/data/miniature_bestiary.json contains the 144 release asset associations reviewed and confirmed on 2026-10-09. Eight custom characters remain unassociated. Visual variants confirmed by the user map to the selected base creature; this is a reference association, not a modification of creature mechanics.

Regenerate with scripts/generate_miniature_bestiary.py --associations PATH --bestiary-2014 PATH --bestiary-2024 PATH. The first input defaults to the confirmed scripts/data/miniature_5etools_associations.json; bestiary inputs are bestiary-mm.json and bestiary-xmm.json from https://github.com/5etools-mirror-3/5etools-src/tree/main/data/bestiary. Unconfirmed candidates are not included. Link hashes and token paths follow js/utils.js, js/render.js and js/parser.js in the same upstream repository.

Both export presets explicitly include vtt/data/*.json. The generated metadata is local and works without fetching the catalogs at runtime; artwork needs either internet access or a previously cached image.

## Validation

res://tests/test_bestiary_token_hat.gd covers homogeneous and mixed selection, both editions, confirmed aliases, custom characters, footprint scaling, restoration to 3D, stale callbacks and tokens created on a board already in 2D.
