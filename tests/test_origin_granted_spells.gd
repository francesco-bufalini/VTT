extends SceneTree
const Granted = preload("res://vtt/origin_spell_grants.gd")
const Dice = preload("res://vtt/creature_dice_bonuses.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const Applied = preload("res://vtt/creature_active_spells.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")


func _initialize() -> void:
	call_deferred("run")


func _find(rows: Array[Dictionary], spell_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row.get("spell_id", "")) == spell_id:
			return row
	return {}


func run() -> void:
	var bard: Dictionary = {
		"kind": "character", "class": "Bard", "class_source": "PHB",
		"level": 3, "classes": [{"name": "Bard", "source": "PHB", "level": 3}],
		"abilities": {"cha": 16}
	}
	var inspiration: Dictionary = _find(Granted.all_grants(bard), Granted.BARDIC)
	assert(not inspiration.is_empty(), "A level-3 bard's Bardic Inspiration is an origin-granted spell")
	assert(not Granted.tracker_for(bard, inspiration).is_empty(),
		"Automatic Bardic Inspiration consumes the existing structured resource")
	assert(Granted.remaining(bard, inspiration) == 3, "Bardic Inspiration uses CHA modifier, at least 1")
	assert(Granted.spend(bard, inspiration))
	assert(Granted.remaining(bard, inspiration) == 2,
		"Spending a granted spell consumes one tracker use, not an ordinary spell slot")
	assert(Spells.is_runtime_usable(Spells.catalog_spell(Granted.BARDIC)))
	assert(Spells.is_runtime_usable(Spells.catalog_spell(Granted.WILD_SHAPE)))
	var receiver: Dictionary = {"kind": "character", "level": 20,
		"abilities": {"cha": 8}}
	assert(Applied.apply(receiver, Granted.BARDIC, Granted.cast_context(bard, Granted.BARDIC)))
	var roll: Array[Dictionary] = Dice.applicable(receiver, "skill:perception")
	assert(roll.size() == 1 and String(roll[0].get("dice", "")) == "1d6",
		"The recipient's level 20 must NOT scale the caster's level-3 die")
	assert(Dice.applicable(receiver, "save:dex").size() == 1)
	assert(Dice.applicable(receiver, "attack_hit:longsword").size() == 1)
	assert(Dice.applicable(receiver, "attack_damage:longsword").is_empty())
	assert(Applied.remove(receiver, "spell:" + Granted.BARDIC))
	assert(Dice.applicable(receiver, "save:dex").is_empty(),
		"Spending an inspiration die removes the spell and its dice grants")
	bard["level"] = 5
	bard["classes"] = [{"name": "Bard", "source": "PHB", "level": 5}]
	assert(String(Granted.cast_context(bard, Granted.BARDIC).get("bonus_dice", "")) == "1d8")
	var druid: Dictionary = {"kind": "character", "class": "Druid", "level": 2,
		"class_source": "PHB", "classes": [{"name": "Druid", "source": "PHB", "level": 2}]}
	assert(not _find(Granted.all_grants(druid), Granted.WILD_SHAPE).is_empty())
	assert(not _find(Granted.all_grants(druid), Granted.WILD_SHAPE).get("tracker_id", "").is_empty())
	var custom: Dictionary = bard.duplicate(true)
	custom["proficiency_origins"] = [{"id": "custom:test", "name": "Gift", "group": "custom"}]
	custom["origin_spell_grants"] = [{
		"id": "test-grant", "origin_id": "custom:test", "origin_name": "Gift",
		"spell_id": "cure_wounds", "tracker_id": String(inspiration.get("tracker_id", ""))
	}]
	var external: Dictionary = _find(Granted.all_grants(custom), "cure_wounds")
	assert(not external.is_empty(), "An origin can grant a standard catalog spell")
	if Granted.remaining(custom, external) <= 0:
		print("DEBUG tracker owner: ", String(inspiration.get("tracker_id", "")),
			" rows=", Trackers.for_creature(custom),
			" grant=", external)
	assert(Granted.remaining(custom, external) > 0,
		"An origin can spend a tracker awarded by another origin")
	custom["origin_spell_configs"] = {"test-grant": {"payment_mode": "tracker", "tracker_cost": 2}}
	custom["origin_spell_grants"].append({
		"id": "second-grant", "origin_id": "custom:test", "origin_name": "Gift",
		"spell_id": "bless", "tracker_id": String(inspiration.get("tracker_id", "")),
		"payment_mode": "tracker", "tracker_cost": 1
	})
	var costly: Dictionary = _find(Granted.all_grants(custom), "cure_wounds")
	var cheap: Dictionary = _find(Granted.all_grants(custom), "bless")
	assert(Granted.tracker_cost(costly) == 2 and Granted.tracker_cost(cheap) == 1,
		"Spells of the same origin and tracker keep independent consumption costs")
	var tracker_id: String = String(costly.get("tracker_id", ""))
	var original_spent: int = int(custom.get("resource_tracker_spent", {}).get(tracker_id, 0))
	assert(Granted.remaining(custom, costly) == 1)
	assert(Granted.spend(custom, costly))
	assert(int(custom.get("resource_tracker_spent", {}).get(tracker_id, 0)) == original_spent + 2
		and Granted.remaining(custom, costly) == 0,
		"Casting a two-charge spell spends two units atomically")
	assert(Dice.valid_dice("2d8") and Dice.valid_dice("1d8+2")
		and not Dice.valid_dice("cha_mod") and not Dice.valid_dice("d20")
		and not Dice.valid_dice("101d6"))
	custom["dice_bonuses"] = [{
		"id": "dice1", "target": "saving_throw", "dice": "1d4",
		"origin_id": "custom:test", "origin_name": "Gift"
	}]
	assert(Dice.applicable(custom, "save:wis").size() == 1)
	assert(Dice.applicable(custom, "initiative").is_empty(),
		"Die grants must be limited to the matching roll category")
	custom["dice_bonuses"][0]["target"] = "damage_roll"
	assert(Dice.applicable(custom, "attack_damage:longsword").size() == 1
		and Dice.applicable(custom, "attack_hit:longsword").is_empty(),
		"Damage dice can target damage rolls without changing attack-hit rolls")
	# 5etools additionalSpells is machine-readable across more origins,
	# not only the two hand-authored action templates.
	var drow: Dictionary = {
		"kind": "character", "level": 5, "class": "Wizard",
		"class_source": "PHB", "classes": [{"name": "Wizard", "source": "PHB", "level": 5}],
		"species": "Elf", "species_source": "PHB",
		"subrace": "Drow", "subrace_source": "PHB", "rules_version": "2014"
	}
	var drow_spells: Dictionary = Structured.for_creature(drow)
	var drow_grants: Array = drow_spells.get("grants", [])
	assert(drow_grants.size() >= 2, "5etools Drow spell grants must be decoded from additionalSpells")
	var has_limited := false
	var has_cantrip := false
	for raw: Variant in drow_grants:
		if not raw is Dictionary:
			continue
		var granted: Dictionary = raw
		if String(granted.get("tracker_id", "")).is_empty():
			has_cantrip = true
		else:
			has_limited = true
	assert(has_limited and has_cantrip,
		"Drow cantrip is at will, while higher-level spells use their own tracker")
	assert(not (drow_spells.get("trackers", []) as Array).is_empty())
	var all_drow: Array[Dictionary] = Granted.all_grants(drow)
	assert(all_drow.size() >= 2, "Structured spells must appear as usable origin-granted spells")
	var limited: Dictionary = {}
	for grant: Dictionary in all_drow:
		if not String(grant.get("tracker_id", "")).is_empty():
			limited = grant
			break
	assert(not limited.is_empty() and Granted.remaining(drow, limited) == 1,
		"Limited racial spell has one cast per long rest")
	assert(Granted.spend(drow, limited))
	assert(Granted.remaining(drow, limited) == 0)
	var restored: Dictionary = Trackers.spent_after_recovery(drow, "long_rest")
	drow["resource_tracker_spent"] = restored
	assert(Granted.remaining(drow, limited) == 1, "Long rest recovers structured racial spell charge")
	# Spell lists which merely expand class preparation do not create
	# unlimited no-slot spell entitlements.
	var azorius: Dictionary = {
		"kind": "character", "background": "Azorius Functionary",
		"background_source": "GGR", "level": 5
	}
	assert((Structured.for_creature(azorius).get("grants", []) as Array).is_empty(),
		"Expanded spell lists are not slot-free grants")
	# True structured choices stay pending until selected.
	var high_elf: Dictionary = {
		"kind": "character", "species": "Elf", "species_source": "PHB",
		"subrace": "High", "subrace_source": "PHB", "level": 1
	}
	assert(not (Structured.for_creature(high_elf).get("choices", []) as Array).is_empty(),
		"Structured spell choose must be exposed instead of guessed")
	print("PASS origin-granted spells, resource charges and caster-scaled dice")
	quit()
