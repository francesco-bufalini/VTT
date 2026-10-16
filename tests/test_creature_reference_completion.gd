extends SceneTree

const Archive = preload("res://vtt/creature_archive.gd")

class TestCampaign extends Node:
	var selected_campaign_group_id := "test_reference_completion"
	var active_campaign_id := ""

class TestBoard extends Node3D:
	var board_sync: Node


class InstantCachedBestiary extends Node:
	signal catalog_ready(entries: Array[Dictionary])

	func load_catalog(_force_refresh: bool = false) -> void:
		# Simulates 5etools returning a warm search/index.json cache before
		# load_catalog() returns. Duergar is intentionally not in the miniature
		# fallback catalogue.
		var cached_rows: Array[Dictionary] = [
			{"name": "Duergar", "source": "MM", "page": 50}
		]
		catalog_ready.emit(cached_rows)


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
	area._archive.setup(campaign)
	var isolated_path := "user://tests/reference_completion_%d/creatures.json" % Time.get_ticks_usec()
	area._archive._storage.path = isolated_path
	area._archive._characters.archive_path = isolated_path
	area._archive._monsters.archive_path = isolated_path

	var cached_client := InstantCachedBestiary.new()
	board.add_child(cached_client)
	cached_client.catalog_ready.connect(area._on_catalog_ready)
	var original_client: Node = area._client
	area._client = cached_client
	area._load_bestiary_catalog(true)
	area._filter_catalog("duergar")
	var found_duergar: bool = false
	for entry: Dictionary in area._filtered_catalog:
		if String(entry.get("name", "")) == "Duergar" and String(entry.get("source", "")) == "MM":
			found_duergar = true
	check(found_duergar,
		"Warm bestiary cache was replaced with bundled miniature entries: Duergar not searchable")
	area._client = original_client
	cached_client.queue_free()

	var full_stat := {"name": "Ape", "source": "MM", "hp": {"average": 19}, "ac": [12]}
	for bonus: int in [0, 5]:
		var pending: Dictionary = area._archive.create_monster({"name": "Ape", "reference_pending": true})
		if bonus > 0:
			pending["formula_bonuses"] = [{"id": "test-hp-bonus", "target": "hp",
				"expression": str(bonus), "origin_id": ""}]
		check(area._archive.save(pending) == OK, "Pending sheet save failed")
		area._complete_auto_reference(String(pending.id), full_stat)
		var stored: Dictionary = area._archive._stored("monster", String(pending.id))
		check(stored.max_hp_base == 19 and stored.max_hp == 19 + bonus, "Bestiary completion lost base HP or bonus")
		check(stored.current_hp == 19 + bonus, "Bestiary completion left inconsistent current HP")
		check(not stored.stat_block.has("reference_pending"), "Reference remains pending after completion")
	var edited: Dictionary = area._archive.create_monster({"name": "Ape", "reference_pending": true})
	edited["max_hp_base"] = 7
	edited["formula_bonuses"] = [{"id": "test-edited-hp-bonus", "target": "hp",
		"expression": "3", "origin_id": ""}]
	edited["current_hp"] = 5
	check(area._archive.save(edited) == OK, "Edited sheet save failed")
	area._complete_auto_reference(String(edited.id), full_stat)
	var preserved: Dictionary = area._archive._stored("monster", String(edited.id))
	check(preserved.max_hp_base == 7 and preserved.max_hp == 10 and preserved.current_hp == 5, "Reference overwrote explicit HP edits")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	await process_frame
	if not failed:
		print("PASS: bestiary completion persists base HP, bonuses, current HP and user edits")
	quit(1 if failed else 0)