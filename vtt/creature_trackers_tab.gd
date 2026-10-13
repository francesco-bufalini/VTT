extends VBoxContainer
const EditorUI = preload("res://vtt/origin_editor_ui.gd")

const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")

# Resource editor using the same origin/grant layout as proficiencies,
# feats and numeric bonuses. A source is only listed if it grants a tracker.
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const ResourceOverrides = preload("res://vtt/class_resource_overrides.gd")
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const OriginButton = preload("res://vtt/bounded_tooltip_button.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")

var _changed: Callable
var _record: Dictionary = {}
var _manual: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _selected_origin := ""
var _loading := false
var _status: Label
var _origin_cards: VBoxContainer
var _tracker_cards: VBoxContainer
var _name_input: LineEdit
var _maximum_input: SpinBox
var _formula_input: LineEdit
var _recharge_input: OptionButton
var _origin_picker: OptionButton
var _description_cache: Dictionary = {}


func setup(on_change: Callable) -> void:
	_changed = on_change
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var columns := HBoxContainer.new()
	columns.name = "EditorColumns"
	columns.add_theme_constant_override("separation", 9)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := _column(columns, "Origini dei tracker", 190)
	var right := _column(columns, "Risorse e utilizzi", 260)
	var origin_scroll := ScrollContainer.new()
	origin_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(origin_scroll)
	origin_scroll.custom_minimum_size.y = 245
	origin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(origin_scroll)
	_origin_cards = VBoxContainer.new()
	_origin_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_cards.add_theme_constant_override("separation", 5)
	origin_scroll.add_child(_origin_cards)
	var tracker_scroll := ScrollContainer.new()
	tracker_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(tracker_scroll)
	tracker_scroll.custom_minimum_size.y = 245
	tracker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(tracker_scroll)
	_tracker_cards = VBoxContainer.new()
	_tracker_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tracker_cards.add_theme_constant_override("separation", 5)
	tracker_scroll.add_child(_tracker_cards)

	var editor := VBoxContainer.new()
	editor.add_theme_constant_override("separation", 4)
	right.add_child(editor)
	var first := HBoxContainer.new()
	editor.add_child(first)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Nome del tracker"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.add_child(_name_input)
	_maximum_input = SpinBox.new()
	_maximum_input.min_value = 0
	_maximum_input.max_value = 99999
	_maximum_input.value = 1
	_maximum_input.custom_minimum_size.x = 86
	_maximum_input.tooltip_text = "Numero massimo di utilizzi, se non viene inserita una formula"
	first.add_child(_maximum_input)
	_formula_input = LineEdit.new()
	_formula_input.placeholder_text = "Formula max (es. cha_mod)"
	_formula_input.custom_minimum_size.x = 128
	_formula_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_formula_input.tooltip_text = "Formula dinamica opzionale: cha_mod, wis_mod, proficiency, level, operazioni aritmetiche"
	first.add_child(_formula_input)
	var second := HBoxContainer.new()
	editor.add_child(second)
	_recharge_input = OptionButton.new()
	for label: String in ["Ricarica manuale", "Inizio turno", "Riposo breve", "Riposo lungo"]:
		_recharge_input.add_item(label)
	_recharge_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.add_child(_recharge_input)
	_origin_picker = OptionButton.new()
	_origin_picker.fit_to_longest_item = false
	_origin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_picker.custom_minimum_size.x = 130
	_origin_picker.tooltip_text = "Origine del tracker; viene registrata solo quando aggiungi la risorsa"
	second.add_child(_origin_picker)
	var add := Button.new()
	add.text = "+ Tracker"
	add.pressed.connect(_add_tracker)
	second.add_child(add)
	EditorUI.popup_form(self, editor, "+ Tracker", add)
	load_record({})


func _column(parent: HBoxContainer, heading: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 15)
	body.add_child(title)
	return body


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_description_cache.clear()
	_origins = Rules.origins(_record)
	_manual.clear()
	var saved: Variant = _record.get("resource_trackers", [])
	if saved is Array:
		for value: Variant in saved:
			if value is Dictionary:
				_manual.append((value as Dictionary).duplicate(true))
	_rows = Trackers.for_creature(_record)
	_refresh()
	_loading = false


func _effective_record() -> Dictionary:
	var effective: Dictionary = _record.duplicate(true)
	effective["resource_trackers"] = _manual.duplicate(true)
	effective["proficiency_origins"] = _origins.duplicate(true)
	return effective


func _source_name(sid: String) -> String:
	if sid.is_empty():
		return "Senza origine"
	for entry: Dictionary in _origins:
		if String(entry.get("id", "")) == sid:
			return String(entry.get("name", sid))
	for entry: Dictionary in _rows:
		if String(entry.get("origin_id", "")) == sid:
			return String(entry.get("origin_name", sid))
	return sid


func _source_tooltip(sid: String) -> String:
	if not _description_cache.has(sid):
		var info: String = _source_name(sid)
		if sid.begins_with("feature:"):
			for feature: Dictionary in Traits.collect_features(_record):
				if "feature:" + String(feature.get("key", "")) == sid:
					info = Catalog.info_text(feature, Catalog.description_text("", feature))
					break
		elif sid.begins_with("item:"):
			for owned: Variant in _record.get("inventory", []):
				if owned is Dictionary and sid == "item:" + String(owned.get("id", "")):
					var item: Dictionary = Items.entry_for(owned)
					info = Catalog.info_text(item, Catalog.description_text("items", item))
					break
		else:
			for candidate: Dictionary in Rules.candidate_sources(_record):
				if String(candidate.get("id", "")) != sid:
					continue
				var category: String = {
					"race": "races", "subrace": "races", "background": "backgrounds",
					"feat": "feats", "class": "classes"
				}.get(String(candidate.get("group", "")), "")
				var data: Dictionary = candidate.get("data", {})
				info = Catalog.info_text(data, Catalog.description_text(category, data))
				break
		_description_cache[sid] = info
	var lines: PackedStringArray = []
	for row: Dictionary in _rows:
		if String(row.get("origin_id", "")) == sid:
			lines.append(("○ " if bool(row.get("disabled", false)) else "✓ ")
				+ String(row.get("name", "")) + ": " + str(row.get("max", 0)))
	return String(_description_cache[sid]) + ("\n\nTracker assegnati:\n" + "\n".join(lines) if not lines.is_empty() else "")


func _refresh() -> void:
	_status.text = "Seleziona un'origine per evidenziarne i tracker. Aggiungi nuove risorse a destra e assegna l'origine nello stesso passaggio."
	OriginChoices.populate(_origin_picker, _effective_record(), _selected_origin)
	_refresh_origins()
	_refresh_trackers()


func _refresh_origins() -> void:
	for node: Node in _origin_cards.get_children():
		_origin_cards.remove_child(node)
		node.queue_free()
	var counts: Dictionary = {}
	for row: Dictionary in _rows:
		var sid: String = String(row.get("origin_id", ""))
		counts[sid] = int(counts.get(sid, 0)) + 1
	var enabled: Dictionary = Rules.origin_enabled_map(_effective_record())
	var display_names: Dictionary = OriginChoices.display_labels(_origins, _effective_record())
	for sid: String in counts.keys():
		var panel := PanelContainer.new()
		_origin_cards.add_child(panel)
		var line := HBoxContainer.new()
		panel.add_child(line)
		var select := OriginButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.clip_text = true
		select.toggle_mode = true
		select.button_pressed = _selected_origin == sid
		select.text = String(display_names.get(sid, _source_name(sid))) + " (%d)" % int(counts[sid])
		select.tooltip_text = _source_tooltip(sid)
		select.pressed.connect(_select_origin.bind(sid))
		line.add_child(select)
		EditorUI.origin_link(self, line, sid, _source_name(sid))
		if not sid.is_empty():
			var toggle := CheckButton.new()
			toggle.text = "⏻"
			toggle.button_pressed = bool(enabled.get(sid, true))
			toggle.tooltip_text = "Attiva/disattiva le risorse con questa origine, senza eliminarle"
			toggle.toggled.connect(_toggle_origin.bind(sid))
			line.add_child(toggle)
		if _selected_origin == sid:
			var border := StyleBoxFlat.new()
			border.draw_center = false
			border.border_color = Color(0.40, 0.72, 0.91)
			border.set_border_width_all(2)
			border.set_corner_radius_all(5)
			panel.add_theme_stylebox_override("panel", border)
		elif not bool(enabled.get(sid, true)):
			panel.modulate.a = 0.58


func _refresh_trackers() -> void:
	for node: Node in _tracker_cards.get_children():
		_tracker_cards.remove_child(node)
		node.queue_free()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Nessun tracker disponibile."
		_tracker_cards.add_child(empty)
		return
	var enabled: Dictionary = Rules.origin_enabled_map(_effective_record())
	for entry: Dictionary in _rows:
		var tracker_id: String = String(entry.get("id", ""))
		var sid: String = String(entry.get("origin_id", ""))
		var automatic: bool = bool(entry.get("automatic", false))
		var active: bool = not bool(entry.get("disabled", false)) and bool(enabled.get(sid, true))
		var panel := PanelContainer.new()
		_tracker_cards.add_child(panel)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
		style.border_color = Color(0.40, 0.72, 0.91) if sid == _selected_origin else Color(0.36, 0.31, 0.27, 0.75)
		style.set_border_width_all(2 if sid == _selected_origin else 1)
		style.set_corner_radius_all(5)
		style.set_content_margin_all(7)
		panel.add_theme_stylebox_override("panel", style)
		panel.tooltip_text = _source_tooltip(sid)
		var body := VBoxContainer.new()
		panel.add_child(body)
		var line := HBoxContainer.new()
		body.add_child(line)
		var details := HBoxContainer.new()
		body.add_child(details)
		var name_label := Label.new()
		name_label.text = String(entry.get("name", "Tracker"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		line.add_child(name_label)
		if automatic:
			var maximum := Label.new()
			maximum.text = "Max: " + (String(entry.get("max_formula", "")) if not String(entry.get("max_formula", "")).is_empty() else str(int(entry.get("max", 0))))
			var formula: String = String(entry.get("max_formula", ""))
			maximum.tooltip_text = ("Formula: " + formula if not formula.is_empty()
				else "Massimo derivato dai dati strutturati")
			line.add_child(maximum)
		else:
			var input := SpinBox.new()
			input.min_value = 0
			input.max_value = 99999
			input.value = int(entry.get("max", 0))
			input.custom_minimum_size.x = 86
			input.tooltip_text = "Massimo utilizzi"

			line.add_child(input)
			var formula_editor := LineEdit.new()
			formula_editor.text = String(entry.get("max_formula", ""))
			formula_editor.placeholder_text = "formula"
			formula_editor.custom_minimum_size.x = 90
			formula_editor.tooltip_text = "Formula massimo; conferma con Invio. Lascia vuoto per usare il valore fisso."

			formula_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.add_child(formula_editor)
			var maximum_label := Label.new()
			maximum_label.text = "Max: " + (formula_editor.text if not formula_editor.text.is_empty() else str(int(input.value)))
			line.add_child(maximum_label)
			EditorUI.edit_fields(panel, details, [input, formula_editor], "massimo", func() -> void: _save_maximum(tracker_id, int(input.value), formula_editor.text))
			var toggle := CheckButton.new()
			toggle.text = "⏻"
			toggle.button_pressed = not bool(entry.get("disabled", false))
			toggle.toggled.connect(_set_enabled.bind(tracker_id))
			line.add_child(toggle)
			var remove := Button.new()
			remove.text = "✕"
			remove.flat = true
			remove.tooltip_text = "Rimuovi solo questo tracker"
			remove.pressed.connect(_remove.bind(tracker_id))
			line.add_child(remove)
		var recovery_key: String = String(entry.get("recharge", "manual"))
		if automatic:
			var recovery := Label.new()
			recovery.text = {
				"short_rest": "Riposo breve", "long_rest": "Riposo lungo",
				"turn": "Inizio turno", "d6": "D6", "manual": "Manuale"
			}.get(recovery_key, recovery_key)
			recovery.tooltip_text = "Recupero del tracker"
			details.add_child(recovery)
		else:
			var recovery_edit := OptionButton.new()
			var modes: Array[String] = ["manual", "turn", "short_rest", "long_rest"]
			for label: String in ["Ricarica manuale", "Inizio turno", "Riposo breve", "Riposo lungo"]:
				recovery_edit.add_item(label)
			recovery_edit.select(maxi(0, modes.find(recovery_key)))
			recovery_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			details.add_child(recovery_edit)
			EditorUI.edit_fields(panel, details, [recovery_edit], "recupero", func() -> void: _set_recharge(recovery_edit.selected, tracker_id))
		if not active and sid != _selected_origin:
			panel.modulate.a = 0.58


func _select_origin(sid: String) -> void:
	_selected_origin = "" if _selected_origin == sid else sid
	_refresh_origins()
	_refresh_trackers()


func _toggle_origin(on: bool, sid: String) -> void:
	var source: Dictionary = {"id": sid, "name": _source_name(sid),
		"group": "custom" if sid.begins_with("tracker:auto:") else "feature"}
	OriginChoices.ensure(_origins, source)
	for entry: Dictionary in _origins:
		if String(entry.get("id", "")) == sid:
			entry["disabled"] = not on
			break
	_publish()


func _add_tracker() -> void:
	var title: String = _name_input.text.strip_edges()
	if title.is_empty():
		_status.text = "Inserisci il nome della nuova risorsa."
		return
	var source: Dictionary = OriginChoices.selected(_origin_picker)
	var sid: String = String(source.get("id", ""))
	OriginChoices.ensure(_origins, source)
	var formula: String = _formula_input.text.strip_edges()
	if not formula.is_empty() and ResourceOverrides.evaluate_max(formula, _record, int(_record.get("level", 1))).is_empty():
		_status.text = "Formula massimo non valida."
		return
	_manual.append({"id": "manual_%d" % Time.get_ticks_usec(),
		"name": title, "max": int(_maximum_input.value), "max_formula": formula,
		"origin_id": sid, "origin_name": String(source.get("name", "Senza origine")),
		"recharge": ["manual", "turn", "short_rest", "long_rest"][clampi(_recharge_input.selected, 0, 3)],
		"disabled": false})
	_selected_origin = sid
	_name_input.clear()
	_formula_input.clear()
	_publish()


func _set_maximum(value: float, tracker_id: String) -> void:
	for entry: Dictionary in _manual:
		if String(entry.get("id", "")) == tracker_id:
			entry["max"] = int(value)
			break
	_publish()


func _set_recharge(index: int, tracker_id: String) -> void:
	var choices: Array[String] = ["manual", "turn", "short_rest", "long_rest"]
	if index < 0 or index >= choices.size():
		return
	for entry: Dictionary in _manual:
		if String(entry.get("id", "")) == tracker_id:
			entry["recharge"] = choices[index]
			break
	_publish()


func _set_formula(formula: String, tracker_id: String) -> void:
	var cleaned: String = formula.strip_edges()
	if not cleaned.is_empty() and ResourceOverrides.evaluate_max(
		cleaned, _record, int(_record.get("level", 1))
	).is_empty():
		_status.text = "Formula massimo non valida."
		return
	for entry: Dictionary in _manual:
		if String(entry.get("id", "")) == tracker_id:
			entry["max_formula"] = cleaned
			break
	_publish()


func _set_enabled(on: bool, tracker_id: String) -> void:
	for entry: Dictionary in _manual:
		if String(entry.get("id", "")) == tracker_id:
			entry["disabled"] = not on
			break
	_publish()


func _remove(tracker_id: String) -> void:
	for i: int in range(_manual.size() - 1, -1, -1):
		if String(_manual[i].get("id", "")) == tracker_id:
			_manual.remove_at(i)
	_publish()


func _publish() -> void:
	_record["resource_trackers"] = _manual.duplicate(true)
	_record["proficiency_origins"] = _origins.duplicate(true)
	_rows = Trackers.for_creature(_record)
	_description_cache.clear()
	_refresh()
	if not _loading and _changed.is_valid():
		_changed.call(_manual.duplicate(true), _origins.duplicate(true))


func _save_maximum(tracker_id: String, maximum: int, formula: String) -> void:
	var cleaned: String = formula.strip_edges()
	if not cleaned.is_empty() and ResourceOverrides.evaluate_max(cleaned, _record, int(_record.get("level", 1))).is_empty():
		_status.text = "Formula massimo non valida."
		return
	for entry: Dictionary in _manual:
		if String(entry.get("id", "")) == tracker_id:
			entry["max"] = maximum
			entry["max_formula"] = cleaned
			break
	_publish()
