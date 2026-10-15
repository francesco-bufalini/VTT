extends SceneTree

const Rules = preload("res://vtt/creature_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const MonsterStore = preload("res://vtt/master_creature_store.gd")
const Archive = preload("res://vtt/creature_archive.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")


class FakeCampaign extends Node:
	var selected_campaign_group_id: String = (
		"test_creature_sheet_temp"
	)
	var active_campaign_id: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sheet_script: Script = load("res://vtt/creature_area.gd")
	assert(sheet_script != null, "CreatureArea must load without parse errors")
	var sheet_node: Node = sheet_script.new()
	sheet_node.free()
	var stat := {
		"name": "Test Dragon",
		"source": "MM",
		"cr": "1/2",
		"type": "dragon",
		"speed": 40,
		"hp": {"average": 178},
		"ac": [{"ac": 18, "from": ["natural armor"]}],
		"str": 23,
		"dex": 10,
		"legendaryActions": 3,
		"legendary": [{"name": "Tail Attack"}],
		"action": [
			{"name": "Tail", "entries": ["{@atk mw} reach 10 ft., one target."]},
			{"name": "Fire Breath (Recharge 5–6)", "entries": ["range 90 ft."]},
			{"name": "Frightful Presence (3/day)"}
		],
		"spellcasting": [{
			"spells": {"1": {"slots": 4}, "2": {"slots": 3}}
		}]
	}
	var monster := MonsterStore.new()
	var creature: Dictionary = monster.create_creature(stat, "enemy")
	assert(creature.armor_class == 18)
	assert(creature.abilities.str == 23)
	var skill_catalog: Script = load("res://vtt/creature_skills_5etools.gd")
	assert(skill_catalog.SKILLS.size() == 18,
		"The complete 5etools skills table must remain available")
	var bestiary_skill_record: Dictionary = {
		"stat_block": {"skill": {"perception": "+2", "stealth": "+4"}}
	}
	var inferred: Dictionary = skill_catalog.ranks_from_bestiary(
		bestiary_skill_record, 2, {"wis": 10, "dex": 10}
	)
	assert(inferred.get("perception", 0) == 1 and inferred.get("stealth", 0) == 2,
		"Monster skill modifiers must determine proficiency and expertise")
	assert(creature.species == "Test Dragon" and creature.species_source == "MM")
	assert(creature.class == "" and creature.level == 0 and creature.classes.is_empty(),
		"A new monster has no class levels regardless of CR")
	assert(creature.stat_block.cr == "1/2" and is_equal_approx(Rules.monster_cr_value(creature.stat_block), 0.5),
		"Monster challenge rating retains its exact fractional bestiary value")
	assert(creature.subclass == "" and Rules.monster_type_reference(creature.stat_block).name == "Drago",
		"Monster creature type does not become a subclass")
	assert(creature.speed == 40, "Monster speed should come from structured 5etools speed")
	assert(creature.second_form_hp == 0 and creature.second_form_max_hp == 0,
		"All new creatures must start without transformed HP")
	var layered: Dictionary = creature.duplicate(true)
	layered["current_hp"] = 20
	layered["temporary_hp"] = 3
	layered["second_form_hp"] = 7
	layered["second_form_max_hp"] = 7
	layered = Rules.apply_damage_layers(layered, 12)
	assert(layered.temporary_hp == 0 and layered.second_form_hp == 0
		and layered.current_hp == 18,
		"Damage must cross temporary -> transformed -> base HP in order")
	layered = Rules.apply_damage_layers(layered, 2)
	assert(layered.current_hp == 16 and layered.second_form_hp == 0,
		"Damage beyond a spent second-form pool must reduce the original HP")
	var with_bonuses: Dictionary = creature.duplicate(true)
	with_bonuses["formula_bonuses"] = [
		{"id": "speed", "target": "speed", "expression": "10", "origin_id": ""},
		{"id": "ac", "target": "ac", "expression": "3", "origin_id": ""},
		{"id": "init", "target": "initiative", "expression": "2", "origin_id": ""}
	]
	with_bonuses = monster.normalize_creature(with_bonuses)
	assert(with_bonuses.speed == 50 and with_bonuses.speed_base == 40
		and Bonuses.bonus(with_bonuses, "speed") == 10,
		"Monster speed uses its base and additive originless grant")
	assert(with_bonuses.armor_class == 21 and with_bonuses.armor_class_base == 18,
		"Monster armor class keeps the base while adding a grant")
	assert(with_bonuses.initiative == 2 and with_bonuses.initiative_base == 0,
		"Monster initiative derives from DEX and additive grants")
	assert(creature.reach_feet == 10.0,
		"Monster melee reach must be derived from 5etools, not a fixed 5 ft")
	var attack_data: Script = load("res://vtt/creature_attack_data.gd")
	assert(attack_data != null, "Attack calculation helper must load")
	var character_attack: Dictionary = {
		"kind": "character", "attack_ability": "str",
		# Unarmed strikes are exposed as selectable hand attacks.
		"hand_main_special": "unarmed",
		"abilities": {"str": 16, "dex": 12},
		"attack_overrides": {}, "inventory": []
	}
	var unarmed: Dictionary = attack_data.definitions(character_attack)[0]
	assert(unarmed.id == "unarmed" and unarmed.proficient,
		"Characters must always be proficient in unarmed strikes")
	assert(attack_data.attack_bonus(character_attack, unarmed, 2) == 5
		and attack_data.damage_label(character_attack, unarmed) == "4 contundenti",
		"Unarmed hit and damage use STR; proficiency only affects hit")
	character_attack["attack_ability"] = "dex"
	assert(attack_data.attack_bonus(character_attack, unarmed, 2) == 5
		and attack_data.damage_label(character_attack, unarmed) == "4 contundenti",
		"2014 unarmed strikes remain STR without a specific class feature")
	character_attack["attack_overrides"] = {"unarmed": {"range_feet": 15}}
	character_attack["formula_bonuses"] = [
		{"id": "hit", "target": "attack_hit:unarmed", "expression": "2", "origin_id": ""},
		{"id": "damage", "target": "attack_damage:unarmed", "expression": "2", "origin_id": ""}
	]
	var normalized_character: Dictionary = PlayerStore.new().normalize_character(character_attack)
	assert(normalized_character.attack_ability == "dex"
		and Bonuses.bonus(normalized_character, "attack_hit:unarmed") == 2
		and Bonuses.bonus(normalized_character, "attack_damage:unarmed") == 2,
		"Character attacks use independent cumulative hit and damage grants")
	assert(attack_data.range_for(normalized_character, unarmed) == 15
		and attack_data.attack_bonus(normalized_character, unarmed, 2) == 7,
		"Range and enhancement bonus belong to the attack, not to the creature")
	var monster_attack: Dictionary = monster.normalize_creature(creature.duplicate(true))
	monster_attack["stat_block"] = {
		"action": [
			{"name": "Claw", "entries": ["{@atk mw} {@hit 5}, reach 10 ft, {@damage 2d6+3}"]},
			{"name": "Bow", "entries": ["{@atk rw} {@hit 5}, range 80/320 ft, {@damage 1d8+3}"]}
		]
	}
	monster_attack["attack_ability"] = "str"
	monster_attack["attack_overrides"] = {"monster:action:0": {"range_feet": 15}}
	monster_attack["formula_bonuses"] = [
		{"id": "claw-hit", "target": "attack_hit:monster:action:0", "expression": "2", "origin_id": ""}
	]
	var monster_attacks: Array[Dictionary] = attack_data.definitions(monster_attack)
	assert(monster_attacks.size() == 2
		and monster_attacks[0].range_feet == 10 and monster_attacks[1].range_feet == 80,
		"Every 5etools attack must retain its own melee or ranged distance")
	assert(attack_data.attack_bonus(monster_attack, monster_attacks[0], 3) == 7,
		"Monster hit already contains proficiency: apply only additional grants")
	assert(attack_data.max_melee_range(monster_attack) == 15.0,
		"Legacy token engagement distance must use the longest melee attack")
	monster_attack["attack_ability"] = "dex"
	assert(attack_data.attack_bonus(monster_attack, monster_attacks[0], 3) == 7,
		"Bestiary fixed hit bonuses do not change without structured finesse")
	var normalized_attack: Dictionary = monster.normalize_creature(monster_attack)
	assert(normalized_attack.attack_ability == "dex"
		and normalized_attack.attack_overrides["monster:action:0"].range_feet == 15,
		"Monster attack reach and bonus must persist independently of its stat block")

	assert(creature.owner_id == Owner.local_id())
	assert(not creature.has("trackers"), "New creatures must not generate legacy resources.")
	assert(Rules.monster_armor_class(stat) == 18)
	assert(Rules.monster_abilities(stat).str == 23)
	assert(is_equal_approx(Rules.monster_cr_value({"cr": {"cr": "1/8"}}), 0.125))
	assert(Rules.experience_for_level(5) == 6500 and Rules.experience_for_level(20) == 355000)
	assert(Rules.walking_speed({"walk": 25, "fly": 50}) == 25)
	var found_racial_speed := false
	for race: Dictionary in Player5eTools.entries("races"):
		if String(race.get("name", "")) == "Aarakocra" and String(race.get("source", "")) == "DMG":
			found_racial_speed = Rules.walking_speed(race.get("speed", 30)) == 20
			break
	assert(found_racial_speed, "5etools race movement must remain available in the offline catalogue")
	var racially_slow: Dictionary = PlayerStore.new().create_character()
	racially_slow["species"] = "Aarakocra"
	racially_slow["species_source"] = "DMG"
	racially_slow["speed_base"] = 99 # Corrupted legacy stored speed is ignored.
	var normalized_race: Dictionary = PlayerStore.new().normalize_character(racially_slow)
	assert(normalized_race.speed_base == 20 and Bonuses.value(normalized_race, "speed") == 20,
		"Walking speed must be resolved from the current race, not a saved copy")
	assert(normalized_race.xp >= Rules.minimum_experience(normalized_race),
		"Character minimum XP must always follow the current class levels")
	var multiclass_monster := creature.duplicate(true)
	multiclass_monster["classes"].append({"name": "Wizard", "level": 3, "source": "PHB"})
	var normalized_monster: Dictionary = monster.normalize_creature(multiclass_monster)
	assert(normalized_monster.classes.size() == 1
		and normalized_monster.classes[0].name == "Wizard"
		and normalized_monster.level == 3 and normalized_monster.class == "Wizard",
		"The first actual monster class becomes primary and CR never adds levels")
	assert(is_equal_approx(Rules.effective_monster_cr(normalized_monster), 3.5),
		"The base fractional CR plus every class level gives effective CR")
	assert(normalized_monster.stat_block.cr == "1/2",
		"Class levels cannot mutate the original bestiary challenge rating")
	assert(normalized_monster.xp >= Rules.monster_experience_for_cr(3.5),
		"Monster XP floor must use effective CR, not class-only level thresholds")
	assert(Bonuses.value(normalized_monster, "proficiency") == 2,
		"Effective CR below 5 retains proficiency +2")
	var advanced_monster: Dictionary = normalized_monster.duplicate(true)
	advanced_monster["classes"][0]["level"] = 5
	advanced_monster = monster.normalize_creature(advanced_monster)
	assert(is_equal_approx(Rules.effective_monster_cr(advanced_monster), 5.5)
		and Bonuses.value(advanced_monster, "proficiency") == 3
		and advanced_monster.xp >= Rules.monster_experience_for_cr(5.5),
		"Monster proficiency and XP floor must grow when class levels grow")
	assert(Rules.monster_experience_for_cr(0.125) == 25
		and Rules.monster_experience_for_cr(0.25) == 50
		and Rules.monster_experience_for_cr(0.5) == 100,
		"Fractional monster challenge ratings retain their own XP thresholds")
	var character_level: Dictionary = {
		"kind": "character", "class": "Wizard", "level": 5,
		"classes": [{"name": "Wizard", "level": 3}, {"name": "Fighter", "level": 2}]
	}
	assert(Rules.proficiency_bonus(character_level) == 3
		and Rules.minimum_experience(character_level) == Rules.experience_for_level(5),
		"Character progression uses the sum of the class levels")
	var controller: Script = load("res://vtt/creature_sheet_controller.gd")
	var resource_character: Dictionary = {
		"kind": "character", "class": "Wizard", "level": 3,
		"classes": [{"name": "Wizard", "source": "PHB", "level": 3}],
		"abilities": {"int": 16},
		"prepared_spells": [{"id": "spell:test", "name": "Test"}],
		"proficiency_choices": [{"id": "choice:test", "origin_id": "custom:test"}],
		"spell_slots_total": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_spent": [0, 2, 1, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_manual": false, "spell_slots_automatic": false,
		"pact_slots_spent": 0, "resource_tracker_spent": {"custom": 2}
	}
	controller.sync_automatic_progression(resource_character)
	assert(resource_character.spell_slots_total[1] == 4
		and resource_character.spell_slots_total[2] == 2
		and resource_character.spell_slots_spent[1] == 2
		and resource_character.spell_slots_spent[2] == 1,
		"Automatic level progression must retain already consumed slots")
	assert(resource_character.prepared_spells.size() == 1
		and resource_character.proficiency_choices.size() == 1
		and resource_character.resource_tracker_spent.custom == 2,
		"Automatic progression must preserve spells, prior origin choices and resource usage")

	# Editions are alternatives for a class, not separate entries for each book.
	for edition: String in ["2014", "2024"]:
		var class_names: Dictionary = {}
		for choice: Dictionary in Player5eTools.class_choices(edition):
			var key := String(choice.get("name", "")).to_lower()
			if String(choice.get("origin", "")) != "homebrew":
				assert(not class_names.has(key), "Official class duplicated in %s: %s" % [edition, key])
				class_names[key] = choice.get("source", "")
		assert(class_names.get("wizard") == ("PHB" if edition == "2014" else "XPHB"))
		assert(class_names.get("artificer") == ("TCE" if edition == "2014" else "EFA"))
	# Supplemental books contribute source-qualified features to a base class.
	var tce_feature_found := false
	for feature: Dictionary in Player5eTools.entries("class_features"):
		if String(feature.get("class_name", "")) == "Barbarian" and String(feature.get("class_source", "")) == "PHB" and String(feature.get("source", "")) == "TCE":
			tce_feature_found = true
			break
	assert(tce_feature_found, "TCE optional class features must remain available for PHB classes")
	var player := PlayerStore.new()
	var character: Dictionary = player.normalize_character(player.create_character())
	assert(character.owner_id == Owner.local_id())
	character["armor_class_base"] = 12
	character["abilities"]["dex"] = 14
	character["formula_bonuses"] = [
		{"id": "armor", "target": "ac", "expression": "4", "origin_id": ""},
		{"id": "initiative", "target": "initiative", "expression": "3", "origin_id": ""}
	]
	character = player.normalize_character(character)
	assert(character.armor_class == 16 and character.initiative == 5,
		"Character bonuses must contribute to effective AC and initiative")

	var campaign := FakeCampaign.new()
	root.add_child(campaign)
	var archive := Archive.new()
	archive.setup(campaign)
	creature["kind"] = "monster"
	character["kind"] = "character"
	assert(archive.save(creature) == OK)
	assert(archive.save(character) == OK)
	assert(archive.list_owned().size() >= 2)
	# Authorization is enforced before mutation, independently of role.
	character["owner_id"] = "external_player_id_0123456789"
	assert(archive.save(character) == ERR_UNAUTHORIZED)
	assert(archive.delete(character) == ERR_UNAUTHORIZED)
	# Disk-level migration / compatibility uses the original store layouts.
	var incoming: Dictionary = archive.relinquish(
		creature, "external_player_id_0123456789"
	)
	assert(incoming.format == "vtt_creature_transfer_v1")
	assert(archive.save(creature) == ERR_UNAUTHORIZED, "Stale owner cannot resurrect a transferred sheet")
	var returned: Dictionary = incoming.duplicate(true)
	returned["recipient"] = Owner.local_id()
	returned.creature["owner_id"] = Owner.local_id()
	returned.creature["transfer_revision"] = int(incoming.creature.transfer_revision) + 1
	assert(archive.import_transfer(returned) == OK)
	assert(archive.import_transfer(returned) == ERR_ALREADY_EXISTS, "Replayed transfer must not overwrite edits")
	returned.creature["conditions"] = ["poisoned", "homebrew:test:conditions:mark"]
	assert(archive.save(returned.creature) == OK)
	var reloaded := archive.list_owned()
	var preserved := false
	for row: Dictionary in reloaded:
		if row.id == creature.id:
			preserved = row.conditions == returned.creature.conditions
	assert(preserved, "Independent conditions persist without token")
	# Official feats and homebrew merge into the same searchable catalog.
	var races: Array[Dictionary] = Player5eTools.entries("races")
	for index: int in range(1, races.size()):
		assert(String(races[index - 1].get("name", "")).naturalnocasecmp_to(
			String(races[index].get("name", ""))
		) <= 0, "Races must have one alphabetical ordering across sources.")
	assert(not Player5eTools.entries("feats").is_empty(),
		"5e.tools feats must be available to the sheet search.")
	assert(archive.list_owned().size() >= 1)
	# The receiving side cannot import another user's transfer code.
	assert(archive.import_transfer(incoming) == ERR_UNAUTHORIZED)

	# Removal persists, is idempotent, and cannot remove a sheet owned by
	# another installation or accidentally wipe unrelated records.
	var doomed: Dictionary = player.create_character()
	doomed["kind"] = "character"
	assert(archive.save(doomed) == OK)
	assert(archive.delete(doomed) == OK)
	assert(archive.delete(doomed) == ERR_DOES_NOT_EXIST)
	var removed_found := false
	var retained_found := false
	for sheet: Dictionary in archive.list_owned():
		removed_found = removed_found or String(sheet.get("id", "")) == String(doomed.id)
		retained_found = retained_found or String(sheet.get("id", "")) == String(returned.creature.id)
	assert(not removed_found and retained_found)
	assert(archive.delete(returned.creature) == OK)
	assert(archive.delete(returned.creature) == ERR_DOES_NOT_EXIST)

	var folder := ProjectSettings.globalize_path("user://master_creatures")
	var filename := folder.path_join("campaign_test_creature_sheet_temp.json")
	if FileAccess.file_exists(filename):
		DirAccess.remove_absolute(filename)
	folder = ProjectSettings.globalize_path("user://player_characters")
	filename = folder.path_join("campaign_test_creature_sheet_temp.json")
	if FileAccess.file_exists(filename):
		DirAccess.remove_absolute(filename)
	campaign.queue_free()
	print("PASS: creature sheets, sorted references, retired trackers and local ownership")
	quit()
