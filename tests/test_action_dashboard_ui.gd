extends SceneTree

const Actions = preload("res://vtt/creature_action_economy_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func _find_button(root_node: Node, caption: String) -> Button:
	if root_node is Button and String((root_node as Button).text) == caption:
		return root_node as Button
	for child: Node in root_node.get_children():
		var found := _find_button(child, caption)
		if found != null:
			return found
	return null

func run() -> void:
	var tab := Actions.new()
	root.add_child(tab)
	tab.size = Vector2(1250, 880)
	var record: Dictionary = {
		"kind": "character", "rules_version": "2014",
		"action_grants": [{"name": "Manovra", "action_type": "bonus", "tracker_id": "charge"}],
		"resource_trackers": [{"id": "charge", "name": "Cariche", "max": 3, "recharge": "long_rest"}],
		"prepared_spells": [{"id": "spell_action_test", "name": "Raggio di prova",
			"level": 1, "time": "action", "entries": ["Una scarica luminosa."]}]
	}
	tab.load_record(record)
	assert(tab._panels.size() == 5 and tab._sections.size() == 5)
	assert(tab._layout_two.visible)
	assert(tab._panels[0].get_parent() == tab._layout_left)
	assert(tab._panels[1].get_parent() == tab._layout_right)
	assert(tab._panels[3].get_parent() == tab._layout_left)
	assert(tab._skill_buttons.columns == 2)
	var minus := _find_button(tab, "−")
	assert(minus != null and not minus.disabled, "Tracker must have active spend control")
	var actions: Array = []
	tab.tracker_change_requested.connect(func(id: String, delta: int, maximum: int) -> void:
		actions.append([id, delta, maximum]))
	minus.pressed.emit()
	assert(actions == [["charge", 1, 3]], "Native action tracker uses stable resource ID")
	var cast := _find_button(tab, "Lancia")
	assert(cast != null, "Class spells must have a casting control, not a slot counter")
	var spells: Array = []
	tab.cast_spell_requested.connect(func(id: String, grant: String) -> void: spells.append([id, grant]))
	cast.pressed.emit()
	assert(spells == [["spell_action_test", ""]])
	tab.size.x = 570
	tab.call("_arrange_columns")
	assert(tab._layout_one.visible and not tab._layout_two.visible)
	assert(tab._panels[4].get_parent() == tab._layout_one)
	tab.queue_free()
	print("PASS: native action boxes, responsive layout, saved tracker signals and class spell casting")
	quit(0)
