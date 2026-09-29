extends StaticBody3D

@export var size_cells: Vector3 = Vector3(6, 8, 6)
@export var cell_size: float = 1.0
@export var collapsible: bool = true
var collapsed: bool = false
var _visual: MeshInstance3D
var _shape: CollisionShape3D
var _tween: Tween

func _ready() -> void:
	add_to_group("encounter_obstacle")
	collision_layer = 1
	collision_mask = 0
	var box := BoxMesh.new()
	box.size = size_cells * cell_size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.63, 0.62)
	box.material = material
	_visual = MeshInstance3D.new()
	_visual.mesh = box
	_visual.position.y = box.size.y * 0.5
	add_child(_visual)
	var shape := BoxShape3D.new()
	shape.size = box.size
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position = _visual.position
	add_child(_shape)

func get_world_bounds() -> AABB:
	var size := size_cells * cell_size
	return global_transform * AABB(Vector3(-size.x * 0.5, 0, -size.z * 0.5), size)

func update_collapse(hazards: Node, animate: bool) -> void:
	if not collapsible:
		return
	var box := get_world_bounds()
	var should_collapse := false
	for cell: Vector2i in hazards.collapsed_cells:
		var point: Vector2 = Vector2(cell.x + 0.5, cell.y + 0.5) * hazards.cell_size
		if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).has_point(point):
			should_collapse = true
			break
	if should_collapse == collapsed:
		return
	collapsed = should_collapse
	_shape.disabled = collapsed
	if _tween != null:
		_tween.kill()
	var target_scale := Vector3(1.2, 0.08, 1.2) if collapsed else Vector3.ONE
	var target_y := size_cells.y * cell_size * (0.04 if collapsed else 0.5)
	if animate and collapsed:
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_visual, "scale", target_scale, 0.7)
		_tween.tween_property(_visual, "position:y", target_y, 0.7)
	else:
		_visual.scale = target_scale
		_visual.position.y = target_y
