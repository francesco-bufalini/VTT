extends VBoxContainer

# Damage resistances and immunities are ranked like proficiency/expertise:
# none (0) -> resistance (1) -> immunity (2). Never stack the two.
# A saved override is independent of the bestiary/species baseline.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")

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


static func _sources(record: Dictionary) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var stat: Variant = record.get("stat_block", {})
	if stat is Dictionary:
		sources.append(stat)
	var species: String = String(record.get("species", ""))
	var book: String = String(record.get("species_source", ""))
	if String(record.get("kind", "character")) == "character" and not species.is_empty():
		for race: Dictionary in Catalog.entries("races"):
			if String(race.get("name", "")).nocasecmp_to(species) == 0 and String(race.get("source", "")) == book:
				sources.append(race)
				break
		var subrace: String = String(record.get("subrace", ""))
		if not subrace.is_empty():
			for race: Dictionary in Catalog.entries("races"):
				if (String(race.get("name", "")).nocasecmp_to(species + " (" + subrace + ")") == 0
					and String(race.get("source", "")) == String(record.get("subrace_source", book))):
					sources.append(race)
					break
	return sources


static func base_rank(record: Dictionary, damage_type: String) -> int:
	var rank := 0
	for source: Dictionary in _sources(record):
		if damage_type in _direct_type_list(source.get("resist", [])):
			rank = maxi(rank, 1)
		if damage_type in _direct_type_list(source.get("immune", [])):
			rank = 2
	return rank


static func rank(record: Dictionary, damage_type: String) -> int:
	var overrides: Variant = record.get("damage_defense_overrides", {})
	if overrides is Dictionary and (overrides as Dictionary).has(damage_type):
		return clampi(int((overrides as Dictionary)[damage_type]), 0, 2)
	return base_rank(record, damage_type)


static func base_condition_immune(record: Dictionary, condition: String) -> bool:
	for source: Dictionary in _sources(record):
		if condition in _direct_type_list(source.get("conditionImmune", [])):
			return true
	return false


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
	_damage_buttons.clear()
	_condition_buttons.clear()
	if _damage_rows == null:
		return
	for root: GridContainer in [_damage_rows, _condition_rows]:
		for node: Node in root.get_children():
			root.remove_child(node)
			node.queue_free()
	var warnings: Array[String] = []
	for source: Dictionary in _sources(_record):
		for key: String in ["resist", "immune", "conditionImmune"]:
			for item: Variant in source.get(key, []):
				if item is Dictionary:
					warnings.append(JSON.stringify(item))
	_base_hint.text = ("Le difese condizionali del bestiario restano descritte nei tratti e non diventano immunità generali: "
		+ "; ".join(warnings)) if not warnings.is_empty() else "Valori iniziali derivati da specie o bestiario; le modifiche sono salvate nella creatura."
	for item: Dictionary in DAMAGE_TYPES:
		var key: String = String(item["key"])
		var level: int = rank(_record, key)
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
		immune.set_pressed_no_signal(condition_immune(_record, condition))
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
