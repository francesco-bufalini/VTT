extends SceneTree
const View = preload("res://vtt/creature_spellcasting_view.gd")

var _record: Dictionary

func _initialize() -> void:
	call_deferred("run")

func _ignore(_a: Variant = null, _b: Variant = null) -> void:
	pass

func _current() -> Dictionary:
	return _record

func _language() -> String:
	return "it"

func _section_ability(_id: String, _suggested: Array[String]) -> String:
	return "wis"

func _stats(_ability: String) -> String:
	return "Modificatore: +5 · CD: 13"

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 860)
	var host := Control.new()
	host.theme = preload("res://vtt/ui/dnd5e_theme.tres").duplicate()
	host.theme.default_font_size = 26
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var view := View.new()
	view.custom_minimum_size.x = 1060
	host.add_child(view)
	_record = {"kind": "character", "resource_tracker_spent": {"shared": 1}}
	view.setup({
		"record": _current, "gui_language": _language,
		"section_ability": _section_ability, "casting_stats": _stats,
		"set_section_ability": _ignore, "cast_origin": _ignore, "tracker": _ignore
	})
	var pair: Array[VBoxContainer] = view._pair()
	view._heading(pair[0], "Origine · Talento · Shadow Touched")
	view._casting_statistics(pair[0], "origin:test", ["wis"])
	var list: VBoxContainer = view._list(pair[0], 2)
	var grant: Dictionary = {"origin_id": "feat:test", "spell_id": "invisibility",
		"payment_mode": "tracker", "tracker_id": "shared", "tracker_cost": 2}
	view._spell_button(list, {"name": "Invisibility", "level": 2, "description": "Effect"}, {}, grant)
	var other: Dictionary = grant.duplicate(true)
	other["tracker_cost"] = 1
	view._spell_button(list, {"name": "Inflict Wounds", "level": 1, "description": "Effect"}, {}, other)
	for i: int in range(2):
		var entry: HBoxContainer = list.get_child(i)
		assert(entry.get_child_count() == 2,
			"Tracker-paid powers separate the action from the cost")
		assert(entry.get_child(0) is Button and entry.get_child(1) is Label,
			"The power name stays inside the button with cost to its right")
		var power: Button = entry.get_child(0)
		var price: Label = entry.get_child(1)
		assert(not "utilizzi" in power.text and not "Costo" in power.text,
			"The clickable power contains only its name and level")
		assert(price.text == ("Costo: 2" if i == 0 else "Costo: 1")
			and price.size_flags_horizontal == Control.SIZE_SHRINK_END,
			"Each independent spell charge appears aligned to the right")
	view._tracker(pair[1], _record,
		{"id": "shared", "name": "Shadow Touched · scelta", "max": 3, "origin_id": "feat:test"})
	view._tracker(pair[1], _record,
		{"id": "another", "name": "Shadow Touched · invisibility", "max": 1, "origin_id": "feat:test"})
	assert(pair[1].get_child_count() == 2,
		"No heading or explanatory cost paragraph bloats the tracker column")
	for item: Node in pair[1].get_children():
		assert(item is HBoxContainer and item.get_child_count() == 2,
			"Each tracker is represented by one horizontal row")
		var counter: HBoxContainer = item.get_child(0)
		var title: Label = item.get_child(1)
		assert(counter.get_child(0) is Button and counter.get_child(1) is Button,
			"Tracker actions appear before the resource name")
		assert(title.name == "TrackerName" and title.text.begins_with("Shadow Touched")
			and not title.text.begins_with("Tracker"),
			"Tracker name is not prefixed by redundant wording")
	await view._balance_lists()
	await process_frame
	var spell_scroll: ScrollContainer = list.get_parent()
	var first_row: HBoxContainer = list.get_child(0)
	assert(spell_scroll.custom_minimum_size.y >= first_row.get_combined_minimum_size().y + 8,
		"Section must fully display casting stats and at least one power before scrolling")
	assert(view._rows[0].get_child(0).size.y >= first_row.size.y,
		"Paired panel height cannot clip the first spell")
	print("PASS compact tracker rows, right-aligned individual power costs and minimum visible spell")
	quit()
