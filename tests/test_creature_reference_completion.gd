extends SceneTree

const Archive = preload("res://vtt/creature_archive.gd")

class TestCampaign extends Node:
	var selected_campaign_group_id := "test_reference_completion"
	var active_campaign_id := ""

class TestBoard extends Node3D:
	var board_sync: Node

var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func run() -> void:
	var campaign := TestCampaign.new()
	campaign.selected_campaign_group_id += "_%d" % Time.get_ticks_usec()
	root.add_child(campaign)
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	check(area._current_miniature.get_parent() != null and not area._current_miniature.visible,
		"Hidden appearance caption must have a parent to be freed with the sheet")
	area._archive.setup(campaign)
	var full_stat := {"name": "Ape", "source": "MM", "hp": {"average": 19}, "ac": [12]}
	for bonus: int in [0, 5]:
		var pending: Dictionary = area._archive.create_monster({"name": "Ape", "reference_pending": true})
		pending["max_hp_bonus"] = bonus
		check(area._archive.save(pending) == OK, "Pending sheet save failed")
		area._complete_auto_reference(String(pending.id), full_stat)
		var stored: Dictionary = area._archive._stored("monster", String(pending.id))
		check(stored.max_hp_base == 19 and stored.max_hp == 19 + bonus, "Bestiary completion lost base HP or bonus")
		check(stored.current_hp == 19 + bonus, "Bestiary completion left inconsistent current HP")
		check(not stored.stat_block.has("reference_pending"), "Reference remains pending after completion")
	var edited: Dictionary = area._archive.create_monster({"name": "Ape", "reference_pending": true})
	edited["max_hp_base"] = 7
	edited["max_hp_bonus"] = 3
	edited["current_hp"] = 5
	check(area._archive.save(edited) == OK, "Edited sheet save failed")
	area._complete_auto_reference(String(edited.id), full_stat)
	var preserved: Dictionary = area._archive._stored("monster", String(edited.id))
	check(preserved.max_hp_base == 7 and preserved.max_hp == 10 and preserved.current_hp == 5, "Reference overwrote explicit HP edits")
	for store in [area._archive._characters, area._archive._monsters]:
		if FileAccess.file_exists(store._file_path()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(store._file_path()))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	await process_frame
	if not failed:
		print("PASS: bestiary completion persists base HP, bonuses, current HP and user edits")
	quit(1 if failed else 0)