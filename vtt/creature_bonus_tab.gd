extends VBoxContainer
const EditorUI = preload("res://vtt/origin_editor_ui.gd")

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
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const PendingChoices = preload("res://vtt/creature_pending_choices.gd")
const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const DiceBonuses = preload("res://vtt/creature_dice_bonuses.gd")
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
var _dice_cards: VBoxContainer
var _dice_rows: Array[Dictionary] = []
var _dice_target: OptionButton
var _dice_origin: OptionButton
var _dice_value: LineEdit
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

	_origin_cards = EditorUI.origin_list(left)

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
	EditorUI.popup_form(self, new_row, "+ Bonus", add_bonus)
	# Dice modifiers do not alter the static numeric value of a stat.
	var dice_panel := PanelContainer.new()
	add_child(dice_panel)
	var dice_body := VBoxContainer.new()
	dice_body.add_theme_constant_override("separation", 5)
	dice_panel.add_child(dice_body)
	var dice_heading := Label.new()
	dice_heading.text = "Bonus ai tiri con dadi · assegnati alle origini"
	dice_heading.add_theme_font_size_override("font_size", 15)
	dice_body.add_child(dice_heading)
	_dice_cards = VBoxContainer.new()
	dice_body.add_child(_dice_cards)
	var dice_inputs := HBoxContainer.new()
	dice_body.add_child(dice_inputs)
	_dice_target = OptionButton.new()
	_dice_target.fit_to_longest_item = false
	_dice_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_inputs.add_child(_dice_target)
	_dice_value = LineEdit.new()
	_dice_value.text = "1d4"
	_dice_value.placeholder_text = "1d6"
	_dice_value.custom_minimum_size.x = 75
	dice_inputs.add_child(_dice_value)
	_dice_origin = OptionButton.new()
	_dice_origin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dice_origin.fit_to_longest_item = false
	dice_inputs.add_child(_dice_origin)
	var dice_add := Button.new()
	dice_add.text = "+ Dado"
	dice_add.pressed.connect(_add_dice_bonus)
	dice_inputs.add_child(dice_add)
	EditorUI.popup_form(self, dice_inputs, "+ Bonus ai tiri", dice_add)
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
	_dice_rows.clear()
	for raw: Variant in record.get("dice_bonuses", []):
		if raw is Dictionary:
			_dice_rows.append((raw as Dictionary).duplicate(true))
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
		if not bool(attack.get("melee", false)) and int(attack.get("long_range_feet", 0)) > 0:
			result.append({"key": "attack_long_range:" + aid, "name": "Gittata lunga · " + name})
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
	if _dice_origin != null:
		OriginChoices.populate(_dice_origin, current)
	if _dice_target != null:
		var previous: String = ""
		if _dice_target.selected >= 0:
			previous = String(_dice_target.get_item_metadata(_dice_target.selected))
		_dice_target.clear()
		for target: Dictionary in DiceBonuses.TARGETS:
			_dice_target.add_item(String(target.get("name", "")))
			_dice_target.set_item_metadata(_dice_target.item_count - 1, String(target.get("key", "")))
		for target: Dictionary in _all_targets():
			var key: String = String(target.get("key", ""))
			if key.begins_with("skill:") or key.begins_with("save:") or key.begins_with("attack_hit:") or key.begins_with("attack_damage:") or key.begins_with("ability_mod:"):
				_dice_target.add_item(String(target.get("name", key)))
				_dice_target.set_item_metadata(_dice_target.item_count - 1, key)
		for i: int in range(_dice_target.item_count):
			if String(_dice_target.get_item_metadata(i)) == previous:
				_dice_target.select(i)
				break


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
	return EditorUI.grants_tooltip(selections, automatic, bonuses, "Bonus assegnati")

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
	_refresh_dice_cards()
	_status.text = "Seleziona un'origine a sinistra per evidenziarne i bonus. Ogni bonus è indipendente e cumulabile; il pulsante di attivazione non elimina la concessione."
	var source_record: Dictionary = _record.duplicate(true)
	source_record["proficiency_origins"] = _origins.duplicate(true)
	if not PendingChoices.missing_feat_abilities(source_record).is_empty():
		_status.text += " ⚠ Alcuni talenti richiedono di scegliere la caratteristica: premi l'avviso accanto all'origine."


func _refresh_origins() -> void:
	EditorUI.clear_origin_cards(_origin_cards)
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
	var display_names: Dictionary = OriginChoices.display_labels(origins, current)
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
		var origin_title: String = String(origin.get("name", _origin_label(sid)))
		var tooltip: String = _origin_description(sid)
		var actions: Array[Dictionary] = []
		if pending.has(sid):
			tooltip += "\n\n⚠ Scegli la caratteristica da aumentare"
			actions.append({
				"text": "⚠", "warning": true,
				"tooltip": "Scegli la caratteristica per il bonus +%d di %s" % [
					int((pending[sid] as Dictionary).get("amount", 1)),
					String((pending[sid] as Dictionary).get("name", "Talento"))
				],
				"callback": _open_feat_ability_choice.bind(sid)
			})
		elif editable_choices.has(sid):
			actions.append({
				"text": "✎",
				"tooltip": "Modifica la caratteristica che riceve il bonus del talento.",
				"callback": _open_feat_ability_choice.bind(sid)
			})
		var active: bool = bool(enabled.get(sid, not bool(origin.get("disabled", false))))
		EditorUI.origin_card(self, _origin_cards, {
			"id": sid, "name": origin_title,
			"text": String(display_names.get(sid, origin_title)) +
				(" (%d)" % count if count > 0 else " · da completare"),
			"tooltip": tooltip, "selected": _selected_origin == sid,
			"active": active, "actions": actions,
			"on_select": _select_origin.bind(sid),
			"on_toggle": _toggle_origin.bind(sid),
			"toggle_disabled": not active and not bool(origin.get("disabled", false)),
			"toggle_tooltip": "Attiva o disattiva l'intera origine senza perdere i bonus."
		})


func _select_origin(sid: String) -> void:
	_selected_origin = sid
	_refresh()


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

			line.add_child(expression)
			if expression.editable:
				var formula_label := Label.new()
				formula_label.text = expression.text
				formula_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line.add_child(formula_label)
				EditorUI.edit_fields(card, line, [expression], "formula", func() -> void: _set_expression(expression.text, index))
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



func _refresh_dice_cards() -> void:
	if _dice_cards == null:
		return
	for child: Node in _dice_cards.get_children():
		_dice_cards.remove_child(child)
		child.queue_free()
	var active: Dictionary = Proficiencies.origin_enabled_map(_record)
	for index: int in range(_dice_rows.size()):
		var entry: Dictionary = _dice_rows[index]
		var line := HBoxContainer.new()
		_dice_cards.add_child(line)
		var scope: String = String(entry.get("target", ""))
		var info := Label.new()
		info.text = String(entry.get("origin_name", "Senza origine")) + " · " + scope
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		line.add_child(info)
		var dice := LineEdit.new()
		dice.text = String(entry.get("dice", "1d4"))
		dice.custom_minimum_size.x = 75

		line.add_child(dice)
		var dice_label := Label.new()
		dice_label.text = dice.text
		line.add_child(dice_label)
		EditorUI.edit_fields(line, line, [dice], "dadi", func() -> void: _set_dice_formula(dice.text, index))
		var enabled := CheckButton.new()
		enabled.text = "⏻"
		enabled.button_pressed = not bool(entry.get("disabled", false))
		enabled.toggled.connect(_set_dice_enabled.bind(index))
		line.add_child(enabled)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(_remove_dice_bonus.bind(index))
		line.add_child(remove)
		if not bool(active.get(String(entry.get("origin_id", "")), true)):
			line.modulate.a = 0.6


func _add_dice_bonus() -> void:
	if _dice_target.selected < 0 or not DiceBonuses.valid_dice(_dice_value.text):
		_status.text = "Il dado deve essere nel formato 1d4, 1d6, 2d8, ecc."
		return
	var origin: Dictionary = OriginChoices.selected(_dice_origin)
	OriginChoices.ensure(_origins, origin)
	_dice_rows.append({
		"id": "dice_bonus_%d" % Time.get_ticks_usec(),
		"target": String(_dice_target.get_item_metadata(_dice_target.selected)),
		"dice": _dice_value.text.strip_edges().to_lower(),
		"origin_id": String(origin.get("id", "")),
		"origin_name": String(origin.get("name", "Senza origine")),
		"disabled": false
	})
	_publish()


func _set_dice_formula(value: String, index: int) -> void:
	if index < 0 or index >= _dice_rows.size():
		return
	var cleaned: String = value.strip_edges().to_lower()
	if cleaned == String(_dice_rows[index].get("dice", "")):
		return
	if not DiceBonuses.valid_dice(cleaned):
		_status.text = "Formula dado non valida."
		return
	_dice_rows[index]["dice"] = cleaned
	_publish()


func _set_dice_enabled(active: bool, index: int) -> void:
	if index < 0 or index >= _dice_rows.size():
		return
	_dice_rows[index]["disabled"] = not active
	_publish()


func _remove_dice_bonus(index: int) -> void:
	if index < 0 or index >= _dice_rows.size():
		return
	_dice_rows.remove_at(index)
	_publish()


func _publish(feat_choice_changed: bool = false) -> void:
	_record["formula_bonuses"] = _rows.duplicate(true)
	_record["dice_bonuses"] = _dice_rows.duplicate(true)
	_record["proficiency_origins"] = _origins.duplicate(true)
	_refresh_options()
	_refresh()
	if not _loading and _changed.is_valid():
		if feat_choice_changed:
			_changed.call(_rows.duplicate(true), _origins.duplicate(true),
				_record.get("feats_catalog", []).duplicate(true), _dice_rows.duplicate(true))
		else:
			_changed.call(_rows.duplicate(true), _origins.duplicate(true), [], _dice_rows.duplicate(true))
