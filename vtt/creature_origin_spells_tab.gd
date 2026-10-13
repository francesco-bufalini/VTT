extends VBoxContainer
# Spell entitlements are edited with the same origin -> benefits pattern as
# proficiencies/trackers. Class spell preparation is NOT edited here.
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const ScrollGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")

const ABILITIES := ["", "str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := ["Automatica", "FOR", "DES", "COS", "INT", "SAG", "CAR"]
var _changed: Callable
var _record: Dictionary = {}
var _manual: Array = []
var _configs: Dictionary = {}
var _selected_origin := ""
var _origins: VBoxContainer
var _spells: VBoxContainer
var _origin_picker: OptionButton
var _spell_picker: OptionButton
var _spell_search: LineEdit
var _tracker_picker: OptionButton
var _payment_picker: OptionButton
var _ability_picker: OptionButton
var _catalog: Array[Dictionary] = []
var _shown: Array[Dictionary] = []
var _choice: Dictionary = {}
var _warning: Label


func setup(on_change: Callable) -> void:
	_changed = on_change
	add_theme_constant_override("separation", 8)
	var intro := Label.new()
	intro.text = "Incantesimi concessi dalle origini (talenti, razze, privilegi, oggetti)"
	intro.add_theme_font_size_override("font_size", 15)
	add_child(intro)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_warning)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	add_child(columns)
	var left := _column(columns, "Origini che concedono incantesimi", 195)
	var right := _column(columns, "Incantesimi concessi", 340)
	_origins = _scroll_column(left)
	_spells = _scroll_column(right)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 5)
	right.add_child(form)
	_origin_picker = OptionButton.new()
	_origin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_label("Origine da associare", form))
	form.add_child(_origin_picker)
	_spell_search = LineEdit.new()
	_spell_search.placeholder_text = "Cerca incantesimo..."
	_spell_search.text_changed.connect(_refresh_spell_picker)
	form.add_child(_label("Incantesimo", form))
	form.add_child(_spell_search)
	_spell_picker = OptionButton.new()
	_spell_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_spell_picker)
	var settings := HBoxContainer.new()
	form.add_child(settings)
	var pay := VBoxContainer.new()
	pay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(pay)
	_label("Consumo", pay)
	_payment_picker = OptionButton.new()
	for name: String in ["Senza costo", "Slot di classe", "Tracker"]:
		_payment_picker.add_item(name)
	pay.add_child(_payment_picker)
	var ability := VBoxContainer.new()
	ability.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(ability)
	_label("Caratteristica", ability)
	_ability_picker = OptionButton.new()
	for name: String in ABILITY_NAMES:
		_ability_picker.add_item(name)
	ability.add_child(_ability_picker)
	_label("Tracker (anche di un'altra origine)", form)
	_tracker_picker = OptionButton.new()
	_tracker_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_tracker_picker)
	var add := Button.new()
	add.text = "+ Concedi incantesimo"
	add.pressed.connect(_add)
	form.add_child(add)
	load_record({})


func _label(value: String, parent: Control) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label


func _column(parent: HBoxContainer, caption: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	_label(caption, box)
	return box


func _scroll_column(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	ScrollGuard.install(scroll)
	scroll.custom_minimum_size.y = 245
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content


func load_record(record: Dictionary) -> void:
	_record = record.duplicate(true)
	_manual = (record.get("origin_spell_grants", []) as Array).duplicate(true) if record.get("origin_spell_grants", []) is Array else []
	_configs = (record.get("origin_spell_configs", {}) as Dictionary).duplicate(true) if record.get("origin_spell_configs", {}) is Dictionary else {}
	_catalog = Catalog.all_spells_for_rules(String(record.get("rules_version", "2014")))
	_choice.clear()
	_refresh()


func _current_record() -> Dictionary:
	var record: Dictionary = _record.duplicate(true)
	record["origin_spell_grants"] = _manual.duplicate(true)
	record["origin_spell_configs"] = _configs.duplicate(true)
	return record


func _clear(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _refresh() -> void:
	if _origins == null:
		return
	var record: Dictionary = _current_record()
	var grants: Array[Dictionary] = OriginSpells.all_grants(record)
	var structured: Dictionary = Structured.for_creature(record)
	var groups: Dictionary = {}
	for grant: Dictionary in grants:
		var sid: String = String(grant.get("origin_id", ""))
		if not groups.has(sid):
			groups[sid] = []
		groups[sid].append(grant)
	var warnings: Array[String] = []
	for raw: Variant in structured.get("choices", []):
		if not raw is Dictionary:
			continue
		var choice: Dictionary = raw
		var selected := 0
		for saved: Variant in _manual:
			if saved is Dictionary and String(saved.get("source_choice_id", "")) == String(choice.get("id", "")):
				selected += 1
		if selected >= int(choice.get("count", 1)):
			continue
		var sid: String = String(choice.get("origin_id", ""))
		if not groups.has(sid):
			groups[sid] = []
		var pending: Dictionary = choice.duplicate(true)
		pending["pending_selection"] = true
		groups[sid].append(pending)
		warnings.append(String(choice.get("origin_name", sid)) + ": " + str(int(choice.get("count", 1)) - selected) + " scelta/e")
	_warning.text = "⚠ " + "; ".join(warnings) if not warnings.is_empty() else ""
	_clear(_origins)
	_clear(_spells)
	if not groups.has(_selected_origin):
		_selected_origin = String(groups.keys()[0]) if not groups.is_empty() else ""
	for sid: String in groups.keys():
		var source_entries: Array = groups[sid]
		var first: Dictionary = source_entries[0]
		var select := Button.new()
		select.text = String(first.get("origin_name", sid)) + " (%d)" % source_entries.size()
		select.toggle_mode = true
		select.button_pressed = _selected_origin == sid
		select.pressed.connect(_select_origin.bind(sid))
		_origins.add_child(select)
	if _selected_origin.is_empty():
		_label("Nessuna concessione. Usa il menu a destra per aggiungerne una.", _spells)
	else:
		for raw: Variant in groups.get(_selected_origin, []):
			var grant: Dictionary = raw
			if bool(grant.get("pending_selection", false)):
				var choose := Button.new()
				choose.text = "⚠ Scegli %d incantesimo/i · %s" % [int(grant.get("count", 1)), String(grant.get("filter", ""))]
				choose.pressed.connect(_choose.bind(grant.duplicate(true)))
				_spells.add_child(choose)
				continue
			_draw_grant(grant, record)
	_fill_origin_picker(record)
	_fill_tracker_picker(record)
	_refresh_spell_picker(_spell_search.text)


func _draw_grant(grant: Dictionary, record: Dictionary) -> void:
	var id: String = String(grant.get("id", ""))
	var spell: Dictionary = Catalog.catalog_spell(String(grant.get("spell_id", "")))
	var panel := VBoxContainer.new()
	_spells.add_child(panel)
	var heading := HBoxContainer.new()
	panel.add_child(heading)
	var title := Label.new()
	title.text = String(spell.get("name", grant.get("spell_id", "")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	if not bool(grant.get("automatic", false)):
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Rimuovi la concessione"
		remove.pressed.connect(_remove.bind(id))
		heading.add_child(remove)
	var settings := HBoxContainer.new()
	panel.add_child(settings)
	var pay := OptionButton.new()
	for name: String in ["Senza costo", "Slot di classe", "Tracker"]:
		pay.add_item(name)
	pay.select(["free", "slot", "tracker"].find(String(grant.get("payment_mode", "free"))))
	pay.item_selected.connect(_set_option.bind(id, "payment_mode", ["free", "slot", "tracker"]))
	settings.add_child(pay)
	var ability := OptionButton.new()
	for name: String in ABILITY_NAMES:
		ability.add_item(name)
	ability.select(maxi(0, ABILITIES.find(String(grant.get("spellcasting_ability", "")))))
	ability.item_selected.connect(_set_option.bind(id, "spellcasting_ability", ABILITIES))
	settings.add_child(ability)
	var trackers := OptionButton.new()
	trackers.add_item("Senza tracker")
	trackers.set_item_metadata(0, "")
	var select := 0
	for tracker: Dictionary in Trackers.for_creature(record):
		var tid: String = String(tracker.get("id", ""))
		trackers.add_item(String(tracker.get("name", tid)))
		trackers.set_item_metadata(trackers.item_count - 1, tid)
		if tid == String(grant.get("tracker_id", "")):
			select = trackers.item_count - 1
	trackers.select(select)
	trackers.item_selected.connect(_set_tracker.bind(id, trackers))
	panel.add_child(trackers)
	trackers.visible = String(grant.get("payment_mode", "")) == "tracker"
	var separator := HSeparator.new()
	panel.add_child(separator)


func _select_origin(sid: String) -> void:
	_selected_origin = sid
	_refresh()


func _fill_origin_picker(record: Dictionary) -> void:
	var current: String = ""
	if _origin_picker.selected >= 0:
		current = String(_origin_picker.get_item_metadata(_origin_picker.selected))
	_origin_picker.clear()
	for source: Dictionary in OriginChoices.available(record):
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or sid == OriginChoices.SPELL_PICKER_ID:
			continue
		_origin_picker.add_item(String(source.get("name", sid)))
		_origin_picker.set_item_metadata(_origin_picker.item_count - 1, sid)
		if sid == current or (current.is_empty() and sid == _selected_origin):
			_origin_picker.select(_origin_picker.item_count - 1)


func _fill_tracker_picker(record: Dictionary) -> void:
	_tracker_picker.clear()
	_tracker_picker.add_item("Nessuno")
	_tracker_picker.set_item_metadata(0, "")
	for tracker: Dictionary in Trackers.for_creature(record):
		_tracker_picker.add_item(String(tracker.get("name", "")))
		_tracker_picker.set_item_metadata(_tracker_picker.item_count - 1, String(tracker.get("id", "")))


func _refresh_spell_picker(value: String) -> void:
	_spell_picker.clear()
	_shown.clear()
	var query: String = value.strip_edges().to_lower()
	for spell: Dictionary in _catalog:
		if bool(spell.get("internal_grant", false)) and _choice.is_empty():
			continue
		if not _choice.is_empty() and not _matches_choice(spell):
			continue
		if not query.is_empty() and query not in String(spell.get("name", "")).to_lower():
			continue
		_shown.append(spell)
		_spell_picker.add_item(String(spell.get("name", "")) + " [" + String(spell.get("source", "")) + "]")
		if _shown.size() >= 300:
			break


func _matches_choice(spell: Dictionary) -> bool:
	var filters: Array = _choice.get("filters", [])
	if filters.is_empty():
		filters = [String(_choice.get("filter", ""))]
	for item: Variant in filters:
		var valid := true
		for clause: String in String(item).to_lower().split("|"):
			var parts: PackedStringArray = clause.split("=", true, 1)
			if parts.size() != 2:
				continue  # Unknown operators: permit a wider choice, not a wrong one.
			var vals: PackedStringArray = parts[1].split(";")
			match parts[0]:
				"level":
					if str(int(spell.get("level", -1))) not in vals:
						valid = false
				"class":
					var matched := false
					for classname: Variant in spell.get("classes", []):
						if String(classname).to_lower() in vals:
							matched = true
					if not matched:
						valid = false
				"school":
					var codes := {"Abjuration": "a", "Conjuration": "c", "Divination": "d", "Enchantment": "e", "Evocation": "v", "Illusion": "i", "Necromancy": "n", "Transmutation": "t"}
					if String(spell.get("school", "")).to_lower() not in vals and String(codes.get(String(spell.get("school", "")), "")) not in vals:
						valid = false
		if valid:
			return true
	return false


func _choose(choice: Dictionary) -> void:
	_choice = choice.duplicate(true)
	_selected_origin = String(choice.get("origin_id", ""))
	_fill_origin_picker(_current_record())
	for i: int in range(_origin_picker.item_count):
		if String(_origin_picker.get_item_metadata(i)) == _selected_origin:
			_origin_picker.select(i)
			break
	_spell_search.clear()
	_refresh_spell_picker("")
	_payment_picker.select(2 if not String(choice.get("tracker_id", "")).is_empty() else 0)
	for i: int in range(_tracker_picker.item_count):
		if String(_tracker_picker.get_item_metadata(i)) == String(choice.get("tracker_id", "")):
			_tracker_picker.select(i)
			break
	_warning.text = "Scelta per " + String(choice.get("origin_name", "")) + ": " + String(choice.get("filter", ""))


func _add() -> void:
	if _origin_picker.selected < 0 or _spell_picker.selected < 0 or _spell_picker.selected >= _shown.size():
		return
	var spell: Dictionary = _shown[_spell_picker.selected]
	var sid: String = String(_origin_picker.get_item_metadata(_origin_picker.selected))
	var spell_id: String = String(spell.get("id", ""))
	if sid.is_empty() or spell_id.is_empty():
		return
	if not _choice.is_empty() and sid != String(_choice.get("origin_id", "")):
		return
	var choice_id: String = String(_choice.get("id", ""))
	if not choice_id.is_empty():
		var count := 0
		for raw: Variant in _manual:
			if raw is Dictionary and String(raw.get("source_choice_id", "")) == choice_id:
				count += 1
		if count >= int(_choice.get("count", 1)):
			return
	for raw: Variant in _manual:
		if raw is Dictionary and String(raw.get("origin_id", "")) == sid and String(raw.get("spell_id", "")) == spell_id:
			return
	_manual.append({
		"id": "origin_spell_%d" % Time.get_ticks_usec(),
		"origin_id": sid, "origin_name": _origin_picker.get_item_text(_origin_picker.selected),
		"spell_id": spell_id,
		"tracker_id": String(_tracker_picker.get_item_metadata(_tracker_picker.selected)),
		"payment_mode": ["free", "slot", "tracker"][_payment_picker.selected],
		"spellcasting_ability": ABILITIES[_ability_picker.selected],
		"source_choice_id": choice_id
	})
	_choice.clear()
	_publish()


func _set_option(index: int, id: String, field: String, values: Array) -> void:
	if index < 0 or index >= values.size():
		return
	var row: Dictionary = _configs.get(id, {}).duplicate(true)
	row[field] = values[index]
	_configs[id] = row
	_publish()


func _set_tracker(index: int, id: String, picker: OptionButton) -> void:
	if index < 0:
		return
	var row: Dictionary = _configs.get(id, {}).duplicate(true)
	row["tracker_id"] = String(picker.get_item_metadata(index))
	_configs[id] = row
	_publish()


func _remove(id: String) -> void:
	for i: int in range(_manual.size() - 1, -1, -1):
		if _manual[i] is Dictionary and String(_manual[i].get("id", "")) == id:
			_manual.remove_at(i)
	_configs.erase(id)
	_publish()


func _publish() -> void:
	_record["origin_spell_grants"] = _manual.duplicate(true)
	_record["origin_spell_configs"] = _configs.duplicate(true)
	if _changed.is_valid():
		_changed.call(_manual.duplicate(true), _configs.duplicate(true))
	_refresh()
