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
	var actions := {"record":current}
	for action: String in ["manual","resource_settings","edit_class","cast_class","cast_origin","slot","pact","tracker","restore","edit_origin","choose_origin"]:
		actions[action] = ignore
	view.setup(actions)
	view.refresh()
	for i: int in range(6):
		await process_frame
	var pair: HBoxContainer = view._rows[0]
	var left: VBoxContainer = pair.get_child(0).get_child(0)
	var right: VBoxContainer = pair.get_child(1).get_child(0)
	var spell_list: ScrollContainer = left.find_children("*", "ScrollContainer", true, false)[0]
	assert(spell_list.custom_minimum_size.y > 180, "Hidden spells use the spare height beside slots")
	assert(absf(pair.get_child(0).size.y - pair.get_child(1).size.y) < 1, "Paired panels fill the same row")
	assert(left.get_combined_minimum_size().y >= right.get_combined_minimum_size().y - 2,
		"No unused row height while spells still need scrolling")
	var grid: GridContainer = right.get_node("SlotGrid")
	for level: int in range(1,10):
		var ordinary: HBoxContainer = grid.get_child(level * 3 + 1)
		var pact: HBoxContainer = grid.get_child(level * 3 + 2)
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
	assert(grid.get_child(11).find_children("*", "Button", true, false).size() == 2)
	for level: int in range(1,10):
		assert(absf(grid.get_child(level * 3 + 2).position.x - grid.get_child(11).position.x) < 1,
			"Real Pact controls do not shift the table")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://spellcasting_scaled_review.png")
	var selector := Selector.new()
	host.add_child(selector)
	for physical_size: Vector2i in [Vector2i(1024,720),Vector2i(800,600)]:
		root.size = physical_size
		selector.choose(options, {"book_mode":true, "details":"Origine e formula della lista. ".repeat(80)}, ignore)
		for i: int in range(6):
			await process_frame
		var area := host.get_viewport().get_visible_rect()
		assert(selector.size.x <= area.size.x and selector.size.y <= area.size.y)
		assert(selector.position.x >= 0 and selector.position.y >= 0)
		assert(selector.position.y + selector.size.y <= area.size.y)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://spellcasting_scaled_selector_%d.png" % physical_size.x)
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
