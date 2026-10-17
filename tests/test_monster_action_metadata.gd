extends SceneTree

const Metadata = preload("res://vtt/monster_action_metadata.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const Store = preload("res://vtt/master_creature_store.gd")


func _initialize() -> void:
	call_deferred("run")


func _attack(record: Dictionary, name: String) -> Dictionary:
	for row: Dictionary in Attacks.definitions(record):
		if String(row.get("name", "")) == name:
			return row
	return {}


func _tracker(record: Dictionary, name: String) -> Dictionary:
	for row: Dictionary in Trackers.for_creature(record):
		if String(row.get("name", "")) == name:
			return row
	return {}


func run() -> void:
	var sample: Dictionary = {
		"source": "AI", "name": "Ancient Deep Crow",
		"legendaryActions": 3,
		"action": [
			{"name": "Mandibles", "entries": [
				"{@atk mw} {@hit 11} to hit, reach 10 ft. {@damage 2d10 + 6} piercing damage."]},
			{"name": "Shadow Caw", "entries": [
				"Each creature makes a save, taking {@damage 3d6} psychic damage."]},
			{"name": "Versatile Lance", "entries": [
				"{@atk mw,rw} {@hit +7} to hit, reach 10 ft. or range 30/120 ft. {@damage 1d10+4}."]},
			{"name": "Fire Breath {@recharge 5}", "entries": ["{@dc 16}"]}
		]
	}
	var normalized: Dictionary = Metadata.prepare(sample)
	assert(int(normalized.get("vtt_action_metadata_version", 0)) == 1)
	var record: Dictionary = {"kind": "monster", "stat_block": normalized}
	var mandibles: Dictionary = _attack(record, "Mandibles")
	assert(int(mandibles.get("base_hit", 0)) == 11)
	assert(int(mandibles.get("range_feet", 0)) == 10)
	assert(mandibles.get("damage", "") == "2d10 + 6")
	assert(_attack(record, "Shadow Caw").is_empty(),
		"Saving-throw damage must not become a weapon attack")
	var hybrid: Dictionary = _attack(record, "Versatile Lance")
	assert(bool(hybrid.get("melee", false)) and bool(hybrid.get("has_ranged_mode", false)))
	assert(int(hybrid.get("melee_reach_feet", 0)) == 10)
	assert(int(hybrid.get("range_feet", 0)) == 30)
	assert(int(hybrid.get("long_range_feet", 0)) == 120)
	assert(int(_tracker(record, "Fire Breath").get("recharge_min", 0)) == 5)
	assert(int(_tracker(record, "Azioni leggendarie").get("max", 0)) == 3)
	assert(Metadata.prepare(normalized) == normalized, "Prepared metadata is idempotent")
	var revised: Dictionary = normalized.duplicate(true)
	(revised["action"][2] as Dictionary)["entries"] = [
		"{@atk mw,rw} {@hit +10} to hit, reach 10 ft. or range 30/120 ft. {@damage 1d10+4}."
	]
	revised = Metadata.prepare(revised)
	assert(int(_attack({"kind": "monster", "stat_block": revised},
		"Versatile Lance").get("base_hit", 0)) == 10,
		"Editing a bestiary action must invalidate its old cached metadata")
	assert(Metadata.prepare(revised) == revised,
		"Revision tracking must not trigger repeated conversions")


	# Deleting the source prose after import must not cause any new regex or
	# change the attack/recharge result. The typed fields are authoritative.
	for entry: Variant in normalized["action"]:
		(entry as Dictionary).erase("entries")
	assert(_attack(record, "Mandibles").get("damage") == "2d10 + 6")
	assert(int(_tracker(record, "Fire Breath").get("recharge_min", 0)) == 5)

	# Fight Club supplemental recharge is joined once during import, not
	# every time the tracker view refreshes.
	var chaos: Dictionary = Metadata.prepare({
		"source": "AI", "name": "Chaos Quadrapod",
		"action": [{"name": "Chaos Cloud (Recharges after a Short or Long Rest)"}]
	})
	var chaos_record := {"kind": "monster", "stat_block": chaos}
	assert(String(_tracker(chaos_record,
		"Chaos Cloud (Recharges after a Short or Long Rest)").get("recharge", "")) == "short_rest")
	assert(String(_tracker(chaos_record,
		"Chaos Cloud (Recharges after a Short or Long Rest)").get("id", "")) == "fightclub:action:0")

	var generated: Dictionary = Store.new().create_creature({
		"source": "PHB", "name": "Animated Object (Huge)",
		"hp": {"special": "80"}, "speed": {"walk": 30},
		"action": [{"name": "Slam", "entries": [
			"{@atk mw} {@hit 8} to hit, reach 5 ft. {@damage 2d12 + 4}."]}]
	}, "enemy")
	assert(int((generated.get("stat_block", {}) as Dictionary).get("vtt_action_metadata_version", 0)) == 1)
	assert(_attack(generated, "Slam").get("damage") == "2d12 + 4")
	assert(int(_attack(generated, "Slam").get("base_hit", 0)) == 8)

	# 5etools duration[] is machine-readable; text heuristics should be
	# consulted only for legacy homebrew. Mixed structured values stay safe.
	assert(not ActiveSpells.has_duration({"duration": [{"type": "instant"}]}))
	assert(ActiveSpells.has_duration({"duration": [
		{"type": "instant"}, {"type": "timed", "duration": {"type": "minute", "amount": 1}}
	]}))
	assert(ActiveSpells.requires_concentration({"duration": [
		{"type": "timed", "concentration": true, "duration": {"type": "minute", "amount": 1}}
	]}))
	assert(not ActiveSpells.requires_concentration({"duration": [{"type": "timed"}]}))
	assert(not ActiveSpells.has_duration({"duration": "Instantaneous"}))
	assert(ActiveSpells.requires_concentration({"duration": "Concentration, up to 1 minute"}))

	print("PASS: structured monster actions, Fight Club recharge and typed spell durations")
	quit()
