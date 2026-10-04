extends StaticBody3D

# Independent item identity: items never join dnd_token.
const MODEL := "res://assets/items/roman_chariot_with_painted_front.glb"

var item_id: String = ""
var linked_token_id: String = ""
var link_offset := Vector3.ZERO
var cell_size: float = 1.0
var _selection_marker: MeshInstance3D


func configure(grid_cell_size: float) -> void:
	cell_size = grid_cell_size
	add_to_group("dnd_item")
	add_to_group("tactical_platform")
	collision_layer = 1 | 4
	collision_mask = 0
	set_meta("sync_id", item_id)
	set_meta("passenger_deck_extent", Vector2.ONE * cell_size * 2.0)

	var scene := load(MODEL) as PackedScene
	if scene != null:
		var visual := scene.instantiate() as Node3D
		# Source deck spans about 1.29 x 1.54 units before its 0.01
		# export transform. Uniform scale preserves wheels and painted front.
		visual.scale = Vector3.ONE * (2.0 / 0.0154) * cell_size
		visual.position = (
			Vector3(-0.00562, 0.0035, 0.0)
			* (2.0 / 0.0154)
			* cell_size
		)
		add_child(visual)

	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 0.06, 2.0) * cell_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -0.03 * cell_size
	add_child(collision)

	_build_selection_marker()
	set_selected(false)


func _build_selection_marker() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.76, 0.12, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.48, 0.04, 1.0)
	material.emission_energy_multiplier = 1.2
	material.no_depth_test = true

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half: float = cell_size * 1.03
	var y: float = cell_size * 0.06
	var points: Array[Vector3] = [
		Vector3(-half, y, -half),
		Vector3(half, y, -half),
		Vector3(half, y, half),
		Vector3(-half, y, half),
	]
	for index: int in range(4):
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[(index + 1) % 4])
	mesh.surface_end()

	_selection_marker = MeshInstance3D.new()
	_selection_marker.name = "ItemSelectionMarker"
	_selection_marker.mesh = mesh
	_selection_marker.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(_selection_marker)


func set_selected(value: bool) -> void:
	if _selection_marker != null and is_instance_valid(_selection_marker):
		_selection_marker.visible = value


func contains_passenger(
	token: CharacterBody3D,
	at_transform: Transform3D
) -> bool:
	var point: Vector3 = at_transform.affine_inverse() * token.global_position
	var bottom: float = (
		point.y
		- float(token.get("token_height_cells")) * cell_size * 0.5
	)
	# Same occupied horizontal cells, with a vertical band to exclude
	# creatures below the deck or flying well above it.
	return (
		absf(point.x) < cell_size
		and absf(point.z) < cell_size
		and bottom > -cell_size * 0.9
		and bottom < cell_size * 0.25
	)


func interact() -> void:
	pass
