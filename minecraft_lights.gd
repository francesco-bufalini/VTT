extends Node3D

# Best-effort bridge for Mineways/Blender imports.
# It does not need Minecraft metadata: it looks for emissive Minecraft block
# names in imported material / texture / surface names and derives one
# OmniLight3D per luminous block from the surface triangles.
#
# This works best with Mineways:
# - Export separate types
# - Split by block type
# - Custom material
# - individual textures
#
# If those names are not preserved by the import path, nothing is generated
# and the scene keeps working normally.

@export var enabled: bool = true
@export_range(1, 512, 1) var max_lights: int = 192
@export var cast_shadows: bool = false
@export_range(0.1, 5.0, 0.1) var default_attenuation: float = 1.35

var _scan_root: Node3D = null
var _cell_size: float = 1.0
var _generated_root: Node3D = null
var _rebuild_queued := false


func setup(root: Node3D, new_cell_size: float = 1.0) -> void:
	_scan_root = root
	_cell_size = maxf(new_cell_size, 0.001)

	if _generated_root == null or not is_instance_valid(_generated_root):
		_generated_root = Node3D.new()
		_generated_root.name = "MinecraftGeneratedLights"
		add_child(_generated_root)

	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)

	_queue_rebuild()


func rebuild() -> void:
	_rebuild_queued = false

	if not enabled:
		_clear_generated()
		return
	if _scan_root == null or not is_instance_valid(_scan_root):
		return

	_clear_generated()

	var sources: Dictionary = {}

	for node in _scan_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if _generated_root != null and _generated_root.is_ancestor_of(mesh_instance):
			continue

		_collect_mesh_sources(mesh_instance, sources)

	_spawn_sources(sources)


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild")


func _on_tree_node_added(node: Node) -> void:
	if _scan_root == null or not is_instance_valid(_scan_root):
		return
	if not node is MeshInstance3D:
		return
	if not _scan_root.is_ancestor_of(node):
		return
	_queue_rebuild()


func _collect_mesh_sources(
	mesh_instance: MeshInstance3D,
	sources: Dictionary
) -> void:
	var mesh := mesh_instance.mesh

	for surface_index in range(mesh.get_surface_count()):
		if (
			mesh.surface_get_primitive_type(surface_index)
			!= Mesh.PRIMITIVE_TRIANGLES
		):
			continue

		var signature := _surface_signature(mesh_instance, surface_index)
		var profile := _profile_for_signature(signature)
		if profile.is_empty():
			continue

		var arrays := mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

		if indices.is_empty():
			for vertex_index in range(0, vertices.size() - 2, 3):
				_collect_triangle(
					mesh_instance,
					vertices[vertex_index],
					vertices[vertex_index + 1],
					vertices[vertex_index + 2],
					profile,
					sources
				)
		else:
			for index_offset in range(0, indices.size() - 2, 3):
				var a_index := indices[index_offset]
				var b_index := indices[index_offset + 1]
				var c_index := indices[index_offset + 2]

				if (
					a_index < 0
					or b_index < 0
					or c_index < 0
					or a_index >= vertices.size()
					or b_index >= vertices.size()
					or c_index >= vertices.size()
				):
					continue

				_collect_triangle(
					mesh_instance,
					vertices[a_index],
					vertices[b_index],
					vertices[c_index],
					profile,
					sources
				)


func _collect_triangle(
	mesh_instance: MeshInstance3D,
	local_a: Vector3,
	local_b: Vector3,
	local_c: Vector3,
	profile: Dictionary,
	sources: Dictionary
) -> void:
	var a := mesh_instance.to_global(local_a)
	var b := mesh_instance.to_global(local_b)
	var c := mesh_instance.to_global(local_c)

	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()

	var centroid := (a + b + c) / 3.0
	var thin_source := bool(profile.get("thin", false))
	var inward_offset := (
		0.12 * _cell_size
		if thin_source
		else 0.42 * _cell_size
	)

	# For a normal cube this moves every visible face towards the block centre,
	# so all triangles of the same block collapse to the same spatial bucket.
	var candidate := centroid - normal * inward_offset
	var bucket_size := (
		_cell_size * 0.75
		if thin_source
		else _cell_size * 0.5
	)
	bucket_size = maxf(bucket_size, 0.05)

	var key := Vector3i(
		roundi(candidate.x / bucket_size),
		roundi(candidate.y / bucket_size),
		roundi(candidate.z / bucket_size)
	)

	if not sources.has(key):
		sources[key] = {
			"sum": candidate,
			"count": 1,
			"color": profile.get("color", Color.WHITE),
			"energy": float(profile.get("energy", 1.2)),
			"range": float(profile.get("range", 5.0)),
			"kind": String(profile.get("kind", "minecraft"))
		}
		return

	var source: Dictionary = sources[key]
	source["sum"] = (source.get("sum", Vector3.ZERO) as Vector3) + candidate
	source["count"] = int(source.get("count", 0)) + 1
	sources[key] = source


func _spawn_sources(sources: Dictionary) -> void:
	if _generated_root == null or not is_instance_valid(_generated_root):
		return

	var created := 0

	for source_value in sources.values():
		if created >= max_lights:
			break

		var source: Dictionary = source_value
		var count := maxi(1, int(source.get("count", 1)))
		var position: Vector3 = (
			(source.get("sum", Vector3.ZERO) as Vector3)
			/ float(count)
		)

		var light := OmniLight3D.new()
		light.name = "MinecraftLight_%03d_%s" % [
			created,
			String(source.get("kind", "source"))
		]
		light.light_color = source.get("color", Color.WHITE)
		light.light_energy = float(source.get("energy", 1.2))
		light.omni_range = float(source.get("range", 5.0))
		light.omni_attenuation = default_attenuation
		light.shadow_enabled = cast_shadows
		light.light_size = 0.12 * _cell_size
		light.light_bake_mode = Light3D.BAKE_DISABLED

		_generated_root.add_child(light)
		light.global_position = position
		created += 1


func _surface_signature(
	mesh_instance: MeshInstance3D,
	surface_index: int
) -> String:
	var parts: Array[String] = [
		String(mesh_instance.name),
		mesh_instance.mesh.resource_name
	]

	var mesh := mesh_instance.mesh
	if mesh.has_method("surface_get_name"):
		parts.append(String(mesh.surface_get_name(surface_index)))

	var material := mesh.surface_get_material(surface_index)
	if material != null:
		parts.append(material.resource_name)
		parts.append(material.resource_path)

		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			if standard.albedo_texture != null:
				parts.append(standard.albedo_texture.resource_name)
				parts.append(standard.albedo_texture.resource_path)
			if standard.emission_texture != null:
				parts.append(standard.emission_texture.resource_name)
				parts.append(standard.emission_texture.resource_path)

	return " ".join(parts).to_lower()


func _profile_for_signature(signature: String) -> Dictionary:
	# Explicitly ignore known non-emitting states first.
	if (
		signature.contains("torch_off")
		or signature.contains("lantern_off")
		or signature.contains("redstone_lamp_off")
	):
		return {}

	if signature.contains("sea_lantern"):
		return _profile(
			"sea_lantern",
			Color(0.68, 0.90, 1.0),
			1.35,
			6.5,
			false
		)

	if (
		signature.contains("soul_torch")
		or signature.contains("soul_lantern")
		or signature.contains("soul_fire")
	):
		return _profile(
			"soul_light",
			Color(0.28, 0.72, 1.0),
			1.30,
			5.5,
			true
		)

	if signature.contains("glowstone"):
		return _profile(
			"glowstone",
			Color(1.0, 0.72, 0.38),
			1.25,
			6.5,
			false
		)

	if signature.contains("shroomlight"):
		return _profile(
			"shroomlight",
			Color(1.0, 0.58, 0.30),
			1.15,
			6.0,
			false
		)

	if signature.contains("froglight"):
		return _profile(
			"froglight",
			Color(0.90, 0.86, 1.0),
			1.20,
			6.0,
			false
		)

	if signature.contains("jack_o_lantern"):
		return _profile(
			"jack_o_lantern",
			Color(1.0, 0.55, 0.20),
			1.20,
			5.5,
			false
		)

	if (
		signature.contains("redstone_lamp_on")
		or signature.contains("redstone_lamp_lit")
	):
		return _profile(
			"redstone_lamp",
			Color(1.0, 0.55, 0.26),
			1.25,
			6.0,
			false
		)

	if signature.contains("redstone_torch"):
		return _profile(
			"redstone_torch",
			Color(1.0, 0.18, 0.08),
			0.95,
			4.0,
			true
		)

	if signature.contains("end_rod"):
		return _profile(
			"end_rod",
			Color(0.88, 0.86, 1.0),
			1.00,
			4.5,
			true
		)

	if signature.contains("campfire"):
		return _profile(
			"campfire",
			Color(1.0, 0.40, 0.12),
			1.35,
			5.5,
			true
		)

	if signature.contains("lantern"):
		return _profile(
			"lantern",
			Color(1.0, 0.62, 0.28),
			1.30,
			5.5,
			true
		)

	if signature.contains("torch"):
		return _profile(
			"torch",
			Color(1.0, 0.52, 0.20),
			1.15,
			5.0,
			true
		)

	return {}


func _profile(
	kind: String,
	color: Color,
	energy: float,
	range_value: float,
	thin: bool
) -> Dictionary:
	return {
		"kind": kind,
		"color": color,
		"energy": energy,
		"range": range_value,
		"thin": thin
	}


func _clear_generated() -> void:
	if _generated_root == null or not is_instance_valid(_generated_root):
		return

	for child in _generated_root.get_children():
		child.queue_free()
