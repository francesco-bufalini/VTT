extends SceneTree
const Combat = preload("res://vtt/combat_basic_actions.gd")
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")

class Board:
	extends Node3D
	var cell_size := 1.0
	var status_calls: Array[Dictionary] = []
	func _set_token_status(target: Node3D, id: String, enabled: bool) -> void:
		status_calls.append({"target": target, "id": id, "enabled": enabled})
	func _sync_explicit_token_change(_target: Node3D = null) -> void:
		pass
	func push_undo_state() -> void:
		pass

class Token:
	extends CharacterBody3D
	func get_reach_feet() -> float:
		return 5.0
	func get_footprint_cells() -> float:
		return 1.0

func _initialize() -> void:
	call_deferred("run")

func _has(rows: Array[Dictionary], name: String, group: int) -> bool:
	for row: Dictionary in rows:
		if row.get("name") == name and int(row.get("time", -1)) == group:
			return true
	return false

func run() -> void:
	assert(ContentCatalog.valid_effect_id("helped"))
	for edition: String in ["2014", "2024"]:
		var definitions: Array[Dictionary] = ContentCatalog.condition_definitions(edition)
		assert(definitions.any(func(v: Dictionary) -> bool: return v.get("id") == "helped"))
		var rows: Array[Dictionary] = Actions.entries({"rules_version": edition, "abilities": {"str": 14, "dex": 16}})
		assert(_has(rows, "Aiutare", 0))
		assert(_has(rows, "Spingere", 0))
		assert(_has(rows, "Buttare prono", 0))
		assert(_has(rows, "Muoversi", 3))
		assert(_has(rows, "Movimento furtivo", 3))
	var modern: Dictionary = Combat.shove_details({"rules_version": "2024"}, 7, 3, 4)
	assert(int(modern.dc) == 15)
	var old: Dictionary = Combat.shove_details({"rules_version": "2014"}, 7, 3, 4)
	assert(int(old.athletics_bonus) == 7 and not old.has("dc"))
	var skills: Array[Dictionary] = Actions.best_skills({"abilities": {"str": 10, "dex": 18, "con": 10, "int": 10, "wis": 10, "cha": 10}})
	assert(skills.size() == 4)
	assert(int(skills[0].bonus) >= int(skills[1].bonus))
	var board := Board.new()
	root.add_child(board)
	var source := Token.new()
	var target := Token.new()
	board.add_child(source)
	board.add_child(target)
	source.global_position = Vector3.ZERO
	target.global_position = Vector3(1, 0, 0)
	assert(Combat.validate(board, source, target, "shove").ok)
	assert(Combat.execute(board, source, target, "help").ok)
	assert(board.status_calls.size() == 1 and board.status_calls[0].id == "helped")
	assert(not Combat.execute(board, source, target, "prone").ok)
	assert(board.status_calls.size() == 1)
	assert(Combat.execute(board, source, target, "prone", true).ok)
	assert(board.status_calls[1].id == "prone")
	target.set_meta("size_name", "Huge")
	assert(not Combat.validate(board, source, target, "shove").ok)
	target.set_meta("size_name", "Medium")
	target.global_position = Vector3(3, 0, 0)
	assert(not Combat.validate(board, source, target, "shove").ok)
	board.queue_free()
	print("PASS: 5e basic combat actions, helped marker, shove resolution and top skill list")
	quit(0)
