extends Node3D

var _positions: Array[Vector3] = []
var _tween: Tween
var footprint_world: Vector2
var height_world: float
var climb: Node
var motion: Node

func configure_positions(markers: Node3D, distance_tool: Node3D) -> void:
	climb = preload("res://encounter/kaos_climb.gd").new()
	climb.name = "ClimbController"
	add_child(climb)
	motion = preload("res://encounter/kaos_motion.gd").new()
	add_child(motion)
	motion.setup($KaosVisual,distance_tool.meters_to_world(1),$ShoulderPlatform)
	footprint_world = Vector2(distance_tool.meters_to_world(30), distance_tool.meters_to_world(24))
	height_world = distance_tool.meters_to_world(150)
	_positions.clear()
	for index in range(11):
		var marker := markers.get_node("KaosPosition_%02d" % index) as Marker3D
		marker.position = Vector3(0, 0, distance_tool.meters_to_world(12.0 + 15.0 * index))
		_positions.append(marker.global_position)
	# Prepare geometry during scene loading, not in the middle of the final advance.
	climb.prepare()

func snap_to_step(step: int) -> void:
	climb.reset_pose()
	motion.reset()
	if _tween != null:
		_tween.kill()
	global_position = _positions[clampi(step, 0, 10)]

func animate_to_step(step: int, duration: float, round_index: int = 1) -> void:
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_parallel(true)
	var phase := float((round_index-1)%2)
	_tween.tween_method(motion.set_stride,phase,phase+1.0,duration)
	_tween.tween_property(self, "global_position", _positions[clampi(step, 0, 10)], duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished

func get_swept_bounds(from_step: int, to_step: int) -> AABB:
	var first := _positions[clampi(from_step, 0, 10)]
	var last := _positions[clampi(to_step, 0, 10)]
	return AABB(Vector3(first.x - footprint_world.x * 0.5, first.y, minf(first.z, last.z) - footprint_world.y * 0.5), Vector3(footprint_world.x, height_world, absf(first.z - last.z) + footprint_world.y))
