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


static func choices(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_sources: Dictionary = _active_identity_sources(record)
	var raw: Variant = record.get("proficiency_choices", [])
	if raw is Array:
		for value: Variant in raw:
			if not value is Dictionary:
				continue
			var row: Dictionary = value
			if _is_replaced_identity(String(row.get("origin_id", "")), current_sources):
				continue
			var kind: String = String(row.get("kind", ""))
			var key: String = normalized_key(String(row.get("key", "")))
			if kind not in TYPES or key.is_empty():
				continue
			result.append({
				"kind": kind, "key": key,
				"origin_id": String(row.get("origin_id", "")),
				"origin_name": String(row.get("origin_name", "")),
				"disabled": bool(row.get("disabled", false)),
				"automatic": bool(row.get("automatic", false))
			})
	# Only import the old rank arrays before the new choice model exists:
	# otherwise an intentionally disabled proficiency would be resurrected.
	var migrate_legacy: bool = not record.has("proficiency_choices")
	if record.has("proficiency_choices") and not record.has("proficiency_origins"):
		var previous: Variant = record.get("proficiency_choices", [])
		migrate_legacy = previous is Array and (previous as Array).is_empty()
	if migrate_legacy:
		for pair: Dictionary in [
			{"kind": "skill", "field": "skill_proficiencies"},
			{"kind": "expertise", "field": "skill_expertise"},
			{"kind": "save", "field": "saving_throw_proficiencies"}
		]:
			var list: Variant = record.get(String(pair.field), [])
			if not list is Array:
				continue
			for value: Variant in list:
				var kind: String = String(pair.kind)
				var key: String = normalized_key(String(value))
				if not has_choice(result, kind, key):
					result.append({"kind": kind, "key": key, "origin_id": "", "origin_name": "", "disabled": false})
		var overrides: Variant = record.get("attack_overrides", {})
		if overrides is Dictionary:
			for raw_id: Variant in overrides.keys():
				var attack_id: String = String(raw_id)
				var flags: Variant = overrides[raw_id]
				if not attack_id.begins_with("item:") or not flags is Dictionary or not bool(flags.get("proficient", false)):
					continue
				var item_id: String = attack_id.substr(5)
				for prefix: String in ["throw:main:", "throw:off:", "off:"]:
					if item_id.begins_with(prefix):
						item_id = item_id.substr(prefix.length())
						break
				var inv: Variant = record.get("inventory", [])
				if inv is Array:
					for raw_item: Variant in inv:
						if raw_item is Dictionary and String(raw_item.get("id", "")) == item_id:
							var item_name: String = normalized_key(String(raw_item.get("name", "")))
							if not item_name.is_empty() and not has_choice(result, "weapon", item_name):
								result.append({"kind": "weapon", "key": item_name, "origin_id": "", "origin_name": "", "disabled": false})
	# Structured unconditional grants are materialized for every eligible
	# origin, including a fresh sheet that has never opened the editor.
	for source: Dictionary in candidate_sources(record):
		if not source_has_grants(source):
			continue
		var fixed: Array[Dictionary] = fixed_grants(source)
		for grant: Dictionary in fixed:
			var exists: bool = false
			for row: Dictionary in result:
				if String(row.get("kind", "")) == String(grant.get("kind", "")) and String(row.get("key", "")) == String(grant.get("key", "")) and String(row.get("origin_id", "")) == String(source.get("id", "")):
					# Catalog-fixed grants cannot be deleted, but may be
					# temporarily disabled like any other proficiency.
					# Preserve an explicitly stored disabled flag.
					row["automatic"] = true
					exists = true
					break
			if not exists:
				var automatic: Dictionary = grant.duplicate(true)
				automatic["origin_id"] = String(source.get("id", ""))
				automatic["origin_name"] = String(source.get("name", ""))
				automatic["automatic"] = true
				automatic["disabled"] = false
				result.append(automatic)
	return result


static func has_choice(rows: Array[Dictionary], kind: String, key: String) -> bool:
	for row: Dictionary in rows:
		if String(row.get("kind", "")) == kind and normalized_key(String(row.get("key", ""))) == normalized_key(key):
			return true
	return false


static func has_proficiency(record: Dictionary, kind: String, key: String) -> bool:
	var origin_state: Dictionary = origin_enabled_map(record)
	for row: Dictionary in choices(record):
		if String(row.get("kind", "")) == kind and normalized_key(String(row.get("key", ""))) == normalized_key(key) and not bool(row.get("disabled", false)) and bool(origin_state.get(String(row.get("origin_id", "")), true)):
			return true
	return false


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
	var enabled: Dictionary = origin_enabled_map(record)
	for pair: Dictionary in [
		{"kind": "skill", "field": "skill_proficiencies"},
		{"kind": "expertise", "field": "skill_expertise"},
		{"kind": "save", "field": "saving_throw_proficiencies"}
	]:
		var entries: Array[String] = []
		for row: Dictionary in rows:
			if String(row.get("kind", "")) != String(pair.kind) or bool(row.get("disabled", false)) or not bool(enabled.get(String(row.get("origin_id", "")), true)):
				continue
			var key: String = normalized_key(String(row.get("key", "")))
			if String(pair.kind) == "expertise" and key not in record.get("skill_proficiencies", []):
				# A retained expertise switch stays dormant if all sources
				# of the underlying skill have been disabled.
				continue
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
			if not _selected_source(record, group, name, source, row):
				continue
			# Every indexed grant is taken from a structured 2014-compatible
			# record, never from feature/feat prose.
			var row_mode := "starting"
			if group == "class":
				var classes: Variant = record.get("classes", [])
				# Monster levels are separate from character classes: every
				# class added to a monster receives starting privileges.
				if String(record.get("kind", "")) != "monster" and classes is Array and not (classes as Array).is_empty():
					var primary: Dictionary = {}
					for candidate_class: Variant in classes:
						if candidate_class is Dictionary and not String(candidate_class.get("name", "")).is_empty():
							primary = candidate_class
							break
					if not primary.is_empty() and (String(primary.get("name", "")).nocasecmp_to(name) != 0 or String(primary.get("source", "")) != source):
						row_mode = "multiclass"
			var stable_id := group + "|" + source.to_lower() + "|" + name.to_lower()
			candidates.append({
				"id": stable_id,
				"name": _origin_title(group, name, row_mode) + " · " + source,
				"group": group, "data": row, "mode": row_mode
			})
	return candidates


static func _selected_source(record: Dictionary, group: String, name: String, source: String, indexed: Dictionary = {}) -> bool:
	match group:
		"class":
			var list: Variant = record.get("classes", [])
			if list is Array and not list.is_empty():
				for raw: Variant in list:
					if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and String(raw.get("source", "")) == source:
						return true
			return String(record.get("class", "")).nocasecmp_to(name) == 0 and String(record.get("class_source", "")) == source
		"race":
			return (String(record.get("species", "")).nocasecmp_to(name) == 0
				and String(record.get("species_source", "")) == source)
		"subrace":
			return (
				String(record.get("subrace", "")).nocasecmp_to(name) == 0
				and String(record.get("subrace_source", "")) == source
				and String(record.get("species", "")).nocasecmp_to(
					String(indexed.get("raceName", ""))) == 0
				and String(record.get("species_source", "")) == String(indexed.get("raceSource", ""))
			)
		"background":
			if String(record.get("background", "")).nocasecmp_to(name) != 0:
				return false
			# Free-form older sheets may not store a book. Offer all structured
			# candidates with their source visible, never silently pick one.
			var selected_book := String(record.get("background_source", ""))
			return selected_book.is_empty() or selected_book == source
		"feat":
			var list: Variant = record.get("feats_catalog", [])
			if list is Array:
				for raw: Variant in list:
					if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and String(raw.get("source", "")) == source:
						return true
	return false


static func _origin_title(group: String, name: String, mode: String) -> String:
	match group:
		"class": return ("Multiclass " if mode == "multiclass" else "Starting ") + name
		"race": return "Specie · " + name
		"subrace": return "Sottorazza · " + name
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
			"weapon": return granted.get("weaponProficiencies", granted.get("weapons", []))
			"armor": return granted.get("armorProficiencies", granted.get("armor", []))
			"tool": return granted.get("toolProficiencies", granted.get("tools", []))
			"skill": return granted.get("skills", [])
		return []
	var field_names: Dictionary = {
		"weapon": "weaponProficiencies", "armor": "armorProficiencies",
		"skill": "skillProficiencies", "expertise": "expertise",
		"tool": "toolProficiencies", "language": "languageProficiencies"
	}
	var field_name: String = String(field_names.get(kind, ""))
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
		var exact: Variant = value.get(wanted, false)
		if exact is bool and exact:
			return 2
		for found: Variant in value.keys():
			var literal: String = normalized_key(String(found).split("|")[0])
			var granted: Variant = value[found]
			if literal == wanted and granted is bool and granted:
				return 2
		var choose: Variant = value.get("choose", {})
		if choose is Dictionary:
			var options: Variant = choose.get("from", [])
			if options is Array and wanted in options:
				best = maxi(best, 1)
			# A structured filter can offer individual martial weapons,
			# but cannot grant proficiency with the entire category.
			var filter_text := String(choose.get("fromFilter", "")).to_lower()
			if kind == "weapon" and wanted not in ["simple", "martial", "all"]:
				if "type=martial weapon" in filter_text and _weapon_group(wanted) == "martial":
					best = maxi(best, 1)
			if options is Array and options.is_empty() and choose.has("any") and (kind != "weapon" or wanted not in ["simple", "martial", "all"]):
				best = maxi(best, 1)
		if (value.has("any") and (kind != "weapon" or wanted not in ["simple", "martial", "all"])) or (kind == "skill" and value.has("anyProficientSkill")):
			best = maxi(best, 1)
		if kind == "tool" and value.has("anyArtisansTool") and _tool_type(wanted) == "AT":
			best = maxi(best, 1)
		if kind == "tool" and value.has("anyMusicalInstrument") and _tool_type(wanted) == "INS":
			best = maxi(best, 1)
		if kind == "tool" and value.has("anyGamingSet") and _tool_type(wanted) == "GS":
			best = maxi(best, 1)
		# A bare 'any' in 5etools is a structured choice, not a fixed grant.
		# Standard/exotic languages must not be conflated.
		if kind == "language" and value.has("anyStandard") and _language_group(wanted) == "standard":
			best = maxi(best, 1)
		if kind == "language" and value.has("anyExotic") and _language_group(wanted) == "exotic":
			best = maxi(best, 1)
	return best


# The reduced 5etools item catalog may omit tool metadata. Keep a
# canonical fallback for structured "any artisan tool / gaming set /
# instrument" choices, so their count is recognized after selection.
const TOOL_TYPE_FALLBACK := {
	"AT": [
		"alchemist's supplies", "brewer's supplies", "calligrapher's supplies",
		"carpenter's tools", "cartographer's tools", "cobbler's tools",
		"cook's utensils", "glassblower's tools", "jeweler's tools",
		"leatherworker's tools", "mason's tools", "painter's supplies",
		"potter's tools", "smith's tools", "tinker's tools", "weaver's tools",
		"woodcarver's tools"
	],
	"GS": ["dice set", "dragonchess set", "playing card set", "three-dragon ante set"],
	"INS": [
		"bagpipes", "drum", "dulcimer", "flute", "lute", "lyre",
		"horn", "pan flute", "shawm", "viol"
	],
	"OTHER": [
		"disguise kit", "forgery kit", "herbalism kit",
		"navigator's tools", "poisoner's kit", "thieves' tools",
		"vehicles (land)", "vehicles (water)"
	]
}


static func _tool_type(key: String) -> String:
	for item: Dictionary in Catalog.entries("tools"):
		if normalized_key(String(item.get("name", ""))) == key:
			return String(item.get("type", "")).split("|")[0].to_upper()
	for type_code: String in TOOL_TYPE_FALLBACK.keys():
		if key in TOOL_TYPE_FALLBACK[type_code]:
			return type_code
	return ""


static func _language_group(key: String) -> String:
	var fallback := ""
	for item: Dictionary in Catalog.entries("languages"):
		if normalized_key(String(item.get("name", ""))) != key:
			continue
		var type_name := String(item.get("type", "")).to_lower()
		if String(item.get("source", "")) == "PHB":
			return type_name
		if fallback.is_empty() and type_name in ["standard", "exotic"]:
			fallback = type_name
	return fallback


static func _weapon_group(key: String) -> String:
	if key in ["simple", "martial"]:
		return key
	var fallback := ""
	for item: Dictionary in Catalog.entries("items"):
		if normalized_key(String(item.get("name", ""))) != key:
			continue
		if String(item.get("type", "")).split("|")[0].to_upper() not in ["M", "R"]:
			continue
		var category := normalized_key(String(item.get("weapon_category", "")))
		if category not in ["simple", "martial"]:
			continue
		if String(item.get("source", "")) == "PHB":
			return category
		if fallback.is_empty():
			fallback = category
	return fallback


static func suggest_origins(record: Dictionary, kind: String, key: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var group := _weapon_group(normalized_key(key)) if kind == "weapon" else ""
	for candidate: Dictionary in candidate_sources(record):
		var grants: Variant = _grants_data(candidate, kind)
		var matching := grant_matches(grants, kind, key)
		if matching == 0 and kind == "weapon" and not group.is_empty() and group != normalized_key(key):
			matching = grant_matches(grants, kind, group)
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



# Automatic source and proficiency materialization. The permanent identity is
# source ID + kind + key: two different origins may grant the same competence.
static func source_has_grants(source: Dictionary) -> bool:
	# A non-empty source JSON field is not necessarily a proficiency grant.
	# Only real fixed proficiencies or actionable structured choices qualify.
	return not fixed_grants(source).is_empty() or not choice_requirements(source).is_empty()


static func _active_identity_sources(record: Dictionary) -> Dictionary:
	var active: Dictionary = {}
	for source: Dictionary in candidate_sources(record):
		if source_has_grants(source):
			active[String(source.get("id", ""))] = true
	# Explicit item-based origins only exist while the owned item exists.
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		for item: Variant in inventory:
			if item is Dictionary:
				active["item:" + String((item as Dictionary).get("id", ""))] = true
	# Trait origins depend on the creature's current species/classes/feats.
	# Delay loading the traits script: it already preloads these rules.
	var needs_features := false
	var needs_numeric_sources := false
	for field: String in ["proficiency_origins", "proficiency_choices"]:
		var existing: Variant = record.get(field, [])
		if existing is Array:
			for row: Variant in existing:
				if not row is Dictionary:
					continue
				var sid := String((row as Dictionary).get("id", (row as Dictionary).get("origin_id", "")))
				if sid.begins_with("feature:"):
					needs_features = true
				if not active.has(sid) and (sid.begins_with("race|") or sid.begins_with("subrace|") or sid.begins_with("background|") or sid.begins_with("feat|")):
					needs_numeric_sources = true
	# Numeric-only identities may be absent from the proficiency index.
	# Load their structured grants only when a saved origin needs checking;
	# deriving them uses candidate_sources(), never this origins() path.
	if needs_numeric_sources:
		var numeric: Script = load("res://vtt/creature_structured_bonuses.gd") as Script
		if numeric != null:
			var grants: Variant = numeric.call("derive", record)
			if grants is Array:
				for grant: Variant in grants:
					if grant is Dictionary:
						active[String((grant as Dictionary).get("origin_id", ""))] = true
	if needs_features:
		var traits: Script = load("res://vtt/creature_traits_tab.gd") as Script
		if traits != null:
			var features: Variant = traits.call("collect_features", record)
			if features is Array:
				for feature: Variant in features:
					if feature is Dictionary:
						active["feature:" + String((feature as Dictionary).get("key", ""))] = true
	return active


static func _is_replaced_identity(sid: String, active: Dictionary) -> bool:
	# Historical catalog origins must not survive a change of race, class,
	# background or trait. Unknown (empty) and custom origins remain editable.
	if not (sid.begins_with("race|") or sid.begins_with("subrace|")
		or sid.begins_with("background|") or sid.begins_with("class|")
		or sid.begins_with("feat|") or sid.begins_with("feature:")
		or sid.begins_with("item:")):
		return false
	return not active.has(sid)


static func is_mandatory_grant(record: Dictionary, sid: String, kind: String, key: String) -> bool:
	if sid.is_empty():
		return false
	for source: Dictionary in candidate_sources(record):
		if String(source.get("id", "")) != sid:
			continue
		for grant: Dictionary in fixed_grants(source):
			if String(grant.get("kind", "")) == kind and String(grant.get("key", "")) == key:
				return true
	return false


static func fixed_grants(source: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in TYPES:
		var raw: Variant = _grants_data(source, kind)
		if not raw is Array:
			continue
		for item: Variant in raw:
			if item is String:
				var key: String = normalized_key(String(item))
				if key.begins_with("{@item ") and key.ends_with("}"):
					key = key.substr(7).split("|")[0].strip_edges()
				elif " " in key and kind not in ["skill", "language"]:
					# Never interpret sentences such as "one artisan tool of your choice".
					if not key in ["simple", "martial", "all"]:
						continue
				if not key.is_empty() and not key.begins_with("{@"):
					_add_fixed_grant(result, kind, key)
			elif item is Dictionary:
				for raw_key: Variant in (item as Dictionary).keys():
					var key: String = normalized_key(String(raw_key))
					if key in ["choose", "any", "anyArtisansTool", "anyGamingSet", "anyMusicalInstrument", "anyStandard", "anyExotic", "anyProficientSkill"]:
						continue
					var granted: Variant = (item as Dictionary)[raw_key]
					if granted is bool and granted:
						_add_fixed_grant(result, kind, key.split("|")[0])
	return result


static func _add_fixed_grant(rows: Array[Dictionary], kind: String, key: String) -> void:
	if not has_choice(rows, kind, key):
		rows.append({"kind": kind, "key": key})


static func choice_requirements(source: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in TYPES:
		var data: Variant = _grants_data(source, kind)
		if not data is Array:
			continue
		for raw: Variant in data:
			if not raw is Dictionary:
				continue
			var item: Dictionary = raw
			var choose: Variant = item.get("choose", {})
			if item.has("choose") and choose is Dictionary and not (choose as Dictionary).is_empty():
				var count: int = maxi(1, int((choose as Dictionary).get("count", 1)))
				result.append({"kind": kind, "count": count, "label": "Scegli %d · %s" % [count, kind], "data": item})
			for field: String in ["any", "anyArtisansTool", "anyGamingSet", "anyMusicalInstrument", "anyStandard", "anyExotic", "anyProficientSkill"]:
				if item.has(field):
					result.append({"kind": kind, "count": maxi(1, int(item[field])), "label": "Scegli %d · %s" % [maxi(1, int(item[field])), kind], "data": item})
	return result


# An explicit 5etools from-list is authoritative for the origin picker.
# Empty result means there is no restricted list (e.g. any skill).
static func restricted_choices(origin: Dictionary, kind: String) -> Array[String]:
	var options: Array[String] = []
	for requirement: Dictionary in origin.get("requirements", []):
		if String(requirement.get("kind", "")) != kind:
			continue
		var data: Dictionary = requirement.get("data", {})
		var choose: Variant = data.get("choose", {})
		if choose is Dictionary:
			var raw: Variant = (choose as Dictionary).get("from", [])
			if raw is Array:
				for value: Variant in raw:
					var key: String = normalized_key(String(value))
					if not key.is_empty() and key not in options:
						options.append(key)
	return options


static func origins(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var live: Dictionary = _active_identity_sources(record)
	var saved: Dictionary = {}
	var raw: Variant = record.get("proficiency_origins", [])
	if raw is Array:
		for item: Variant in raw:
			if item is Dictionary and not String(item.get("id", "")).is_empty():
				var sid: String = String(item.get("id", ""))
				if _is_replaced_identity(sid, live):
					continue
				saved[sid] = item
	for source: Dictionary in candidate_sources(record):
		if not source_has_grants(source):
			continue
		var sid: String = String(source.get("id", ""))
		var previous: Dictionary = saved.get(sid, {})
		# Sources can be muted even when they grant fixed proficiencies.
		# Muting never deletes their structural entitlement.
		result.append({"id": sid, "name": String(source.get("name", "")),
			"group": String(source.get("group", "")),
			"disabled": bool(previous.get("disabled", false)),
			"automatic": true, "requirements": choice_requirements(source)})
	for sid: String in saved.keys():
		var item: Dictionary = saved[sid]
		var found := false
		for row: Dictionary in result:
			if String(row.get("id", "")) == sid:
				found = true
				break
		if not found:
			var withdrawn: bool = bool(item.get("automatic", false)) and not live.has(sid)
			result.append({"id": sid,
				"name": ("⚠ Origine non più disponibile · " if withdrawn else "") + String(item.get("name", "Origine")),
				"group": String(item.get("group", "custom")),
				"disabled": withdrawn or bool(item.get("disabled", false)),
				"automatic": withdrawn, "requirements": []})
	var stored_choices: Variant = record.get("proficiency_choices", [])
	if not stored_choices is Array:
		stored_choices = []
	for row: Variant in stored_choices:
		if not row is Dictionary:
			continue
		var sid: String = String(row.get("origin_id", ""))
		if sid.is_empty() or _is_replaced_identity(sid, live):
			continue
		var present := false
		for item: Dictionary in result:
			if String(item.get("id", "")) == sid:
				present = true
				break
		if not present:
			var structured: bool = false
			for prefix: String in ["class|", "race|", "subrace|", "background|", "feat|"]:
				if sid.begins_with(prefix):
					structured = true
					break
			result.append({"id": sid,
				"name": ("⚠ Origine non più disponibile · " if structured else "") + String(row.get("origin_name", sid)),
				"group": "custom", "disabled": structured,
				"automatic": structured, "requirements": []})
	return result


static func origin_enabled_map(record: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item: Dictionary in origins(record):
		result[String(item.get("id", ""))] = not bool(item.get("disabled", false))
	return result


static func requirement_missing(source: Dictionary, rows: Array[Dictionary], enabled: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var sid: String = String(source.get("id", ""))
	for requirement: Dictionary in source.get("requirements", []):
		var kind: String = String(requirement.get("kind", ""))
		var present := 0
		for row: Dictionary in rows:
			if String(row.get("origin_id", "")) != sid or String(row.get("kind", "")) != kind:
				continue
			if bool(row.get("disabled", false)) or not bool(enabled.get(sid, true)):
				continue
			# Fixed grants in the same group do not satisfy a choose quota.
			if grant_matches(requirement.get("data", {}), kind, String(row.get("key", ""))) == 1:
				present += 1
		var count: int = int(requirement.get("count", 1))
		# Chosen proficiencies are represented only after manual selection.
		if present < count:
			result.append("%s · %d/%d" % [kind, present, count])
	return result


static func _readable_grants(value: Variant) -> String:
	var pieces := PackedStringArray()
	if not value is Array:
		return ""
	for raw: Variant in value:
		if raw is String:
			var label: String = String(raw)
			if label.begins_with("{@item "):
				label = label.substr(7).split("|")[0].strip_edges()
			pieces.append(label.capitalize() if label in ["simple", "martial", "light", "medium", "heavy", "shield"] else label)
		elif raw is Dictionary:
			var item: Dictionary = raw
			for field: String in item.keys():
				# A 5etools grant may also contain nested dictionaries (choose),
				# counts or filters. Only a literal boolean true is fixed.
				var granted: Variant = item[field]
				if field != "choose" and granted is bool and granted:
					pieces.append(field.capitalize())
			var choose: Variant = item.get("choose", {})
			if item.has("choose") and choose is Dictionary and not (choose as Dictionary).is_empty():
				var count: int = maxi(1, int((choose as Dictionary).get("count", 1)))
				var options: Variant = (choose as Dictionary).get("from", [])
				if options is Array and not (options as Array).is_empty():
					pieces.append("Choose %d: %s" % [count, ", ".join(PackedStringArray(options))])
				else:
					pieces.append("Choose %d from %s" % [count, String((choose as Dictionary).get("fromFilter", "the available options"))])
			for field: String in ["any", "anyStandard", "anyExotic", "anyArtisansTool", "anyMusicalInstrument", "anyGamingSet", "anyProficientSkill"]:
				if item.has(field):
					pieces.append("Choose %d (%s)" % [int(item[field]), field])
	return "; ".join(pieces)


static func _clean_equipment(text_value: String) -> String:
	var pattern: RegEx = RegEx.create_from_string("\\{@(?:item|filter|dice) ([^}|]+)(?:\\|[^}]*)?\\}")
	if pattern == null:
		return text_value
	var replaced: String = text_value
	for match_result: RegExMatch in pattern.search_all(text_value):
		replaced = replaced.replace(match_result.get_string(0), match_result.get_string(1))
	return replaced


static func starting_description(source: Dictionary) -> String:
	var data: Dictionary = source.get("data", {})
	var meta: Dictionary = data.get("startingMeta", {})
	var mode: String = String(source.get("mode", "starting"))
	var lines := PackedStringArray()
	lines.append("Multiclassing" if mode == "multiclass" else "Core Traits")
	var dice: String = String(meta.get("hitDice", ""))
	if mode == "starting" and not dice.is_empty():
		lines.append("Hit Point Die: %s per level" % dice)
		lines.append("Hit Points at Level 1: %d + Constitution modifier" % int(meta.get("hitPointsAtFirst", 0)))
		lines.append("Hit Points per additional level: %s + Constitution modifier" % dice)
	var saving: String = _readable_grants(data.get("savingThrows", []))
	if mode == "starting" and not saving.is_empty():
		lines.append("Saving Throw Proficiencies: " + saving)
	var start: Dictionary = data.get("startingProficiencies", {})
	for group: String in (["skills", "weapons", "armor", "tools"] if mode == "starting" else []):
		var raw: Variant = start.get(group, [])
		if group == "armor":
			raw = start.get("armor", [])
		var displayed := _readable_grants(raw)
		if not displayed.is_empty():
			var names: Dictionary = {"skills": "Skill Proficiencies", "weapons": "Weapon Proficiencies", "armor": "Armor Training", "tools": "Tool Proficiencies"}
			var title: String = String(names.get(group, group.capitalize()))
			lines.append(title + ": " + _clean_equipment(displayed))
	var equipment: Variant = meta.get("equipment", [])
	if mode == "starting" and equipment is Array and not (equipment as Array).is_empty():
		lines.append("")
		lines.append("Starting Equipment")
		for item: Variant in equipment:
			lines.append("• " + _clean_equipment(String(item)))
		var gold_option: String = String(meta.get("gold", ""))
		if not gold_option.is_empty():
			lines.append("Alternativamente: " + _clean_equipment(gold_option) + " per acquistare l'equipaggiamento")
	if mode == "starting":
		lines.append("")
		lines.append("Multiclassing")
	var requirements: Variant = meta.get("multiclass", {})
	if requirements is Dictionary and not (requirements as Dictionary).is_empty():
		var requirement_pieces := PackedStringArray()
		for ability: String in (requirements as Dictionary).keys():
			requirement_pieces.append(ability.to_upper() + " " + str((requirements as Dictionary)[ability]))
		lines.append("Ability Score Minimum: " + ", ".join(requirement_pieces))
	var multi: Dictionary = data.get("multiclassProficiencies", {})
	for group: String in ["skills", "weapons", "armor", "tools"]:
		var displayed := _readable_grants(multi.get(group, []))
		if not displayed.is_empty():
			var names: Dictionary = {"skills": "Skill Proficiencies", "weapons": "Weapon Proficiencies", "armor": "Armor Training", "tools": "Tool Proficiencies"}
			var title: String = String(names.get(group, group.capitalize()))
			lines.append(title + ": " + _clean_equipment(displayed))
	lines.append("")
	lines.append("Applicate a questa creatura: " + ("competenze iniziali" if mode == "starting" else "competenze da multiclasse"))
	lines.append("Source: " + String(data.get("source", "")))
	return "\n".join(lines)
