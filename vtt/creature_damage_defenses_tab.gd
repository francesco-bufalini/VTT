extends VBoxContainer

# Damage resistances and immunities are ranked like proficiency/expertise:
# none (0) -> resistance (1) -> immunity (2). Never stack the two.
# A saved override is independent of the bestiary/species baseline.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")

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
var _damage_rows: GridContainer
var _condition_rows: GridContainer
var _base_hint: Label


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
	for field: String in ["resist", "immune", "conditionImmune"]:
		var raw: Variant = data.get(field, [])
		if (raw is Array and not (raw as Array).is_empty()
			or raw is String and not String(raw).is_empty()):
			has_fields = true
	if not has_fields or seen.has(sid):
		return
	seen[sid] = true
	output.append({
		"id": sid, "name": name, "active": active,
		"resist": data.get("resist", []), "immune": data.get("immune", []),
		"conditionImmune": data.get("conditionImmune", [])
	})


# Derive from structured 5etools keys only. Traits.collect_features already
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
	if String(record.get("kind", "character")) == "character":
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
			var sid: String = ("subrace|" + source_book.to_lower() + "|" + name.to_lower()
				if is_subrace else "race|" + source_book.to_lower() + "|" + name.to_lower())
			_add_source(sources, seen, race, sid, "Specie · " + name,
				not bool(disabled.get(sid, false)))
	# The feature array contains current class, subclass, feat and species
	# traits. Structured resistance keys survive the feature extraction.
	for feature: Dictionary in Traits.collect_features(record):
		var sid: String = "feature:" + String(feature.get("key", ""))
		_add_source(sources, seen, feature, sid,
			String(feature.get("origin", "Tratto")) + " · " + String(feature.get("name", "")),
			not bool(feature.get("inactive", false))
				and not bool(disabled.get(sid, false))
				and not bool(disabled.get(String(feature.get("origin_key", "")), false)))
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
				Items.origin_active(owned) and not bool(disabled.get("item:" + id, false)))
	return sources

static func _base_rank_from_sources(sources: Array[Dictionary], damage_type: String) -> int:
	var rank := 0
	for source: Dictionary in sources:
		if not bool(source.get("active", true)):
			continue
		if damage_type in _direct_type_list(source.get("resist", [])):
			rank = maxi(rank, 1)
		if damage_type in _direct_type_list(source.get("immune", [])):
			rank = 2
	return rank


static func base_rank(record: Dictionary, damage_type: String) -> int:
	return _base_rank_from_sources(_sources(record), damage_type)


static func rank(record: Dictionary, damage_type: String) -> int:
	var overrides: Variant = record.get("damage_defense_overrides", {})
	if overrides is Dictionary and (overrides as Dictionary).has(damage_type):
		return clampi(int((overrides as Dictionary)[damage_type]), 0, 2)
	return base_rank(record, damage_type)


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
	var overrides: Variant = record.get("condition_immunity_overrides", {})
	if overrides is Dictionary and (overrides as Dictionary).has(condition):
		return bool((overrides as Dictionary)[condition])
	return base_condition_immune(record, condition)


func setup(on_change: Callable) -> void:
	_changed = on_change
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var description := Label.new()
	description.text = "Resistenza dimezza i danni del tipo indicato; immunità li annulla. Attiva Immunità come la Maestria: include il grado inferiore."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	_base_hint = Label.new()
	_base_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_base_hint)
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	scroll.custom_minimum_size.y = 280
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	var title := Label.new()
	title.text = "RESISTENZE E IMMUNITÀ AI DANNI"
	title.add_theme_font_size_override("font_size", 16)
	body.add_child(title)
	_damage_rows = GridContainer.new()
	_damage_rows.columns = 3
	_damage_rows.add_theme_constant_override("h_separation", 12)
	body.add_child(_damage_rows)
	var condition_title := Label.new()
	condition_title.text = "IMMUNITÀ ALLE CONDIZIONI"
	condition_title.add_theme_font_size_override("font_size", 16)
	body.add_child(condition_title)
	_condition_rows = GridContainer.new()
	_condition_rows.columns = 2
	_condition_rows.add_theme_constant_override("h_separation", 12)
	body.add_child(_condition_rows)


func load_record(record: Dictionary) -> void:
	_record = record.duplicate(true)
	_cached_sources = _sources(_record)
	_damage_buttons.clear()
	_condition_buttons.clear()
	if _damage_rows == null:
		return
	for root: GridContainer in [_damage_rows, _condition_rows]:
		for node: Node in root.get_children():
			root.remove_child(node)
			node.queue_free()
	var warnings: Array[String] = []
	for source: Dictionary in _cached_sources:
		for key: String in ["resist", "immune", "conditionImmune"]:
			for item: Variant in source.get(key, []):
				if item is Dictionary:
					warnings.append(JSON.stringify(item))
	_base_hint.text = ("Le difese condizionali del bestiario restano descritte nei tratti e non diventano immunità generali: "
		+ "; ".join(warnings)) if not warnings.is_empty() else "Valori iniziali derivati da specie o bestiario; le modifiche sono salvate nella creatura."
	for item: Dictionary in DAMAGE_TYPES:
		var key: String = String(item["key"])
		var baseline: int = _base_rank_from_sources(_cached_sources, key)
		var overrides: Dictionary = _record.get("damage_defense_overrides", {})
		var level: int = clampi(int(overrides.get(key, baseline)), 0, 2)
		var name := Label.new()
		name.text = String(item["label"])
		name.custom_minimum_size.x = 110
		_damage_rows.add_child(name)
		var resistant := CheckButton.new()
		resistant.text = "Resistenza"
		resistant.set_pressed_no_signal(level >= 1)
		resistant.tooltip_text = "Primo grado: dimezza i danni di questo tipo"
		resistant.toggled.connect(_on_resistance_changed.bind(key))
		_damage_rows.add_child(resistant)
		var immune := CheckButton.new()
		immune.text = "Immunità"
		immune.set_pressed_no_signal(level >= 2)
		immune.tooltip_text = "Secondo grado: annulla i danni di questo tipo"
		immune.toggled.connect(_on_immunity_changed.bind(key))
		_damage_rows.add_child(immune)
		_damage_buttons[key] = {"resistance": resistant, "immunity": immune}
	for condition: String in CONDITIONS:
		var name := Label.new()
		name.text = condition.capitalize()
		_condition_rows.add_child(name)
		var immune := CheckButton.new()
		immune.text = "Immune"
		var condition_overrides: Dictionary = _record.get("condition_immunity_overrides", {})
		immune.set_pressed_no_signal(bool(condition_overrides.get(condition,
			_base_condition_from_sources(_cached_sources, condition))))
		immune.toggled.connect(_on_condition_changed.bind(condition))
		_condition_rows.add_child(immune)
		_condition_buttons[condition] = immune


func _on_resistance_changed(enabled: bool, key: String) -> void:
	_change_rank(key, 1 if enabled else 0)


func _on_immunity_changed(enabled: bool, key: String) -> void:
	_change_rank(key, 2 if enabled else 1)


func _change_rank(key: String, level: int) -> void:
	var overrides: Dictionary = _record.get("damage_defense_overrides", {}).duplicate(true)
	overrides[key] = level
	_record["damage_defense_overrides"] = overrides
	var pair: Dictionary = _damage_buttons.get(key, {})
	(pair.get("resistance") as CheckButton).set_pressed_no_signal(level >= 1)
	(pair.get("immunity") as CheckButton).set_pressed_no_signal(level == 2)
	_publish()


func _on_condition_changed(enabled: bool, key: String) -> void:
	var overrides: Dictionary = _record.get("condition_immunity_overrides", {}).duplicate(true)
	overrides[key] = enabled
	_record["condition_immunity_overrides"] = overrides
	_publish()


func _publish() -> void:
	if _changed.is_valid():
		_changed.call(
			_record.get("damage_defense_overrides", {}).duplicate(true),
			_record.get("condition_immunity_overrides", {}).duplicate(true)
	)
