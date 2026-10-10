extends SceneTree

const RaceRules = preload("res://vtt/creature_race_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const MonsterStore = preload("res://vtt/master_creature_store.gd")


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
	var record := PlayerStore.new().create_character()
	record["species"] = "Elf"
	record["species_source"] = "PHB"
	record["species_id"] = String(elf.get("id", ""))
	record["subrace"] = "High"
	record["subrace_source"] = "PHB"
	record["subrace_id"] = String(high.get("id", ""))
	assert(Proficiencies.has_proficiency(record, "skill", "perception")
		and Proficiencies.has_proficiency(record, "weapon", "longsword|phb"),
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
	var legacy := record.duplicate(true)
	legacy["species"] = "Elf (High)"
	legacy["species_source"] = "PHB"
	legacy["subrace"] = ""
	legacy["subrace_id"] = ""
	legacy["subrace_source"] = ""
	var migrated := RaceRules.migrate_legacy_species(legacy)
	assert(migrated.species == "Elf" and migrated.subrace == "High",
		"Legacy flattened races migrate without discarding selected child")
	var stat := {"name": "Sample Monster", "source": "MM", "cr": "1/4", "type": "beast"}
	var monsters := MonsterStore.new()
	var creature := monsters.create_creature(stat, "enemy")
	assert(creature.classes.is_empty() and creature.level == 0
		and creature.stat_block.cr == "1/4",
		"Bestiary CR must be independent from class levels")
	var old := creature.duplicate(true)
	old["class"] = "Mostro"
	old["class_source"] = "5etools"
	old["classes"] = [
		{"name": "Mostro", "source": "5etools", "level": 1},
		{"name": "Fighter", "source": "PHB", "level": 2}
	]
	var restored := monsters.normalize_creature(old)
	assert(restored.classes.size() == 1 and restored.class == "Fighter"
		and restored.level == 2 and restored.stat_block.cr == "1/4",
		"Legacy synthetic Monster levels must be removed without changing CR")
	print("PASS: structured subrace filtering, legacy migration and monster CR/classes")
	quit()
