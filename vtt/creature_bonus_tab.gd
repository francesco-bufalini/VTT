extends VBoxContainer

# The same two-column origin/benefit editor used by proficiencies. Unlike
# proficiencies, each individual bonus is kept, even when targets/amounts match.
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const OriginButton = preload("res://vtt/bounded_tooltip_button.gd")

var _changed: Callable
var _record: Dictionary = {}
var _rows: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _selected_origin := ""
var _selected_target := ""
var _origin_cards: VBoxContainer
var _bonus_cards: VBoxContainer
var _status: Label
var _origin_editor: VBoxContainer
var _origin_picker: OptionButton
var _origin_name: LineEdit
var _target_filter: OptionButton
var _new_target: OptionButton
var _loading := false
var _description_cache: Dictionary = {}


func setup(on_change: Callable) -> void:
	_changed = on_change
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 9)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := _make_column(columns, "Origini dei bonus", 190)
	var right := _make_column(columns, "Bonus per statistica", 260)

	var origin_scroll := ScrollContainer.new()
	origin_scroll.custom_minimum_size.y = 245
	origin_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	origin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(origin_scroll)
	_origin_cards = VBoxContainer.new()
	_origin_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_cards.add_theme_constant_override("separation", 5)
	origin_scroll.add_child(_origin_cards)
	var add_origin := Button.new()
	add_origin.text = "+ Origine"
	add_origin.pressed.connect(func() -> void:
		_origin_editor.visible = not _origin_editor.visible
	)
	left.add_child(add_origin)
	_origin_editor = VBoxContainer.new()
	_origin_editor.hide()
	left.add_child(_origin_editor)
	_origin_picker = OptionButton.new()
	_origin_editor.add_child(_origin_picker)
	_origin_name = LineEdit.new()
	_origin_name.placeholder_text = "Nome origine personalizzata"
	_origin_editor.add_child(_origin_name)
	var confirm_origin := Button.new()
	confirm_origin.text = "Seleziona / aggiungi origine"
	confirm_origin.pressed.connect(_add_origin)
	_origin_editor.add_child(confirm_origin)

	_target_filter = OptionButton.new()
	_target_filter.fit_to_longest_item = false
	_target_filter.add_item("Tutti i target")
	_target_filter.set_item_metadata(0, "")
	_target_filter.item_selected.connect(_on_filter_changed)
	right.add_child(_target_filter)
	var bonuses_scroll := ScrollContainer.new()
	bonuses_scroll.custom_minimum_size.y = 245
	bonuses_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bonuses_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(bonuses_scroll)
	_bonus_cards = VBoxContainer.new()
	_bonus_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_cards.add_theme_constant_override("separation", 5)
	bonuses_scroll.add_child(_bonus_cards)
	var new_row := HBoxContainer.new()
	right.add_child(new_row)
	_new_target = OptionButton.new()
	_new_target.fit_to_longest_item = false
	_new_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_target.custom_minimum_size.x = 115
	new_row.add_child(_new_target)
	var add_bonus := Button.new()
	add_bonus.text = "+ Bonus"
	add_bonus.tooltip_text = "Aggiungi un bonus all'origine selezionata. I bonus uguali di origini diverse non vengono unificati."
	add_bonus.pressed.connect(_add_bonus)
	new_row.add_child(add_bonus)
	load_record({})


func _make_column(parent: HBoxContainer, title: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 15)
	content.add_child(heading)
	return content


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_description_cache.clear()
	_rows = Bonuses.grants(_record)
	_origins = Proficiencies.origins(_record)
	# Sources without proficiencies are also available to the bonus editor.
	for entry: Dictionary in Bonuses.available_origins(_record):
		var found := false
		for origin: Dictionary in _origins:
			if String(origin.get("id", "")) == String(entry.get("id", "")):
				found = true
				break
		if not found:
			_origins.append(entry.duplicate(true))
	_refresh_options()
	_refresh()
	_loading = false


func select_target(target: String) -> void:
	_selected_target = target
	_refresh_options()
	_refresh()


func _all_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"key": "hp", "name": "PF massimi"},
		{"key": "second_max", "name": "PF seconda forma"},
		{"key": "ac", "name": "Classe Armatura"},
		{"key": "initiative", "name": "Iniziativa"},
		{"key": "speed", "name": "Velocità"},
		{"key": "proficiency", "name": "Bonus competenza"},
		{"key": "passive_perception", "name": "Percezione passiva"},
		{"key": "spell_attack", "name": "Attacco incantesimi"},
		{"key": "spell_dc", "name": "CD incantesimi"},
		{"key": "spell_damage", "name": "Danni incantesimi"},
		{"key": "save_concentration", "name": "TS concentrazione"}
	]
	for ability: String in Bonuses.ABILITIES:
		result.append({"key": "ability:" + ability, "name": ability.to_upper() + " · Punteggio"})
		result.append({"key": "ability_mod:" + ability, "name": ability.to_upper() + " · Modificatore"})
		result.append({"key": "save:" + ability, "name": ability.to_upper() + " · Tiro salvezza"})
	for skill: Dictionary in Skills.SKILLS:
		result.append({"key": "skill:" + String(skill["id"]), "name": "Abilità · " + String(skill["label"])})
	for attack: Dictionary in Attacks.definitions(_record):
		var aid: String = String(attack.get("id", ""))
		var name: String = String(attack.get("name", aid))
		for category: Dictionary in [
			{"key": "attack_hit:", "name": "Colpire"},
			{"key": "attack_damage:", "name": "Danni"},
			{"key": "attack_range:", "name": "Gittata"}
		]:
			result.append({"key": String(category["key"]) + aid, "name": String(category["name"]) + " · " + name})
	for level: int in range(1, 10):
		result.append({"key": "slot:" + str(level), "name": "Slot livello " + str(level)})
	result.append({"key": "pact_slot", "name": "Slot del Patto"})
	for tracker: Dictionary in Trackers.for_creature(_record):
		result.append({"key": "tracker:" + String(tracker.get("id", "")), "name": "Risorsa · " + String(tracker.get("name", ""))})
	for row: Dictionary in _rows:
		var key: String = String(row.get("target", ""))
		var known := false
		for item: Dictionary in result:
			if String(item.get("key", "")) == key:
				known = true
				break
		if not known and not key.is_empty():
			result.append({"key": key, "name": "Altro · " + key})
	return result


func _refresh_options() -> void:
	if _target_filter == null:
		return
	_target_filter.clear()
	_target_filter.add_item("Tutti i target")
	_target_filter.set_item_metadata(0, "")
	_new_target.clear()
	var entries: Array[Dictionary] = _all_targets()
	for item: Dictionary in entries:
		var key: String = String(item["key"])
		_target_filter.add_item(String(item["name"]))
		_target_filter.set_item_metadata(_target_filter.item_count - 1, key)
		_new_target.add_item(String(item["name"]))
		_new_target.set_item_metadata(_new_target.item_count - 1, key)
	var filter_id := 0
	for i: int in range(_target_filter.item_count):
		if String(_target_filter.get_item_metadata(i)) == _selected_target:
			filter_id = i
			break
	_target_filter.select(filter_id)
	_selected_target = String(_target_filter.get_item_metadata(filter_id))
	for i: int in range(_new_target.item_count):
		if String(_new_target.get_item_metadata(i)) == (_selected_target if not _selected_target.is_empty() else "initiative"):
			_new_target.select(i)
			break
	_origin_picker.clear()
	_origin_picker.add_item("Manuale (senza origine)")
	_origin_picker.set_item_metadata(0, "")
	_origin_picker.add_item("Personalizzata…")
	_origin_picker.set_item_metadata(1, "~new~")
	for origin: Dictionary in _origins:
		var sid: String = String(origin.get("id", ""))
		if sid.is_empty():
			continue
		_origin_picker.add_item(String(origin.get("name", sid)))
		_origin_picker.set_item_metadata(_origin_picker.item_count - 1, sid)


func _on_filter_changed(index: int) -> void:
	_selected_target = String(_target_filter.get_item_metadata(index))
	if not _selected_target.is_empty():
		for i: int in range(_new_target.item_count):
			if String(_new_target.get_item_metadata(i)) == _selected_target:
				_new_target.select(i)
				break
	_refresh()


func _origin_label(sid: String) -> String:
	if sid.is_empty():
		return "Manuale"
	for origin: Dictionary in _origins:
		if String(origin.get("id", "")) == sid:
			return String(origin.get("name", sid))
	return sid


func _origin_description(sid: String) -> String:
	if not _description_cache.has(sid):
		_description_cache[sid] = _resolve_origin_description(sid)
	return String(_description_cache[sid])


func _resolve_origin_description(sid: String) -> String:
	if sid.is_empty():
		return "Bonus senza origine specifica."
	for feature: Dictionary in Traits.collect_features(_record):
		if sid == "feature:" + String(feature.get("key", "")):
			return String(feature.get("name", "")) + "\n" + String(feature.get("entries", ""))
	if sid.begins_with("item:"):
		for owned: Variant in _record.get("inventory", []):
			if owned is Dictionary and sid == "item:" + String(owned.get("id", "")):
				var definition: Dictionary = Items.entry_for(owned)
				return Catalog.info_text(definition)
	for source: Dictionary in Proficiencies.candidate_sources(_record):
		if sid == String(source.get("id", "")):
			return Catalog.info_text(source.get("data", {}))
	return _origin_label(sid)


func _refresh() -> void:
	_refresh_origins()
	_refresh_bonuses()
	_status.text = "Seleziona un'origine a sinistra per evidenziarne i bonus. Ogni bonus è indipendente e cumulabile; il pulsante di attivazione non elimina la concessione."


func _refresh_origins() -> void:
	for child: Node in _origin_cards.get_children():
		_origin_cards.remove_child(child)
		child.queue_free()
	var origins: Array[Dictionary] = [{"id": "", "name": "Manuale", "disabled": false}]
	origins.append_array(_origins)
	var visited: Dictionary = {}
	for origin: Dictionary in origins:
		var sid: String = String(origin.get("id", ""))
		if visited.has(sid):
			continue
		visited[sid] = true
		var count := 0
		for grant: Dictionary in _rows:
			if String(grant.get("origin_id", "")) == sid:
				count += 1
		if count == 0 and not sid.is_empty():
			continue
		var cell := PanelContainer.new()
		_origin_cards.add_child(cell)
		var line := HBoxContainer.new()
		cell.add_child(line)
		var select := OriginButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.toggle_mode = true
		select.button_pressed = _selected_origin == sid
		select.clip_text = true
		select.text = _origin_label(sid) + " (%d)" % count
		select.tooltip_text = _origin_description(sid)
		select.pressed.connect(func() -> void:
			_selected_origin = sid
			_refresh()
		)
		line.add_child(select)
		if not sid.is_empty():
			var enable := CheckButton.new()
			enable.text = "⏻"
			enable.button_pressed = not bool(origin.get("disabled", false))
			enable.tooltip_text = "Attiva o disattiva l'intera origine senza perdere i bonus."
			enable.toggled.connect(_toggle_origin.bind(sid))
			line.add_child(enable)
		if _selected_origin == sid:
			var border := StyleBoxFlat.new()
			border.draw_center = false
			border.border_color = Color(0.40, 0.72, 0.91)
			border.set_border_width_all(2)
			border.set_corner_radius_all(5)
			cell.add_theme_stylebox_override("panel", border)
		elif bool(origin.get("disabled", false)):
			cell.modulate.a = 0.58


func _refresh_bonuses() -> void:
	for child: Node in _bonus_cards.get_children():
		_bonus_cards.remove_child(child)
		child.queue_free()
	var names: Dictionary = {}
	for item: Dictionary in _all_targets():
		names[String(item["key"])] = String(item["name"])
	var groups: Dictionary = {}
	for index: int in range(_rows.size()):
		var key: String = String(_rows[index].get("target", ""))
		if not _selected_target.is_empty() and key != _selected_target:
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(index)
	if groups.is_empty():
		var empty := Label.new()
		empty.text = "Nessun bonus per questo target."
		_bonus_cards.add_child(empty)
		return
	var ordered: Array = groups.keys()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(names.get(a, a)).naturalnocasecmp_to(String(names.get(b, b))) < 0
	)
	var live: Dictionary = _record.duplicate(true)
	live["proficiency_origins"] = _origins.duplicate(true)
	live["formula_bonuses"] = _rows.duplicate(true)
	var enabled: Dictionary = {}
	for item: Dictionary in _origins:
		enabled[String(item.get("id", ""))] = not bool(item.get("disabled", false))
	for target: Variant in ordered:
		var header := Label.new()
		header.text = String(names.get(target, target)) + " · %+d" % Bonuses.bonus(live, String(target))
		header.add_theme_font_size_override("font_size", 15)
		_bonus_cards.add_child(header)
		for raw_index: Variant in groups[target]:
			var index: int = int(raw_index)
			var grant: Dictionary = _rows[index]
			var sid: String = String(grant.get("origin_id", ""))
			var active: bool = not bool(grant.get("disabled", false)) and bool(enabled.get(sid, true))
			var card := PanelContainer.new()
			_bonus_cards.add_child(card)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
			var selected_source: bool = sid == _selected_origin
			style.border_color = (Color(0.40, 0.72, 0.91, 1.0)
				if selected_source else Color(0.36, 0.31, 0.27, 0.75))
			style.set_border_width_all(2 if selected_source else 1)
			style.set_corner_radius_all(5)
			style.set_content_margin_all(7)
			card.add_theme_stylebox_override("panel", style)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 5)
			card.add_child(line)
			# The source is shown once, in the left column. The card's
			# outline links this bonus to the selected origin instead.
			card.tooltip_text = _origin_description(sid)
			var expression := LineEdit.new()
			expression.text = String(grant.get("expression", "0"))
			expression.custom_minimum_size.x = 70
			expression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			expression.placeholder_text = "Formula"
			expression.editable = not bool(grant.get("automatic", false))
			expression.tooltip_text = "Bonus strutturato: valore calcolato dalla fonte 5etools" if not expression.editable else "Espressione senza dadi, es. 2 * wis_mod"
			if expression.editable:
				expression.text_submitted.connect(_set_expression.bind(index))
				expression.focus_exited.connect(func() -> void: _set_expression(expression.text, index))
			line.add_child(expression)
			var toggle := CheckButton.new()
			toggle.text = "⏻"
			toggle.button_pressed = not bool(grant.get("disabled", false))
			toggle.tooltip_text = "Disattiva solo questo bonus (anche se automatico)."
			toggle.toggled.connect(_set_enabled.bind(index))
			line.add_child(toggle)
			if not bool(grant.get("automatic", false)):
				var remove := Button.new()
				remove.text = "✕"
				remove.flat = true
				remove.tooltip_text = "Elimina questo bonus manuale, senza toccare gli altri."
				remove.pressed.connect(_remove.bind(index))
				line.add_child(remove)
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size.x = 29
				line.add_child(spacer)
			if not active and not selected_source:
				card.modulate.a = 0.55


func _add_origin() -> void:
	var sid: String = String(_origin_picker.get_item_metadata(_origin_picker.selected))
	if sid == "~new~":
		var label: String = _origin_name.text.strip_edges()
		if label.is_empty():
			_status.text = "Inserisci un nome per l'origine personalizzata."
			return
		sid = "custom|" + label.to_lower().uri_encode()
		var exists := false
		for source: Dictionary in _origins:
			if String(source.get("id", "")) == sid:
				exists = true
				break
		if not exists:
			_origins.append({"id": sid, "name": label, "group": "custom", "disabled": false, "automatic": false})
	_selected_origin = sid
	_origin_editor.hide()
	_origin_name.clear()
	_publish()


func _add_bonus() -> void:
	if _new_target.selected < 0:
		return
	var key: String = String(_new_target.get_item_metadata(_new_target.selected))
	if key.is_empty():
		return
	_rows.append({"id": "bonus_%d" % Time.get_ticks_usec(),
		"target": key, "expression": "0", "origin_id": _selected_origin,
		"origin_name": _origin_label(_selected_origin), "disabled": false, "automatic": false})
	_selected_target = key
	_publish()


func _toggle_origin(active: bool, sid: String) -> void:
	for i: int in range(_origins.size()):
		if String(_origins[i].get("id", "")) == sid:
			_origins[i]["disabled"] = not active
			_publish()
			return


func _set_expression(value: String, index: int) -> void:
	if index < 0 or index >= _rows.size() or bool(_rows[index].get("automatic", false)):
		return
	var cleaned: String = value.strip_edges()
	if String(_rows[index].get("expression", "")) == cleaned:
		return
	_rows[index]["expression"] = cleaned
	_publish()


func _set_enabled(active: bool, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index]["disabled"] = not active
	_publish()


func _remove(index: int) -> void:
	if index < 0 or index >= _rows.size() or bool(_rows[index].get("automatic", false)):
		return
	_rows.remove_at(index)
	_publish()


func _publish() -> void:
	_record["formula_bonuses"] = _rows.duplicate(true)
	_record["proficiency_origins"] = _origins.duplicate(true)
	_refresh_options()
	_refresh()
	if not _loading and _changed.is_valid():
		_changed.call(_rows.duplicate(true), _origins.duplicate(true))
