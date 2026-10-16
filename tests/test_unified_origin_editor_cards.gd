extends SceneTree

const UI = preload("res://vtt/origin_editor_ui.gd")
const Bonus = preload("res://vtt/creature_bonus_tab.gd")
const Proficiencies = preload("res://vtt/creature_proficiencies_tab.gd")
const Feats = preload("res://vtt/creature_feats_tab.gd")
const Trackers = preload("res://vtt/creature_trackers_tab.gd")
const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")

func _initialize() -> void:
	call_deferred("_run")


func _card(tab: Control) -> PanelContainer:
	var container: VBoxContainer = tab.get("_origin_cards") as VBoxContainer
	assert(container != null and container.get_child_count() > 0,
		"Origin editor must render at least one shared origin card")
	var panel: PanelContainer = container.get_child(0) as PanelContainer
	assert(panel != null and panel.name == "OriginCard",
		"All origin editors must use the same card container")
	var line: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert(line != null and line.name == "OriginCardActions")
	assert(line.get_child(0) is Button
		and line.get_child(0).name == "OriginSelect")
	var border: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(border != null and border.border_width_left >= 1)
	return panel


func _run() -> void:
	# Renderer: disabled benefits are legible, selection outline survives, and
	# warning/edit buttons precede activation and keep their original callbacks.
	var owner := Control.new()
	root.add_child(owner)
	var column := VBoxContainer.new()
	owner.add_child(column)
	var events := {"select": false, "warning": false, "toggle": false}
	var button: Button = UI.origin_card(owner, column, {
		"id": "feature:test", "name": "Test origin", "text": "Test origin (2)",
		"tooltip": "Concessioni disabilitate: conservate",
		"selected": true, "active": false,
		"on_select": func() -> void: events["select"] = true,
		"on_toggle": func(value: bool) -> void: events["toggle"] = value,
		"actions": [{"text": "⚠", "warning": true,
			"tooltip": "Completa la scelta",
			"callback": func() -> void: events["warning"] = true}]
	})
	assert(column.get_child_count() == 1)
	var panel: PanelContainer = column.get_child(0) as PanelContainer
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(style.border_width_left == 2 and panel.modulate.a == 1.0,
		"Selected disabled origin must remain highlighted")
	assert("conservate" in button.tooltip_text)
	var line: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert(line.get_child_count() == 4, "Selection + trait link + warning + activation")
	assert(line.get_child(1).name == "OriginTraitLink")
	var warning: Button = line.get_child(2) as Button
	assert(warning.text == "⚠" and warning.tooltip_text == "Completa la scelta")
	warning.pressed.emit()
	assert(events["warning"])
	var toggle: CheckButton = line.get_child(3) as CheckButton
	assert(not toggle.button_pressed, "Disabled origin must retain its state")
	toggle.set_pressed_no_signal(true)
	toggle.toggled.emit(true)
	assert(events["toggle"])
	button.pressed.emit()
	assert(events["select"])
	UI.origin_card_state(panel, false, false)
	style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(style.border_width_left == 1 and panel.modulate.a < 1.0)
	UI.clear_origin_cards(column)
	assert(column.get_child_count() == 0)

	# Each editor keeps its own grant filtering and actions, but uses the
	# identical card hierarchy (including defenses' manual source).
	var sid := "custom|common"
	var record := {"kind": "character", "classes": [], "inventory": [],
		"proficiency_origins": [{"id": sid, "name": "Origine test",
			"disabled": false}], "proficiency_choices": [],
		"feats_catalog": [], "formula_bonuses": []}

	var bonus := Bonus.new()
	root.add_child(bonus)
	bonus.setup(Callable())
	bonus._record = record.duplicate(true)
	bonus._origins = (record["proficiency_origins"] as Array).duplicate(true)
	bonus._rows = [{"id": "test-bonus", "origin_id": sid, "origin_name": "Origine test",
		"target": "ac", "expression": "1"}]
	bonus._refresh_origins()
	_card(bonus)

	var prof := Proficiencies.new()
	root.add_child(prof)
	prof.setup(Callable())
	prof._record = record.duplicate(true)
	prof._origins = (record["proficiency_origins"] as Array).duplicate(true)
	prof._rows = [{"kind": "skill", "key": "athletics", "origin_id": sid}]
	prof._refresh_origins()
	_card(prof)

	var feats := Feats.new()
	root.add_child(feats)
	feats.setup(Callable())
	feats._record = record.duplicate(true)
	feats._origins = (record["proficiency_origins"] as Array).duplicate(true)
	feats._feats = [{"name": "Alert", "source": "PHB", "origin_id": sid}]
	feats._refresh_origins()
	_card(feats)

	var trackers := Trackers.new()
	root.add_child(trackers)
	trackers.setup(Callable())
	trackers._record = record.duplicate(true)
	trackers._origins = (record["proficiency_origins"] as Array).duplicate(true)
	trackers._rows = [{"name": "Risorsa", "max": 2, "origin_id": sid}]
	trackers._refresh_origins()
	_card(trackers)

	var defenses := Defenses.new()
	root.add_child(defenses)
	defenses.setup(Callable())
	defenses.load_record({"kind": "monster", "stat_block":
		{"name": "Guardian", "resist": ["fire"]},
		"proficiency_origins": [], "damage_defense_entries": []})
	_card(defenses)
	assert(defenses._origin_buttons.has("__manual__"))
	assert(defenses._origin_buttons["__manual__"] is Button)

	owner.queue_free()
	bonus.queue_free()
	prof.queue_free()
	feats.queue_free()
	trackers.queue_free()
	defenses.queue_free()
	await process_frame
	print("PASS: unified origin cards, domain actions, disabled selections and all five editors")
	quit()
