extends SceneTree
const View = preload("res://vtt/creature_spellcasting_view.gd")
const Selector = preload("res://vtt/spell_selection_dialog.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
var record: Dictionary
func _initialize() -> void:
	call_deferred("run")
func ignore(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	pass
func current() -> Dictionary:
	return record
func casting_stats(ability: String) -> String:
	return "Caratteristica: " + ability + " · Tiro per colpire: +5 · CD: 13"
func class_ability(_class_name: String) -> String:
	return "int"
func default_ability() -> String:
	return "int"
func gui_language() -> String:
	return "it"
func section_ability(_section: String, _suggested: Array[String]) -> String:
	return "int"
func run() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 900)
	root.size = Vector2i(1024, 720)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.theme = preload("res://vtt/ui/dnd5e_theme.tres").duplicate()
	host.theme.default_font_size = 28
	root.add_child(host)
	var outer := ScrollContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(outer)
	var view := View.new()
	outer.add_child(view)
	var options: Array[Dictionary] = []
	for spell: Dictionary in Catalog.all_spells():
		options.append(spell)
	var selected: Array = []
	for spell: Dictionary in options.slice(0, 16):
		selected.append({"id":spell.id, "name":spell.name, "casting_classes":["manual"]})
	record = {"kind":"character", "prepared_spells":selected,
		"spell_slots_total":[0,4,3,3,2,0,0,0,0,0], "spell_slots_spent":[],
		"pact_slots_total":0, "pact_slot_level":1}
	var actions := {"record":current, "casting_stats":casting_stats,
		"class_ability":class_ability, "default_ability":default_ability,
		"section_ability":section_ability, "gui_language":gui_language}
	for action: String in ["set_section_ability","slot_max_edit","slot_max_bonus","manual","resource_settings","edit_class","cast_class","cast_origin","slot","pact","tracker","restore","edit_origin","choose_origin"]:
		actions[action] = ignore
	view.setup(actions)
	view.refresh()
	var summaries: Array[Node] = view.find_children("CastingStatistics", "Label", true, false)
	assert(not summaries.is_empty() and "int" in (summaries[0] as Label).text,
		"Manual spell section displays its own spellcasting statistics")
	for i: int in range(6):
		await process_frame
	var pair: HBoxContainer = view._rows[0]
	var left: VBoxContainer = pair.get_child(0).get_child(0)
	var right: VBoxContainer = pair.get_child(1).get_child(0)
	var spell_list: ScrollContainer
	for candidate: Node in left.find_children("*", "ScrollContainer", true, false):
		if candidate.has_meta("spell_list"):
			spell_list = candidate as ScrollContainer
			break
	assert(spell_list != null, "The prepared powers list has its own ScrollContainer")
	assert(spell_list.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and spell_list.get_child(0) is VBoxContainer,
		"Prepared spell list remains vertically scrollable after resizing")
	assert(absf(pair.get_child(0).size.y - pair.get_child(1).size.y) < 1, "Paired panels fill the same row")
	assert(left.get_combined_minimum_size().y >= right.get_combined_minimum_size().y - 2,
		"No unused row height while spells still need scrolling")
	var grid: GridContainer = right.get_node("SlotGrid")
	for level: int in range(1,10):
		var ordinary: HBoxContainer = grid.get_child(level * 3 + 1)
		var pact: HBoxContainer = grid.get_child(level * 3 + 2)
		if level == 1:
			assert(ordinary.get_child_count() == 3, "Visible slot counter has a fixed action cell and two values")
			assert(ordinary.get_child(0) is HBoxContainer
				and ordinary.get_child(0).get_child_count() == 2,
				"Slot action buttons occupy the fixed cell before the remaining count")
			assert((ordinary.get_child(0).get_child(0) as Button).text == "−"
				and (ordinary.get_child(0).get_child(1) as Button).text == "+")
			assert((ordinary.get_child(1) as Label).text == "4" and (ordinary.get_child(2) as Label).text == "/4",
				"Current and maximum slot values stay together")
		assert(pact.find_children("*", "Button", true, false).is_empty(), "No Pact controls without Pact slots")
		assert(absf(pact.position.x - grid.get_child(5).position.x) < 1, "Pact cells stay in their column")
		if level >= 5:
			assert(ordinary.find_children("*", "Button", true, false).is_empty(), "No controls for nonexistent slots")
	record.pact_slots_total = 2
	record.pact_slot_level = 3
	view.refresh()
	for i: int in range(6):
		await process_frame
	grid = view._rows[0].get_child(1).get_child(0).get_node("SlotGrid")
	var active_pact: HBoxContainer = grid.get_child(11)
	assert(active_pact.find_children("*", "Button", true, false).size() == 2)
	assert(active_pact.get_child(0) is HBoxContainer
		and active_pact.get_child(0).get_child_count() == 2,
		"Pact action buttons occupy the fixed cell before the remaining count")
	assert((active_pact.get_child(1) as Label).text == "2" and (active_pact.get_child(2) as Label).text == "/2")
	for level: int in range(1,10):
		assert(absf(grid.get_child(level * 3 + 2).position.x - grid.get_child(11).position.x) < 1,
			"Real Pact controls do not shift the table")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://spellcasting_scaled_review.png")
	var selector := Selector.new()
	host.add_child(selector)
	for physical_size: Vector2i in [Vector2i(1024,720),Vector2i(800,600),Vector2i(640,480)]:
		root.size = physical_size
		if physical_size.x == 640:
			root.content_scale_size = physical_size
		selector.choose(options, {"book_mode":true, "details":"Origine e formula della lista. ".repeat(80)}, ignore)
		for i: int in range(6):
			await process_frame
		var area := host.get_viewport().get_visible_rect()
		assert(selector.size.x <= area.size.x and selector.size.y <= area.size.y)
		assert(selector.position.x >= 0 and selector.position.y >= 0)
		assert(selector.position.y >= selector.get_theme_constant("title_height", "Window") + 8, "The title bar also stays on screen")
		assert(selector.position.y + selector.size.y <= area.size.y)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://spellcasting_scaled_selector_%d.png" % physical_size.x)
		var results: ScrollContainer = selector._rows.get_parent()
		assert(results.size.y > selector.size.y * 0.3, "The results use the available popup height")
		selector._details.show()
		for i: int in range(4):
			await process_frame
		assert(selector.size.y <= area.size.y, "Long details scroll within the popup")
		var cancel: Button = selector.get_cancel_button()
		assert(Rect2(Vector2.ZERO, Vector2(selector.size)).encloses(cancel.get_global_rect()),
			"Cancel stays visible with large text and viewport scaling")
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		selector.push_input(key, true)
		await process_frame
		assert(not selector.visible, "The popup can be dismissed with Escape")
	host.free()
	await process_frame
	print("PASS themed list heights, aligned absent/active Pact pools, scaled popup and reachable Cancel")
	quit()
