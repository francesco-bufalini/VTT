extends Node3D

var cell_size: float = 1.0
var _threats: MultiMeshInstance3D
var _rubble: MultiMeshInstance3D
var _craters: MultiMeshInstance3D
var _falling: MultiMeshInstance3D
var _fall_tween: Tween
var _obstacle_boxes: Array[AABB] = []
var _debris_body: StaticBody3D
var _shapes: Array[BoxShape3D] = []
var _last_collapsed_count: int = -1
var _last_seed: int = -1

func setup(size: float) -> void:
	cell_size = size
	_threats = _batch("ThreatenedCells", Color(0.95, 0.24, 0.06, 0.65), Vector3(0.94, 0.025, 0.94), true)
	_craters = _batch("CollapsedCells", Color(0.025, 0.025, 0.028), Vector3(0.98, 0.025, 0.98))
	_rubble = _batch("PersistentRubble", Color(0.48, 0.50, 0.48), Vector3.ONE)
	_falling = _batch("FallingSlabs", Color(0.72, 0.73, 0.70), Vector3.ONE)
	_debris_body = StaticBody3D.new()
	_debris_body.name = "DebrisCollision"
	_debris_body.collision_layer = 1
	_debris_body.collision_mask = 0
	add_child(_debris_body)
	for height in range(1, 21):
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.95, height, 0.95) * cell_size
		_shapes.append(shape)

func _batch(label: String, color: Color, size: Vector3, emissive: bool = false) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	if color.a < 1:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = emissive
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = 0.55
	var mesh := BoxMesh.new()
	mesh.size = size * cell_size
	mesh.material = material
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = mesh
	add_child(batch)
	return batch

func _place(batch: MultiMeshInstance3D, cells: Array[Vector2i], rubble: bool = false) -> void:
	batch.multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		var cell := cells[i]
		var center := Vector3(cell.x + 0.5, 0.035, cell.y + 0.5) * cell_size
		var rubble_basis := Basis.IDENTITY
		if rubble:
			# Geometry depends on the cell, never on the hazard RNG or animation.
			var angle := float(posmod(cell.x * 17 + cell.y * 31, 100)) * 0.0628
			rubble_basis = Basis.from_euler(Vector3(0.3, angle, 0.2))
			center.y = 0.10 * cell_size
		batch.multimesh.set_instance_transform(i, Transform3D(rubble_basis, center))

func rebuild(hazards: Node, animate_objects: bool = false) -> void:
	_place(_threats, hazards.threatened_cells)
	_place(_craters, hazards.collapsed_cells)
	if _last_collapsed_count != hazards.collapsed_cells.size() or _last_seed != hazards.rng.seed:
		_last_collapsed_count = hazards.collapsed_cells.size()
		_last_seed = hazards.rng.seed
		_build_debris(hazards)
	for object in get_tree().get_nodes_in_group("encounter_obstacle"):
		object.update_collapse(hazards, animate_objects)
	if hazards.collapsed_cells.is_empty():
		if _fall_tween != null:
			_fall_tween.kill()
		_falling.visible = false

func stop_effects() -> void:
	_last_collapsed_count = -1
	if _fall_tween != null:
		_fall_tween.kill()
	_falling.visible = false

func animate_collapse(cells: Array[Vector2i]) -> void:
	if _fall_tween != null:
		_fall_tween.kill()
	_falling.multimesh.instance_count = cells.size()
	for index in range(cells.size()):
		var cell := cells[index]
		var height := 2.0 + posmod(cell.x * 17 + cell.y * 31, 7)
		var size := Vector3(0.85, height, 0.85)
		_falling.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(size), Vector3(cell.x + 0.5, height * 0.5, cell.y + 0.5) * cell_size))
	_falling.position.y = cell_size * 32
	_falling.visible = true
	_fall_tween = create_tween()
	_fall_tween.tween_property(_falling, "position:y", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_callback(func(): _falling.visible = false)

func _build_debris(hazards: Node) -> void:
	_obstacle_boxes.clear()
	PhysicsServer3D.body_clear_shapes(_debris_body.get_rid())
	_rubble.multimesh.instance_count = hazards.collapsed_cells.size()
	for index in range(hazards.collapsed_cells.size()):
		var cell: Vector2i = hazards.collapsed_cells[index]
		var value := posmod(cell.x * 73856093 ^ cell.y * 19349663 ^ int(hazards.rng.seed), 10000)
		var height: int = 1
		if value < hazards.config.tall_debris_fraction * 10000:
			height = 4 + posmod(value, maxi(1, hazards.config.debris_max_height_cells - 3))
		var center := Vector3(cell.x + 0.5, height * 0.5, cell.y + 0.5) * cell_size
		var size := Vector3(0.95, height, 0.95) * cell_size
		_rubble.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(size / cell_size), center))
		_obstacle_boxes.append(AABB(center - size * 0.5, size))
		PhysicsServer3D.body_add_shape(_debris_body.get_rid(), _shapes[height - 1].get_rid(), Transform3D(Basis.IDENTITY, center))

func get_obstacle_boxes() -> Array[AABB]:
	var result: Array[AABB] = _obstacle_boxes.duplicate()
	for object in get_tree().get_nodes_in_group("encounter_obstacle"):
		if not object.collapsed:
			result.append(object.get_world_bounds())
	return result
