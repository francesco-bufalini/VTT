extends SceneTree
const Area = preload("res://vtt/creature_area.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const SpellTab = preload("res://vtt/creature_spellcasting_tab.gd")

class Sheet extends Area:
	var fixture: Dictionary = {}
	func _current() -> Dictionary:
		return fixture

class CastSink extends Node:
	var grant: Dictionary = {}
	func cast(_spell: Dictionary, _level: int, source: Dictionary = {}) -> bool:
		grant = source.duplicate(true)
		return true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var record: Dictionary = {"kind": "character", "name": "Bardo di prova", "rules_version": "2014",
		"class": "Bard", "class_source": "PHB", "level": 3,
		"classes": [{"name": "Bard", "source": "PHB", "level": 3}],
		"abilities": {"str": 10, "dex": 14, "con": 12, "int": 10, "wis": 12, "cha": 16},
		"feats_catalog": [{"name": "Magic Initiate", "source": "PHB"}]}
	var board := Node3D.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	board.add_child(ui)
	var area := Sheet.new()
	board.add_child(area)
	area.board_root = board
	area.ui_root = ui
	area.fixture = record
	area._build_ui()
	assert(area._tabs.get_tab_title(2) == "Origini")
	assert(area._proficiencies_ui.get_parent().get_parent().get_parent().name == "Origini")
	area._panel.show()
	area._tabs.current_tab = 2
	area._select_details_editor(6)
	var editor = area._origin_spells_ui
	var choices: Array = Structured.for_creature(record).get("choices", [])
	var cantrips: Dictionary = {}
	for choice: Dictionary in choices:
		if "level=0" in String(choice.get("filter", "")):
			cantrips = choice
	assert(not cantrips.is_empty())
	editor._choose(cantrips)
	assert(editor._add_dialog.visible, "Choosing opens a popup")
	assert(not editor._tracker_picker.visible, "Cantrips need no tracker")
	assert("class=wizard" in editor._filter_label.text.to_lower() and "class=bard" in editor._filter_label.text.to_lower(),
		"Magic Initiate shows all alternative class filters, independent of character class")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1400, 900)
		await capture("origin_choice_review")
	editor._bypass.button_pressed = true
	assert(editor._shown.size() > 0)
	editor._add_dialog.hide()
	area._select_details_editor(4)
	var tracker_editor = area._trackers_ui
	var formula_found := false
	for label: Node in tracker_editor.find_children("*", "Label", true, false):
		if "Max:" in label.text and "cha_mod" in label.text:
			formula_found = true
	assert(formula_found, "Bardic Inspiration shows its maximum formula")
	var granted: Dictionary = {}
	for grant: Dictionary in Grants.all_grants(record):
		if String(grant.get("spell_id", "")) == Grants.BARDIC:
			granted = grant
	assert(not granted.is_empty())
	area._open_origin_trait(String(granted.get("origin_id", "")), "Bardic Inspiration")
	await process_frame
	var feature_key: String = String(granted.get("origin_id", "")).trim_prefix("feature:")
	assert(bool(area._traits_ui._expanded.get(feature_key, false)), "Origin link opens its exact trait")
	var tracker_id: String = String(granted.get("tracker_id", ""))
	record["resource_tracker_spent"] = {tracker_id: 3}
	assert(Grants.remaining(record, granted) == 0)
	var free: Dictionary = granted.duplicate(true)
	free["skip_payment"] = true
	assert(Grants.spend(record, free))
	assert(int(record.resource_tracker_spent[tracker_id]) == 3, "Bypass never spends an exhausted tracker")
	assert(not Grants.spend(record, granted), "Ordinary tracker payment remains protected")
	var sink := CastSink.new()
	root.add_child(sink)
	var spells = area._spellcasting_ui
	spells._on_cast_spell = Callable(sink, "cast")
	spells.load_record(record)
	spells._cast_granted_spell(granted)
	assert(spells._cast_dialog.visible)
	assert(spells._cast_slot_choice.item_count == 1, "An exhausted tracker offers only explicit bypass")
	spells._confirm_cast_spell()
	assert(bool(sink.grant.get("skip_payment", false)))
	assert(spells._slot_grid.get_parent().get_parent().get_parent() == spells._known_list.get_parent().get_parent(),
		"Slots and class spell lists share the same horizontal row")
	spells._cast_dialog.hide()
	for i: int in range(area._tabs.get_tab_count()):
		if area._tabs.get_tab_title(i) == "Incantesimi":
			area._tabs.current_tab = i
	if DisplayServer.get_name() != "headless":
		await capture("spellcasting_review")
	area._tabs.current_tab = 2
	area._select_details_editor(6)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1400, 900)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://origin_editor_review.png")
		print("REVIEW_IMAGE ", ProjectSettings.globalize_path("user://origin_editor_review.png"))
	sink.free()
	board.free()
	await process_frame
	print("PASS origin editor experience: dedicated tab, popup, formula, lists and exhausted tracker bypass")
	quit()


func capture(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + filename + ".png")
	print("REVIEW_IMAGE ", ProjectSettings.globalize_path("user://" + filename + ".png"))
