extends SceneTree

const Rules = preload("res://vtt/creature_rules.gd")
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
	assert(creature.species == "Test Dragon" and creature.species_source == "MM")
	assert(creature.class == "Mostro" and creature.level == Rules.monster_level(stat))
	assert(creature.classes.size() == 1
		and creature.classes[0].level == Rules.monster_level(stat),
		"Monster base class level is an integer, while stat_block.cr retains fractions")
	assert(creature.subclass == "Drago" and creature.subclass_id == "monster_type|dragon",
		"Monster subtype must come from structured 5etools monster type")
	assert(creature.speed == 40, "Monster speed should come from structured 5etools speed")
	assert(creature.reach_feet == 10.0,
		"Monster melee reach must be derived from 5etools, not a fixed 5 ft")
	assert(creature.owner_id == Owner.local_id())
	assert(not creature.has("trackers"), "New creatures must not generate legacy resources.")
	assert(Rules.monster_armor_class(stat) == 18)
	assert(Rules.monster_abilities(stat).str == 23)
	assert(is_equal_approx(Rules.monster_cr_value({"cr": {"cr": "1/8"}}), 0.125))
	var multiclass_monster := creature.duplicate(true)
	multiclass_monster["classes"].append({"name": "Wizard", "level": 3, "source": "PHB"})
	var normalized_monster: Dictionary = monster.normalize_creature(multiclass_monster)
	assert(normalized_monster.classes.size() == 2
		and normalized_monster.classes[0].level == Rules.monster_level(stat)
		and normalized_monster.classes[1].name == "Wizard"
		and normalized_monster.level == Rules.monster_level(stat) + 3,
		"Monster class normalization must not discard extra real classes")
	assert(normalized_monster.xp >= Rules.experience_for_level(3),
		"Monster CR must not contribute to class-level XP requirements")
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
