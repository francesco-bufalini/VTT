# Blender source

This directory is for editable, project-specific Blender source. Rebuildable third-party libraries live in the ignored .vtt_assets/ workspace instead of Git.

Suggested structure:

    blender/
    |-- arenas/
    |-- modular/
    |-- geometry_nodes/
    \-- manifests/

Track a .blend file only when it is specific to this VTT and worth versioning. Blender backup files are ignored. Do not vendor whole Poly Haven, ambientCG, BlenderKit, Fab or similar caches.

Use Git LFS for large project-specific source only after intentionally configuring it for this repository.

See tools/blender_env/README.md for setup, extension management, lazy assets and Godot export.
