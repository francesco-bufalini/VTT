extends RefCounted

const CreatureOwner = preload("res://vtt/creature_owner.gd")
const CreatureRules = preload("res://vtt/creature_rules.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const RaceRules = preload("res://vtt/creature_race_rules.gd")
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
	return CreatureOwner.storage_scope_id(_campaign_manager)

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
			var merge_error: Error = CreatureOwner.merge_transferred_records(merged, saved_value, allow_transfer)
			if merge_error != OK:
				return merge_error
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
		"resource_trackers": [],
		"conditions": [],
		"concentrating_spell_id": "",
		"damage_defense_overrides": {},
		"condition_immunity_overrides": {},
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
		"subrace": "", "subrace_source": "", "subrace_id": "",
		"subtype": "",
		"subtype_is_custom": false,
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
		"armor_class_base": 10,
		"armor_natural_formula": "",
		"temporary_ac": 0,
		"initiative": 0,
		"initiative_base": 0,
		"max_hp": 1,
		"max_hp_base": 1,
		"current_hp": 1,
		"temporary_hp": 0,
		"second_form_hp": 0,
		"second_form_max_hp": 0,
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
		"hand_main_special": "none",
		"hand_off_special": "none",
		"hand_grip_two_handed": false,
		"two_weapon_fighting": false,
		"fighting_styles": [],
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
		"spell_slots_spent": [
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		],
		"pact_slots_total": 0,
		"pact_slots_spent": 0,
		"pact_slot_level": 1,
		"spell_slots_visible": true,
		"pact_slots_visible": true,
		"linked_token_sync_id": "",
		"linked_token_name": ""
	}


func normalize_character(value: Dictionary) -> Dictionary:
	value = RaceRules.migrate_legacy_species(value)
	var defaults: Dictionary = create_character()
	defaults["id"] = String(
		value.get("id", defaults.get("id", ""))
	)

	for key: Variant in defaults.keys():
		if value.has(key):
			defaults[key] = value[key]

	defaults["armor_class_base"] = maxi(0, int(value.get("armor_class_base", value.get("armor_class", 10))))
	var natural_default: String = str(defaults["armor_class_base"])
	if String(defaults.get("kind", "")) == "monster":
		natural_default = str(CreatureRules.monster_armor_class(defaults.get("stat_block", {})))
	elif int(defaults["armor_class_base"]) == 10:
		natural_default = "10 + dex_mod"
	defaults["armor_natural_formula"] = String(value.get("armor_natural_formula", natural_default)).strip_edges()
	if String(defaults["armor_natural_formula"]).is_empty():
		defaults["armor_natural_formula"] = natural_default
	defaults["initiative_base"] = 0

	# Persistent usage counters survive reloads and level changes.
	if not defaults.get("resource_tracker_spent", {}) is Dictionary:
		defaults["resource_tracker_spent"] = {}

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
		"inventory",
		"resource_trackers"
	]:
		if not defaults.get(array_key, []) is Array:
			defaults[array_key] = []

	defaults["concentrating_spell_id"] = String(defaults.get("concentrating_spell_id", "")).strip_edges()
	defaults["spell_slots_visible"] = bool(defaults.get("spell_slots_visible", true))
	defaults["pact_slots_visible"] = bool(defaults.get("pact_slots_visible", true))
	# A character can track Pact Magic separately from shared spell slots.
	defaults["pact_slots_total"] = maxi(0, int(defaults.get("pact_slots_total", 0)))
	defaults["pact_slots_spent"] = maxi(0, int(defaults.get("pact_slots_spent", 0)))
	defaults["pact_slot_level"] = clampi(int(defaults.get("pact_slot_level", 1)), 1, 5)
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
	defaults["max_hp_base"] = maxi(0, int(value.get("max_hp_base", value.get("max_hp", 1))))
	defaults["max_hp"] = int(defaults["max_hp_base"])
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
	defaults["damage_defense_overrides"] = value.get("damage_defense_overrides", {}).duplicate(true) if value.get("damage_defense_overrides", {}) is Dictionary else {}
	# Keep the origin-backed defense editor state when normalizing/saving.
	# It is intentionally optional: legacy characters without this array
	# still read their damage_defense_overrides during migration.
	if value.get("damage_defense_entries", null) is Array:
		defaults["damage_defense_entries"] = (value["damage_defense_entries"] as Array).duplicate(true)
	defaults["condition_immunity_overrides"] = value.get("condition_immunity_overrides", {}).duplicate(true) if value.get("condition_immunity_overrides", {}) is Dictionary else {}
	defaults["equipped_attack_id"] = String(value.get("equipped_attack_id", "")).strip_edges()
	defaults["equipped_inventory_index"] = maxi(-1, int(value.get("equipped_inventory_index", -1)))
	defaults["hand_main_special"] = String(value.get("hand_main_special", "none"))
	defaults["hand_off_special"] = String(value.get("hand_off_special", "none"))
	defaults["hand_grip_two_handed"] = bool(value.get("hand_grip_two_handed", false))
	defaults["two_weapon_fighting"] = bool(value.get("two_weapon_fighting", false))
	defaults["fighting_styles"] = value.get("fighting_styles", []).duplicate(true) if value.get("fighting_styles", []) is Array else []
	defaults["proficiency_origins"] = Proficiencies.origins(value)
	defaults["proficiency_choices"] = Proficiencies.choices(value)
	defaults["formula_bonuses"] = Bonuses.grants(value)
	defaults["pact_slots_spent"] = mini(
		int(defaults["pact_slots_spent"]),
		maxi(0, Bonuses.add(defaults, "pact_slot", int(defaults["pact_slots_total"])))
	)
	Proficiencies.sync_legacy_fields(defaults, Proficiencies.choices(defaults))
	defaults["reach_feet"] = maxf(5.0, float(defaults.get("reach_feet", 5.0)))
	defaults["visual_front_quarter_turns"] = clampi(int(defaults.get("visual_front_quarter_turns", 0)), 0, 3)
	defaults["party_id"] = String(defaults.get("party_id", ""))
	defaults["armor_class"] = maxi(0, int(defaults.get("armor_class", 10)))
	defaults["speed_base"] = maxi(0, int(value.get("speed_base", value.get("speed", 30))))
	defaults["speed"] = int(defaults["speed_base"])
	defaults["speed_is_custom"] = bool(defaults.get("speed_is_custom", false))
	defaults["darkvision"] = maxi(0, int(defaults.get("darkvision", 0)))
	defaults["exhaustion"] = clampi(int(defaults.get("exhaustion", 0)), 0, 6)
	defaults["max_hp"] = maxi(0, Bonuses.value(defaults, "hp"))
	defaults["armor_class"] = maxi(0, Bonuses.value(defaults, "ac"))
	defaults["initiative_base"] = Bonuses.value(defaults, "ability_mod:dex")
	defaults["initiative"] = Bonuses.value(defaults, "initiative")
	defaults["proficiency_bonus"] = Bonuses.value(defaults, "proficiency")
	defaults["speed"] = maxi(0, Bonuses.value(defaults, "speed"))
	return defaults


func _file_path() -> String:
	return ROOT_DIR.path_join(scope_id() + ".json")
