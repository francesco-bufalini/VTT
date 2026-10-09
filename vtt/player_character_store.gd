extends RefCounted

const CreatureOwner = preload("res://vtt/creature_owner.gd")

const ROOT_DIR := "user://player_characters"
const FILE_VERSION := 3

var _campaign_manager: Node


func setup(campaign_manager: Node) -> void:
	_campaign_manager = campaign_manager
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT_DIR)
	)


func scope_id() -> String:
	if _campaign_manager != null and is_instance_valid(_campaign_manager):
		var campaign_group_id: String = String(
			_campaign_manager.get("selected_campaign_group_id")
		).strip_edges()
		if not campaign_group_id.is_empty():
			return "campaign_" + _safe_id(campaign_group_id)

		var active_campaign_id: String = String(
			_campaign_manager.get("active_campaign_id")
		).strip_edges()
		if not active_campaign_id.is_empty():
			return "scenario_" + _safe_id(active_campaign_id)

	return "default"


func list_characters() -> Array[Dictionary]:
	var path: String = _file_path()
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return []

	var root: Dictionary = parsed as Dictionary
	var characters_value: Variant = root.get("characters", [])
	if not characters_value is Array:
		return []

	var result: Array[Dictionary] = []
	for item: Variant in characters_value:
		if item is Dictionary:
			var character := normalize_character(item as Dictionary)
			if CreatureOwner.is_owner(character):
				result.append(character)
	return result


func save_characters(characters: Array[Dictionary]) -> Error:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT_DIR)
	)

	# Keep private records transferred to another installation intact when
	# a local controller saves their visible subset.
	var merged: Array[Dictionary] = characters.duplicate(true)
	var previous := FileAccess.open(_file_path(), FileAccess.READ)
	if previous != null:
		var root_value: Variant = JSON.parse_string(previous.get_as_text())
		previous.close()
		if root_value is Dictionary:
			var saved_value: Variant = (root_value as Dictionary).get("characters", [])
			if saved_value is Array:
				for raw: Variant in saved_value as Array:
					if not raw is Dictionary:
						continue
					var stored: Dictionary = raw as Dictionary
					if CreatureOwner.is_owner(stored):
						continue
					var exists := false
					for visible: Dictionary in merged:
						if String(visible.get("id", "")) == String(stored.get("id", "")):
							exists = true
							break
					if not exists:
						merged.append(stored.duplicate(true))
	var payload: Dictionary = {
		"version": FILE_VERSION,
		"scope": scope_id(),
		"characters": merged
	}
	var file := FileAccess.open(_file_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(payload, "  "))
	var error: Error = file.get_error()
	file.close()
	return error


func create_character() -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var unique: int = int(Time.get_ticks_usec())
	return {
		"id": "character_%d_%d" % [now, unique],
		"name": "Nuovo personaggio",
		"owner_id": CreatureOwner.local_id(),
		"default_miniature_id": "",
		"current_miniature_id": "",
		"classes": [],
		"trackers": [],
		"player_name": "",
		"rules_version": "2024",
		"class": "",
		"class_source": "",
		"level": 1,
		"species": "",
		"species_source": "",
		"background": "",
		"background_source": "",
		"alignment": "",
		"sex": "",
		"inspiration": false,
		"abilities": {
			"str": 10,
			"dex": 10,
			"con": 10,
			"int": 10,
			"wis": 10,
			"cha": 10
		},
		"saving_throw_proficiencies": [],
		"skill_proficiencies": [],
		"skill_expertise": [],
		"armor_class": 10,
		"temporary_ac": 0,
		"initiative": 0,
		"max_hp": 1,
		"current_hp": 1,
		"temporary_hp": 0,
		"speed": 30,
		"darkvision": 0,
		"exhaustion": 0,
		"hit_dice": "",
		"death_save_successes": 0,
		"death_save_failures": 0,
		"attacks": "",
		"ammunition": "",
		"armor_proficiencies": "",
		"weapon_proficiencies": "",
		"tool_proficiencies": "",
		"languages": "",
		"feats": "",
		"equipment": "",
		"consumables": "",
		"magic_items": "",
		"class_features": "",
		"racial_background_traits": "",
		"limited_features": "",
		"age": "",
		"height": "",
		"weight": "",
		"eyes": "",
		"skin": "",
		"hair": "",
		"appearance": "",
		"faction": "",
		"symbol": "",
		"personality_traits": "",
		"ideals": "",
		"bonds": "",
		"flaws": "",
		"enemies": "",
		"additional_traits": "",
		"spellcasting_class": "",
		"spellcasting_ability": "",
		"spell_save_dc": 0,
		"spell_attack_bonus": 0,
		"spells": [],
		"prepared_spells": [],
		"weapons_catalog": [],
		"armor_catalog": [],
		"tools_catalog": [],
		"languages_catalog": [],
		"feats_catalog": [],
		"class_features_catalog": [],
		"species_traits_catalog": [],
		"optional_features_catalog": [],
		"inventory_mundane": [],
		"inventory_magic": [],
		"spell_slots_total": [
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		],
		"spell_slots_spent": [
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		],
		"linked_token_sync_id": "",
		"linked_token_name": ""
	}


func normalize_character(value: Dictionary) -> Dictionary:
	var defaults: Dictionary = create_character()
	defaults["id"] = String(
		value.get("id", defaults.get("id", ""))
	)

	for key: Variant in defaults.keys():
		if value.has(key):
			defaults[key] = value[key]

	var abilities_value: Variant = value.get("abilities", {})
	if abilities_value is Dictionary:
		var abilities: Dictionary = defaults["abilities"] as Dictionary
		for ability_id: String in ["str", "dex", "con", "int", "wis", "cha"]:
			abilities[ability_id] = clampi(
				int((abilities_value as Dictionary).get(ability_id, 10)),
				1,
				30
			)
		defaults["abilities"] = abilities

	for array_key: String in [
		"saving_throw_proficiencies",
		"skill_proficiencies",
		"skill_expertise",
		"spells",
		"prepared_spells",
		"weapons_catalog",
		"armor_catalog",
		"tools_catalog",
		"languages_catalog",
		"feats_catalog",
		"class_features_catalog",
		"species_traits_catalog",
		"optional_features_catalog",
		"inventory_mundane",
		"inventory_magic"
	]:
		if not defaults.get(array_key, []) is Array:
			defaults[array_key] = []

	for slots_key: String in ["spell_slots_total", "spell_slots_spent"]:
		var slots_value: Variant = defaults.get(slots_key, [])
		var slots: Array = slots_value if slots_value is Array else []
		while slots.size() < 10:
			slots.append(0)
		if slots.size() > 10:
			slots.resize(10)
		for index: int in range(slots.size()):
			slots[index] = maxi(0, int(slots[index]))
		defaults[slots_key] = slots

	defaults["owner_id"] = String(defaults.get("owner_id", CreatureOwner.local_id()))
	if defaults["owner_id"].is_empty():
		defaults["owner_id"] = CreatureOwner.local_id()
	if not defaults.get("classes", []) is Array:
		defaults["classes"] = []
	if not defaults.get("trackers", []) is Array:
		defaults["trackers"] = []
	defaults["level"] = clampi(int(defaults.get("level", 1)), 1, 20)
	defaults["max_hp"] = maxi(0, int(defaults.get("max_hp", 1)))
	defaults["current_hp"] = int(defaults.get("current_hp", 1))
	defaults["temporary_hp"] = maxi(0, int(defaults.get("temporary_hp", 0)))
	defaults["armor_class"] = maxi(0, int(defaults.get("armor_class", 10)))
	defaults["speed"] = maxi(0, int(defaults.get("speed", 30)))
	defaults["darkvision"] = maxi(0, int(defaults.get("darkvision", 0)))
	defaults["exhaustion"] = clampi(int(defaults.get("exhaustion", 0)), 0, 6)
	return defaults


func _file_path() -> String:
	return ROOT_DIR.path_join(scope_id() + ".json")


func _safe_id(value: String) -> String:
	var result := ""
	for character: String in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		elif character in ["-", "_"]:
			result += character
		else:
			result += "_"
	return result
