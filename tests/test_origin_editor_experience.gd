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
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1400, 900)
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
	assert(area._tabs.get_tab_title(area._tabs.get_tab_count() - 1) == "Origini", "Origins must be last")
	assert(area._proficiencies_ui.get_parent().get_parent().get_parent().name == "Origini")
	area._panel.show()
	area._show_sheet_tab("Origini")
	await process_frame
	# Check the first visible layout, before changing editor sections.
	for row: Node in area._origins_overview.get_children():
		if row is HBoxContainer:
			assert(row.get_child(0).size.x >= 180, "Origins are legible on first opening")
	if DisplayServer.get_name() != "headless":
		await capture("origin_first_open_review")
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
	area._show_sheet_tab("Origini")
	area._select_details_editor(6)
	await process_frame
	await process_frame
	var actual_link: Button = null
	for link: Node in area._origin_spells_ui.find_children("OriginTraitLink", "Button", true, false):
		if String(link.get_meta("origin_id", "")) == String(granted.get("origin_id", "")):
			actual_link = link
	assert(actual_link != null)
	await click(actual_link)
	await process_frame
	var feature_key: String = String(granted.get("origin_id", "")).trim_prefix("feature:")
	assert(area._tabs.get_tab_title(area._tabs.current_tab) == "Tratti", "The real origin link changes tabs")
	assert(bool(area._traits_ui._expanded.get(feature_key, false)), "Origin link opens its exact trait")
	# Repeat from the overview, whose controls live outside the CreatureArea node.
	area._show_sheet_tab("Origini")
	area._select_details_editor(0)
	await process_frame
	await process_frame
	var overview_link: Button = null
	for link: Node in area._origins_overview.find_children("OriginTraitLink", "Button", true, false):
		if String(link.get_meta("origin_id", "")) == String(granted.get("origin_id", "")):
			overview_link = link
	assert(overview_link != null)
	var origin_label: Control = overview_link.get_parent().get_child(0)
	var hover := InputEventMouseMotion.new()
	hover.position = origin_label.get_global_rect().get_center()
	hover.global_position = hover.position
	root.push_input(hover, true)
	await process_frame
	assert("Concessioni" in origin_label.tooltip_text or "Concessioni" in root.get_node("ScrollableCaptions")._text, "Overview labels display the live benefit preview")
	for index: int in range(area._tabs.get_tab_count()):
		if area._tabs.get_tab_control(index).name == "Origini":
			area._tabs.set_tab_title(index, "Origins")
		elif area._tabs.get_tab_control(index).name == "Tratti":
			area._tabs.set_tab_title(index, "Traits")
	await click(overview_link)
	assert(area._tabs.get_tab_control(area._tabs.current_tab).name == "Tratti", "Navigation works with translated tab titles")
	for index: int in range(area._tabs.get_tab_count()):
		area._tabs.set_tab_title(index, area._tabs.get_tab_control(index).name)
	var tracker_id: String = String(granted.get("tracker_id", ""))
	record["resource_tracker_spent"] = {tracker_id: 3}
	area._refresh_trackers(record)
	var active_adjustments := 0
	for button: Node in area._tracker_rows.find_children("*", "Button", true, false):
		if button.text in ["−", "+", "↺"]:
			assert(not button.disabled, "Exhausted active trackers retain usable buttons")
			active_adjustments += 1
	assert(active_adjustments >= 3)
	area._show_sheet_tab("Statistiche")
	if DisplayServer.get_name() != "headless":
		await capture("exhausted_tracker_review")
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
	assert(spells._view._rows[0].get_child_count() == 2, "Class spells and slot trackers form the first paired row")
	spells._cast_dialog.hide()
	for i: int in range(area._tabs.get_tab_count()):
		if area._tabs.get_tab_title(i) == "Incantesimi":
			area._tabs.current_tab = i
	await process_frame
	await process_frame
	var sheet_scroll: ScrollContainer = area._tabs.get_tab_control(area._tabs.current_tab)
	assert(spells._view.visible, "The two-column view is the visible spell interface")
	assert(spells._view._rows.size() > 1, "Origin spells have their own paired rows")
	# Use a narrow viewport and wheel events over real content, not just a scrollbar assignment.
	root.size = Vector2i(1000, 650)
	await process_frame
	await process_frame
	var before: int = sheet_scroll.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = sheet_scroll.get_global_rect().position + Vector2(20, 45)
	wheel.global_position = wheel.position
	for i: int in range(8):
		root.push_input(wheel, true)
		await process_frame
	assert(sheet_scroll.scroll_vertical > before, "Spell sheet responds to the mouse wheel")
	sheet_scroll.scroll_vertical = 0
	var class_scroll: ScrollContainer = spells._view._rows[0].get_child(0).find_children("*", "ScrollContainer", true, false)[0]
	class_scroll.get_v_scroll_bar().value = class_scroll.get_v_scroll_bar().max_value
	await process_frame
	before = sheet_scroll.scroll_vertical
	wheel.position = class_scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	root.push_input(wheel, true)
	await process_frame
	assert(sheet_scroll.scroll_vertical > before, "At the end of the class list the wheel reaches origin spells")
	var pending: Dictionary = Structured.for_creature(record).get("choices", [])[0]
	area._edit_origin_spell_popup(String(pending.get("origin_id", "")), pending)
	assert(editor._shared_picker.visible, "Origin selection opens the same popup from the spellcasting page")
	assert(area._tabs.get_tab_control(area._tabs.current_tab).name == "Incantesimi", "Choosing an origin spell keeps the spellcasting page open")
	editor._shared_picker.hide()
	root.size = Vector2i(1400, 900)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await capture("spellcasting_review")
	area._show_sheet_tab("Origini")
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


func click(button: Button) -> void:
	assert(button.is_visible_in_tree())
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = button.get_global_rect().get_center()
	mouse.global_position = mouse.position
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse, true)
	await process_frame
