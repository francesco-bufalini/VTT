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
	root.gui_embed_subwindows = true
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
	assert(tab._section_counts.size() == 5 and int(tab._section_counts[0].text) > 0,
		"Each bordered action panel must expose its live action count")
	assert(tab._layout_two.visible)
	assert(tab._panels[0].get_parent() == tab._layout_left)
	assert(tab._panels[1].get_parent() == tab._layout_right)
	assert(tab._panels[3].get_parent() == tab._layout_left)
	assert(tab._skill_buttons.columns == 1)
	# Titles and separate arrows must preserve the existing action routing.
	var basic: Array[String] = []
	tab.basic_action_requested.connect(func(id: String) -> void: basic.append(id))
	var help := _find_button(tab, "Aiutare")
	assert(help != null)
	var details := help.get_parent().get_parent().get_node("ActionDetails") as Button
	details.pressed.emit()
	assert(basic == ["help"], "The new arrow must route the stable action ID")
	# Composite skill rows must still act as one button across their labels/icons.
	var rolls: Array[String] = []
	tab.skill_requested.connect(func(key: String) -> void: rolls.append(key))
	var skill := tab._skill_buttons.get_child(0) as Button
	assert(skill.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for child: Control in skill.get_child(0).get_children():
		assert(child.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	skill.pressed.emit()
	assert(rolls == ["skill:" + String(Actions.best_skills(record)[0]["id"])])
	var minus := _find_button(tab, "−")
	assert(minus != null and not minus.disabled, "Tracker must have active spend control")
	var actions: Array = []
	tab.tracker_change_requested.connect(func(id: String, delta: int, maximum: int) -> void:
		actions.append([id, delta, maximum]))
	minus.pressed.emit()
	assert(actions == [["charge", 1, 3]], "Native action tracker uses stable resource ID")
	var cast := _find_button(tab, "Lancia · slot")
	assert(cast != null, "Class spells must offer slot casting, not a separate spell tracker")
	var spells: Array = []
	tab.cast_spell_requested.connect(func(id: String, grant: String) -> void: spells.append([id, grant]))
	cast.pressed.emit()
	assert(spells == [["spell_action_test", ""]])
	# Real desktop archives expose roughly 830 logical pixels after the sidebar.
	tab.size.x = 820
	tab.call("_arrange_columns")
	assert(tab._layout_two.visible, "Two columns must fit the actual desktop archive")
	tab.size.x = 570
	tab.call("_arrange_columns")
	assert(tab._layout_one.visible and not tab._layout_two.visible)
	assert(tab._panels[4].get_parent() == tab._layout_one)
	# Long descriptions opened by the new arrows stay readable in a compact window.
	root.size = Vector2i(570, 640)
	tab._show_entry({"name": "Dettagli", "detail": "Una descrizione lunga e leggibile. ".repeat(200)})
	for frame: int in range(4):
		await process_frame
	var dialog: AcceptDialog
	for child: Node in tab.get_children():
		if child is AcceptDialog:
			dialog = child
	assert(dialog != null and dialog.visible)
	assert(dialog.size.x <= 570 and dialog.size.y <= 640)
	var description: RichTextLabel = dialog.find_children("*", "RichTextLabel", true, false)[0]
	assert(description.scroll_active and description.size.x > 100 and description.size.y > 100)
	dialog.hide()
	tab.queue_free()
	print("PASS: native action boxes, responsive layout, saved tracker signals and class spell casting")
	quit(0)
