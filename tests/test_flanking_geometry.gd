extends SceneTree

const FlankingSystem = preload("res://vtt/flanking_system.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var half := Vector3(0.5, 1.0, 0.5)

	# Touching hitboxes have zero gap; one empty cell between them is 1 world unit.
	assert(is_equal_approx(
		FlankingSystem.aabb_gap_distance_world(
			Vector3.ZERO,
			half,
			Vector3(1.0, 0.0, 0.0),
			half
		),
		0.0
	))
	assert(is_equal_approx(
		FlankingSystem.aabb_gap_distance_world(
			Vector3.ZERO,
			half,
			Vector3(2.0, 0.0, 0.0),
			half
		),
		1.0
	))

	# Two allies on opposite sides produce a segment through the enemy hitbox.
	var valid := FlankingSystem.flanking_segment(
		Vector3(-2.0, 0.0, 0.0),
		half,
		Vector3(2.0, 0.0, 0.0),
		half,
		Vector3.ZERO,
		half
	)
	assert(valid.size() == 2)
	assert(FlankingSystem.segment_intersects_aabb(
		valid[0],
		valid[1],
		Vector3.ZERO,
		half
	))

	# Allies on the same side do not flank a target outside their connecting line.
	var invalid := FlankingSystem.flanking_segment(
		Vector3(-3.0, 0.0, 0.0),
		half,
		Vector3(-1.5, 0.0, 0.0),
		half,
		Vector3.ZERO,
		half
	)
	assert(invalid.is_empty())

	# Opposite diagonal corners are valid under the DMG square-grid rule.
	var diagonal_valid := FlankingSystem.flanking_segment(
		Vector3(-2.0, 0.0, -2.0),
		half,
		Vector3(2.0, 0.0, 2.0),
		half,
		Vector3.ZERO,
		half
	)
	assert(diagonal_valid.size() == 2)
	assert(FlankingSystem.centers_cross_opposite_borders(
		Vector3(-2.0, 0.0, -2.0),
		Vector3(2.0, 0.0, 2.0),
		Vector3.ZERO,
		half
	))

	# Crossing adjacent borders is not flanking, even though the line
	# intersects the target's space.
	assert(not FlankingSystem.centers_cross_opposite_borders(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 2.0),
		Vector3.ZERO,
		half
	))

	# Side-to-corner is deliberately rejected: the DMG requires opposite
	# sides or opposite corners rather than any generic intersection.
	assert(not FlankingSystem.centers_cross_opposite_borders(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 2.0),
		Vector3.ZERO,
		half
	))

	# A diagonal line that misses the target hitbox must not count.
	var miss := FlankingSystem.flanking_segment(
		Vector3(-2.0, 0.0, 2.0),
		half,
		Vector3(2.0, 0.0, 2.0),
		half,
		Vector3.ZERO,
		half
	)
	assert(miss.is_empty())

	print("PASS: flanking follows opposite-side and opposite-corner grid geometry")
	quit()
