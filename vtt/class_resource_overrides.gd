extends RefCounted
# Curated, build-time Fight Club XML supplement. No runtime network access.
# Complements vtt/data/class_mechanics_5etools.json; never replaces 5etools.
const PATH := "res://vtt/data/class_resource_overrides.json"
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const VARIABLES := {
	"1": "str_mod", "2": "dex_mod", "3": "con_mod",
	"4": "int_mod", "5": "wis_mod", "6": "cha_mod",
	"7": "level", "8": "proficiency"
}
static var _loaded := false
static var _classes: Array = []


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Optional class resources unavailable: " + PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and (parsed as Dictionary).get("classes", []) is Array:
		_classes = (parsed as Dictionary)["classes"]


static func _subclass_key(value: String) -> String:
	var name: String = value.strip_edges().to_lower()
	for prefix: String in ["school of ", "circle of ", "oath of ", "college of ", "domain of ", "way of the ", "way of ", "the "]:
		if name.begins_with(prefix):
			name = name.substr(prefix.length())
	for suffix: String in [" domain", " school"]:
		if name.ends_with(suffix):
			name = name.trim_suffix(suffix)
	return name


# Parse only supported arithmetic and symbolic placeholders, not XML prose.
# The VTT's existing bonus evaluator includes effective ability modifiers.
static func evaluate_max(raw: Variant, record: Dictionary, class_level: int, minimum: int = 0) -> Dictionary:
	if raw is int or raw is float:
		return {"max": maxi(minimum, int(raw)), "max_formula": ""}
	var formula: String = String(raw).strip_edges()
	if formula.is_empty():
		return {}
	if formula.is_valid_int():
		return {"max": maxi(minimum, int(formula)), "max_formula": ""}
	var expr: String = formula
	var placeholders := RegEx.create_from_string("%[0-9]+")
	if placeholders == null:
		return {}
	for item: RegExMatch in placeholders.search_all(formula):
		var symbol: String = item.get_string()
		var index: String = symbol.substr(1)
		if not VARIABLES.has(index):
			return {}
		expr = expr.replace(symbol, String(VARIABLES[index]))
	# Reject any remaining percent sign or unknown characters before evaluation.
	var allowed := RegEx.create_from_string("^[0-9a-z_ .+*/()\\-]+$")
	if allowed == null or allowed.search(expr.to_lower()) == null:
		return {}
	var effective: Dictionary = record.duplicate(false)
	effective["level"] = class_level
	var result: Dictionary = Bonuses._evaluate_expression(effective, expr, {})
	if not bool(result.get("ok", false)):
		return {}
	return {"max": maxi(minimum, int(result.get("value", 0))), "max_formula": expr}


static func for_class(
	class_name: String, class_source: String, class_level: int,
	subclass_name: String, record: Dictionary
) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	if class_level < 1 or class_level > 20:
		return result
	for raw_class: Variant in _classes:
		if not raw_class is Dictionary:
			continue
		var group: Dictionary = raw_class as Dictionary
		if String(group.get("class", "")).nocasecmp_to(class_name) != 0:
			continue
		if String(group.get("source", "")).nocasecmp_to(class_source) != 0:
			continue
		for raw_resource: Variant in group.get("resources", []):
			if not raw_resource is Dictionary:
				continue
			var entry: Dictionary = raw_resource as Dictionary
			var required_subclass: String = String(entry.get("subclass", ""))
			if not required_subclass.is_empty() and _subclass_key(required_subclass) != _subclass_key(subclass_name):
				continue
			var chosen: Dictionary = {}
			for raw_step: Variant in entry.get("steps", []):
				if raw_step is Dictionary and int(raw_step.get("level", 0)) <= class_level:
					if chosen.is_empty() or int(raw_step.get("level", 0)) >= int(chosen.get("level", 0)):
						chosen = raw_step
			if chosen.is_empty():
				continue
			var computed: Dictionary = evaluate_max(
				chosen.get("value", ""), record, class_level, int(entry.get("minimum", 0)))
			if computed.is_empty() or int(computed.get("max", 0)) <= 0:
				continue
			var name: String = String(entry.get("name", ""))
			if name.is_empty():
				continue
			computed["name"] = name
			computed["column"] = String(entry.get("column", name))
			computed["origin"] = String(entry.get("origin_feature", name))
			computed["subclass"] = required_subclass
			computed["recharge"] = String(chosen.get("reset", "manual"))
			result.append(computed)
	return result
