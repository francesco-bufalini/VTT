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

	# Grid reach counts occupied spaces, not continuous empty-edge distance.
	# Adjacent Medium bases are 5 ft apart; one whole empty square is 10 ft.
	assert(is_equal_approx(
		FlankingSystem.grid_reach_distance_feet(
			Vector3.ZERO,
			half,
			Vector3(1.0, 0.0, 0.0),
			half,
			1.0
		),
		5.0
	))
	assert(is_equal_approx(
		FlankingSystem.grid_reach_distance_feet(
			Vector3.ZERO,
			half,
			Vector3(2.0, 0.0, 0.0),
			half,
			1.0
		),
		10.0
	))
	assert(is_equal_approx(
		FlankingSystem.grid_reach_distance_feet(
			Vector3.ZERO,
			half,
			Vector3(1.0, 0.0, 1.0),
			half,
			1.0
		),
		5.0
	))

	# Tactical reach used by opportunity attacks has the same diagonal rule:
	# moving between orthogonal and diagonal adjacency stays within 5 ft.
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3.ZERO,
			half,
			Vector3(1.0, 0.0, 0.0),
			half,
			1.0
		),
		5.0
	))
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3.ZERO,
			half,
			Vector3(1.0, 0.0, 1.0),
			half,
			1.0
		),
		5.0
	))

	# Same-plane line geometry is projected down to the miniature bases.
	var projected := FlankingSystem.project_centers_to_shared_base(
		Vector3(-1.0, 1.0, 0.0),
		half,
		Vector3(1.0, 1.0, 0.0),
		half,
		Vector3(0.0, 1.0, 0.0),
		half,
		0.08,
		0.03
	)
	assert(projected.size() == 3)
	assert(is_equal_approx(projected[0].y, 0.03))
	assert(is_equal_approx(projected[1].y, 0.03))
	assert(is_equal_approx(projected[2].y, 0.03))

	# Flanking remains mechanically active regardless of selection, but its
	# visual relationship is contextual: any one of the three tokens is enough.
	assert(not FlankingSystem.flanking_relationship_visible(false, false, false))
	assert(FlankingSystem.flanking_relationship_visible(true, false, false))
	assert(FlankingSystem.flanking_relationship_visible(false, true, false))
	assert(FlankingSystem.flanking_relationship_visible(false, false, true))

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

	# Strict DMG square-grid handling restored: diagonal + side ("L")
	# arrangements do not qualify. Only opposite sides/corners do.
	assert(not FlankingSystem.centers_form_flanking_pair(
		Vector3(1.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3.ZERO,
		half
	))
	assert(not FlankingSystem.centers_form_flanking_pair(
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3.ZERO,
		half
	))
	assert(not FlankingSystem.centers_form_flanking_pair(
		Vector3(0.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3.ZERO,
		half
	))

	assert(not FlankingSystem.centers_cross_opposite_borders(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 2.0),
		Vector3.ZERO,
		half
	))

	# The visual replacement is two directional arrows converging on target.
	var arrow := FlankingSystem.flanking_arrow_segment(
		Vector3(-1.0, 0.03, 0.0),
		half,
		Vector3(0.0, 0.03, 0.0),
		half,
		1.0
	)
	assert(arrow.size() == 2)
	assert(is_equal_approx(arrow[0].y, arrow[1].y))
	assert(is_equal_approx(arrow[0].y, 0.048))
	assert(
		arrow[1].distance_to(Vector3(0.0, 0.048, 0.0))
		< arrow[0].distance_to(Vector3(0.0, 0.048, 0.0))
	)

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
