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
		"hp": {"average": 178},
		"ac": [{"ac": 18, "from": ["natural armor"]}],
		"str": 23,
		"dex": 10,
		"legendaryActions": 3,
		"legendary": [{"name": "Tail Attack"}],
		"action": [
			{"name": "Fire Breath (Recharge 5–6)"},
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
	assert(creature.owner_id == Owner.local_id())
	assert(creature.trackers.size() == 5)
	var recharge: Dictionary = {}
	for item: Dictionary in creature.trackers:
		if item.kind == "recharge":
			recharge = item
	assert(recharge.recharge_min == 5)
	var spent: Array = creature.trackers.duplicate(true)
	spent[0]["current"] = 0
	var merged: Array[Dictionary] = Rules.reconcile_trackers(
		spent, Rules.monster_trackers(stat)
	)
	assert(merged[0].current == 0)
	assert(Rules.apply_reset(merged, "turn")[0].current == 3)

	var wizard := {
		"class": "Wizard", "level": 5,
		"classes": [{"name": "Wizard", "level": 5}],
		"rules_version": "2024"
	}
	var slots: Array[Dictionary] = Rules.character_trackers(wizard)
	assert(slots.size() == 3)
	assert(slots[0].maximum == 4 and slots[1].maximum == 3)
	assert(slots[2].maximum == 2)
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
	var fighter_2014 := Rules.character_trackers({"classes": [{"name": "Fighter", "source": "PHB", "level": 10}]})
	assert(fighter_2014[0].maximum == 1 and fighter_2014[0].reset == "short_rest")
	assert(Rules.monster_trackers({"action": [{"name": "Breath {@recharge 5}"} ]})[0].recharge_min == 5)
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
	print("PASS: creature sheets derive trackers, persist state and enforce local ownership")
	quit()
