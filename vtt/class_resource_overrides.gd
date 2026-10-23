extends RefCounted
# Curated, build-time Fight Club XML supplement. No runtime network access.
# Complements vtt/data/class_mechanics_5etools.json; never replaces 5etools.
const BenefitRequirements = preload("res://vtt/benefit_requirements.gd")
const PATH := "res://vtt/data/class_resource_overrides.json"
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
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


# Runtime resource formulas use ONLY the same VTT notation as numeric bonuses
# (e.g. cha_mod, proficiency, 1 + cha_mod). External source placeholders
# are converted by the offline build tool and are intentionally rejected here.
static func evaluate_max(raw: Variant, record: Dictionary, class_level: int, minimum: int = 0) -> Dictionary:
	if raw is int or raw is float:
		return {"max": maxi(minimum, int(raw)), "max_formula": ""}
	var formula: String = String(raw).strip_edges()
	if formula.is_empty():
		return {}
	if formula.is_valid_int():
		return {"max": maxi(minimum, int(formula)), "max_formula": ""}
	# Keep external placeholders and arbitrary functions out of runtime formula
	# evaluation. Bonuses._evaluate_expression validates symbols and arithmetic.
	var allowed := RegEx.create_from_string("^[0-9a-z_ .+*/()\\-]+$")
	if allowed == null or allowed.search(formula.to_lower()) == null:
		return {}
	var effective: Dictionary = record.duplicate(false)
	effective["level"] = int(record.get("level", class_level))
	var result: Dictionary = Bonuses._evaluate_expression(effective, formula, {})
	if not bool(result.get("ok", false)):
		return {}
	return {"max": maxi(minimum, int(result.get("value", 0))), "max_formula": formula}


static func for_class(
	klass_name: String, class_source: String, class_level: int,
	subclass_name: String, record: Dictionary
) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	if class_level < 1 or class_level > 20:
		return result
	if klass_name.nocasecmp_to("Artificer") == 0 and class_source == "TCE":
		var extra: Array[Dictionary] = [
			{"name": "Flash of Genius", "level": 7, "max": maxi(1, Bonuses.value(record, "ability_mod:int"))},
			{"name": "Defensive Field", "subclass": "Armorer", "level": 3, "max": Bonuses.value(record, "proficiency")},
			{"name": "Experimental Elixir", "subclass": "Alchemist", "level": 3, "max": 3 if class_level >= 15 else 2 if class_level >= 6 else 1},
			{"name": "Restorative Reagents", "subclass": "Alchemist", "level": 9, "max": maxi(1, Bonuses.value(record, "ability_mod:int"))},
			{"name": "Chemical Mastery (Heal)", "origin": "Chemical Mastery", "subclass": "Alchemist", "level": 15, "max": 1},
			{"name": "Chemical Mastery (Greater Restoration)", "origin": "Chemical Mastery", "subclass": "Alchemist", "level": 15, "max": 1},
			{"name": "Eldritch Cannon", "subclass": "Artillerist", "level": 3, "max": 1},
			{"name": "Arcane Jolt", "subclass": "Battle Smith", "level": 9, "max": maxi(1, Bonuses.value(record, "ability_mod:int"))},
			{"name": "Perfected Armor", "origin": "Guardian", "subclass": "Armorer", "level": 15, "max": Bonuses.value(record, "proficiency")}
		]
		for resource: Dictionary in extra:
			if class_level < int(resource.level) or (resource.has("subclass") and _subclass_key(String(resource.subclass)) != _subclass_key(subclass_name)):
				continue
			resource["column"] = resource.name
			resource["origin"] = resource.get("origin", resource.name)
			resource["recharge"] = "long_rest"
			result.append(resource)
	for raw_class: Variant in _classes:
		if not raw_class is Dictionary:
			continue
		var group: Dictionary = raw_class as Dictionary
		if String(group.get("class", "")).nocasecmp_to(klass_name) != 0:
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
			var chosen: Dictionary = BenefitRequirements.highest_step(
				record, entry.get("steps", []), "class",
				klass_name, class_source, class_level
			)
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
			computed["origin_feature_key"] = String(entry.get("origin_feature_key", ""))
			computed["recharge"] = String(chosen.get("reset", "manual"))
			result.append(computed)
	return result
