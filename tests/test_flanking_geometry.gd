extends SceneTree

const FlankingSystem = preload("res://vtt/flanking_system.gd")
const TokenScene = preload("res://token.tscn")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Frequent condition badge polls must be trivial for clean tokens.
	var clean_token: CharacterBody3D = TokenScene.instantiate()
	assert(clean_token.get_active_condition_display_parts().is_empty())
	assert(clean_token.get_condition_presentations().is_empty())
	clean_token.free()
	# Public condition definitions must not let one caller mutate the cache.
	var condition_rows: Array[Dictionary] = ContentCatalog.condition_definitions("2014")
	if not condition_rows.is_empty():
		var first_name: String = String(condition_rows[0].get("name", ""))
		condition_rows[0]["name"] = "TEST MUTATION"
		assert(String(ContentCatalog.condition_definitions("2014")[0].get("name", "")) == first_name)
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

	# Small vertical/base offsets must not switch reach to continuous AABB
	# distance. With one full square between two Medium bases the tactical
	# distance remains 10 ft even if one legacy token sits slightly higher.
	assert(FlankingSystem.bases_share_tactical_plane(0.0, 0.15, 1.0))
	assert(not FlankingSystem.bases_share_tactical_plane(0.0, 0.55, 1.0))
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3(0.0, 1.0, 0.0),
			half,
			Vector3(2.0, 1.15, 0.0),
			half,
			1.0
		),
		10.0
	))
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3(0.0, 1.0, 0.0),
			half,
			Vector3(1.0, 1.15, 1.0),
			half,
			1.0
		),
		5.0
	))

	# Regression: immediately after spawning, token bases can be on
	# different elevations (before placement/physics stabilizes). A full
	# empty square between two Medium tokens must still be 10 ft, not the
	# 5 ft physical gap between their hitbox edges.
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3(0.5, 1.0, 0.5),
			half,
			Vector3(2.5, 2.0, 0.5),
			half,
			1.0
		),
		10.0
	))
	# Adjacent squares remain in 5 ft reach at different elevations.
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3(0.5, 1.0, 0.5),
			half,
			Vector3(1.5, 2.0, 0.5),
			half,
			1.0
		),
		5.0
	))
	# An entirely empty vertical cell between two hitboxes is also 10 ft.
	assert(is_equal_approx(
		FlankingSystem.tactical_reach_distance_feet(
			Vector3(0.5, 1.0, 0.5),
			half,
			Vector3(0.5, 4.0, 0.5),
			half,
			1.0
		),
		10.0
	))


	# Tiny still occupies a full square; adjacent Tiny creatures have 5 ft
	# reach just like Medium ones. Larger footprints are measured edge-to-edge.
	var tiny := TokenScene.instantiate()
	root.add_child(tiny)
	tiny.call("set_token_size", 0.5)
	var tiny_half: Vector3 = FlankingSystem.token_half_extents_world(tiny, 1.0)
	assert(is_equal_approx(tiny_half.x, 0.5))
	assert(is_equal_approx(FlankingSystem.grid_reach_distance_feet(
		Vector3.ZERO, tiny_half, Vector3(1.0, 0.0, 0.0), tiny_half, 1.0
	), 5.0))
	var huge := TokenScene.instantiate()
	root.add_child(huge)
	huge.call("set_size_category", "Huge", 3.0, true)
	assert(is_equal_approx(float(huge.call("get_reach_feet")), 5.0),
		"Footprint alone must not increase melee reach")
	var legacy_state: Dictionary = huge.call("get_appearance_state")
	legacy_state["reach_feet"] = 15.0
	legacy_state["reach_overridden"] = false
	assert(bool(huge.call("apply_appearance_state", legacy_state)))
	assert(is_equal_approx(float(huge.call("get_reach_feet")), 5.0),
		"Legacy size-derived reach must not persist after reload")
	var huge_half: Vector3 = FlankingSystem.token_half_extents_world(huge, 1.0)
	assert(is_equal_approx(huge_half.x, 1.5))
	assert(is_equal_approx(FlankingSystem.grid_reach_distance_feet(
		Vector3.ZERO, huge_half, Vector3(2.0, 0.0, 0.0), half, 1.0
	), 5.0))
	assert(FlankingSystem.flanking_segment(
		Vector3(-2.0, 0.0, 0.0), half,
		Vector3(2.0, 0.0, 0.0), half,
		Vector3.ZERO, huge_half
	).size() == 2)
	tiny.queue_free()
	huge.queue_free()

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

	# Shared tactical badge keeps Affiancato and named conditions in one
	# comma-separated popup, while perspective scaling shrinks with distance.
	var badge_conditions := PackedStringArray([
		"☠️ Avvelenato",
		"⛓️ Trattenuto",
	])
	assert(
		FlankingSystem.compose_status_badge_text(
			true,
			badge_conditions
		)
		== "⚔ Affiancato, ☠️ Avvelenato, ⛓️ Trattenuto"
	)
	var near_badge_scale := FlankingSystem.perspective_badge_scale(
		90.0,
		30.0
	)
	var far_badge_scale := FlankingSystem.perspective_badge_scale(
		24.0,
		30.0
	)
	assert(far_badge_scale < near_badge_scale)

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

	# Reach indicators exist only between enemy parties. Blank party values
	# normalize to Default, so two unassigned tokens are allies.
	assert(not FlankingSystem.party_keys_are_enemies("Eroi", "eroi"))
	assert(not FlankingSystem.party_keys_are_enemies("", "Default"))
	assert(FlankingSystem.party_keys_are_enemies("Eroi", "Nemici"))

	# Flankers only need to be enemies of the target. They may belong to
	# different parties from one another.
	assert(FlankingSystem.flankers_are_hostile_to_target(
		"Eroi",
		"Mercenari",
		"Cultisti"
	))
	assert(not FlankingSystem.flankers_are_hostile_to_target(
		"Eroi",
		"Cultisti",
		"Cultisti"
	))
	assert(not FlankingSystem.flankers_are_hostile_to_target(
		"Cultisti",
		"Eroi",
		"Cultisti"
	))

	# Reciprocal adjacent reach is rendered once as a compact ↔ marker,
	# rather than as two overlapping directional arrows.
	assert(FlankingSystem.should_use_mutual_adjacent_marker(
		true,
		true,
		5.0
	))
	assert(not FlankingSystem.should_use_mutual_adjacent_marker(
		true,
		false,
		5.0
	))
	assert(not FlankingSystem.should_use_mutual_adjacent_marker(
		true,
		true,
		10.0
	))
	var mutual_marker := FlankingSystem.mutual_reach_marker_segment(
		Vector3.ZERO,
		half,
		Vector3(1.0, 0.0, 0.0),
		half,
		1.0
	)
	assert(mutual_marker.size() == 2)
	assert(is_equal_approx(mutual_marker[0].y, mutual_marker[1].y))
	assert(mutual_marker[0].z > 0.0)
	assert(mutual_marker[1].z > 0.0)
	assert(absf(mutual_marker[0].distance_to(mutual_marker[1]) - 0.44) < 0.001)

	# Reach uses a flat directional vector from the source base to the target
	# base; the renderer now applies this to every in-range directed pair.
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


	# A line through the flankers' centres would miss; the occupied volumes
	# contain points connected across both opposite X faces.
	assert(FlankingSystem.flanking_segment(
		Vector3(-2.0, 0.0, 1.1), Vector3(0.5, 1.0, 1.0),
		Vector3(2.0, 0.0, 1.1), Vector3(0.5, 1.0, 1.0),
		Vector3.ZERO, half
	).size() == 2, "Flanking must use any points within both occupied volumes")

	# Facing one another above the target is not flanking in 3D.
	assert(FlankingSystem.flanking_segment(
		Vector3(-2.0, 3.0, 0.0), half,
		Vector3(2.0, 3.0, 0.0), half,
		Vector3.ZERO, half
	).is_empty(), "A horizontal projection must not ignore elevation")

	# The top and bottom count as opposing faces, including a tall target.
	assert(FlankingSystem.flanking_segment(
		Vector3(0.0, -3.0, 0.0), half,
		Vector3(0.0, 3.0, 0.0), half,
		Vector3.ZERO, Vector3(1.5, 2.0, 1.5)
	).size() == 2, "Vertical flanking must cross both height faces")

	# The new volume-to-volume rule can flank even in an L formation:
	# offset points inside both footprints cross the target on opposite faces.
	assert(FlankingSystem.flanking_segment(
		Vector3(1.0, 0.0, 1.0), half,
		Vector3(0.0, 0.0, -1.0), half,
		Vector3.ZERO, half
	).size() == 2, "Do not restrict flanking to miniature centres")

	# A pair confined to one side cannot create an opposing-face crossing.
	assert(FlankingSystem.flanking_segment(
		Vector3(2.0, 0.0, 0.0), half,
		Vector3(3.0, 0.0, 0.0), half,
		Vector3.ZERO, half
	).is_empty())

	# The first melee attack wins even when later ones have longer reach;
	# explicit per-attack range overrides apply immediately.
	var monster := {
		"kind": "monster",
		"stat_block": {
			"action": [
				{"name": "Tiro", "entries": ["{@atk rw} {@hit 4} range 100 ft."]},
				{"name": "Spada", "entries": ["{@atk mw} {@hit 4} reach 10 ft."]},
				{"name": "Tentacolo", "entries": ["{@atk mw} {@hit 4} reach 15 ft."]}
			]
		}
	}
	assert(is_equal_approx(AttackData.first_melee_range(monster), 10.0))
	monster["attack_overrides"] = {"monster:action:1": {"range_feet": 20}}
	assert(is_equal_approx(AttackData.first_melee_range(monster), 20.0))
	assert(is_equal_approx(AttackData.first_melee_range({"kind": "character"}), 5.0))
	print("PASS: volume-based 3D flanking and first melee reach")
	quit()
