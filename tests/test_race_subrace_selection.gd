extends SceneTree

const RaceRules = preload("res://vtt/creature_race_rules.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Fixtures = preload("res://tests/fixtures/creature_record.gd")


func _initialize() -> void:
	call_deferred("run")


func _find(rows: Array[Dictionary], name: String, source: String) -> Dictionary:
	for row: Dictionary in rows:
		if (String(row.get("name", "")).nocasecmp_to(name) == 0
			and String(row.get("source", "")) == source):
			return row
	return {}


func run() -> void:
	var races: Array[Dictionary] = RaceRules.base_races()
	var elf := _find(races, "Elf", "PHB")
	assert(not elf.is_empty(), "PHB Elf must remain a selectable base race")
	assert(_find(races, "Elf (High)", "PHB").is_empty(),
		"Flattened High Elf must not appear in the base race menu")
	# Callers still receive independent copies, while internal scans reuse data.
	var changed_index: Array[Dictionary] = RaceRules.indexed_subraces()
	if not changed_index.is_empty():
		var original_name: String = String(changed_index[0].get("name", ""))
		changed_index[0]["name"] = "MUTATED TEST NAME"
		assert(String(RaceRules.indexed_subraces()[0].get("name", "")) == original_name,
			"Indexed subrace API must return an independent copy")
	var children := RaceRules.subraces_for(elf)
	var high := _find(children, "High", "PHB")
	var wood := _find(children, "Wood", "PHB")
	assert(not high.is_empty() and not wood.is_empty(),
		"5etools child sources must filter by parent race and source")
	var dwarf := _find(races, "Dwarf", "PHB")
	assert(not dwarf.is_empty())
	assert(not _find(RaceRules.subraces_for(dwarf), "Mountain", "PHB").is_empty(),
		"A dwarf offers its dwarf subraces")
	assert(_find(RaceRules.subraces_for(dwarf), "High", "PHB").is_empty(),
		"An elf subrace must never be selectable for a dwarf")
	var record := Fixtures.character()
	record["species"] = "Elf"
	record["species_source"] = "PHB"
	record["species_id"] = String(elf.get("id", ""))
	record["subrace"] = "High"
	record["subrace_source"] = "PHB"
	record["subrace_id"] = String(high.get("id", ""))
	assert(Proficiencies.has_proficiency(record, "skill", "perception")
		and Proficiencies.has_proficiency(record, "weapon", "longsword"),
		"Parent and selected child each contribute structured proficiencies")
	record["subrace"] = "Wood"
	var has_high := false
	var has_wood := false
	for origin: Dictionary in Proficiencies.candidate_sources(record):
		if String(origin.get("id", "")) == "subrace|phb|high":
			has_high = true
		if String(origin.get("id", "")) == "subrace|phb|wood":
			has_wood = true
	assert(not has_high and has_wood,
		"Switching subrace must revoke the previous origin without removing shared proficiencies")
	# Reproduce the real crash: a cached 5etools race speed is a float,
	# while legacy saves may keep a stale numeric speed_base.
	assert(RaceRules.has_speed(25.0) and RaceRules.has_speed(25)
		and RaceRules.has_speed({"walk": 30, "fly": 60})
		and not RaceRules.has_speed({}) and not RaceRules.has_speed(null),
		"Numeric and structured racial speeds need type-safe detection")
	var numeric_race: Dictionary = Fixtures.character()
	numeric_race["species"] = "Elf"
	numeric_race["species_source"] = "PHB"
	numeric_race["species_id"] = String(elf.get("id", ""))
	numeric_race["speed_base"] = 99
	var race_key: String = JSON.stringify([
		numeric_race.get("species_id", ""), numeric_race.get("species", ""),
		numeric_race.get("species_source", ""), numeric_race.get("subrace", ""),
		numeric_race.get("subrace_source", "")
	])
	RaceRules._speed_cache_revision = ContentCatalog.revision()
	RaceRules._speed_cache[race_key] = 20.0
	RaceRules._speed_cache.erase(race_key)
	assert(Bonuses.value({"kind": "character", "species_speed": 25.0,
		"speed_base": 99}, "speed") == 25,
		"Formula-based speed must accept a float without comparing it with a Dictionary")
	assert(Bonuses.value({"kind": "character", "species_speed": {"walk": 40, "fly": 60},
		"speed_base": 99}, "speed") == 40,
		"Structured walking speed must still be honored by formula evaluation")
	print("PASS: structured subrace filtering, numeric speed and proficiencies")
	quit()
