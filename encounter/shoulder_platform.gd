extends AnimatableBody3D

@export var height_meters: float = 120.0
@export var width_meters: float = 30.0
@export var depth_meters: float = 12.0
var _head_floor: CollisionShape3D

func setup(distance_tool: Node) -> void:
	add_to_group("tactical_platform")
	# Tokens transport explicitly in the platform grid frame; no double velocity.
	constant_linear_velocity = Vector3.ZERO
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	position.y = distance_tool.meters_to_world(height_meters)
	var size := Vector2(distance_tool.meters_to_world(width_meters), distance_tool.meters_to_world(depth_meters))
	var gap: float = distance_tool.meters_to_world(4.0)
	_head_floor = CollisionShape3D.new()
	var head_shape := BoxShape3D.new()
	head_shape.size = Vector3(gap*2,0.4,size.y)
	_head_floor.shape = head_shape
	_head_floor.position.y = -.2
	_head_floor.disabled = true
	add_child(_head_floor)
	for side in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x * 0.5 - gap, 0.4, size.y)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(side * (size.x * 0.5 + gap) * 0.5, -0.2, 0)
		add_child(collision)
	# SurfaceGrid creates one overlay for each enabled solid collision.

func open_head_space(enabled: bool) -> void:
	_head_floor.set_deferred("disabled", not enabled)
