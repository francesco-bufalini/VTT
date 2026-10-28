extends SceneTree
class MemoryArchive:
	extends RefCounted
	var records: Array[Dictionary] = []
	var saves := 0
	func list_owned() -> Array[Dictionary]:
		return records.duplicate(true)
	func save(record: Dictionary) -> Error:
		records.assign([record.duplicate(true)])
		saves += 1
		return OK

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	var token_scene := load("res://token.tscn")
	var hero: CharacterBody3D = token_scene.instantiate()
	var selected: CharacterBody3D = token_scene.instantiate()
	board.tokens_root.add_child(hero)
	board.tokens_root.add_child(selected)
	hero.position = Vector3(3.5, 5, 3.5)
	selected.position = Vector3(10.5, 5, 10.5)
	hero.set_meta("creature_owner_id", "foreign-mobile-owner")
	hero.set_meta("creature_id", "remote-character")
	board._selected_tokens.assign([selected])
	var selected_position := selected.global_position
	var origin := hero.global_position
	assert(board.nudge_token_from_mobile(hero, Vector3i(1, 0, 0)))
	assert(is_equal_approx(hero.global_position.x, origin.x + board.cell_size))
	assert(selected.global_position == selected_position and board._selected_tokens == [selected])
	assert(board.nudge_token_from_mobile(hero, Vector3i(0, 1, 0)))
	assert(hero.global_position.y > origin.y)
	board._set_token_status(hero, "poisoned", true)
	assert(hero.has_condition("poisoned"), "Board must set conditions on foreign-owned tokens")
	var sheet: Node = load("res://vtt/creature_area.gd").new()
	root.add_child(sheet)
	var archive := MemoryArchive.new()
	var token_id: String = board.board_sync.get_sync_id_for_node(hero)
	archive.records.assign([{"id": "remote-character", "linked_token_sync_id": token_id,
		"conditions": [], "private_note": "preserve", "owner_id": "mobile-owner"}])
	sheet._archive = archive
	sheet._touch_layout = true
	var public: Dictionary = board.board_sync.get_tactical_map_data()
	sheet._sync_mobile_map_status(public)
	assert(archive.records[0].conditions.has("poisoned") and archive.records[0].private_note == "preserve")
	var saves := archive.saves
	sheet._sync_mobile_map_status(public)
	assert(archive.saves == saves, "Polling unchanged conditions must not write repeatedly")
	board._set_token_status(hero, "poisoned", false)
	sheet._sync_mobile_map_status(board.board_sync.get_tactical_map_data())
	assert(not archive.records[0].conditions.has("poisoned"))
	board._token_profiles.append({"id": "test-mobile-base", "footprint": 1.0, "size_name": "Medium"})
	board._token_profiles.append({"id": "test-mobile-form", "footprint": 2.0, "size_name": "Large"})
	hero.set_meta("default_miniature_id", "test-mobile-base")
	hero.set_token_pack_id("test-mobile-form")
	hero.set_reach_feet(10)
	var rejected: Dictionary = await board.board_sync._handle_mobile_action("set_appearance", {"token_id": token_id, "owner_id": "wrong", "miniature_id": "test-mobile-base"})
	assert(not rejected.ok and hero.get_token_pack_id() == "test-mobile-form")
	var restored: Dictionary = await board.board_sync._handle_mobile_action("set_appearance", {"token_id": token_id, "owner_id": "foreign-mobile-owner", "miniature_id": "test-mobile-base"})
	assert(restored.ok and hero.get_token_pack_id() == "test-mobile-base")
	assert(hero.get_reach_feet() == 10, "Appearance must preserve combat properties")
	# Colpisci directly marks a target; no roll result or success flag exists.
	var victim_id: String = board.board_sync.get_sync_id_for_node(selected)
	var hit_payload := {"token_id": token_id, "target_id": victim_id,
		"owner_id": "foreign-mobile-owner",
		"attack_id": "class_feature:thunder_gauntlets", "attack_name": "Thunder Gauntlets",
		"effects": [{"trigger": "on_hit", "operation": "roll_mode", "target": "attack_roll",
			"mode": "disadvantage", "duration": "until_start_of_next_turn",
			"condition_label": "Attacchi contro creature diverse dall'Artefice"}]}
	var unauthorized: Dictionary = await board.board_sync._handle_mobile_action(
		"hit_attack", hit_payload.merged({"owner_id": "wrong-owner"}, true))
	assert(not unauthorized.ok, "Only the controlling token owner can apply a hit")
	var hit_result: Dictionary = await board.board_sync._handle_mobile_action("hit_attack", hit_payload)
	assert(hit_result.ok and hit_result.effects_applied == 1,
		"The target accepts a hit with structured effect but no dice")
	var projected_target: Dictionary = {}
	for row: Dictionary in board.board_sync.get_tactical_map_data().tokens:
		if String(row.id) == victim_id:
			projected_target = row
			break
	var marks: Array = projected_target.get("hit_effects", [])
	assert(marks.size() == 1 and String(marks[0].get("mode", "")) == "disadvantage",
		"On-hit effects are visible on all shared tokens, including unowned monsters")
	# Repeated hits refresh their own mark, never stack duplicates.
	var repeated_hit: Dictionary = await board.board_sync._handle_mobile_action("hit_attack", hit_payload)
	assert(bool(repeated_hit.get("ok", false)))
	assert((selected.get_meta("attack_hit_effects", []) as Array).size() == 1)
	var ordinary: Dictionary = await board.board_sync._handle_mobile_action("hit_attack",
		{"token_id": token_id, "target_id": victim_id,
		 "owner_id": "foreign-mobile-owner", "attack_id": "unarmed",
		 "attack_name": "Colpo senz'armi", "effects": []})
	assert(ordinary.ok and ordinary.effects_applied == 0,
		"Every attack can hit a token, even with no additional effect")

	var alias_result: Dictionary = await board.board_sync._handle_mobile_action("set_appearance", {"token_id": token_id, "owner_id": "foreign-mobile-owner", "miniature_id": "test-mobile-base", "display_name": "Alias della creatura"})
	assert(alias_result.ok and hero.get_display_name() == "Alias della creatura")
	assert(hero.get_meta("creature_id") == "remote-character" and hero.get_meta("creature_owner_id") == "foreign-mobile-owner")
	assert(hero.get_reach_feet() == 10)

	sheet._sync_mobile_map_status(board.board_sync.get_tactical_map_data())
	assert(archive.records[0].current_miniature_id == "test-mobile-base")
	hero.set_token_pack_id("test-mobile-form")
	sheet._sync_mobile_map_status(board.board_sync.get_tactical_map_data())
	assert(archive.records[0].current_miniature_id == "test-mobile-form" and archive.records[0].default_miniature_id == "test-mobile-base")
	assert(archive.records[0].private_note == "preserve")
	hero.set_party_id("Culto del Drago")
	hero.set_size_category("Large", 2.0, false)
	var projected: Dictionary = {}
	for row: Dictionary in board.board_sync.get_tactical_map_data().tokens:
		if String(row.id) == token_id:
			projected = row
			break
	assert(projected.get("party_id") == "Culto del Drago")
	assert(projected.get("size_name") == "Large")
	assert(is_equal_approx(float(projected.get("footprint_cells", 0)), 2.0))
	assert(projected.get("conditions") is Array)
	print("PASS: mobile projection includes live faction, size and footprint")
	print("PASS: mobile appearance restore, ownership, combat preservation and desktop appearance polling")
	print("PASS: production movement, unchanged desktop selection, foreign conditions and private mobile sheet sync")
	sheet.queue_free()
	board.queue_free()
	await process_frame
	quit()
