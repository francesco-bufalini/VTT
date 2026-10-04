extends SceneTree

const AttackSystem = preload("res://vtt/attack_system.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var center := Vector3.ZERO
	var footprint := 1.0

	# One-cell attacker: range originates at x/z = ±0.5, not at the centre.
	assert(is_equal_approx(
		AttackSystem.distance_from_footprint_to_point_world(
			center,
			footprint,
			Vector3(1.0, 0.0, 0.0)
		),
		0.5
	))
	assert(is_equal_approx(
		AttackSystem.distance_from_footprint_to_point_world(
			center,
			footprint,
			Vector3(2.0, 0.0, 0.0)
		),
		1.5
	))

	# Diagonal distance starts at the footprint corner.
	var diagonal := AttackSystem.distance_from_footprint_to_point_world(
		center,
		footprint,
		Vector3(1.0, 0.0, 1.0)
	)
	assert(is_equal_approx(
		diagonal,
		sqrt(0.5 * 0.5 + 0.5 * 0.5)
	))

	# Points vertically above the footprint keep the old 3D vertical distance.
	assert(is_equal_approx(
		AttackSystem.distance_from_footprint_to_point_world(
			center,
			footprint,
			Vector3(0.0, 2.0, 0.0)
		),
		2.0
	))

	# Larger creatures start range at the outer edge of their larger footprint.
	assert(is_equal_approx(
		AttackSystem.distance_from_footprint_to_point_world(
			center,
			2.0,
			Vector3(2.0, 0.0, 0.0)
		),
		1.0
	))

	print("PASS: weapon range starts from token footprint sides and corners")
	quit()
