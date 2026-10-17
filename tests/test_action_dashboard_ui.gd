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
	tab._options_path = "user://action_overview_test_%d.cfg" % Time.get_ticks_usec()
	root.add_child(tab)
	tab.size = Vector2(1250, 880)
	var record: Dictionary = {
		"kind": "character", "rules_version": "2014",
		"class": "Rogue", "class_source": "PHB", "level": 2,
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
	assert(tab._panels[3].get_parent() == tab._layout_right)
	assert(tab._skill_buttons.columns == 1)
	assert(tab._layout_left.get_child_count() == 1, "Only actions belong in the first column")
	assert(tab._skill_list.get_parent() == tab._sections[2], "Quick rolls have no intrinsic action cost")
	var checks_title := _find_button(tab, "Prove di abilità")
	assert(checks_title != null)
	var checks_card := checks_title.get_parent().get_parent().get_parent().get_parent()
	var checks_entry: Dictionary = checks_card.get_meta("action_entry")
	var check_ids: Array = []
	for check: Dictionary in checks_entry["children"]:
		check_ids.append(check["id"])
		assert(check.get("parent_action", "").is_empty())
		assert(int(check["time"]) == 0)
	assert(not "hide" in check_ids and "search" in check_ids)
	assert(not "grapple" in check_ids and not "shove" in check_ids)
	var move_count := 0
	for section in tab._sections:
		for card in section.get_children():
			if not card.has_meta("action_entry"): continue
			var entry: Dictionary = card.get_meta("action_entry")
			if not String(entry.get("id", "")).begins_with("movement_options_"): continue
			move_count += 1
			for option: Dictionary in entry["children"]:
				assert(option["time"] == entry["time"], "Movement groups preserve the actual action cost")
	assert(move_count == 3, "Movement options are grouped separately for action, bonus and movement costs")
	# Titles and separate arrows must preserve the existing action routing.
	var basic: Array[String] = []
	tab.basic_action_requested.connect(func(id: String) -> void: basic.append(id))
	var help := _find_button(tab, "Aiutare")
	assert(help != null)
	var details := help.get_parent().get_parent().get_node("ActionDetails") as Button
	details.pressed.emit()
	assert(basic.is_empty(), "Description arrows must not execute tactical actions")
	for child: Node in tab.get_children():
		if child is AcceptDialog:
			child.hide()
			child.queue_free()
	var target: Button = help.get_parent().get_parent().get_child(2).get_child(0)
	target.pressed.emit()
	assert(basic == ["help"], "Target control must route the stable action ID")
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
	assert(_find_button(tab, "Incantesimi") != null)
	assert(_find_button(tab, "Raggio di prova") != null, "Selected spells appear inside their action group")
	var original := record.duplicate(true)
	tab._open_variant_settings()
	assert(tab._settings_dialog.find_children("*", "CheckButton", true, false).size() >= 70)
	tab._settings_dialog.hide()
	assert(tab._set_variant_enabled("disarm_dmg", true) == OK)
	assert(record == original, "Choosing a variant must never edit the creature")
	var saved := ConfigFile.new()
	assert(saved.load(tab._options_path) == OK)
	assert("disarm_dmg" in saved.get_value("2014", "variants", []))
	var attack := _find_button(tab, "Attaccare")
	var card: Control = attack.get_parent().get_parent().get_parent().get_parent()
	assert(card.get_meta("action_entry")["children"].any(func(row: Dictionary) -> bool: return row.get("id") == "disarm"))
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tab._options_path))
	tab.queue_free()
	print("PASS: native action groups, source descriptions, variant settings, dice routing and conditional spell groups")
	quit(0)
