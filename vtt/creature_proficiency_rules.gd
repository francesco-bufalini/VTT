extends RefCounted

# The granted choices are explicit sheet state. 5etools data only suggests
# origins; never infer proficiencies by parsing feature descriptions.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const SourcePath := "res://vtt/data/proficiency_grants_5etools.json"
const TYPES := ["weapon", "armor", "skill", "expertise", "save", "tool", "language"]
const SKILLS := ["acrobatics", "animal handling", "arcana", "athletics", "deception",
	"history", "insight", "intimidation", "investigation", "medicine", "nature",
	"perception", "performance", "persuasion", "religion", "sleight of hand",
	"stealth", "survival"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ARMORS := ["light", "medium", "heavy", "shield"]

static var _sources: Dictionary = {}


static func _load_sources() -> void:
	if not _sources.is_empty():
		return
	var file: FileAccess = FileAccess.open(SourcePath, FileAccess.READ)
	if file == null:
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if raw is Dictionary:
		_sources = raw


static func normalized_key(value: String) -> String:
	return value.strip_edges().to_lower()


static func selection_id(kind: String, key: String) -> String:
	return kind + "|" + normalized_key(key)


static func choices(record: Dictionary) -> Array[Dictionary]:
	var raw: Variant = record.get("proficiency_choices", [])
	var result: Array[Dictionary] = []
	if raw is Array:
		for value: Variant in raw:
			if not value is Dictionary:
				continue
			var row: Dictionary = value as Dictionary
			var kind := String(row.get("kind", ""))
			var key := normalized_key(String(row.get("key", "")))
			if kind not in TYPES or key.is_empty():
				continue
			result.append({
				"kind": kind,
				"key": key,
				"origin_id": String(row.get("origin_id", "")),
				"origin_name": String(row.get("origin_name", ""))
			})
	# Legacy skill ranks/saving throws are already authoritative; attach
	# empty origins rather than silently granting or removing anything.
	for pair: Dictionary in [
		{"kind": "skill", "field": "skill_proficiencies"},
		{"kind": "expertise", "field": "skill_expertise"},
		{"kind": "save", "field": "saving_throw_proficiencies"}
	]:
		var list: Variant = record.get(String(pair.field), [])
		if not list is Array:
			continue
		for value: Variant in list:
			var kind := String(pair.kind)
			var key := normalized_key(String(value))
			if not has_choice(result, kind, key):
				result.append({"kind": kind, "key": key, "origin_id": "", "origin_name": ""})
	# Pre-change per-attack proficiency is migrated to a shared weapon-name
	# proficiency, not kept on attack instances. It needs a source assignment.
	if not record.has("proficiency_choices"):
		var overrides: Variant = record.get("attack_overrides", {})
		if overrides is Dictionary:
			for raw_id: Variant in overrides.keys():
				var attack_id := String(raw_id)
				var flags: Variant = overrides[raw_id]
				if not attack_id.begins_with("item:") or not flags is Dictionary or not bool(flags.get("proficient", false)):
					continue
				var item_id := attack_id.substr(5)
				var inv: Variant = record.get("inventory", [])
				if inv is Array:
					for raw_item: Variant in inv:
						if raw_item is Dictionary and String(raw_item.get("id", "")) == item_id:
							var item_name := normalized_key(String(raw_item.get("name", "")))
							if not item_name.is_empty() and not has_choice(result, "weapon", item_name):
								result.append({"kind": "weapon", "key": item_name, "origin_id": "", "origin_name": ""})
	return result


static func has_choice(rows: Array[Dictionary], kind: String, key: String) -> bool:
	for row: Dictionary in rows:
		if String(row.get("kind", "")) == kind and normalized_key(String(row.get("key", ""))) == normalized_key(key):
			return true
	return false


static func has_proficiency(record: Dictionary, kind: String, key: String) -> bool:
	return has_choice(choices(record), kind, key)


static func weapon_proficient(record: Dictionary, entry: Dictionary) -> bool:
	var weapon_name := normalized_key(String(entry.get("name", "")))
	if has_proficiency(record, "weapon", weapon_name):
		return true
	var group := normalized_key(String(entry.get("weapon_category", "")))
	# Catalog's simple/martial is a separate axis from melee/ranged (type M/R).
	if group in ["simple", "martial"] and has_proficiency(record, "weapon", group):
		return true
	return has_proficiency(record, "weapon", "all")


static func sync_legacy_fields(record: Dictionary, rows: Array[Dictionary]) -> void:
	record["proficiency_choices"] = rows.duplicate(true)
	for pair: Dictionary in [
		{"kind": "skill", "field": "skill_proficiencies"},
		{"kind": "expertise", "field": "skill_expertise"},
		{"kind": "save", "field": "saving_throw_proficiencies"}
	]:
		var entries: Array[String] = []
		for row: Dictionary in rows:
			if String(row.get("kind", "")) == String(pair.kind):
				var key := normalized_key(String(row.get("key", "")))
				if key not in entries:
					entries.append(key)
		record[String(pair.field)] = entries


static func candidate_sources(record: Dictionary) -> Array[Dictionary]:
	_load_sources()
	var candidates: Array[Dictionary] = []
	var kinds := ["class", "race", "subrace", "background", "feat"]
	for group: String in kinds:
		var rows: Variant = _sources.get(group, [])
		if not rows is Array:
			continue
		for raw: Variant in rows:
			if not raw is Dictionary:
				continue
			var row: Dictionary = raw
			var name := String(row.get("name", ""))
			var source := String(row.get("source", ""))
			if not _selected_source(record, group, name, source):
				continue
			# Every indexed grant is taken from a structured 2014-compatible
			# record, never from feature/feat prose.
			var row_mode := "starting"
			if group == "class":
				var classes: Variant = record.get("classes", [])
				if classes is Array and (classes as Array).size() > 0:
					var first: Dictionary = classes[0] if classes[0] is Dictionary else {}
					if String(first.get("name", "")).nocasecmp_to(name) != 0:
						row_mode = "multiclass"
			var stable_id := group + "|" + source.to_lower() + "|" + name.to_lower()
			candidates.append({
				"id": stable_id, "name": _origin_title(group, name, row_mode),
				"group": group, "data": row, "mode": row_mode
			})
	return candidates


static func _selected_source(record: Dictionary, group: String, name: String, source: String) -> bool:
	match group:
		"class":
			var list: Variant = record.get("classes", [])
			if list is Array and not list.is_empty():
				for raw: Variant in list:
					if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and String(raw.get("source", "")) == source:
						return true
			return String(record.get("class", "")).nocasecmp_to(name) == 0 and String(record.get("class_source", "")) == source
		"race", "subrace":
			return String(record.get("species", "")).nocasecmp_to(name) == 0 and String(record.get("species_source", "")) == source
		"background":
			return String(record.get("background", "")).nocasecmp_to(name) == 0 and String(record.get("background_source", "")) == source
		"feat":
			var list: Variant = record.get("feats_catalog", [])
			if list is Array:
				for raw: Variant in list:
					if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and String(raw.get("source", "")) == source:
						return true
	return false


static func _origin_title(group: String, name: String, mode: String) -> String:
	match group:
		"class": return "Classe · " + name + (" (multiclasse)" if mode == "multiclass" else " (iniziale)")
		"race", "subrace": return "Specie · " + name
		"background": return "Background · " + name
		"feat": return "Talento · " + name
	return name


static func _grants_data(candidate: Dictionary, kind: String) -> Variant:
	var row: Dictionary = candidate.get("data", {})
	if String(candidate.get("group", "")) == "class":
		var mode := String(candidate.get("mode", "starting"))
		if kind == "save":
			return row.get("savingThrows", []) if mode == "starting" else []
		var granted: Dictionary = row.get(
			"multiclassProficiencies" if mode == "multiclass" else "startingProficiencies", {}
		)
		match kind:
			"weapon": return granted.get("weapons", [])
			"armor": return granted.get("armorProficiencies", granted.get("armor", []))
			"tool": return granted.get("toolProficiencies", [])
			"skill": return granted.get("skills", [])
		return []
	var field_name := {
		"weapon": "weaponProficiencies", "armor": "armorProficiencies",
		"skill": "skillProficiencies", "expertise": "expertise",
		"tool": "toolProficiencies", "language": "languageProficiencies"
	}.get(kind, "")
	return row.get(field_name, [])


static func grant_matches(grants: Variant, kind: String, key: String) -> int:
	# 0 = not indicated, 1 = selectable from a structured choice, 2 = fixed.
	var wanted := normalized_key(key)
	if grants is Dictionary:
		return grant_matches([grants], kind, wanted)
	if not grants is Array:
		return 0
	var best := 0
	for raw: Variant in grants:
		if raw is String:
			var item := normalized_key(String(raw))
			if item == wanted or item == "all":
				return 2
			# Explicit 5etools item link, not an English sentence.
			if item.begins_with("{@item ") and item.ends_with("}"):
				var item_name := item.substr(7).split("|")[0].strip_edges()
				if item_name == wanted:
					return 2
			continue
		if not raw is Dictionary:
			continue
		var value: Dictionary = raw
		if bool(value.get(wanted, false)):
			return 2
		for found: Variant in value.keys():
			var literal: String = normalized_key(String(found).split("|")[0])
			if literal == wanted and value[found] == true:
				return 2
		var choose: Variant = value.get("choose", {})
		if choose is Dictionary:
			var options: Variant = choose.get("from", [])
			if options is Array and wanted in options:
				best = maxi(best, 1)
			var from_filter := String(choose.get("fromFilter", "")).to_lower()
			# fromFilter selects individual items, never a whole category.
			if options is Array and options.is_empty() and choose.has("any"):
				best = maxi(best, 1)
		if value.has("any") or (kind == "skill" and value.has("anyProficientSkill")):
			best = maxi(best, 1)
		if kind == "tool" and value.has("anyArtisansTool") and _tool_type(wanted) == "AT":
			best = maxi(best, 1)
		if kind == "tool" and value.has("anyMusicalInstrument") and _tool_type(wanted) == "INS":
			best = maxi(best, 1)
		# A bare 'any' in 5etools is a structured choice, not a fixed grant.
		# Standard/exotic languages must not be conflated.
		if kind == "language" and value.has("anyStandard") and _language_group(wanted) == "standard":
			best = maxi(best, 1)
		if kind == "language" and value.has("anyExotic") and _language_group(wanted) == "exotic":
			best = maxi(best, 1)
	return best


static func _tool_type(key: String) -> String:
	for item: Dictionary in Catalog.entries("tools"):
		if normalized_key(String(item.get("name", ""))) == key:
			return String(item.get("type", "")).split("|")[0].to_upper()
	return ""


static func _language_group(key: String) -> String:
	for item: Dictionary in Catalog.entries("languages"):
		if normalized_key(String(item.get("name", ""))) == key:
			return String(item.get("type", "")).to_lower()
	return ""


static func suggest_origins(record: Dictionary, kind: String, key: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for candidate: Dictionary in candidate_sources(record):
		var matching := grant_matches(_grants_data(candidate, kind), kind, key)
		if matching > 0:
			var row := candidate.duplicate(false)
			row.erase("data")
			row["certainty"] = matching
			matches.append(row)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("certainty", 0)) > int(b.get("certainty", 0))
	)
	return matches



static func reconcile_skills(record: Dictionary) -> Array[Dictionary]:
	# The Statistics tab still owns skill rank editing. Drop obsolete rank
	# rows and retain source associations for ranks still selected there.
	var rows: Array[Dictionary] = []
	for row: Dictionary in choices(record):
		var kind := String(row.get("kind", ""))
		var key := String(row.get("key", ""))
		var field := "skill_expertise" if kind == "expertise" else "skill_proficiencies"
		if kind in ["skill", "expertise"]:
			if key not in record.get(field, []):
				continue
		rows.append(row)
	return rows


static func missing_structured(record: Dictionary) -> Array[Dictionary]:
	# Only unconditional machine-readable class grants are reported as
	# omissions. Choice pools and optional feats must never be auto-assigned.
	var missing: Array[Dictionary] = []
	for candidate: Dictionary in candidate_sources(record):
		if String(candidate.get("group", "")) != "class":
			continue
		for kind: String in ["weapon", "armor", "save"]:
			var data: Variant = _grants_data(candidate, kind)
			var keys: Array = ARMORS if kind == "armor" else ABILITIES if kind == "save" else ["simple", "martial"]
			for key: String in keys:
				if grant_matches(data, kind, key) == 2 and not has_proficiency(record, kind, key):
					missing.append({"kind": kind, "key": key, "origin": String(candidate.get("name", ""))})
	return missing


static func unassigned_count(record: Dictionary) -> int:
	var count := 0
	for row: Dictionary in choices(record):
		if String(row.get("origin_id", "")).is_empty():
			count += 1
	return count
