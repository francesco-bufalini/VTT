extends VBoxContainer

# Origin editor for additive bonuses, shared by every framed formula value.
# Changes are persisted on the creature, not on individual GUI widgets.
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")

var _changed: Callable
var _record: Dictionary = {}
var _rows: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _selected_target := "initiative"
var _target_picker: OptionButton
var _origin_picker: OptionButton
var _custom_name: LineEdit
var _cards: VBoxContainer
var _summary: Label
var _loading := false


func setup(on_change: Callable) -> void:
	_changed = on_change
	add_theme_constant_override("separation", 7)
	var heading := Label.new()
	heading.text = "BONUS ALLE FORMULE"
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)
	var hint := Label.new()
	hint.text = "I bonus si sommano. Usa formule senza dadi, ad es. str_mod, proficiency, 2 * wis_mod."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 6)
	add_child(controls)
	var target_label := Label.new()
	target_label.text = "Statistica"
	controls.add_child(target_label)
	_target_picker = OptionButton.new()
	_target_picker.custom_minimum_size.x = 200
	_target_picker.item_selected.connect(_on_target_changed)
	controls.add_child(_target_picker)
	var origin_label := Label.new()
	origin_label.text = "Origine"
	controls.add_child(origin_label)
	_origin_picker = OptionButton.new()
	_origin_picker.custom_minimum_size.x = 185
	controls.add_child(_origin_picker)
	_custom_name = LineEdit.new()
	_custom_name.custom_minimum_size.x = 120
	_custom_name.placeholder_text = "Nuova origine"
	_custom_name.tooltip_text = "Per una nuova origine personalizzata, inserisci un nome e scegli 'Personalizzata'."
	controls.add_child(_custom_name)
	var add := Button.new()
	add.text = "+ Bonus"
	add.pressed.connect(_add_bonus)
	controls.add_child(add)
	_summary = Label.new()
	add_child(_summary)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 3)
	add_child(_cards)


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_rows = Bonuses.grants(_record)
	_origins.clear()
	var existing: Variant = _record.get("proficiency_origins", [])
	if existing is Array:
		for value: Variant in existing:
			if value is Dictionary:
				_origins.append((value as Dictionary).duplicate(true))
	_refresh_pickers()
	_refresh_cards()
	_loading = false


func select_target(target: String) -> void:
	_selected_target = target
	_refresh_pickers()
	_refresh_cards()


func _all_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"key": "hp", "name": "PF massimi"},
		{"key": "second_max", "name": "PF seconda forma"},
		{"key": "ac", "name": "Classe Armatura"},
		{"key": "initiative", "name": "Iniziativa"},
		{"key": "speed", "name": "Velocità"},
		{"key": "proficiency", "name": "Bonus competenza"},
		{"key": "passive_perception", "name": "Percezione passiva"}
	]
	for ability: String in Bonuses.ABILITIES:
		result.append({"key": "ability:" + ability, "name": ability.to_upper() + " · Punteggio"})
		result.append({"key": "ability_mod:" + ability, "name": ability.to_upper() + " · Modificatore"})
		result.append({"key": "save:" + ability, "name": ability.to_upper() + " · Tiro salvezza"})
	for skill: Dictionary in Skills.SKILLS:
		result.append({"key": "skill:" + String(skill["id"]), "name": "Abilità · " + String(skill["label"])})
	for attack: Dictionary in Attacks.definitions(_record):
		var aid: String = String(attack.get("id", ""))
		var label: String = String(attack.get("name", aid))
		for section: Dictionary in [
			{"key": "attack_hit:", "name": "Colpire"},
			{"key": "attack_damage:", "name": "Danni"},
			{"key": "attack_range:", "name": "Gittata"}
		]:
			result.append({"key": String(section["key"]) + aid, "name": String(section["name"]) + " · " + label})
	for lvl: int in range(1, 10):
		result.append({"key": "slot:" + str(lvl), "name": "Slot livello " + str(lvl)})
	result.append({"key": "pact_slot", "name": "Slot del Patto"})
	for row: Dictionary in _rows:
		var key: String = String(row.get("target", ""))
		var exists := false
		for known: Dictionary in result:
			if String(known["key"]) == key:
				exists = true
				break
		if not exists:
			result.append({"key": key, "name": "Non più presente · " + key})
	return result


func _refresh_pickers() -> void:
	if _target_picker == null:
		return
	_target_picker.clear()
	for entry: Dictionary in _all_targets():
		_target_picker.add_item(String(entry["name"]))
		_target_picker.set_item_metadata(_target_picker.item_count - 1, String(entry["key"]))
	var selected := 0
	for index: int in range(_target_picker.item_count):
		if String(_target_picker.get_item_metadata(index)) == _selected_target:
			selected = index
			break
	_target_picker.select(selected)
	_selected_target = String(_target_picker.get_item_metadata(selected))
	_origin_picker.clear()
	_origin_picker.add_item("Manuale")
	_origin_picker.set_item_metadata(0, {"id": "", "name": "Manuale"})
	_origin_picker.add_item("Personalizzata…")
	_origin_picker.set_item_metadata(1, {"id": "~new~", "name": ""})
	var options: Dictionary = {}
	var effective: Dictionary = _record.duplicate(true)
	effective["proficiency_origins"] = _origins.duplicate(true)
	for origin: Dictionary in Bonuses.available_origins(effective):
		var id: String = String(origin.get("id", ""))
		if options.has(id):
			continue
		options[id] = true
		_origin_picker.add_item(String(origin.get("name", "")) + (" (non attiva)" if bool(origin.get("disabled", false)) else ""))
		_origin_picker.set_item_metadata(_origin_picker.item_count - 1, {"id": id, "name": String(origin.get("name", ""))})


func _on_target_changed(index: int) -> void:
	_selected_target = String(_target_picker.get_item_metadata(index))
	_refresh_cards()


func _add_bonus() -> void:
	var source: Dictionary = _origin_picker.get_item_metadata(_origin_picker.selected)
	var sid: String = String(source.get("id", ""))
	var origin_name: String = String(source.get("name", "Manuale"))
	if sid == "~new~":
		origin_name = _custom_name.text.strip_edges()
		if origin_name.is_empty():
			_summary.text = "Inserisci il nome della nuova origine."
			return
		sid = "custom|" + origin_name.to_lower().uri_encode()
		var found := false
		for origin: Dictionary in _origins:
			if String(origin.get("id", "")) == sid:
				found = true
				break
		if not found:
			_origins.append({"id": sid, "name": origin_name, "group": "custom", "disabled": false, "automatic": false})
	if _selected_target.is_empty():
		return
	_rows.append({
		"id": "bonus_%d" % Time.get_ticks_usec(),
		"target": _selected_target, "expression": "0",
		"origin_id": sid, "origin_name": origin_name, "disabled": false
	})
	_custom_name.clear()
	_publish()


func _refresh_cards() -> void:
	if _cards == null:
		return
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var effective: Dictionary = _record.duplicate(true)
	effective["formula_bonuses"] = _rows.duplicate(true)
	effective["proficiency_origins"] = _origins.duplicate(true)
	var active: int = 0
	for index: int in range(_rows.size()):
		var row: Dictionary = _rows[index]
		if String(row.get("target", "")) != _selected_target:
			continue
		active += 1
		var line := HBoxContainer.new()
		_cards.add_child(line)
		var enabled := CheckBox.new()
		enabled.button_pressed = not bool(row.get("disabled", false))
		enabled.tooltip_text = "Bonus attivo"
		enabled.toggled.connect(_set_enabled.bind(index))
		line.add_child(enabled)
		var source: Label = Label.new()
		source.text = String(row.get("origin_name", "Manuale"))
		source.custom_minimum_size.x = 150
		source.clip_text = true
		line.add_child(source)
		var expression := LineEdit.new()
		expression.text = String(row.get("expression", "0"))
		expression.placeholder_text = "Formula senza dadi"
		expression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expression.text_submitted.connect(func(v: String) -> void: _set_expression(v, index))
		expression.focus_exited.connect(func() -> void: _set_expression(expression.text, index))
		line.add_child(expression)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Elimina solo questo bonus dalla sua origine"
		remove.pressed.connect(_remove.bind(index))
		line.add_child(remove)
	_summary.text = ("%d bonus assegnati a questo valore.\n" % active) + Bonuses.description(effective, _selected_target)
	if active == 0:
		_summary.text = "Nessun bonus su questo valore."


func _set_expression(value: String, index: int) -> void:
	if index < 0 or index >= _rows.size() or String(_rows[index].get("expression", "")) == value.strip_edges():
		return
	_rows[index]["expression"] = value.strip_edges()
	_publish()


func _set_enabled(enabled: bool, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index]["disabled"] = not enabled
	_publish()


func _remove(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows.remove_at(index)
	_publish()


func _publish() -> void:
	_record["formula_bonuses"] = _rows.duplicate(true)
	_record["proficiency_origins"] = _origins.duplicate(true)
	_refresh_pickers()
	_refresh_cards()
	if not _loading and _changed.is_valid():
		_changed.call(_rows.duplicate(true), _origins.duplicate(true))
