extends RefCounted

# The granted choices are explicit sheet state. 5etools data only suggests
# origins; never infer proficiencies by parsing feature descriptions.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const LocalCatalog = preload("res://vtt/content_catalog.gd")
const SourcePath := "res://vtt/data/proficiency_grants_5etools.json"
const TYPES := ["weapon", "armor", "skill", "expertise", "save", "tool", "language"]
const SKILLS := ["acrobatics", "animal handling", "arcana", "athletics", "deception",
	"history", "insight", "intimidation", "investigation", "medicine", "nature",
	"perception", "performance", "persuasion", "religion", "sleight of hand",
	"stealth", "survival"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ARMORS := ["light", "medium", "heavy", "shield"]
# Some secret and exotic languages are omitted by the compact player catalog.
# Use canonical 5e names, and supplement them with names from structured grants.
const LANGUAGE_FALLBACK := {
	"standard": ["Common", "Dwarvish", "Elvish", "Giant", "Gnomish", "Goblin", "Halfling", "Orc"],
	"exotic": ["Abyssal", "Celestial", "Deep Speech", "Draconic", "Infernal", "Primordial", "Sylvan", "Undercommon"],
	"secret": ["Druidic", "Thieves' Cant"],
	"other": ["Aquan", "Auran", "Ignan", "Terran"]
}


static func feat_source_id(feat: Dictionary) -> String:
	var name: String = normalized_key(String(feat.get("name", "")))
	var source: String = normalized_key(String(feat.get("source", "")))
	return "feat|" + source + "|" + name if not name.is_empty() else ""


# Normalized 5etools language types, refreshed from the latest tagged
# upstream data/languages.json. Cache only the static metadata; homebrew
# entries remain dynamic through Catalog.entries("languages").
const LANGUAGE_INDEX_PATH := "res://vtt/data/languages_5etools.json"
const LANGUAGE_TYPE_LABELS := {
	"standard": "Standard", "exotic": "Esotico",
	"rare": "Raro", "secret": "Segreto", "other": "Altro"
}
static var _language_metadata: Dictionary = {}


static func _load_language_metadata() -> void:
	if not _language_metadata.is_empty():
		return
	var file: FileAccess = FileAccess.open(LANGUAGE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	for item: Variant in (parsed as Dictionary).get("languages", []):
		if item is Dictionary:
			var key: String = normalized_key(String((item as Dictionary).get("key", "")))
			if not key.is_empty():
				_language_metadata[key] = item


static func language_type(key: String) -> String:
	var normalized: String = normalized_key(key)
	# These two remain class-exclusive secret tongues even if a modern
	# source reclassifies them as "rare" for its own language glossary.
	if normalized in ["druidic", "thieves' cant"]:
		return "secret"
	_load_language_metadata()
	if _language_metadata.has(normalized):
		return String((_language_metadata[normalized] as Dictionary).get("group", "other"))
	for group: String in LANGUAGE_FALLBACK.keys():
		for name: String in LANGUAGE_FALLBACK[group]:
			if normalized_key(name) == normalized:
				return group
	for item: Dictionary in Catalog.entries("languages"):
		if normalized_key(String(item.get("name", ""))) == normalized:
			var kind: String = String(item.get("type", "")).to_lower()
			return kind if not kind.is_empty() else "other"
	return ""


static func language_type_for_edition(key: String, edition: String) -> String:
	var category: String = language_type(key)
	if category == "secret":
		return category
	_load_language_metadata()
	var known: Dictionary = _language_metadata.get(normalized_key(key), {})
	var types: Variant = known.get("types", [])
	if edition == "2024" and types is Array and "rare" in types:
		return "rare"
	if edition == "2014" and types is Array and "exotic" in types:
		return "exotic"
	return category


static func language_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	_load_language_metadata()
	for raw_key: Variant in _language_metadata.keys():
		var entry: Dictionary = _language_metadata[raw_key]
		var key: String = String(raw_key)
		var category: String = language_type(key)
		var name: String = String(entry.get("label", key.capitalize()))
		seen[key] = true
		result.append({"key": key,
			"label": "%s · %s" % [name, LANGUAGE_TYPE_LABELS.get(category, "Altro")],
			"source": String(entry.get("source", "PHB")),
			"group": category, "edition": ""})
	# Add names not covered by the snapshot (homebrew or compact catalog).
	for item: Dictionary in Catalog.entries("languages"):
		var name: String = String(item.get("name", "")).strip_edges()
		var key: String = normalized_key(name)
		if key.is_empty() or seen.has(key):
			continue
		var category: String = language_type(key)
		seen[key] = true
		result.append({"key": key,
			"label": "%s · %s" % [name, LANGUAGE_TYPE_LABELS.get(category, "Altro")],
			"source": String(item.get("source", "")), "group": category,
			"edition": String(item.get("edition", ""))})
	# Canonical secret/standard/exotic names remain available even if the
	# mirror or player subset omits them.
	for group: String in LANGUAGE_FALLBACK.keys():
		for name: String in LANGUAGE_FALLBACK[group]:
			var key: String = normalized_key(name)
			if seen.has(key):
				continue
			var category: String = language_type(key)
			seen[key] = true
			result.append({"key": key, "label": "%s · %s" % [
				name, LANGUAGE_TYPE_LABELS.get(category, "Altro")],
				"source": "PHB", "group": category})
	_load_sources()
	for group: String in ["class", "race", "subrace", "background", "feat"]:
		for row: Dictionary in _sources.get(group, []):
			var grants: Variant = row.get("languageProficiencies", [])
			if not grants is Array:
				continue
			for raw: Variant in grants:
				var candidates: Array = []
				if raw is String:
					candidates.append(raw)
				elif raw is Dictionary:
					var data: Dictionary = raw
					for raw_key: Variant in data.keys():
						if data[raw_key] is bool and bool(data[raw_key]):
							candidates.append(raw_key)
					var choose: Variant = data.get("choose", {})
					if choose is Dictionary:
						var offered: Variant = (choose as Dictionary).get("from", [])
						if offered is Array:
							candidates.append_array(offered)
				for candidate: Variant in candidates:
					var key: String = normalized_key(String(candidate).split("|")[0])
					if key.is_empty() or key.begins_with("any") or key.begins_with("{@") or seen.has(key):
						continue
					var category: String = language_type(key)
					seen[key] = true
					result.append({"key": key,
						"label": "%s · %s" % [key.capitalize(),
							LANGUAGE_TYPE_LABELS.get(category, "Altro")],
						"source": String(row.get("source", "")), "group": category})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("label", "")).naturalnocasecmp_to(String(b.get("label", ""))) < 0)
	return result


static var _sources: Dictionary = {}
static var _source_names: Dictionary = {}


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
		_source_names.clear()
		for group: String in ["class", "race", "subrace", "background", "feat"]:
			var by_name: Dictionary = {}
			var rows: Variant = _sources.get(group, [])
			if rows is Array:
				for index: int in range(rows.size()):
					if not rows[index] is Dictionary:
						continue
					var key := String(rows[index].get("name", "")).to_lower()
					if not by_name.has(key):
						by_name[key] = []
					by_name[key].append(index)
			_source_names[group] = by_name


static func normalized_key(value: String) -> String:
	return value.strip_edges().to_lower()


static func choices(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_sources: Dictionary = _active_identity_sources(record)
	var replaced_parent_source := ""
	for source: Dictionary in candidate_sources(record):
		if String(source.get("group", "")) == "race" and bool((source.get("data", {}) as Dictionary).get("parent_languages_replaced", false)):
			replaced_parent_source = String(source.get("id", ""))
			break
	var raw: Variant = record.get("proficiency_choices", [])
	if raw is Array:
		for value: Variant in raw:
			if not value is Dictionary:
				continue
			var row: Dictionary = value
			if _is_replaced_identity(String(row.get("origin_id", "")), current_sources):
				continue
			var kind: String = String(row.get("kind", ""))
			if kind == "language" and String(row.get("origin_id", "")) == replaced_parent_source:
				continue
			var key: String = normalized_key(String(row.get("key", "")))
			if kind == "language" and key == "other":
				continue # Legacy 5etools placeholder, never a spoken language.
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
	for source: Dictionary in _grant_sources(record):
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


# Narrow the catalog by name, then retain the existing source/parent checks.
# Sorting original indices preserves catalog order, including ambiguous legacy
# backgrounds and duplicate names from different books.
static func _candidate_indices(record: Dictionary, group: String) -> Array[int]:
	var names: Array[String] = []
	match group:
		"class", "feat":
			var rows: Variant = record.get("classes" if group == "class" else "feats_catalog", [])
			if rows is Array:
				for row: Variant in rows:
					if row is Dictionary:
						names.append(String(row.get("name", "")).to_lower())
			if group == "class":
				names.append(String(record.get("class", "")).to_lower())
		"race":
			names.append(String(record.get("species", "")).to_lower())
		_:
			names.append(String(record.get(group, "")).to_lower())
	var indices: Array[int] = []
	var by_name: Dictionary = _source_names.get(group, {})
	for name: String in names:
		for index: int in by_name.get(name, []):
			if index not in indices:
				indices.append(index)
	indices.sort()
	return indices

static func candidate_sources(record: Dictionary) -> Array[Dictionary]:
	_load_sources()
	var candidates: Array[Dictionary] = []
	var kinds := ["class", "race", "subrace", "background", "feat"]
	for group: String in kinds:
		var rows: Variant = _sources.get(group, [])
		if not rows is Array:
			continue
		for index: int in _candidate_indices(record, group):
			var row: Dictionary = rows[index]
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
	# Quick-created local backgrounds and feats contain typed fixed
	# proficiency grants. Match only selected identities, never arbitrary
	# catalog contents, so they work through the ordinary origin engine.
	for group: String in ["background", "feat"]:
		var category: String = "backgrounds" if group == "background" else "feats"
		for row: Dictionary in LocalCatalog.home_entries(category):
			if not String(row.get("id", "")).begins_with("homebrew:quick_local:"):
				continue
			var name: String = String(row.get("name", ""))
			var source: String = String(row.get("source", ""))
			if not _selected_source(record, group, name, source, row):
				continue
			var sid: String = group + "|" + normalized_key(source) + "|" + normalized_key(name)
			var exists := false
			for candidate: Dictionary in candidates:
				if String(candidate.get("id", "")) == sid:
					exists = true
					break
			if not exists:
				candidates.append({"id": sid,
					"name": _origin_title(group, name, "starting") + " · " + source,
					"group": group, "data": row, "mode": "starting"})
	# A few 2014-era subraces replace the parent's full Languages feature.
	# Keep the race identity but hide only its language grants and choices.
	var replaced_languages := false
	var enabled_sources: Dictionary = record.get("origin_enabled", {})
	var saved_origins: Variant = record.get("proficiency_origins", [])
	for candidate: Dictionary in candidates:
		if String(candidate.get("group", "")) != "subrace" or not bool((candidate.get("data", {}) as Dictionary).get("replaces_parent_languages", false)):
			continue
		var sid: String = String(candidate.get("id", ""))
		if not bool(enabled_sources.get(sid, true)):
			continue
		var disabled := false
		if saved_origins is Array:
			for origin: Variant in saved_origins:
				if origin is Dictionary and String(origin.get("id", "")) == sid and bool(origin.get("disabled", false)):
					disabled = true
					break
		if not disabled:
			replaced_languages = true
			break
	if replaced_languages:
		for candidate: Dictionary in candidates:
			if String(candidate.get("group", "")) != "race":
				continue
			var adjusted: Dictionary = (candidate.get("data", {}) as Dictionary).duplicate(true)
			adjusted["languageProficiencies"] = []
			adjusted["parent_languages_replaced"] = true
			candidate["data"] = adjusted
	return candidates


# Feature grants use the exact live trait identity. Keep this separate from
# candidate_sources(), which is called while the feature list is assembled.
static func _grant_sources(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = candidate_sources(record)
	_load_sources()
	var by_id: Dictionary = {}
	for group: String in ["classFeature", "subclassFeature"]:
		for row: Dictionary in _sources.get(group, []):
			by_id[String(row.get("id", ""))] = row
	for feature_origin: Dictionary in trait_origins(record):
		var sid: String = String(feature_origin.get("id", ""))
		var feature_id: String = sid.substr(sid.rfind("|") + 1)
		if not by_id.has(feature_id):
			continue
		result.append({"id": sid, "name": String(feature_origin.get("name", "")),
			"group": "feature", "data": by_id[feature_id], "mode": "feature"})
	return result


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
		"tool": "toolProficiencies", "language": "languageProficiencies",
		"save": "saveProficiencies"
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
		# "anyStandard" means a free language choice here: allow standard,
		# exotic, rare and other languages, but never class-exclusive secrets.
		if kind == "language" and value.has("anyStandard") and language_type(wanted) not in ["", "secret"]:
			best = maxi(best, 1)
		if kind == "language" and value.has("anyExotic") and language_type(wanted) in ["exotic", "rare"]:
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
	return language_type(key)


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
	for candidate: Dictionary in _grant_sources(record):
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
	# Any selected catalog identity can be referenced by a manually granted
	# bonus, feat, proficiency or tracker, even when 5etools lists no
	# built-in proficiency for it. Do not discard such live references.
	for source: Dictionary in candidate_sources(record):
		active[String(source.get("id", ""))] = true
	# Explicit item-based origins only exist while the owned item exists.
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		for item: Variant in inventory:
			if item is Dictionary:
				active["item:" + String((item as Dictionary).get("id", ""))] = true
	# A feat is an origin even if it has no indexed proficiency grant.
	for feat: Variant in record.get("feats_catalog", []):
		if feat is Dictionary:
			var feat_sid: String = feat_source_id(feat)
			if not feat_sid.is_empty():
				active[feat_sid] = true
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
		var traits: Script = load("res://vtt/creature_features.gd") as Script
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
	for source: Dictionary in _grant_sources(record):
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
	for source: Dictionary in _grant_sources(record):
		if not source_has_grants(source) and String(source.get("group", "")) != "feat":
			continue
		var sid: String = String(source.get("id", ""))
		var previous: Dictionary = saved.get(sid, {})
		# Sources can be muted even when they grant fixed proficiencies.
		# Muting never deletes their structural entitlement.
		result.append({"id": sid, "name": String(source.get("name", "")),
			"group": String(source.get("group", "")),
			"disabled": bool(previous.get("disabled", false)),
			"automatic": true, "requirements": choice_requirements(source)})
	# Homebrew or otherwise unindexed feats must also be selectable as origins.
	for raw_feat: Variant in record.get("feats_catalog", []):
		if not raw_feat is Dictionary:
			continue
		var feat: Dictionary = raw_feat
		var sid: String = feat_source_id(feat)
		if sid.is_empty():
			continue
		var present := false
		for existing: Dictionary in result:
			if String(existing.get("id", "")) == sid:
				present = true
				break
		if not present:
			var previous: Dictionary = saved.get(sid, {})
			result.append({"id": sid, "name": "Talento · " + String(feat.get("name", "")),
				"group": "feat", "disabled": bool(previous.get("disabled", false)),
				"automatic": true, "requirements": []})
	for sid: String in saved.keys():
		var item: Dictionary = saved[sid]
		var found := false
		for row: Dictionary in result:
			if String(row.get("id", "")) == sid:
				found = true
				break
		if not found:
			var withdrawn: bool = bool(item.get("automatic", false)) and not live.has(sid) and String(item.get("group", "")) != "spell"
			result.append({"id": sid,
				"name": ("⚠ Origine non più disponibile · " if withdrawn else "") + String(item.get("name", "Origine")),
				"group": String(item.get("group", "custom")),
				"disabled": withdrawn or bool(item.get("disabled", false)),
				"automatic": withdrawn, "applied": bool(item.get("applied", false)), "requirements": []})
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


# The headless feature projection defines canonical live trait origins. No description text is
# interpreted as a grant: the explicit 5etools "feats" field is authoritative.
static func trait_origins(record: Dictionary, only_feat_granters: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var traits: Script = load("res://vtt/creature_features.gd") as Script
	if traits == null:
		return result
	var saved: Dictionary = {}
	for origin: Variant in record.get("proficiency_origins", []):
		if origin is Dictionary:
			saved[String(origin.get("id", ""))] = bool(origin.get("disabled", false))
	for feature: Dictionary in traits.call("collect_features", record):
		var feats: Variant = feature.get("feats", [])
		var grants_feats: bool = (
			(feats is Array and not (feats as Array).is_empty())
			or (feats is Dictionary and not (feats as Dictionary).is_empty())
			or (feats is String and not String(feats).strip_edges().is_empty())
		)
		if only_feat_granters and not grants_feats:
			continue
		var sid: String = "feature:" + String(feature.get("key", ""))
		result.append({"id": sid, "name": "Tratto · " + String(feature.get("name", "")),
			"group": "feature", "feats": feats,
			"disabled": bool(saved.get(sid, false)), "automatic": true,
			"origin_key": String(feature.get("origin_key", "")),
			# The selected class and *feature level* identify each occurrence
			# of repeatable traits like Ability Score Improvement (4/8/12...).
			# These fields are UI metadata; the stable ID and grants stay intact.
			"origin": String(feature.get("origin", "")),
			"class_name": String(feature.get("class_name", "")),
			"class_source": String(feature.get("class_source", "")),
			"level": int(feature.get("level", 0)),
			"book": String(feature.get("book", "")),
			"category": String(feature.get("category", ""))})
	return result


# Physical removal withdraws saved dependent grants. Temporary switches
# (disabled/equipped/attuned) instead keep the graph intact and only mute it.
static func _live_origin_ids(record: Dictionary) -> Dictionary:
	var live: Dictionary = {"": true}
	for alias: String in preload("res://vtt/monster_trait_projection.gd").legacy_sources(record):
		live[alias] = true
	for source: Dictionary in candidate_sources(record):
		live[String(source.get("id", ""))] = true
	for feature: Dictionary in trait_origins(record):
		live[String(feature.get("id", ""))] = true
		live[String(feature.get("origin_key", ""))] = true
	for identity: Dictionary in [
		{"group": "race", "name": record.get("species", ""), "source": record.get("species_source", "")},
		{"group": "subrace", "name": record.get("subrace", ""), "source": record.get("subrace_source", "")},
		{"group": "background", "name": record.get("background", ""), "source": record.get("background_source", "")}
	]:
		if not String(identity.name).is_empty():
			live[String(identity.group) + "|" + String(identity.source).to_lower() + "|" + String(identity.name).to_lower()] = true
	var classes: Variant = record.get("classes", [])
	if classes is Array:
		for member: Variant in classes:
			if member is Dictionary and not String(member.get("name", "")).is_empty():
				live["class|" + String(member.get("source", "")).to_lower() + "|" + String(member.get("name", "")).to_lower()] = true
	for value: Variant in record.get("inventory", []):
		if value is Dictionary and int(value.get("quantity", 1)) > 0:
			live["item:" + String(value.get("id", ""))] = true
	for feat: Variant in record.get("feats_catalog", []):
		if feat is Dictionary:
			live[feat_source_id(feat)] = true
	for origin: Variant in record.get("proficiency_origins", []):
		if origin is Dictionary and String(origin.get("group", "")) in ["custom", "spell"]:
			live[String(origin.get("id", ""))] = true
	return live


# 5etools uses the structured "feats" field for fixed grants as well as
# choose/any options. Only fixed references are created automatically;
# selectable variants remain choices for the user, not guessed feats.
static func _fixed_feat_refs(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is String:
		var token: String = String(value).strip_edges()
		if token.is_empty():
			return result
		var parts: PackedStringArray = token.split("|")
		result.append({"name": parts[0], "source": parts[1] if parts.size() > 1 else ""})
	elif value is Array:
		for part: Variant in value:
			result.append_array(_fixed_feat_refs(part))
	elif value is Dictionary:
		var data: Dictionary = value
		if data.has("name"):
			result.append({"name": String(data.get("name", "")), "source": String(data.get("source", ""))})
		else:
			for key: String in data.keys():
				if key in ["choose", "any", "count", "from", "weighted"]:
					continue
				if data[key] is bool and not bool(data[key]):
					continue
				if data[key] is Dictionary or data[key] is Array:
					continue
				result.append_array(_fixed_feat_refs(key))
	return result


static func _grant_fixed_feats(record: Dictionary) -> void:
	var feats: Array = record.get("feats_catalog", []).duplicate(true)
	# An inherited feat can itself carry a structured grant. Iterate until
	# no new grant appears, with identity+parent deduplication for cycles.
	for _pass: int in range(20):
		record["feats_catalog"] = feats
		var sources: Array[Dictionary] = trait_origins(record, true)
		var additions := 0
		var feat_catalog: Array[Dictionary] = []
		for source: Dictionary in sources:
			var sid: String = String(source.get("id", ""))
			for ref: Dictionary in _fixed_feat_refs(source.get("feats", [])):
				var feat_name: String = String(ref.get("name", ""))
				var feat_book: String = String(ref.get("source", ""))
				if feat_name.is_empty():
					continue
				if feat_catalog.is_empty():
					feat_catalog = Catalog.entries("feats")
				for candidate: Dictionary in feat_catalog:
					if String(candidate.get("name", "")).nocasecmp_to(feat_name) != 0:
						continue
					if not feat_book.is_empty() and String(candidate.get("source", "")).nocasecmp_to(feat_book) != 0:
						continue
					var duplicate := false
					for owned: Variant in feats:
						if owned is Dictionary and feat_source_id(owned) == feat_source_id(candidate) and String(owned.get("origin_id", "")) == sid:
							duplicate = true
							break
					if not duplicate:
						feats.append({"id": candidate.get("id", ""),
							"name": candidate.get("name", ""), "source": candidate.get("source", ""),
							"origin_id": sid, "origin_name": source.get("name", ""),
							"automatic": true, "disabled": false})
						additions += 1
					break
		if additions == 0:
			break
	record["feats_catalog"] = feats


static func reconcile_origin_dependents(record: Dictionary) -> void:
	_grant_fixed_feats(record)
	# Iterative fixed point: a deleted item may have granted a feat which
	# granted another feat, a competence, and a formula bonus.
	var feats: Array = record.get("feats_catalog", []).duplicate(true)
	for _pass: int in range(feats.size() + 2):
		record["feats_catalog"] = feats
		var live: Dictionary = _live_origin_ids(record)
		var remaining: Array = []
		for raw: Variant in feats:
			if not raw is Dictionary:
				continue
			var parent: String = String(raw.get("origin_id", ""))
			if parent.is_empty() or live.has(parent):
				remaining.append(raw)
		if remaining.size() == feats.size():
			break
		feats = remaining
	record["feats_catalog"] = feats
	var live: Dictionary = _live_origin_ids(record)
	for field: String in ["proficiency_choices", "formula_bonuses", "resource_trackers", "damage_defense_entries", "origin_spell_grants", "dice_bonuses"]:
		var current: Variant = record.get(field, [])
		if not current is Array:
			continue
		var kept: Array = []
		for raw: Variant in current:
			if raw is Dictionary:
				var parent: String = String(raw.get("origin_id", ""))
				if parent.is_empty() or live.has(parent) or (field == "damage_defense_entries" and bool((raw as Dictionary).get("automatic", false))):
					kept.append(raw)
		record[field] = kept
	var origins_saved: Variant = record.get("proficiency_origins", [])
	if origins_saved is Array:
		var kept_origins: Array = []
		for origin: Variant in origins_saved:
			if not origin is Dictionary:
				continue
			var sid: String = String(origin.get("id", ""))
			if live.has(sid) or String(origin.get("group", "")) in ["custom", "spell"]:
				kept_origins.append(origin)
		# An applied spell exists only while it grants at least one benefit.
		# Otherwise an abandoned spell would remain listed as an active effect.
		var used_origins: Dictionary = {}
		for field: String in ["proficiency_choices", "formula_bonuses", "resource_trackers", "damage_defense_entries", "feats_catalog", "origin_spell_grants", "dice_bonuses"]:
			for raw: Variant in record.get(field, []):
				if raw is Dictionary:
					used_origins[String((raw as Dictionary).get("origin_id", ""))] = true
		for feature: Dictionary in trait_origins(record):
			if used_origins.has(String(feature.get("id", ""))):
				used_origins[String(feature.get("origin_key", ""))] = true
		var active_origins: Array = []
		for origin: Dictionary in kept_origins:
			if String(origin.get("group", "")) == "spell" and not bool(origin.get("applied", false)) and not used_origins.has(String(origin.get("id", ""))):
				continue
			active_origins.append(origin)
		record["proficiency_origins"] = active_origins


static func _resolved_source_active(
	sid: String, own: Dictionary, feat_grants: Dictionary, feature_parents: Dictionary,
	visiting: Dictionary, cached: Dictionary
) -> bool:
	if sid.is_empty():
		return true
	if cached.has(sid):
		return bool(cached[sid])
	if visiting.has(sid):
		return false
	if not bool(own.get(sid, false)):
		cached[sid] = false
		return false
	visiting[sid] = true
	var active := true
	if feat_grants.has(sid):
		active = false
		for entry: Dictionary in feat_grants[sid]:
			if not bool(entry.get("disabled", false)) and _resolved_source_active(
				String(entry.get("origin_id", "")), own, feat_grants, feature_parents, visiting, cached
			):
				active = true
				break
	if active and feature_parents.has(sid):
		active = _resolved_source_active(String(feature_parents[sid]), own, feat_grants, feature_parents, visiting, cached)
	visiting.erase(sid)
	cached[sid] = active
	return active


static func origin_enabled_map(record: Dictionary) -> Dictionary:
	var own: Dictionary = {}
	for item: Dictionary in origins(record):
		own[String(item.get("id", ""))] = not bool(item.get("disabled", false))
	own[""] = true
	# All live traits are potential origins, even when they grant no
	# proficiency. Do not expose all of them in each editor's source list.
	for identity: Dictionary in [
		{"group": "race", "name": record.get("species", ""), "source": record.get("species_source", "")},
		{"group": "subrace", "name": record.get("subrace", ""), "source": record.get("subrace_source", "")},
		{"group": "background", "name": record.get("background", ""), "source": record.get("background_source", "")}
	]:
		if not String(identity.name).is_empty():
			var identity_id: String = String(identity.group) + "|" + String(identity.source).to_lower() + "|" + String(identity.name).to_lower()
			if not own.has(identity_id):
				own[identity_id] = true
	var selected_classes: Variant = record.get("classes", [])
	if selected_classes is Array:
		for member: Variant in selected_classes:
			if member is Dictionary and not String(member.get("name", "")).is_empty():
				var identity_id: String = "class|" + String(member.get("source", "")).to_lower() + "|" + String(member.get("name", "")).to_lower()
				if not own.has(identity_id):
					own[identity_id] = true
	for feature: Dictionary in trait_origins(record):
		var sid: String = String(feature.get("id", ""))
		if not own.has(sid):
			own[sid] = true
		var group_sid: String = String(feature.get("origin_key", ""))
		if not group_sid.is_empty() and not own.has(group_sid):
			own[group_sid] = true
	var item_rules: Script = load("res://vtt/creature_item_rules.gd") as Script
	if item_rules != null:
		var item_sources: Dictionary = {}
		for raw_item: Variant in record.get("inventory", []):
			if not raw_item is Dictionary:
				continue
			var item_id: String = "item:" + String(raw_item.get("id", ""))
			if item_id == "item:" or int(raw_item.get("quantity", 1)) <= 0:
				continue
			# Several physical copies can share the same catalog ID. Only
			# one of them needs to be equipped to keep that origin active.
			item_sources[item_id] = bool(item_sources.get(item_id, false)) or bool(item_rules.call("origin_active", raw_item, record))
		for item_id: String in item_sources.keys():
			own[item_id] = bool(own.get(item_id, true)) and bool(item_sources[item_id])
	var feat_grants: Dictionary = {}
	var feat_feature_prefixes: Dictionary = {}
	var raw_feats: Variant = record.get("feats_catalog", [])
	if raw_feats is Array:
		for raw: Variant in raw_feats:
			if not raw is Dictionary:
				continue
			var feat: Dictionary = raw
			var sid: String = feat_source_id(feat)
			if sid.is_empty():
				continue
			if not feat_grants.has(sid):
				feat_grants[sid] = []
			feat_grants[sid].append(feat)
			var feat_id: String = String(feat.get("id", ""))
			if feat_id.is_empty():
				feat_id = normalized_key(String(feat.get("name", ""))) + "|" + normalized_key(String(feat.get("source", "")))
			feat_feature_prefixes["feature:feat|" + feat_id + "|"] = sid
	var feature_parents: Dictionary = {}
	# The effective species card is a trait group, but its source switch is
	# the stable race identity in the proficiency editor.
	var species_name: String = String(record.get("species", ""))
	if not species_name.is_empty():
		var species_id: String = String(record.get("species_id", ""))
		var species_key: String = "species|" + (species_id if not species_id.is_empty() else species_name.to_lower()) + "|" + String(record.get("species_source", "")).to_lower()
		var race_id: String = "race|" + String(record.get("species_source", "")).to_lower() + "|" + species_name.to_lower()
		if own.has(species_key) and own.has(race_id):
			feature_parents[species_key] = race_id
	for feature: Dictionary in trait_origins(record):
		var sid: String = String(feature.get("id", ""))
		var group_sid: String = String(feature.get("origin_key", ""))
		if group_sid.begins_with("item:"):
			feature_parents[sid] = group_sid
		elif group_sid.begins_with("feat|"):
			# The feat ID stored by Traits can be a catalog or homebrew ID.
			for raw_feat: Variant in record.get("feats_catalog", []):
				if not raw_feat is Dictionary:
					continue
				var feat_id: String = String(raw_feat.get("id", ""))
				if feat_id.is_empty():
					feat_id = normalized_key(String(raw_feat.get("name", ""))) + "|" + normalized_key(String(raw_feat.get("source", "")))
				if group_sid == "feat|" + feat_id:
					feature_parents[sid] = feat_source_id(raw_feat)
					break
		elif not group_sid.is_empty() and group_sid != sid and own.has(group_sid):
			feature_parents[sid] = group_sid
	for raw_id: Variant in own.keys():
		var origin_id: String = String(raw_id)
		for prefix: String in feat_feature_prefixes.keys():
			if origin_id.begins_with(prefix):
				feature_parents[origin_id] = feat_feature_prefixes[prefix]
				break
	var result: Dictionary = {}
	var visiting: Dictionary = {}
	# Removed monster action cards still own existing saved custom benefits.
	# Resolve their stable source IDs through the new granting card.
	var aliases: Dictionary = preload("res://vtt/monster_trait_projection.gd").legacy_sources(record)
	for alias: String in aliases:
		if not own.has(alias):
			own[alias] = record.get("origin_enabled", {}).get(alias, true)
		feature_parents[alias] = aliases[alias]
	for sid: String in own.keys():
		_resolved_source_active(sid, own, feat_grants, feature_parents, visiting, result)
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
