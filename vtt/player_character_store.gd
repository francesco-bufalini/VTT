extends RefCounted

const CreatureOwner = preload("res://vtt/creature_owner.gd")
const CreatureRules = preload("res://vtt/creature_rules.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")

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


func list_characters(include_unowned: bool = false) -> Array[Dictionary]:
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
			if include_unowned or CreatureOwner.is_owner(character):
				result.append(character)
	return result


func save_characters(characters: Array[Dictionary], allow_transfer: bool = false) -> Error:
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
					for candidate: Dictionary in merged:
						if String(candidate.get("id", "")) != String(stored.get("id", "")):
							continue
						if not allow_transfer and (not CreatureOwner.can_edit(candidate, stored) or String(candidate.get("owner_id", "")) != String(stored.get("owner_id", CreatureOwner.local_id()))):
							return ERR_UNAUTHORIZED
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
	var destination := _file_path()
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(payload, "  "))
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))


func create_character() -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var unique: int = int(Time.get_ticks_usec())
	return {
		"id": "character_%d_%d" % [now, unique],
		"name": "Nuovo personaggio",
		"owner_id": CreatureOwner.local_id(),
		"default_miniature_id": "",
		"current_miniature_id": "",
		"size_name": "Medium",
		"footprint": 1.0,
		"reach_feet": 5.0,
		"visual_front_quarter_turns": 0,
		"party_id": "",
		"classes": [],
		"resource_tracker_spent": {},
		"resource_tracker_bonuses": {},
		"conditions": [],
		"transfer_revision": 0,
		"species_id": "",
		"class_id": "",
		"player_name": "",
		"rules_version": "2014",
		"class": "",
		"class_source": "",
		"subclass": "",
		"subclass_source": "",
		"subclass_id": "",
		"level": 1,
		"xp": 0,
		"proficiency_bonus": 2,
		"spellcasting_calculation": {},
		"species": "",
		"species_source": "",
		"subtype": "",
		"subtype_is_custom": false,
		"background": "",
		"background_source": "",
		"alignment": "",
		"sex": "",
		"inspiration": false,
		"ability_bonuses": {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0},
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
		"armor_class_base": 10,
		"armor_class_bonus": 0,
		"temporary_ac": 0,
		"initiative": 0,
		"initiative_base": 0,
		"initiative_bonus": 0,
		"max_hp": 1,
		"max_hp_base": 1,
		"max_hp_bonus": 0,
		"current_hp": 1,
		"temporary_hp": 0,
		"second_form_hp": 0,
		"second_form_max_hp": 0,
		"speed_bonus": 0,
		"speed_base": 30,
		"background_personality": "",
		"speed": 30,
		"speed_is_custom": false,
		"darkvision": 0,
		"exhaustion": 0,
		"hit_dice": "",
		"death_save_successes": 0,
		"death_save_failures": 0,
		"attacks": "",
		"attack_ability": "str",
		"attack_overrides": {},
		"equipped_attack_id": "",
		"equipped_inventory_index": -1,
		"proficiency_choices": [],
		"formula_bonuses": [],
		"documents": [],
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
		"spellbook_spells": [],
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
		"inventory": [],
		"spell_slots_total": [
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		],
		"spell_slots_bonus": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_spent": [
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		],
		"pact_slots_total": 0,
		"pact_slots_bonus": 0,
		"pact_slots_spent": 0,
		"pact_slot_level": 1,
		"spell_slots_visible": true,
		"pact_slots_visible": true,
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

	# Legacy records contain only the effective totals. Migrate them to
	# separate base and manual bonus fields without changing the result.
	defaults["armor_class_bonus"] = clampi(int(value.get("armor_class_bonus", 0)), -99, 99)
	defaults["armor_class_base"] = maxi(0, int(value.get(
		"armor_class_base", int(value.get("armor_class", 10)) - int(defaults["armor_class_bonus"])
	)))
	defaults["armor_class"] = maxi(0, int(defaults["armor_class_base"]) + int(defaults["armor_class_bonus"]) + ItemRules.shield_bonus(defaults.get("inventory", [])))
	defaults["initiative_bonus"] = clampi(int(value.get("initiative_bonus", 0)), -99, 99)
	defaults["initiative_base"] = int(value.get(
		"initiative_base", int(value.get("initiative", 0)) - int(defaults["initiative_bonus"])
	))
	defaults["initiative"] = int(defaults["initiative_base"]) + int(defaults["initiative_bonus"])

	# Persistent usage counters survive reloads and level changes.
	if not defaults.get("resource_tracker_spent", {}) is Dictionary:
		defaults["resource_tracker_spent"] = {}
	var tracker_bonuses: Dictionary = {}
	var saved_bonuses: Variant = value.get("resource_tracker_bonuses", {})
	if saved_bonuses is Dictionary:
		for tracker_id: Variant in (saved_bonuses as Dictionary).keys():
			tracker_bonuses[String(tracker_id)] = clampi(int(saved_bonuses[tracker_id]), -999, 9999)
	defaults["resource_tracker_bonuses"] = tracker_bonuses

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

	var ability_bonuses: Dictionary = {}
	var raw_bonuses: Variant = value.get("ability_bonuses", {})
	for ability_id: String in ["str", "dex", "con", "int", "wis", "cha"]:
		ability_bonuses[ability_id] = clampi(
			int((raw_bonuses as Dictionary).get(ability_id, 0))
			if raw_bonuses is Dictionary else 0, -30, 30
		)
	defaults["ability_bonuses"] = ability_bonuses

	for array_key: String in [
		"conditions",
		"saving_throw_proficiencies",
		"skill_proficiencies",
		"skill_expertise",
		"documents",
		"spells",
		"prepared_spells",
		"spellbook_spells",
		"weapons_catalog",
		"armor_catalog",
		"tools_catalog",
		"languages_catalog",
		"feats_catalog",
		"class_features_catalog",
		"species_traits_catalog",
		"optional_features_catalog",
		"inventory_mundane",
		"inventory_magic",
		"inventory"
	]:
		if not defaults.get(array_key, []) is Array:
			defaults[array_key] = []

	defaults["spell_slots_visible"] = bool(defaults.get("spell_slots_visible", true))
	defaults["pact_slots_visible"] = bool(defaults.get("pact_slots_visible", true))
	# A character can track Pact Magic separately from shared spell slots.
	defaults["pact_slots_total"] = maxi(0, int(defaults.get("pact_slots_total", 0)))
	defaults["pact_slots_bonus"] = clampi(int(defaults.get("pact_slots_bonus", 0)), -8, 20)
	defaults["pact_slots_spent"] = clampi(
		int(defaults.get("pact_slots_spent", 0)),
		0, maxi(0, int(defaults["pact_slots_total"]) + int(defaults["pact_slots_bonus"]))
	)
	defaults["pact_slot_level"] = clampi(int(defaults.get("pact_slot_level", 1)), 1, 5)
	for slots_key: String in ["spell_slots_total", "spell_slots_spent", "spell_slots_bonus"]:
		var slots_value: Variant = defaults.get(slots_key, [])
		var slots: Array = slots_value if slots_value is Array else []
		while slots.size() < 10:
			slots.append(0)
		if slots.size() > 10:
			slots.resize(10)
		for index: int in range(slots.size()):
			slots[index] = (
				clampi(int(slots[index]), -99, 99)
				if slots_key == "spell_slots_bonus"
				else maxi(0, int(slots[index]))
			)
		defaults[slots_key] = slots

	defaults["owner_id"] = String(defaults.get("owner_id", CreatureOwner.local_id()))
	if defaults["owner_id"].is_empty():
		defaults["owner_id"] = CreatureOwner.local_id()
	if not defaults.get("classes", []) is Array:
		defaults["classes"] = []
	defaults["level"] = clampi(int(defaults.get("level", 1)), 1, 20)
	defaults["xp"] = maxi(CreatureRules.experience_for_level(int(defaults["level"])), int(value.get("xp", 0)))
	var classes_value: Variant = defaults.get("classes", [])
	if classes_value is Array and (classes_value as Array).size() == 1:
		var first_value: Variant = (classes_value as Array)[0]
		if first_value is Dictionary:
			var first := (first_value as Dictionary).duplicate(true)
			first["name"] = String(defaults.get("class", ""))
			first["source"] = String(defaults.get("class_source", ""))
			first["level"] = int(defaults["level"])
			defaults["classes"] = [first]
	# Older sheets kept the primary subclass only inside classes[0].
	if classes_value is Array and not (classes_value as Array).is_empty():
		var first_class: Variant = (classes_value as Array)[0]
		if first_class is Dictionary and String(defaults.get("subclass", "")).is_empty():
			defaults["subclass"] = String((first_class as Dictionary).get("subclass", ""))
			defaults["subclass_source"] = String((first_class as Dictionary).get("subclass_source", ""))
			defaults["subclass_id"] = String((first_class as Dictionary).get("subclass_id", ""))
	defaults["max_hp_bonus"] = clampi(int(value.get("max_hp_bonus", 0)), -9999, 99999)
	defaults["max_hp_base"] = maxi(0, int(value.get(
		"max_hp_base", int(value.get("max_hp", 1)) - int(defaults["max_hp_bonus"])
	)))
	defaults["max_hp"] = maxi(0, int(defaults["max_hp_base"]) + int(defaults["max_hp_bonus"]))
	defaults["current_hp"] = int(defaults.get("current_hp", 1))
	defaults["temporary_hp"] = maxi(0, int(defaults.get("temporary_hp", 0)))
	defaults["second_form_max_hp"] = maxi(0, int(defaults.get("second_form_max_hp", defaults.get("second_form_hp", 0))))
	defaults["second_form_hp"] = clampi(int(defaults.get("second_form_hp", 0)), 0, int(defaults["second_form_max_hp"]))
	defaults["background_personality"] = String(defaults.get("background_personality", ""))
	defaults["current_miniature_id"] = String(defaults.get("current_miniature_id", "")).strip_edges()
	if defaults["current_miniature_id"].is_empty():
		defaults["current_miniature_id"] = String(defaults.get("default_miniature_id", ""))
	defaults["size_name"] = String(defaults.get("size_name", "Medium"))
	defaults["footprint"] = maxf(0.5, float(defaults.get("footprint", 1.0)))
	defaults["attack_ability"] = "dex" if String(value.get("attack_ability", "str")) == "dex" else "str"
	defaults["attack_overrides"] = value.get("attack_overrides", {}).duplicate(true) if value.get("attack_overrides", {}) is Dictionary else {}
	defaults["equipped_attack_id"] = String(value.get("equipped_attack_id", "")).strip_edges()
	defaults["equipped_inventory_index"] = maxi(-1, int(value.get("equipped_inventory_index", -1)))
	defaults["proficiency_origins"] = Proficiencies.origins(value)
	defaults["proficiency_choices"] = Proficiencies.choices(value)
	defaults["formula_bonuses"] = Bonuses.grants(value)
	Proficiencies.sync_legacy_fields(defaults, Proficiencies.choices(defaults))
	defaults["reach_feet"] = maxf(5.0, float(defaults.get("reach_feet", 5.0)))
	defaults["visual_front_quarter_turns"] = clampi(int(defaults.get("visual_front_quarter_turns", 0)), 0, 3)
	defaults["party_id"] = String(defaults.get("party_id", ""))
	defaults["armor_class"] = maxi(0, int(defaults.get("armor_class", 10)))
	defaults["speed_bonus"] = clampi(int(defaults.get("speed_bonus", 0)), -999, 999)
	defaults["speed_base"] = maxi(0, int(value.get("speed_base", int(defaults.get("speed", 30)) - int(defaults["speed_bonus"]))))
	defaults["speed"] = maxi(0, int(defaults["speed_base"]) + int(defaults["speed_bonus"]))
	defaults["speed_is_custom"] = bool(defaults.get("speed_is_custom", false))
	defaults["darkvision"] = maxi(0, int(defaults.get("darkvision", 0)))
	defaults["exhaustion"] = clampi(int(defaults.get("exhaustion", 0)), 0, 6)
	Bonuses.migrate_legacy(defaults, not value.has("formula_bonuses") or not value.has("initiative_base"))
	defaults["max_hp"] = maxi(0, Bonuses.value(defaults, "hp"))
	defaults["armor_class"] = maxi(0, Bonuses.value(defaults, "ac"))
	defaults["initiative_base"] = Bonuses.value(defaults, "ability_mod:dex")
	defaults["initiative"] = Bonuses.value(defaults, "initiative")
	defaults["speed"] = maxi(0, Bonuses.value(defaults, "speed"))
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
