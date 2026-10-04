# Blender agent

This is the GitHub/self-hosted-runner bridge for Blender 5.2.x.

Jobs are JSON files under blender/jobs/. The runner executes them with the Blender installed on the self-hosted Windows machine. Large third-party assets stay in VTT_BLENDER_ASSET_ROOT outside Git.

Current schema intentionally supports only a small safe core:
- add_cube
- add_plane
- add_sun
- set_camera
- preview PNG
- scene report JSON
- GLB export
- .blend save

Environment-art operations such as Asset Browser search, kitbashing, Geometry Nodes, scattering and optimization can be added as reusable high-level operations instead of encoding raw low-level Blender commands in every job.

The workflow uploads outputs/blender_agent/** as a GitHub Actions artifact. Binary .blend/.glb results are not committed automatically.
