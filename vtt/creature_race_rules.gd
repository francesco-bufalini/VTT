extends RefCounted

# Race/subrace selection is based on structured 5etools identity fields.
# The compact race catalog also contains flattened "Race (Subrace)" entries.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const INDEX_PATH := "res://vtt/data/proficiency_grants_5etools.json"
static var _indexed_subraces: Array[Dictionary] = []


# Internal scanning must reuse the index without repeatedly deep-copying it.
# Keep the public defensive-copy contract for callers that edit returned rows.
static func indexed_subraces() -> Array[Dictionary]:
	return _indexed_subraces_ref().duplicate(true)


static func _indexed_subraces_ref() -> Array[Dictionary]:
	if not _indexed_subraces.is_empty():
		return _indexed_subraces
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var rows: Variant = (parsed as Dictionary).get("subrace", [])
		if rows is Array:
			for raw: Variant in rows:
				if raw is Dictionary:
					_indexed_subraces.append((raw as Dictionary).duplicate(true))
	return _indexed_subraces


static func _has_parent_name(name: String, source: String, all_races: Array[Dictionary]) -> bool:
	for row: Dictionary in all_races:
		if String(row.get("name", "")).nocasecmp_to(name) == 0 and String(row.get("source", "")) == source:
			return true
	return false


static func _parent_of_flattened(entry: Dictionary, all_races: Array[Dictionary]) -> Dictionary:
	var full_name := String(entry.get("name", ""))
	var cut: int = full_name.rfind(" (")
	if cut <= 0 or not full_name.ends_with(")"):
		return {}
	# A name which is itself the parent of indexed subraces (e.g. Elf
	# (Zendikar)) must remain a selectable race, not be flattened away.
	for candidate: Dictionary in _indexed_subraces_ref():
		if String(candidate.get("raceName", "")).nocasecmp_to(full_name) == 0:
			return {}
	var parent_name := full_name.substr(0, cut)
	var child_name := full_name.substr(cut + 2, full_name.length() - cut - 3)
	for index: Dictionary in _indexed_subraces_ref():
		if (String(index.get("name", "")).nocasecmp_to(child_name) == 0
			and String(index.get("raceName", "")).nocasecmp_to(parent_name) == 0):
			var indexed_book: String = String(index.get("raceSource", ""))
			if _has_parent_name(parent_name, indexed_book, all_races):
				return {"name": parent_name, "source": indexed_book}
	# Unindexed subraces also exist: Hill Dwarf, for example, may not
	# carry an explicit structured proficiency grant.
	if _has_parent_name(parent_name, String(entry.get("source", "")), all_races):
		return {"name": parent_name, "source": String(entry.get("source", ""))}
	return {}


static func base_races() -> Array[Dictionary]:
	var rows: Array[Dictionary] = Catalog.entries("races")
	var result: Array[Dictionary] = []
	for entry: Dictionary in rows:
		if _parent_of_flattened(entry, rows).is_empty():
			result.append(entry)
	return result


static func subraces_for(race: Dictionary) -> Array[Dictionary]:
	var race_name := String(race.get("name", ""))
	var race_source := String(race.get("source", ""))
	if race_name.is_empty():
		return []
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for child: Dictionary in _indexed_subraces_ref():
		if (String(child.get("raceName", "")).nocasecmp_to(race_name) != 0
			or String(child.get("raceSource", "")) != race_source):
			continue
		var name := String(child.get("name", ""))
		var source := String(child.get("source", ""))
		var key := name.to_lower() + "|" + source.to_lower()
		seen[key] = true
		result.append({
			"id": "subrace:" + race_name.to_lower() + "|" + race_source.to_lower() + "|" + key,
			"name": name, "source": source,
			"raceName": race_name, "raceSource": race_source
		})
	var rows: Array[Dictionary] = Catalog.entries("races")
	for entry: Dictionary in rows:
		var parent: Dictionary = _parent_of_flattened(entry, rows)
		if (String(parent.get("name", "")).nocasecmp_to(race_name) != 0
			or String(parent.get("source", "")) != race_source):
			continue
		var name: String = String(entry.get("name", ""))
		var child_name: String = name.substr(race_name.length() + 2, name.length() - race_name.length() - 3)
		var source: String = String(entry.get("source", ""))
		var key := child_name.to_lower() + "|" + source.to_lower()
		var option := {
			"id": String(entry.get("id", "")), "name": child_name,
			"source": source, "raceName": race_name,
			"raceSource": race_source
		}
		if seen.has(key):
			for i: int in range(result.size()):
				if (String(result[i].get("name", "")).nocasecmp_to(child_name) == 0
					and String(result[i].get("source", "")) == source):
					result[i] = option
					break
		else:
			result.append(option)
		seen[key] = true
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0)
	return result


# A flattened 5etools race contains the parent+subrace features together.
# Prefer it for traits, speed and creature type, without double-counting.
static func effective_race(race: Dictionary, subrace: Dictionary) -> Dictionary:
	if subrace.is_empty():
		return race
	var full_name := String(race.get("name", "")) + " (" + String(subrace.get("name", "")) + ")"
	for entry: Dictionary in Catalog.entries("races"):
		if (String(entry.get("name", "")).nocasecmp_to(full_name) == 0
			and String(entry.get("source", "")) == String(subrace.get("source", ""))):
			return entry
	return race


# Existing character saves stored "Dwarf (Hill)" as the species.
static func migrate_legacy_species(record: Dictionary) -> Dictionary:
	var name := String(record.get("species", ""))
	var source := String(record.get("species_source", ""))
	# Most saves already have a base race; avoid remerging the entire
	# 5etools catalog every time a creature sheet is normalized.
	if (name.is_empty() or not String(record.get("subrace", "")).is_empty()
		or not name.ends_with(")") or name.rfind(" (") < 0):
		return record
	var rows: Array[Dictionary] = Catalog.entries("races")
	for entry: Dictionary in rows:
		if (String(entry.get("name", "")).nocasecmp_to(name) != 0
			or String(entry.get("source", "")) != source):
			continue
		var parent := _parent_of_flattened(entry, rows)
		if parent.is_empty():
			break
		var base_name := String(parent.get("name", ""))
		var base_source := String(parent.get("source", ""))
		var race: Dictionary = {}
		for candidate: Dictionary in rows:
			if (String(candidate.get("name", "")).nocasecmp_to(base_name) == 0
				and String(candidate.get("source", "")) == base_source):
				race = candidate
				break
		for child: Dictionary in subraces_for(race):
			if name.nocasecmp_to(base_name + " (" + String(child.get("name", "")) + ")") == 0 and String(child.get("source", "")) == source:
				var copy: Dictionary = record.duplicate(true)
				copy["species"] = base_name
				copy["species_source"] = base_source
				copy["species_id"] = String(race.get("id", ""))
				copy["subrace"] = String(child.get("name", ""))
				copy["subrace_source"] = String(child.get("source", ""))
				copy["subrace_id"] = String(child.get("id", ""))
				return copy
	return record
