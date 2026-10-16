extends RefCounted

# Canonical, view-independent eligibility for structured benefits.
# A "requirements" dictionary is preferred. Legacy min_level/level/
# upgrade_level are translated by the caller, not changed in saved data.
# {"scope":"character","min_level":5}
# {"scope":"class","class_name":"Artificer","class_source":"TCE","min_level":9}

static func level_gate(minimum: int, scope: String = "character",
	class_name: String = "", class_source: String = "") -> Dictionary:
	var result: Dictionary = {
		"scope": scope if scope in ["character", "class"] else "character",
		"min_level": maxi(0, minimum)
	}
	if result["scope"] == "class":
		result["class_name"] = class_name
		result["class_source"] = class_source
	return result


static func normalize(entry: Dictionary, default_scope: String = "character",
	class_name: String = "", class_source: String = "",
	legacy_key: String = "min_level", default_minimum: int = 0) -> Dictionary:
	var raw: Variant = entry.get("requirements", {})
	var data: Dictionary = raw if raw is Dictionary else {}
	var gate: Dictionary = level_gate(
		int(data.get("min_level", entry.get(legacy_key, default_minimum))),
		String(data.get("scope", default_scope)),
		String(data.get("class_name", class_name)),
		String(data.get("class_source", class_source))
	)
	if data.has("max_level"):
		gate["max_level"] = maxi(0, int(data["max_level"]))
	return gate


static func class_level(record: Dictionary, class_name: String,
	class_source: String = "") -> int:
	if class_name.strip_edges().is_empty():
		return 0
	var members: Variant = record.get("classes", [])
	if members is Array and not (members as Array).is_empty():
		for value: Variant in members:
			if not value is Dictionary:
				continue
			var member: Dictionary = value
			if String(member.get("name", "")).nocasecmp_to(class_name) != 0:
				continue
			var book: String = String(member.get("source", ""))
			if not class_source.is_empty() and not book.is_empty() and book.nocasecmp_to(class_source) != 0:
				continue
			return maxi(0, int(member.get("level", 0)))
		return 0
	if String(record.get("class", "")).nocasecmp_to(class_name) != 0:
		return 0
	var book: String = String(record.get("class_source", ""))
	if not class_source.is_empty() and not book.is_empty() and book.nocasecmp_to(class_source) != 0:
		return 0
	return maxi(0, int(record.get("level", 0)))


static func allows(record: Dictionary, gate: Dictionary,
	class_level_override: int = -1) -> bool:
	var current: int = int(record.get("level", 1))
	if String(gate.get("scope", "character")) == "class":
		current = (class_level_override if class_level_override >= 0
			else class_level(record, String(gate.get("class_name", "")),
				String(gate.get("class_source", ""))))
	if current < int(gate.get("min_level", 0)):
		return false
	if gate.has("max_level") and current > int(gate["max_level"]):
		return false
	return true


static func accepts(record: Dictionary, entry: Dictionary,
	default_scope: String = "character", class_name: String = "",
	class_source: String = "", legacy_key: String = "min_level",
	default_minimum: int = 0, class_level_override: int = -1) -> bool:
	return allows(record, normalize(entry, default_scope, class_name,
		class_source, legacy_key, default_minimum), class_level_override)


static func highest_step(record: Dictionary, steps: Array,
	default_scope: String = "class", class_name: String = "",
	class_source: String = "", class_level_override: int = -1) -> Dictionary:
	var selected: Dictionary = {}
	var highest: int = -1
	for raw: Variant in steps:
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		var gate: Dictionary = normalize(candidate, default_scope,
			class_name, class_source, "level", 0)
		if not allows(record, gate, class_level_override):
			continue
		var threshold: int = int(gate.get("min_level", 0))
		if threshold > highest:
			highest = threshold
			selected = candidate
	return selected
