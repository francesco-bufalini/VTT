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
	print("PASS: production movement, unchanged desktop selection, foreign conditions and private mobile sheet sync")
	sheet.queue_free()
	board.queue_free()
	await process_frame
	quit()
