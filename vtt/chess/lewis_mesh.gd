extends RefCounted
## Simplified geometry extracted from the supplied Lewis chess set GLB.
## The original file contains 11 sculpted meshes; these six are selected and
## geometry-clustered so the standalone Godot scenario stays lightweight.
## Quantization: x/z in [-.5,.5], y in [0,1.1], unsigned bytes, ZLIB.
const Data = preload("res://vtt/chess/lewis_mesh_data.gd")

static func create_mesh(kind: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not Data.PIECES.has(kind):
		return mesh
	var packed: PackedByteArray = Marshalls.base64_to_raw(Data.PIECES[kind])
	var raw: PackedByteArray = packed.decompress(int(Data.LENGTHS[kind]), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(Data.LENGTHS[kind]) or raw.size() % 9 != 0:
		push_warning("Lewis chess model invalid for " + kind)
		return mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, raw.size(), 3):
		var v := Vector3(float(raw[i]) / 255.0 - 0.5,
			float(raw[i + 1]) * 1.1 / 255.0,
			float(raw[i + 2]) / 255.0 - 0.5)
		surface.add_vertex(v)
	surface.generate_normals()
	surface.commit(mesh)
	return mesh
