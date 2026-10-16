extends VBoxContainer
const EditorUI = preload("res://vtt/origin_editor_ui.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")

# Damage resistances and immunities are ranked like proficiency/expertise:
# none (0) -> resistance (1) -> immunity (2). Never stack the two.
# A saved override is independent of the bestiary/species baseline.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Features = preload("res://vtt/creature_features.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const Rules = preload("res://vtt/creature_proficiency_rules.gd")

const DAMAGE_TYPES := [
	{"key": "acid", "label": "Acido"}, {"key": "bludgeoning", "label": "Contundente"},
	{"key": "cold", "label": "Freddo"}, {"key": "fire", "label": "Fuoco"},
	{"key": "force", "label": "Forza"}, {"key": "lightning", "label": "Fulmine"},
	{"key": "necrotic", "label": "Necrotico"}, {"key": "piercing", "label": "Perforante"},
	{"key": "poison", "label": "Veleno"}, {"key": "psychic", "label": "Psichico"},
	{"key": "radiant", "label": "Radioso"}, {"key": "slashing", "label": "Tagliente"},
	{"key": "thunder", "label": "Tuono"}
]
const CONDITIONS := [
	"blinded", "charmed", "deafened", "exhaustion", "frightened", "grappled",
	"incapacitated", "invisible", "paralyzed", "petrified", "poisoned",
	"prone", "restrained", "stunned", "unconscious"
]

var _record: Dictionary = {}
var _cached_sources: Array[Dictionary] = []
var _changed: Callable
var _damage_buttons: Dictionary = {}
var _condition_buttons: Dictionary = {}
var _damage_rows: VBoxContainer
var _condition_rows: VBoxContainer
var _origin_cards: VBoxContainer
var _damage_cards: Dictionary = {}
var _condition_cards: Dictionary = {}
var _origin_buttons: Dictionary = {}
var _selected_origin := "__manual__"
var _base_hint: Label
var _active_counts: Label
var _add_panel: VBoxContainer
var _type_picker: OptionButton
var _rank_picker: OptionButton
var _source_picker: OptionButton
var _entry_cards: Dictionary = {}


static func _direct_type_list(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	# 5etools dictionaries inside resist/immune usually describe conditional
	# defenses (e.g. nonmagical bludgeoning). Do not grant them universally.
	if raw is Array:
		for entry: Variant in raw:
			if entry is String:
				var key: String = String(entry).strip_edges().to_lower()
				if not key.is_empty() and key not in result:
					result.append(key)
	elif raw is String:
		var key: String = String(raw).strip_edges().to_lower()
		if not key.is_empty():
			result.append(key)
	return result


static func _add_source(
	output: Array[Dictionary], seen: Dictionary, data: Dictionary,
	sid: String, name: String, active: bool = true
) -> void:
	var has_fields: bool = false
	for field: String in ["vulnerable", "resist", "immune", "conditionImmune"]:
		var raw: Variant = data.get(field, [])
		if (raw is Array and not (raw as Array).is_empty()
			or raw is String and not String(raw).is_empty()):
			has_fields = true
	if not has_fields or seen.has(sid):
		return
	seen[sid] = true
	output.append({
		"id": sid, "name": name, "active": active,
		"vulnerable": data.get("vulnerable", []),
		"resist": data.get("resist", []), "immune": data.get("immune", []),
		"conditionImmune": data.get("conditionImmune", [])
	})


# Derive from structured 5etools keys only. Features.collect_features already
# filters class/subclass features by attained level, equipped inventory and
# the selected species/feats. Preserve their source IDs for highlighting.
static func _sources(record: Dictionary) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var seen: Dictionary = {}
	var disabled: Dictionary = {}
	for entry: Variant in record.get("proficiency_origins", []):
		if entry is Dictionary:
			disabled[String((entry as Dictionary).get("id", ""))] = bool((entry as Dictionary).get("disabled", false))
	var stat: Variant = record.get("stat_block", {})
	if stat is Dictionary:
		_add_source(sources, seen, stat as Dictionary, "monster|stat_block",
			"Bestiario · " + String((stat as Dictionary).get("name", "Creatura")))
	if String(record.get("kind", "character")) == "character" and not String(record.get("species", "")).is_empty():
		var species: String = String(record.get("species", ""))
		var book: String = String(record.get("species_source", ""))
		var subrace: String = String(record.get("subrace", ""))
		for race: Dictionary in Catalog.entries("races"):
			var name: String = String(race.get("name", ""))
			var source_book: String = String(race.get("source", ""))
			var is_species: bool = name.nocasecmp_to(species) == 0 and source_book == book
			var is_subrace: bool = not subrace.is_empty() and name.nocasecmp_to(species + " (" + subrace + ")") == 0 and source_book == String(record.get("subrace_source", book))
			if not is_species and not is_subrace:
				continue
			# Match the canonical subrace origin identity used by all other
			# creature benefits, not the flattened display name "Dwarf (Hill)".
			var sid: String = ("subrace|" + source_book.to_lower() + "|" + subrace.to_lower()
				if is_subrace else "race|" + source_book.to_lower() + "|" + name.to_lower())
			# A child species cannot keep inherited racial defenses alive
			# when the selected base species origin is disabled.
			var parent_sid: String = "race|" + book.to_lower() + "|" + species.to_lower()
			_add_source(sources, seen, race, sid, "Specie · " + name,
				not bool(disabled.get(sid, false))
				and (not is_subrace or not bool(disabled.get(parent_sid, false))))
	# Traits remain independently identifiable, but disabling a parent
	# race/class/feat origin must also mute every child trait it grants.
	var race_parent_id: String = "race|" + String(record.get("species_source", "")).to_lower() + "|" + String(record.get("species", "")).to_lower()
	for feature: Dictionary in Features.collect_features(record):
		var sid: String = "feature:" + String(feature.get("key", ""))
		var parent_id: String = String(feature.get("origin_key", ""))
		var active: bool = (not bool(feature.get("inactive", false))
			and not bool(disabled.get(sid, false))
			and not bool(disabled.get(parent_id, false)))
		if parent_id.begins_with("species|") and bool(disabled.get(race_parent_id, false)):
			active = false
		_add_source(sources, seen, feature, sid,
			String(feature.get("origin", "Tratto")) + " · " + String(feature.get("name", "")),
			active)
	# Equipment may have structured resistances at the item's top level,
	# even if no individually named trait was generated from it.
	for raw_owned: Variant in record.get("inventory", []):
		if raw_owned is Dictionary:
			var owned: Dictionary = raw_owned
			var id: String = String(owned.get("id", ""))
			if id.is_empty():
				continue
			_add_source(sources, seen, Items.entry_for(owned), "item:" + id,
				"Oggetto · " + String(owned.get("name", id)),
				Items.origin_active(owned, record) and not bool(disabled.get("item:" + id, false)))
	return sources

static func _base_rank_from_sources(sources: Array[Dictionary], damage_type: String) -> int:
	var rank := 0
	for source: Dictionary in sources:
		if not bool(source.get("active", true)):
			continue
		if damage_type in _direct_type_list(source.get("vulnerable", [])) and rank == 0:
			rank = -1
		if damage_type in _direct_type_list(source.get("resist", [])):
			rank = maxi(rank, 1)
		if damage_type in _direct_type_list(source.get("immune", [])):
			rank = 2
	return rank


static func base_rank(record: Dictionary, damage_type: String) -> int:
	return _base_rank_from_sources(_sources(record), damage_type)


static func rank(record: Dictionary, damage_type: String) -> int:
	# A legacy explicit zero overrides even an innate defense. Preserve this
	# semantics for records that have not adopted origin-backed entries yet.
	var saved_entries: Variant = record.get("damage_defense_entries", null)
	var old_overrides: Variant = record.get("damage_defense_overrides", {})
	if not saved_entries is Array and old_overrides is Dictionary and (old_overrides as Dictionary).has(damage_type):
		return clampi(int((old_overrides as Dictionary)[damage_type]), -1, 2)
	# Saved entries can be empty or predate a change of species/equipment.
	# Reconcile automatic grants with the *current* structured sources before
	# applying disabled-state overrides or manual entries.
	var sources: Array[Dictionary] = _sources(record)
	var entries: Array[Dictionary] = _entries_from_record(record, sources)
	var active_origins: Dictionary = Rules.origin_enabled_map(record)
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		active_origins[sid] = bool(source.get("active", true)) and bool(active_origins.get(sid, true))
	var best: int = 0
	for entry: Dictionary in entries:
		if String(entry.get("key", "")) != damage_type or bool(entry.get("disabled", false)):
			continue
		var origin: String = String(entry.get("origin_id", ""))
		if not origin.is_empty() and not bool(active_origins.get(origin, false)):
			continue
		var value: int = clampi(int(entry.get("rank", 0)), -1, 2)
		if value == 2:
			return 2
		if value > best or best == 0:
			best = value
	return best

static func _base_condition_from_sources(sources: Array[Dictionary], condition: String) -> bool:
	for source: Dictionary in sources:
		if not bool(source.get("active", true)):
			continue
		if condition in _direct_type_list(source.get("conditionImmune", [])):
			return true
	return false


static func base_condition_immune(record: Dictionary, condition: String) -> bool:
	return _base_condition_from_sources(_sources(record), condition)


static func condition_immune(record: Dictionary, condition: String) -> bool:
	var saved_entries: Variant = record.get("damage_defense_entries", null)
	var old_overrides: Variant = record.get("condition_immunity_overrides", {})
	if not saved_entries is Array and old_overrides is Dictionary and (old_overrides as Dictionary).has(condition):
		return bool((old_overrides as Dictionary)[condition])
	var sources: Array[Dictionary] = _sources(record)
	var entries: Array[Dictionary] = _entries_from_record(record, sources)
	var active_origins: Dictionary = Rules.origin_enabled_map(record)
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		active_origins[sid] = bool(source.get("active", true)) and bool(active_origins.get(sid, true))
	for entry: Dictionary in entries:
		if (String(entry.get("key", "")) != condition
			or int(entry.get("rank", 0)) != 3
			or bool(entry.get("disabled", false))):
			continue
		var origin: String = String(entry.get("origin_id", ""))
		if origin.is_empty() or bool(active_origins.get(origin, false)):
			return true
	return false

func setup(on_change: Callable) -> void:
	_changed = on_change
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_base_hint = Label.new()
	_base_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_base_hint)
	var columns := HBoxContainer.new()
	columns.name = "EditorColumns"
	columns.add_theme_constant_override("separation", 9)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := _make_column(columns, "Origini delle difese", 190)
	var right := _make_column(columns, "Resistenze, immunità e vulnerabilità", 255)
	_origin_cards = EditorUI.origin_list(left)
	var rs := ScrollContainer.new()
	rs.custom_minimum_size.y = 245
	rs.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(rs)
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rs)
	_damage_rows = VBoxContainer.new()
	_damage_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_rows.add_theme_constant_override("separation", 5)
	rs.add_child(_damage_rows)
	var add_button := Button.new()
	add_button.text = "+ Aggiungi voce"
	right.add_child(add_button)
	_add_panel = VBoxContainer.new()
	_add_panel.hide()
	right.add_child(_add_panel)

	_type_picker = OptionButton.new()
	for item: Dictionary in DAMAGE_TYPES:
		_type_picker.add_item(String(item["label"]))
	for condition: String in CONDITIONS:
		_type_picker.add_item(condition.capitalize())
	_add_panel.add_child(_type_picker)
	_rank_picker = OptionButton.new()
	for title: String in ["Vulnerabilità", "Resistenza", "Immunità"]:
		_rank_picker.add_item(title)
	_add_panel.add_child(_rank_picker)
	_source_picker = OptionButton.new()
	_source_picker.fit_to_longest_item = false
	_add_panel.add_child(_source_picker)
	var confirm := Button.new()
	confirm.text = "Aggiungi voce"
	confirm.pressed.connect(_add_defense)
	_add_panel.add_child(confirm)
	_add_panel.show()
	var defense_dialog: AcceptDialog = EditorUI.popup_form(self, _add_panel, "+ Resistenza o immunità", confirm)
	add_button.hide()
	add_button.pressed.connect(func() -> void: DialogLayout.popup(defense_dialog, Vector2i(640, 300)))
	_type_picker.item_selected.connect(func(_index: int) -> void:
		var is_condition: bool = _type_picker.selected >= DAMAGE_TYPES.size()
		_rank_picker.disabled = is_condition
		if is_condition: _rank_picker.select(2)
	)


func _make_column(parent: HBoxContainer, heading: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = heading
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 15)
	content.add_child(title)
	return content


static func _entries_from_record(record: Dictionary, sources: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var saved: Variant = record.get("damage_defense_entries", null)
	if saved is Array:
		# Synchronize structured grants with the currently present origins;
		# preserve only per-grant disabled state or promoted resistance.
		var existing: Dictionary = {}
		for entry: Variant in saved:
			if not entry is Dictionary: continue
			var row: Dictionary = entry
			if bool(row.get("automatic", false)):
				existing[String(row.get("origin_id", "")) + "|" + String(row.get("key", "")) + "|" + str(int(row.get("base_rank", row.get("rank", 0))))] = row
			else:
				result.append(row.duplicate(true))
		for source: Dictionary in sources:
			var sid: String = String(source.get("id", ""))
			for field: String in ["vulnerable", "resist", "immune", "conditionImmune"]:
				var base_level: int = int({"vulnerable": -1, "resist": 1, "immune": 2, "conditionImmune": 3}[field])
				for key: String in _direct_type_list(source.get(field, [])):
					var identifier: String = sid + "|" + key + "|" + str(base_level)
					var row: Dictionary = {"key": key, "rank": base_level, "base_rank": base_level, "origin_id": sid, "automatic": true}
					if existing.has(identifier):
						row["disabled"] = bool(existing[identifier].get("disabled", false))
						if base_level == 1 and int(existing[identifier].get("rank", 1)) == 2: row["rank"] = 2
					result.append(row)
		return result
	# Old data: convert only explicitly saved overrides to independent rows.
	# Automatically granted defenses always come from current structured origins.
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		for field: String in ["vulnerable", "resist", "immune", "conditionImmune"]:
			for key: String in _direct_type_list(source.get(field, [])):
				result.append({"key": key, "rank": {"vulnerable": -1, "resist": 1, "immune": 2, "conditionImmune": 3}[field], "base_rank": {"vulnerable": -1, "resist": 1, "immune": 2, "conditionImmune": 3}[field], "origin_id": sid, "automatic": true})
	for key: String in record.get("damage_defense_overrides", {}):
		var level: int = int(record["damage_defense_overrides"][key])
		if level != 0: result.append({"key": key, "rank": level, "origin_id": "", "automatic": false})
	for key: String in record.get("condition_immunity_overrides", {}):
		if bool(record["condition_immunity_overrides"][key]):
			result.append({"key": key, "rank": 3, "origin_id": "", "automatic": false})
	return result


func load_record(record: Dictionary) -> void:
	_record = record.duplicate(true)
	_cached_sources = _sources(_record)
	_record["damage_defense_entries"] = _entries_from_record(_record, _cached_sources)
	_refresh()


func _refresh() -> void:
	if _damage_rows == null: return
	for parent: VBoxContainer in [_damage_rows, _origin_cards]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_entry_cards.clear()
	_origin_buttons.clear()
	var counts: Dictionary = {}
	for entry: Dictionary in _record.get("damage_defense_entries", []):
		var sid: String = String(entry.get("origin_id", ""))
		counts[sid] = int(counts.get(sid, 0)) + 1
	_origin_buttons["__manual__"] = EditorUI.origin_card(self, _origin_cards, {
		"id": "__manual__", "name": "Senza origine",
		"text": "Senza origine (%d)" % int(counts.get("", 0)),
		"tooltip": "Difese aggiunte senza un'origine specifica.",
		"selected": _selected_origin == "__manual__", "active": true,
		"link": false, "on_select": _select_origin.bind("__manual__")
	})
	OriginChoices.populate(_source_picker, _record)
	var candidates: Array[Dictionary] = OriginChoices.available(_record)
	var known: Dictionary = {}
	for source: Dictionary in candidates:
		known[String(source.get("id", ""))] = true
	for source: Dictionary in _cached_sources:
		var sid: String = String(source.get("id", ""))
		if not known.has(sid):
			candidates.append(source)
	var display_names: Dictionary = OriginChoices.display_labels(candidates, _record)
	var effective_origins: Dictionary = Rules.origin_enabled_map(_record)
	for source: Dictionary in candidates:
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or sid == OriginChoices.SPELL_PICKER_ID or not counts.has(sid):
			continue
		var active: bool = bool(source.get("active", true)) and bool(effective_origins.get(sid, true))
		_origin_buttons[sid] = EditorUI.origin_card(self, _origin_cards, {
			"id": sid, "name": String(source.get("name", sid)),
			"text": "%s (%d)" % [
				String(display_names.get(sid, source.get("name", sid))), int(counts[sid])
			],
			"tooltip": String(source.get("name", sid)),
			"selected": _selected_origin == sid, "active": active,
			"on_select": _select_origin.bind(sid)
		})
	var entries: Array = _record.get("damage_defense_entries", [])
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		var rank_value: int = int(entry.get("rank", 0))
		if rank_value == 0: continue
		var key: String = String(entry.get("key", ""))
		var label := key.capitalize()
		for item: Dictionary in DAMAGE_TYPES:
			if String(item["key"]) == key: label = String(item["label"])
		var row := HBoxContainer.new()
		var panel := PanelContainer.new()
		_damage_rows.add_child(panel)
		panel.add_child(row)
		_entry_cards[i] = panel
		var name_label := Label.new()
		name_label.text = label
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if rank_value >= 1 and rank_value <= 2:
			var promote := CheckButton.new()
			promote.text = "Imm."
			promote.tooltip_text = "Passa da resistenza a immunità"
			promote.set_pressed_no_signal(rank_value == 2)
			promote.toggled.connect(_promote.bind(i))
			row.add_child(promote)
		else:
			var status := Label.new()
			status.text = "Vuln." if rank_value == -1 else "Imm."
			row.add_child(status)
		var enabled := CheckButton.new()
		enabled.text = "Attiva"
		enabled.set_pressed_no_signal(not bool(entry.get("disabled", false)))
		enabled.toggled.connect(_toggle.bind(i))
		row.add_child(enabled)
		if not bool(entry.get("automatic", false)):
			var remove := Button.new()
			remove.text = "×"
			remove.tooltip_text = "Rimuovi questa voce"
			remove.pressed.connect(_remove.bind(i))
			row.add_child(remove)
	_refresh_highlights()
	_base_hint.text = "Resistenze, immunità e vulnerabilità automatiche provengono dalle origini; seleziona un'origine per evidenziarle."


func _select_origin(sid: String) -> void:
	_selected_origin = sid
	_refresh_highlights()


func _refresh_highlights() -> void:
	for sid: String in _origin_buttons:
		var button: Button = _origin_buttons[sid]
		var selected: bool = sid == _selected_origin
		button.set_pressed_no_signal(selected)
		var panel: PanelContainer = button.get_parent().get_parent() as PanelContainer
		if panel != null:
			EditorUI.origin_card_state(panel, selected,
				bool(button.get_meta("origin_active", true)))
	var entries: Array = _record.get("damage_defense_entries", [])
	for index: int in _entry_cards:
		var source_id: String = String(entries[index].get("origin_id", ""))
		var highlighted: bool = source_id == ("" if _selected_origin == "__manual__" else _selected_origin)
		var card: PanelContainer = _entry_cards[index]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
		style.border_color = Color(0.40, 0.72, 0.91) if highlighted else Color(0.36, 0.31, 0.27, 0.75)
		style.set_border_width_all(2 if highlighted else 1)
		style.set_corner_radius_all(5)
		style.set_content_margin_all(7)
		card.add_theme_stylebox_override("panel", style)


func _add_defense() -> void:
	var index: int = _type_picker.selected
	if index < 0: return
	var key: String = String(DAMAGE_TYPES[index]["key"]) if index < DAMAGE_TYPES.size() else CONDITIONS[index - DAMAGE_TYPES.size()]
	var level: int = 3 if index >= DAMAGE_TYPES.size() else [-1, 1, 2][maxi(0, _rank_picker.selected)]
	var source: Dictionary = OriginChoices.selected(_source_picker)
	var sid: String = String(source.get("id", ""))
	var origins: Array[Dictionary] = []
	for raw: Variant in _record.get("proficiency_origins", []):
		if raw is Dictionary:
			origins.append((raw as Dictionary).duplicate(true))
	OriginChoices.ensure(origins, source)
	_record["proficiency_origins"] = origins
	var entries: Array = _record.get("damage_defense_entries", [])
	entries.append({"key": key, "rank": level, "origin_id": sid, "automatic": false})
	_record["damage_defense_entries"] = entries
	_refresh()
	_publish()


func _promote(enabled: bool, index: int) -> void:
	var entries: Array = _record.get("damage_defense_entries", [])
	entries[index]["rank"] = 2 if enabled else 1
	_refresh()
	_publish()


func _toggle(enabled: bool, index: int) -> void:
	var entries: Array = _record.get("damage_defense_entries", [])
	entries[index]["disabled"] = not enabled
	_refresh()
	_publish()


func _remove(index: int) -> void:
	var entries: Array = _record.get("damage_defense_entries", [])
	entries.remove_at(index)
	_refresh()
	_publish()


func _publish() -> void:
	if _changed.is_valid():
		_changed.call(_record.get("damage_defense_overrides", {}).duplicate(true),
			_record.get("condition_immunity_overrides", {}).duplicate(true),
			_record.get("damage_defense_entries", []).duplicate(true),
			_record.get("proficiency_origins", []).duplicate(true))
