extends Node

const VISUAL_ONLY_GROUP := "grid_2d_visual_only"
const EXCLUDED_GROUP := "grid_2d_excluded"

var board_root: Node3D
var cell_size: float = 1.0
var _enabled := false
var _interaction_strength := 0.55
var _overlays: Dictionary = {}
var _shape_signatures: Dictionary = {}


func setup(root: Node3D, new_cell_size: float) -> void:
	board_root = root
	cell_size = maxf(new_cell_size, 0.001)
	get_tree().node_added.connect(_on_node_added)
	refresh()


func set_grid_visible(value: bool) -> void:
	_enabled = value
	_refresh_visibility()


func is_grid_visible() -> bool:
	return _enabled


func set_interaction_strength(value: float) -> void:
	_interaction_strength = clampf(value, 0.0, 1.0)
	for overlay in _overlays.values():
		if is_instance_valid(overlay):
			_apply_overlay_strength(overlay)


func refresh() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return

	for node in board_root.find_children("*", "CollisionShape3D", true, false):
		_consider_collision_shape(node as CollisionShape3D)

	for node in get_tree().get_nodes_in_group(VISUAL_ONLY_GROUP):
		if board_root.is_ancestor_of(node):
			_consider_visual_only(node)

	_refresh_visibility()


func _process(_delta: float) -> void:
	_refresh_changed_collisions()
	_refresh_visibility()


func _on_node_added(node: Node) -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	if node == board_root or not board_root.is_ancestor_of(node):
		return

	call_deferred("_consider_node", node)


func _consider_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return

	if node is CollisionShape3D:
		_consider_collision_shape(node as CollisionShape3D)

	if node.is_in_group(VISUAL_ONLY_GROUP):
		_consider_visual_only(node)


func _consider_collision_shape(collision: CollisionShape3D) -> void:
	if collision == null or not is_instance_valid(collision):
		return
	if _overlays.has(collision):
		return
	if collision.shape == null:
		return

	var body := _find_collision_body(collision)
	if body == null:
		return
	# Areas are interaction/trigger volumes, not physical walkable surfaces.
	# In particular this excludes the invisible pick colliders used by AoEs.
	if body is Area3D:
		return
	if body is CharacterBody3D:
		return
	if _has_group_in_ancestry(body, EXCLUDED_GROUP):
		return
	if body.is_in_group("dnd_token"):
		return

	var rectangle := _collision_top_rectangle(collision.shape)
	if rectangle.is_empty():
		return

	var overlay := _create_grid_overlay(
		Vector2(rectangle.width, rectangle.depth),
		Vector3(rectangle.center_x, rectangle.top_y, rectangle.center_z)
	)
	overlay.name = "AutoGrid2D"
	collision.add_child(overlay)
	_overlays[collision] = overlay
	_shape_signatures[collision] = _collision_signature(collision)
	_apply_overlay_strength(overlay)


func _consider_visual_only(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _overlays.has(node):
		return
	if node.is_in_group(EXCLUDED_GROUP):
		return

	var size := Vector2.ZERO
	var offset := Vector3.ZERO

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var aabb := mesh_instance.mesh.get_aabb()
		size = Vector2(aabb.size.x, aabb.size.z)
		offset = Vector3(
			aabb.position.x + aabb.size.x * 0.5,
			aabb.position.y + aabb.size.y + cell_size * 0.01,
			aabb.position.z + aabb.size.z * 0.5
		)
	elif node.has_meta("grid_2d_size"):
		var declared_size: Variant = node.get_meta("grid_2d_size")
		if declared_size is Vector2:
			size = declared_size
			offset.y = float(node.get_meta("grid_2d_y", 0.0))
	else:
		return

	if size.x <= 0.001 or size.y <= 0.001:
		return

	var overlay := _create_grid_overlay(size, offset)
	overlay.name = "VisualOnlyGrid2D"
	node.add_child(overlay)
	_overlays[node] = overlay
	_apply_overlay_strength(overlay)


func _refresh_changed_collisions() -> void:
	var rebuild: Array[CollisionShape3D] = []

	for source in _overlays.keys():
		# A collision may have been queue_freed by encounter rebuilding.
		# Never use "is" or "as" until the Object reference is confirmed alive.
		if not is_instance_valid(source):
			continue
		if not source is CollisionShape3D:
			continue

		var collision := source as CollisionShape3D
		var signature := _collision_signature(collision)
		if _shape_signatures.get(collision, "") != signature:
			rebuild.append(collision)

	for collision in rebuild:
		var overlay: Variant = _overlays.get(collision)
		if is_instance_valid(overlay):
			(overlay as Node).queue_free()
		_overlays.erase(collision)
		_shape_signatures.erase(collision)
		_consider_collision_shape(collision)


func _collision_signature(collision: CollisionShape3D) -> String:
	if collision == null or not is_instance_valid(collision):
		return "invalid"
	if collision.shape == null:
		return "none"

	var shape := collision.shape
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		return "box:%s" % str(box.size)

	if shape.has_method("get_debug_mesh"):
		var debug_mesh: Variant = shape.call("get_debug_mesh")
		if debug_mesh is Mesh:
			return "%s:%s" % [
				shape.get_class(),
				str((debug_mesh as Mesh).get_aabb())
			]

	return shape.get_class()


func _find_collision_body(node: Node) -> CollisionObject3D:
	var current := node.get_parent()
	while current != null and current != board_root:
		if current is CollisionObject3D:
			return current as CollisionObject3D
		current = current.get_parent()
	return null


func _has_group_in_ancestry(node: Node, group_name: String) -> bool:
	var current: Node = node
	while current != null and current != board_root:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false


func _collision_top_rectangle(shape: Shape3D) -> Dictionary:
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		return {
			"width": box.size.x,
			"depth": box.size.z,
			"center_x": 0.0,
			"center_z": 0.0,
			"top_y": box.size.y * 0.5 + cell_size * 0.01
		}

	# Fallback for other future solid shapes: use the debug mesh bounds.
	# This intentionally creates a rectangular tactical footprint rather than
	# inventing collision geometry that is not actually present.
	if shape.has_method("get_debug_mesh"):
		var debug_mesh: Variant = shape.call("get_debug_mesh")
		if debug_mesh is Mesh:
			var aabb: AABB = debug_mesh.get_aabb()
			if aabb.size.x > 0.001 and aabb.size.z > 0.001:
				return {
					"width": aabb.size.x,
					"depth": aabb.size.z,
					"center_x": aabb.position.x + aabb.size.x * 0.5,
					"center_z": aabb.position.z + aabb.size.z * 0.5,
					"top_y": aabb.position.y + aabb.size.y + cell_size * 0.01
				}

	return {}


func _create_grid_overlay(size: Vector2, offset: Vector3) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()

	var minor_material := _grid_material(
		Color(0.43, 0.69, 0.72, 0.68)
	)
	var major_material := _grid_material(
		Color(0.78, 0.78, 0.59, 0.92)
	)

	var half_x := size.x * 0.5
	var half_z := size.y * 0.5
	var min_x := -half_x
	var max_x := half_x
	var min_z := -half_z
	var max_z := half_z

	var x_start := int(ceil(min_x / cell_size))
	var x_end := int(floor(max_x / cell_size))
	var z_start := int(ceil(min_z / cell_size))
	var z_end := int(floor(max_z / cell_size))

	var minor_vertices: Array[Vector3] = []
	var major_vertices: Array[Vector3] = []

	for x_index in range(x_start, x_end + 1):
		var target := (
			major_vertices
			if posmod(x_index, 5) == 0
			else minor_vertices
		)
		var x := float(x_index) * cell_size
		target.append(Vector3(x, 0.0, min_z))
		target.append(Vector3(x, 0.0, max_z))

	for z_index in range(z_start, z_end + 1):
		var target := (
			major_vertices
			if posmod(z_index, 5) == 0
			else minor_vertices
		)
		var z := float(z_index) * cell_size
		target.append(Vector3(min_x, 0.0, z))
		target.append(Vector3(max_x, 0.0, z))

	if not minor_vertices.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, minor_material)
		for vertex in minor_vertices:
			mesh.surface_add_vertex(vertex)
		mesh.surface_end()

	if not major_vertices.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, major_material)
		for vertex in major_vertices:
			mesh.surface_add_vertex(vertex)
		mesh.surface_end()

	overlay.mesh = mesh
	overlay.position = offset
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return overlay


func _grid_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.set_meta("grid_base_alpha", color.a)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	return material


func _apply_overlay_strength(overlay: MeshInstance3D) -> void:
	if overlay.mesh == null:
		return

	for surface_index in range(overlay.mesh.get_surface_count()):
		var material := overlay.mesh.surface_get_material(surface_index)
		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			var color := standard.albedo_color
			var base_alpha := float(
				standard.get_meta("grid_base_alpha", color.a)
			)
			color.a = base_alpha * _interaction_strength
			standard.albedo_color = color


func _refresh_visibility() -> void:
	var stale: Array = []

	for source in _overlays.keys():
		var overlay: Variant = _overlays[source]
		if (
			not is_instance_valid(source)
			or not is_instance_valid(overlay)
		):
			stale.append(source)
			continue

		var show := _enabled
		if source is CollisionShape3D:
			show = show and not (source as CollisionShape3D).disabled

		(overlay as MeshInstance3D).visible = show

	for source in stale:
		_overlays.erase(source)
		_shape_signatures.erase(source)
