extends "res://tests/test_creature_sheet_ui.gd"

func run() -> void:
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	board.board_sync = TestSync.new()
	board.add_child(board.board_sync)
	var campaign := TestCampaign.new()
	root.add_child(campaign)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	area._archive.setup(campaign)
	var isolated_path := "user://tests/creature_perf_%d/creatures.json" % Time.get_ticks_usec()
	area._archive._storage.path = isolated_path
	area._archive._characters.archive_path = isolated_path
	area._archive._monsters.archive_path = isolated_path
	var record: Dictionary = area._archive.create_character()
	record["class"] = "Wizard"
	record["class_source"] = "PHB"
	record["classes"] = [{"name": "Wizard", "source": "PHB", "level": 5}]
	record["level"] = 5
	assert(area._archive.save(record) == OK)
	area._reload()
	area._on_selected(0)
	for method: String in ["_save", "_refresh_skill_values", "_recalculate_bonus_mirrors", "_refresh_trackers", "_refresh_attack_values", "_refresh_reference", "_apply_sheet_properties", "_sync_token_health"]:
		var start := Time.get_ticks_usec()
		for i: int in range(5):
			if method == "_save":
				area._name.text = "Benchmark %d" % i
				area.call(method)
			else:
				area.call(method, area._current())
		print("BENCH %s: %.3f ms" % [method, (Time.get_ticks_usec() - start) / 5000.0])
	var archive_start := Time.get_ticks_usec()
	for i: int in range(5):
		area._archive.save(area._current())
	print("BENCH archive: %.3f ms" % ((Time.get_ticks_usec() - archive_start) / 5000.0))
	var tab: Node = area._spellcasting_ui
	var start := Time.get_ticks_usec()
	for i: int in range(5):
		tab.update_character_context(area._current())
	print("BENCH spell context: %.3f ms" % ((Time.get_ticks_usec() - start) / 5000.0))
	# Unrelated edits must preserve spell selection (rebuilding loses it).
	var available: ItemList = tab._available
	assert(available.item_count > 0)
	available.select(0)
	var spell_count: int = available.item_count
	area._biography.text = "Persist this biography"
	area._hp.set_value_no_signal(1)
	area._save()
	assert(available.is_selected(0) and available.item_count == spell_count)
	var stored: Dictionary = area._archive.list_owned()[0]
	assert(stored.name == "Benchmark 4" and stored.background_personality == "Persist this biography")
	var context: Dictionary = area._current()
	context["classes"] = [{"name": "Wizard", "source": "PHB", "level": 1}]
	context["class"] = "Wizard"
	context["level"] = 1
	tab.update_character_context(context)
	assert(tab._class_spell_level_limits().get("wizard") == 1)
	context.classes[0]["level"] = 5
	context["level"] = 5
	tab.update_character_context(context)
	assert(tab._class_spell_level_limits().get("wizard") == 3, "Nested class edits must invalidate the snapshot")
	context["rules_version"] = "2024"
	tab.update_character_context(context)
	assert(tab._catalog.any(func(spell: Dictionary) -> bool: return spell.get("source") == "XPHB"))
	# Cached traits must remain isolated, update on level changes, and match
	# the uncached collector after mutations and content reloads.
	var traits: Script = load("res://vtt/creature_traits_tab.gd")
	var features: Array = traits.collect_features(context)
	assert(not features.is_empty())
	features[0]["name"] = "Caller mutation"
	assert(traits.collect_features(context) == traits._collect_features(context))
	context.classes[0]["level"] = 1
	assert(traits.collect_features(context) == traits._collect_features(context))
	traits.ContentCatalog.reload_enrichment()
	assert(traits.collect_features(context) == traits._collect_features(context))
	assert(area._archive.delete(area._current()) == OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	print("PASS: creature edit performance")
	quit()