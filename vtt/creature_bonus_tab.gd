extends VBoxContainer

const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")

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
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const PendingChoices = preload("res://vtt/creature_pending_choices.gd")
const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const ABILITY_LABELS := {
	"str": "Forza", "dex": "Destrezza", "con": "Costituzione",
	"int": "Intelligenza", "wis": "Saggezza", "cha": "Carisma"
}

var _changed: Callable
var _record: Dictionary = {}
var _rows: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _selected_origin := ""
var _selected_target := ""
var _origin_cards: VBoxContainer
var _bonus_cards: VBoxContainer
var _status: Label
var _origin_picker: OptionButton
var _target_filter: OptionButton
var _new_target: OptionButton
var _loading := false
var _description_cache: Dictionary = {}
var _grants_tooltip_cache: Dictionary = {}
var _choice_dialog: ConfirmationDialog
var _choice_selector: OptionButton
var _choice_origin: String = ""


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
	var left := _make_column(columns, "Origini dei bonus", 190)
	var right := _make_column(columns, "Bonus per statistica", 260)

	var origin_scroll := ScrollContainer.new()
	origin_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(origin_scroll)
	origin_scroll.custom_minimum_size.y = 245
	origin_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	origin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(origin_scroll)
	_origin_cards = VBoxContainer.new()
	_origin_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_cards.add_theme_constant_override("separation", 5)
	origin_scroll.add_child(_origin_cards)

	_target_filter = OptionButton.new()
	_target_filter.fit_to_longest_item = false
	_target_filter.add_item("Tutti i target")
	_target_filter.set_item_metadata(0, "")
	_target_filter.item_selected.connect(_on_filter_changed)
	right.add_child(_target_filter)
	var bonuses_scroll := ScrollContainer.new()
	bonuses_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(bonuses_scroll)
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
	_origin_picker = OptionButton.new()
	_origin_picker.fit_to_longest_item = false
	_origin_picker.custom_minimum_size.x = 155
	_origin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_picker.tooltip_text = "Origine che concede il nuovo bonus, oppure senza origine"
	new_row.add_child(_origin_picker)
	var add_bonus := Button.new()
	add_bonus.text = "+ Bonus"
	add_bonus.tooltip_text = "Crea un bonus e collegalo all'origine scelta qui accanto."
	add_bonus.pressed.connect(_add_bonus)
	new_row.add_child(add_bonus)
	_choice_dialog = ConfirmationDialog.new()
	_choice_dialog.title = "Completa il bonus del talento"
	_choice_dialog.ok_button_text = "Applica"
	_choice_dialog.cancel_button_text = "Annulla"
	_choice_dialog.confirmed.connect(_apply_feat_ability_choice)
	add_child(_choice_dialog)
	var choice_box := VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 8)
	_choice_dialog.add_child(choice_box)
	var help := Label.new()
	help.text = "Scegli la caratteristica che riceve il bonus."
	choice_box.add_child(help)
	_choice_selector = OptionButton.new()
	_choice_selector.custom_minimum_size = Vector2(325, 36)
	_choice_selector.item_selected.connect(func(index: int) -> void:
		_choice_dialog.get_ok_button().disabled = index <= 0
	)
	choice_box.add_child(_choice_selector)
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
	if _choice_dialog != null:
		_choice_dialog.hide()
	_choice_origin = ""
	_record = record.duplicate(true)
	_description_cache.clear()
	_grants_tooltip_cache.clear()
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
		{"key": "speed", "name": "Velocità · Camminata"},
		{"key": "speed:climb", "name": "Velocità · Scalata"},
		{"key": "speed:swim", "name": "Velocità · Nuoto"},
		{"key": "speed:fly", "name": "Velocità · Volo"},
		{"key": "speed:burrow", "name": "Velocità · Scavo"},
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
	var current: Dictionary = _record.duplicate(false)
	current["proficiency_origins"] = _origins.duplicate(true)
	OriginChoices.populate(_origin_picker, current, _selected_origin)


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
		return "Senza origine"
	for origin: Dictionary in _origins:
		if String(origin.get("id", "")) == sid:
			return String(origin.get("name", sid))
	return sid


func _origin_description(sid: String) -> String:
	if not _description_cache.has(sid):
		_description_cache[sid] = _resolve_origin_description(sid)
	if not _grants_tooltip_cache.has(sid):
		_grants_tooltip_cache[sid] = _origin_grants_tooltip(sid)
	return String(_description_cache[sid]) + String(_grants_tooltip_cache[sid])


func _origin_grants_tooltip(sid: String) -> String:
	var selections: PackedStringArray = []
	var automatic: PackedStringArray = []
	for grant: Dictionary in Proficiencies.choices(_record):
		if String(grant.get("origin_id", "")) != sid:
			continue
		var prefix: String = "○ " if bool(grant.get("disabled", false)) else "✓ "
		var text_value: String = String(grant.get("kind", "")).capitalize() + ": " + String(grant.get("key", "")).capitalize()
		if bool(grant.get("automatic", false)):
			automatic.append(prefix + text_value)
		else:
			selections.append(prefix + text_value)
	for feat: Variant in _record.get("feats_catalog", []):
		if feat is Dictionary and String(feat.get("origin_id", "")) == sid:
			selections.append(("○ " if bool(feat.get("disabled", false)) else "✓ ") + "Talento: " + String(feat.get("name", "")))
	var bonuses: PackedStringArray = []
	for row: Dictionary in _rows:
		if String(row.get("origin_id", "")) == sid:
			bonuses.append(("○ " if bool(row.get("disabled", false)) else "✓ ") + String(row.get("target", "")) + " = " + String(row.get("expression", "")))
	var parts: PackedStringArray = []
	if not selections.is_empty():
		parts.append("Scelte già effettuate:\n" + "\n".join(selections))
	if not automatic.is_empty():
		parts.append("Concessioni automatiche:\n" + "\n".join(automatic))
	if not bonuses.is_empty():
		parts.append("Bonus assegnati:\n" + "\n".join(bonuses))
	return "\n\n" + "\n\n".join(parts) if not parts.is_empty() else ""


func _resolve_origin_description(sid: String) -> String:
	if sid.is_empty():
		return "Bonus senza origine specifica."
	for feature: Dictionary in Traits.collect_features(_record):
		if sid == "feature:" + String(feature.get("key", "")):
			return Catalog.info_text(feature, Catalog.description_text("", feature))
	if sid.begins_with("item:"):
		for owned: Variant in _record.get("inventory", []):
			if owned is Dictionary and sid == "item:" + String(owned.get("id", "")):
				var definition: Dictionary = Items.entry_for(owned)
				return Catalog.info_text(definition, Catalog.description_text("items", definition))
	for source: Dictionary in Proficiencies.candidate_sources(_record):
		if sid == String(source.get("id", "")):
			var group: String = String(source.get("group", ""))
			var category: String = {"background": "backgrounds", "feat": "feats",
				"race": "races", "subrace": "races", "class": "classes"}.get(group, "")
			var data: Dictionary = source.get("data", {})
			return Catalog.info_text(data, Catalog.description_text(category, data))
	return _origin_label(sid)


func _refresh() -> void:
	_grants_tooltip_cache.clear()
	_refresh_origins()
	_refresh_bonuses()
	_status.text = "Seleziona un'origine a sinistra per evidenziarne i bonus. Ogni bonus è indipendente e cumulabile; il pulsante di attivazione non elimina la concessione."
	var source_record: Dictionary = _record.duplicate(true)
	source_record["proficiency_origins"] = _origins.duplicate(true)
	if not PendingChoices.missing_feat_abilities(source_record).is_empty():
		_status.text += " ⚠ Alcuni talenti richiedono di scegliere la caratteristica: premi l'avviso accanto all'origine."


func _refresh_origins() -> void:
	for child: Node in _origin_cards.get_children():
		_origin_cards.remove_child(child)
		child.queue_free()
	var origins: Array[Dictionary] = [{"id": "", "name": "Senza origine", "disabled": false}]
	origins.append_array(_origins)
	var pending: Dictionary = {}
	var editable_choices: Dictionary = {}
	for owned_value: Variant in _record.get("feats_catalog", []):
		if not owned_value is Dictionary:
			continue
		var owned: Dictionary = owned_value
		var feat_sid: String = Proficiencies.feat_source_id(owned)
		var choice_options: Dictionary = Structured.feat_ability_choice(owned)
		if not feat_sid.is_empty() and not choice_options.is_empty():
			editable_choices[feat_sid] = choice_options
	var effective_record: Dictionary = _record.duplicate(true)
	effective_record["proficiency_origins"] = _origins.duplicate(true)
	for entry: Dictionary in PendingChoices.missing_feat_abilities(effective_record):
		var pending_sid: String = String(entry.get("origin_id", ""))
		pending[pending_sid] = entry
		var already_present: bool = false
		for known: Dictionary in origins:
			if String(known.get("id", "")) == pending_sid:
				already_present = true
				break
		if not already_present:
			origins.append({"id": pending_sid,
				"name": "Talento · " + String(entry.get("name", "")),
				"disabled": false})
	# Include the source of a real grant even if it was not previously saved.
	for grant: Dictionary in _rows:
		var gid: String = String(grant.get("origin_id", ""))
		var known := gid.is_empty()
		for source: Dictionary in origins:
			if String(source.get("id", "")) == gid:
				known = true
				break
		if not known:
			origins.append({"id": gid, "name": String(grant.get("origin_name", gid)), "disabled": false})
	var current: Dictionary = _record.duplicate(true)
	current["proficiency_origins"] = _origins.duplicate(true)
	var enabled: Dictionary = Proficiencies.origin_enabled_map(current)
	for entry: Dictionary in Bonuses.available_origins(current):
		var eid: String = String(entry.get("id", ""))
		if not enabled.has(eid):
			enabled[eid] = not bool(entry.get("inactive", entry.get("disabled", false)))
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
		if count == 0 and not pending.has(sid):
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
		var origin_title: String = String(origin.get("name", _origin_label(sid)))
		select.text = origin_title + (" (%d)" % count if count > 0 else " · da completare")
		select.tooltip_text = _origin_description(sid)
		if pending.has(sid):
			select.tooltip_text += "\n\n⚠ Scegli la caratteristica da aumentare"
		select.pressed.connect(func() -> void:
			_selected_origin = sid
			_refresh()
		)
		line.add_child(select)
		if pending.has(sid):
			var warning := Button.new()
			warning.text = "⚠"
			warning.flat = true
			warning.custom_minimum_size.x = 32
			warning.add_theme_color_override("font_color", Color(1.0, 0.80, 0.33))
			warning.tooltip_text = "Scegli la caratteristica per il bonus +%d di %s" % [
				int((pending[sid] as Dictionary).get("amount", 1)),
				String((pending[sid] as Dictionary).get("name", "Talento"))
			]
			warning.pressed.connect(_open_feat_ability_choice.bind(sid))
			line.add_child(warning)
		elif editable_choices.has(sid):
			var change_choice := Button.new()
			change_choice.text = "✎"
			change_choice.flat = true
			change_choice.custom_minimum_size.x = 30
			change_choice.tooltip_text = "Modifica la caratteristica che riceve il bonus del talento."
			change_choice.pressed.connect(_open_feat_ability_choice.bind(sid))
			line.add_child(change_choice)
		if not sid.is_empty():
			var enable := CheckButton.new()
			enable.text = "⏻"
			enable.button_pressed = bool(enabled.get(sid, not bool(origin.get("disabled", false))))
			enable.disabled = not enable.button_pressed and not bool(origin.get("disabled", false))
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
		elif not bool(enabled.get(sid, not bool(origin.get("disabled", false)))):
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
		var source_record: Dictionary = _record.duplicate(true)
		source_record["proficiency_origins"] = _origins.duplicate(true)
		empty.text = ("Scelta ancora da completare: clicca ⚠ accanto al talento nelle origini."
			if not PendingChoices.missing_feat_abilities(source_record).is_empty()
			else "Nessun bonus per questo target.")
		_bonus_cards.add_child(empty)
		return
	var ordered: Array = groups.keys()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(names.get(a, a)).naturalnocasecmp_to(String(names.get(b, b))) < 0
	)
	var live: Dictionary = _record.duplicate(true)
	live["proficiency_origins"] = _origins.duplicate(true)
	live["formula_bonuses"] = _rows.duplicate(true)
	var enabled: Dictionary = Proficiencies.origin_enabled_map(live)
	for item: Dictionary in Bonuses.available_origins(live):
		var sid: String = String(item.get("id", ""))
		if not enabled.has(sid):
			enabled[sid] = not bool(item.get("inactive", item.get("disabled", false)))
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
				remove.tooltip_text = "Elimina questo bonus, senza toccare gli altri."
				remove.pressed.connect(_remove.bind(index))
				line.add_child(remove)
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size.x = 29
				line.add_child(spacer)
			if not active and not selected_source:
				card.modulate.a = 0.55


func _open_feat_ability_choice(sid: String) -> void:
	var selected: String = ""
	var chosen_feat: Dictionary = {}
	var choice_options: Dictionary = {}
	for feat_value: Variant in _record.get("feats_catalog", []):
		if not feat_value is Dictionary:
			continue
		var feat: Dictionary = feat_value
		if Proficiencies.feat_source_id(feat) != sid:
			continue
		choice_options = Structured.feat_ability_choice(feat)
		if choice_options.is_empty():
			continue
		chosen_feat = feat
		var proposed: String = String(feat.get("ability_choice", "")).to_lower()
		if proposed in choice_options.get("from", []):
			selected = proposed
			break
	if chosen_feat.is_empty():
		return
	_choice_origin = sid
	_selected_origin = sid
	_choice_dialog.title = "Completa · " + String(chosen_feat.get("name", "Talento"))
	_choice_selector.clear()
	_choice_selector.add_item("Scegli una caratteristica…")
	_choice_selector.set_item_metadata(0, "")
	var selected_index: int = 0
	for value: Variant in choice_options.get("from", []):
		var stat: String = String(value)
		_choice_selector.add_item("%s (+%d)" % [
			String(ABILITY_LABELS.get(stat, stat.to_upper())),
			int(choice_options.get("amount", 1))
		])
		_choice_selector.set_item_metadata(_choice_selector.item_count - 1, stat)
		if stat == selected:
			selected_index = _choice_selector.item_count - 1
	_choice_selector.select(selected_index)
	_choice_dialog.get_ok_button().disabled = selected_index <= 0
	DialogLayout.popup(_choice_dialog, Vector2i(435, 220), 0.88)


func _apply_feat_ability_choice() -> void:
	if _choice_origin.is_empty() or _choice_selector.selected <= 0:
		return
	var picked: String = String(_choice_selector.get_item_metadata(_choice_selector.selected))
	var feats: Array = _record.get("feats_catalog", []).duplicate(true)
	var changed: bool = false
	for feat_value: Variant in feats:
		if not feat_value is Dictionary:
			continue
		var feat: Dictionary = feat_value
		if Proficiencies.feat_source_id(feat) != _choice_origin:
			continue
		feat["ability_choice"] = picked
		changed = true
	if not changed:
		return
	_record["feats_catalog"] = feats
	_record["formula_bonuses"] = _rows.duplicate(true)
	_rows = Bonuses.grants(_record)
	_choice_origin = ""
	_selected_target = ""
	_publish(true)


func _add_bonus() -> void:
	if _new_target.selected < 0:
		return
	var key: String = String(_new_target.get_item_metadata(_new_target.selected))
	if key.is_empty():
		return
	var source: Dictionary = OriginChoices.selected(_origin_picker)
	var sid: String = String(source.get("id", ""))
	OriginChoices.ensure(_origins, source)
	_rows.append({"id": "bonus_%d" % Time.get_ticks_usec(),
		"target": key, "expression": "0", "origin_id": sid,
		"origin_name": String(source.get("name", "Senza origine")), "disabled": false, "automatic": false})
	_selected_origin = sid
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


func _publish(feat_choice_changed: bool = false) -> void:
	_record["formula_bonuses"] = _rows.duplicate(true)
	_record["proficiency_origins"] = _origins.duplicate(true)
	_refresh_options()
	_refresh()
	if not _loading and _changed.is_valid():
		if feat_choice_changed:
			_changed.call(_rows.duplicate(true), _origins.duplicate(true),
				_record.get("feats_catalog", []).duplicate(true))
		else:
			_changed.call(_rows.duplicate(true), _origins.duplicate(true))
