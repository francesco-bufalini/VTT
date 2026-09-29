extends "res://token.gd"

var deck: AnimatableBody3D

func setup_chariot(template_grid: MeshInstance3D) -> void:
	configure(Color(.72,.61,.35),cell_size,"Large",2.0)
	for child in visuals.get_children():
		child.hide()
	visuals.scale = Vector3.ONE*cell_size
	var model: Node3D = preload("res://encounter/assets/characters/pegasus_chariot.glb").instantiate()
	model.position.y = -1
	visuals.add_child(model)
	collision_shape.shape.size = Vector3(2,2,4)*cell_size
	selection_marker.scale.z = 4
	deck = AnimatableBody3D.new()
	deck.name = "ChariotDeck"
	deck.collision_layer = 4
	deck.collision_mask = 0
	deck.sync_to_physics = false
	deck.add_to_group("tactical_platform")
	deck.set_meta("passenger_deck_extent",Vector2(2,2)*cell_size)
	add_child(deck)
	deck.position = Vector3(0,-.35,1)*cell_size
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2,.12,2)*cell_size
	collider.shape = shape
	collider.position.y = -.06*cell_size
	deck.add_child(collider)
	add_collision_exception_with(deck)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)*cell_size
	var material: ShaderMaterial = template_grid.mesh.material.duplicate()
	material.shader = material.shader.duplicate()
	material.shader.code = material.shader.code.replace("grid_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;","grid_pos = VERTEX.xz;")
	material.set_shader_parameter("cell_size",cell_size)
	material.set_shader_parameter("interaction_strength",1.0)
	material.set_shader_parameter("shoulder_gap",0.0)
	plane.material = material
	var grid := MeshInstance3D.new()
	grid.name = "ChariotGrid"
	grid.mesh = plane
	grid.position.y = .01*cell_size
	deck.add_child(grid)
	set_meta("compound_chariot",true)
	process_physics_priority = -10

func _carry_passengers() -> void:
	if not is_instance_valid(deck):
		return
	for passenger in get_tree().get_nodes_in_group("dnd_token"):
		if passenger != self and passenger.grid_support == deck and not passenger.flying:
			passenger.global_position = deck.global_transform*(passenger._support_transform.affine_inverse()*passenger.global_position)
			passenger._support_transform = deck.global_transform
			passenger.velocity = Vector3.ZERO

func nudge_vertical(steps: int) -> void:
	super.nudge_vertical(steps)
	_carry_passengers()

func nudge_grid(direction: Vector2i) -> void:
	super.nudge_grid(direction)
	_carry_passengers()

func rotate_grid(turns: int) -> void:
	super.rotate_grid(turns)
	_carry_passengers()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_carry_passengers()

func get_footprint_extent() -> Vector2:
	return Vector2(2,4)*cell_size

func get_movement_exclusions() -> Array[RID]:
	return [get_rid(),deck.get_rid()] if is_instance_valid(deck) else [get_rid()]
