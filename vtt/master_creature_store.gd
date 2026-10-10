extends RefCounted

const CreatureRules = preload("res://vtt/creature_rules.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const CreatureOwner = preload("res://vtt/creature_owner.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")

const ROOT_DIR := "user://master_creatures"
const FILE_VERSION := 2

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


func list_creatures(include_unowned: bool = false) -> Array[Dictionary]:
	var path := _file_path()
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return []

	var creatures_value: Variant = (parsed as Dictionary).get("creatures", [])
	if not creatures_value is Array:
		return []

	var result: Array[Dictionary] = []
	for item: Variant in (creatures_value as Array):
		if item is Dictionary:
			var creature := normalize_creature(item as Dictionary)
			if include_unowned or CreatureOwner.is_owner(creature):
				result.append(creature)
	return result


func save_creatures(creatures: Array[Dictionary], allow_transfer: bool = false) -> Error:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT_DIR)
	)
	# Keep private records transferred to another installation intact when
	# a local controller saves their visible subset.
	var merged: Array[Dictionary] = creatures.duplicate(true)
	var previous := FileAccess.open(_file_path(), FileAccess.READ)
	if previous != null:
		var root_value: Variant = JSON.parse_string(previous.get_as_text())
		previous.close()
		if root_value is Dictionary:
			var saved_value: Variant = (root_value as Dictionary).get("creatures", [])
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
	var payload := {
		"version": FILE_VERSION,
		"scope": scope_id(),
		"creatures": merged
	}
	var destination := _file_path()
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "  "))
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))


func create_creature(stat_block: Dictionary, side: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var unique := int(Time.get_ticks_usec())
	var base_name := String(stat_block.get("name", "Creatura")).strip_edges()
	if base_name.is_empty():
		base_name = "Creatura"
	var hp := _default_hp(stat_block)
	return {
		"id": "master_creature_%d_%d" % [now, unique],
		"name": base_name,
		"base_name": base_name,
		"source": String(stat_block.get("source", "")),
		"side": "ally" if side == "ally" else "enemy",
		"max_hp": hp,
		"max_hp_base": hp,
		"max_hp_bonus": 0,
		"current_hp": hp,
		"inventory": [],
		"documents": [],
		"attacks": "",
		"attack_ability": "str",
		"attack_overrides": {},
		"equipped_attack_id": "",
		"equipped_inventory_index": -1,
		"proficiency_choices": [],
		"formula_bonuses": [],
		"saving_throw_proficiencies": [],
		"skill_proficiencies": [],
		"skill_expertise": [],
		"skill_ranks_custom": false,
		"armor_class": CreatureRules.monster_armor_class(stat_block),
		"armor_class_base": CreatureRules.monster_armor_class(stat_block),
		"armor_class_bonus": 0,
		"speed": CreatureRules.walking_speed(stat_block.get("speed", 30)),
		"speed_is_custom": false,
		"initiative": CreatureRules.ability_modifier(int(stat_block.get("dex", 10))),
		"initiative_base": CreatureRules.ability_modifier(int(stat_block.get("dex", 10))),
		"initiative_bonus": 0,
		"abilities": CreatureRules.monster_abilities(stat_block),
		"ability_bonuses": {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0},
		"resource_tracker_spent": {},
		"resource_tracker_bonuses": {},
		"xp": 0,
		"spells": [],
		"prepared_spells": [],
		"spellbook_spells": [],
		"spell_slots_total": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_bonus": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_spent": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"pact_slots_total": 0,
		"pact_slots_bonus": 0,
		"pact_slots_spent": 0,
		"pact_slot_level": 1,
		"spell_slots_visible": true,
		"pact_slots_visible": true,
		"feats": "",
		"feats_catalog": [],
		"owner_id": CreatureOwner.local_id(),
		"default_miniature_id": _default_miniature_id(stat_block),
		"current_miniature_id": _default_miniature_id(stat_block),
		"size_name": "Medium",
		"footprint": 1.0,
		"reach_feet": CreatureRules.monster_base_reach_feet(stat_block),
		"reach_is_custom": false,
		"visual_front_quarter_turns": 0,
		"party_id": "",
		"temporary_hp": 0,
		"second_form_hp": 0,
		"second_form_max_hp": 0,
		"speed_bonus": 0,
		"speed_base": CreatureRules.walking_speed(stat_block.get("speed", 30)),
		"background_personality": "",
		"stat_block": stat_block.duplicate(true),
		"species": String(stat_block.get("name", base_name)),
		"species_source": String(stat_block.get("source", "")),
		"subtype": CreatureRules.monster_subtype(stat_block),
		"subtype_is_custom": false,
		"class": "Mostro",
		"class_source": "5etools",
		"level": CreatureRules.monster_level(stat_block),
		"subclass": "", "subclass_source": "", "subclass_id": "",
		"classes": [{"name": "Mostro", "source": "5etools",
			"level": CreatureRules.monster_level(stat_block)}],
		"linked_token_sync_id": "",
		"linked_token_name": ""
	}


func normalize_creature(value: Dictionary) -> Dictionary:
	var stat_value: Variant = value.get("stat_block", {})
	var stat_block: Dictionary = (
		(stat_value as Dictionary).duplicate(true)
		if stat_value is Dictionary
		else {}
	)
	var base_name := String(
		value.get("base_name", stat_block.get("name", "Creatura"))
	).strip_edges()
	if base_name.is_empty():
		base_name = "Creatura"
	var fallback_hp := _default_hp(stat_block)
	# Legacy sheets did not record whether reach was edited. Retain
	# non-default values that differ from the bestiary, but migrate the
	# historical fixed 5 ft default to the real 5etools melee reach.
	var bestiary_reach: float = CreatureRules.monster_base_reach_feet(stat_block)
	var saved_reach: float = float(value.get("reach_feet", 5.0))
	var custom_reach: bool = bool(value.get(
		"reach_is_custom",
		absf(saved_reach - 5.0) > 0.01 and absf(saved_reach - bestiary_reach) > 0.01
	))
	# Persisted monster rows may have no kind field. Proficiency rules must
	# still treat every added character class as a starting class.
	var proficiency_record: Dictionary = value.duplicate(true)
	proficiency_record["kind"] = "monster"
	var result := {
		"id": String(value.get("id", "")),
		"name": String(value.get("name", base_name)),
		"base_name": base_name,
		"source": String(value.get("source", stat_block.get("source", ""))),
		"side": (
			"ally"
			if String(value.get("side", "enemy")) == "ally"
			else "enemy"
		),
		"max_hp": maxi(0, int(value.get("max_hp", fallback_hp))),
		"max_hp_bonus": clampi(int(value.get("max_hp_bonus", 0)), -9999, 99999),
		"max_hp_base": maxi(0, int(value.get("max_hp_base", int(value.get("max_hp", fallback_hp)) - int(value.get("max_hp_bonus", 0))))),
		"inventory": value.get("inventory", []).duplicate(true) if value.get("inventory", []) is Array else [],
		"documents": value.get("documents", []).duplicate(true) if value.get("documents", []) is Array else [],
		"attacks": String(value.get("attacks", "")),
		"attack_ability": "dex" if String(value.get("attack_ability", "str")) == "dex" else "str",
		"attack_overrides": value.get("attack_overrides", {}).duplicate(true) if value.get("attack_overrides", {}) is Dictionary else {},
		"equipped_attack_id": String(value.get("equipped_attack_id", "")).strip_edges(),
		"equipped_inventory_index": maxi(-1, int(value.get("equipped_inventory_index", -1))),
		"proficiency_choices": Proficiencies.choices(proficiency_record),
		"formula_bonuses": Bonuses.grants(value),
		"proficiency_origins": Proficiencies.origins(proficiency_record),
		"saving_throw_proficiencies": value.get("saving_throw_proficiencies", []).duplicate(true) if value.get("saving_throw_proficiencies", []) is Array else [],
		"skill_proficiencies": value.get("skill_proficiencies", []).duplicate(true) if value.get("skill_proficiencies", []) is Array else [],
		"skill_expertise": value.get("skill_expertise", []).duplicate(true) if value.get("skill_expertise", []) is Array else [],
		"skill_ranks_custom": bool(value.get("skill_ranks_custom", false)),
		"current_hp": int(value.get("current_hp", fallback_hp)),
		"stat_block": stat_block,
		"species": String(stat_block.get("name", base_name)),
		"species_source": String(stat_block.get("source", value.get("source", ""))),
		"subtype": String(value.get("subtype", "")) if bool(value.get("subtype_is_custom", false)) else CreatureRules.monster_subtype(stat_block),
		"subtype_is_custom": bool(value.get("subtype_is_custom", false)),
		"class": "Mostro",
		"class_source": "5etools",
		"level": CreatureRules.monster_level(stat_block),
		"subclass": "", "subclass_source": "", "subclass_id": "",
		"classes": [],
		"conditions": value.get("conditions", []).duplicate() if value.get("conditions", []) is Array else [],
		"transfer_revision": maxi(0, int(value.get("transfer_revision", 0))),
		"owner_id": String(value.get("owner_id", CreatureOwner.local_id())),
		"default_miniature_id": String(value.get("default_miniature_id", _default_miniature_id(stat_block))),
		"current_miniature_id": String(value.get("current_miniature_id", value.get("default_miniature_id", _default_miniature_id(stat_block)))),
		"size_name": String(value.get("size_name", "Medium")),
		"footprint": maxf(0.5, float(value.get("footprint", 1.0))),
		"reach_feet": maxf(5.0, saved_reach) if custom_reach else bestiary_reach,
		"reach_is_custom": custom_reach,
		"visual_front_quarter_turns": clampi(int(value.get("visual_front_quarter_turns", 0)), 0, 3),
		"party_id": String(value.get("party_id", "")),
		"temporary_hp": maxi(0, int(value.get("temporary_hp", 0))),
		"second_form_hp": maxi(0, int(value.get("second_form_hp", 0))),
		"second_form_max_hp": maxi(0, int(value.get("second_form_max_hp", value.get("second_form_hp", 0)))),
		"speed_base": maxi(0, int(value.get("speed_base", int(value.get("speed", CreatureRules.walking_speed(stat_block.get("speed", 30)))) - int(value.get("speed_bonus", 0))))),
		"speed_bonus": clampi(int(value.get("speed_bonus", 0)), -999, 999),
		"background_personality": String(value.get("background_personality", "")),
		"armor_class": maxi(0, int(value.get("armor_class", CreatureRules.monster_armor_class(stat_block)))),
		"armor_class_bonus": clampi(int(value.get("armor_class_bonus", 0)), -99, 99),
		"armor_class_base": maxi(0, int(value.get(
			"armor_class_base", int(value.get("armor_class", CreatureRules.monster_armor_class(stat_block)))
			- int(value.get("armor_class_bonus", 0))
		))),
		"speed": maxi(0, int(value.get("speed", CreatureRules.walking_speed(stat_block.get("speed", 30))))),
		"speed_is_custom": bool(value.get("speed_is_custom", false)),
		"initiative": int(value.get("initiative", CreatureRules.ability_modifier(int(stat_block.get("dex", 10))))),
		"initiative_bonus": clampi(int(value.get("initiative_bonus", 0)), -99, 99),
		"initiative_base": int(value.get(
			"initiative_base", int(value.get("initiative", CreatureRules.ability_modifier(int(stat_block.get("dex", 10)))))
			- int(value.get("initiative_bonus", 0))
		)),
		"abilities": _normalize_abilities(value.get("abilities", {}), stat_block),
		"ability_bonuses": _normalize_ability_bonuses(value.get("ability_bonuses", {})),
		"resource_tracker_spent": value.get("resource_tracker_spent", {}).duplicate(true) if value.get("resource_tracker_spent", {}) is Dictionary else {},
		"resource_tracker_bonuses": value.get("resource_tracker_bonuses", {}).duplicate(true) if value.get("resource_tracker_bonuses", {}) is Dictionary else {},
		"xp": maxi(0, int(value.get("xp", 0))),
		"spells": value.get("spells", []).duplicate(true) if value.get("spells", []) is Array else [],
		"prepared_spells": value.get("prepared_spells", []).duplicate(true) if value.get("prepared_spells", []) is Array else [],
		"spellbook_spells": value.get("spellbook_spells", []).duplicate(true) if value.get("spellbook_spells", []) is Array else [],
		"spell_slots_total": _normalize_spell_slots(value.get("spell_slots_total", [])),
		"spell_slots_bonus": _normalize_spell_slot_bonuses(value.get("spell_slots_bonus", [])),
		"spell_slots_spent": _normalize_spell_slots(value.get("spell_slots_spent", [])),
		"pact_slots_total": maxi(0, int(value.get("pact_slots_total", 0))),
		"pact_slots_bonus": clampi(int(value.get("pact_slots_bonus", 0)), -8, 20),
		"pact_slots_spent": maxi(0, int(value.get("pact_slots_spent", 0))),
		"pact_slot_level": clampi(int(value.get("pact_slot_level", 1)), 1, 5),
		"spell_slots_visible": bool(value.get("spell_slots_visible", true)),
		"pact_slots_visible": bool(value.get("pact_slots_visible", true)),
		"feats": String(value.get("feats", "")),
		"feats_catalog": value.get("feats_catalog", []).duplicate(true) if value.get("feats_catalog", []) is Array else [],
		"linked_token_sync_id": String(
			value.get("linked_token_sync_id", "")
		),
		"linked_token_name": String(value.get("linked_token_name", ""))
	}
	result["max_hp"] = maxi(0, int(result["max_hp_base"]) + int(result["max_hp_bonus"]))
	result["armor_class"] = maxi(0, int(result["armor_class_base"]) + int(result["armor_class_bonus"]) + ItemRules.shield_bonus(result.get("inventory", [])))
	result["initiative"] = int(result["initiative_base"]) + int(result["initiative_bonus"])
	if not bool(result["speed_is_custom"]):
		result["speed_base"] = CreatureRules.walking_speed(stat_block.get("speed", 30))
	result["speed"] = maxi(0, int(result["speed_base"]) + int(result["speed_bonus"]))
	result["second_form_hp"] = mini(int(result["second_form_hp"]), int(result["second_form_max_hp"]))
	# Rebuild the immutable monster base from the bestiary on every load,
	# preserving any real class levels subsequently added by the user.
	var extra_classes: Array = []
	var old_classes: Variant = value.get("classes", [])
	if old_classes is Array:
		for raw_class: Variant in old_classes:
			if not raw_class is Dictionary:
				continue
			var cls: Dictionary = raw_class as Dictionary
			if String(cls.get("name", "")).to_lower() != "mostro":
				extra_classes.append(cls.duplicate(true))
	var monster_level: int = CreatureRules.monster_level(stat_block)
	var merged_classes: Array = [{"name": "Mostro", "source": "5etools", "level": monster_level}]
	merged_classes.append_array(extra_classes)
	result["classes"] = merged_classes
	var added_levels: int = 0
	for cls: Dictionary in extra_classes:
		added_levels += maxi(0, int(cls.get("level", 0)))
	result["level"] = monster_level + added_levels
	# Only class levels other than Mostro contribute to the XP threshold.
	result["xp"] = maxi(int(result["xp"]), CreatureRules.experience_for_level(added_levels))
	var normalized_bonuses: Dictionary = {}
	for tracker_id: Variant in (result["resource_tracker_bonuses"] as Dictionary).keys():
		normalized_bonuses[String(tracker_id)] = clampi(int(result["resource_tracker_bonuses"][tracker_id]), -999, 9999)
	result["resource_tracker_bonuses"] = normalized_bonuses
	if String(result["id"]).is_empty():
		var now := int(Time.get_unix_time_from_system())
		var unique := int(Time.get_ticks_usec())
		result["id"] = "master_creature_%d_%d" % [now, unique]
	Proficiencies.sync_legacy_fields(result, Proficiencies.choices(result))
	Bonuses.migrate_legacy(result, Bonuses.grants(value).is_empty() or not value.has("initiative_base"))
	result["max_hp"] = maxi(0, Bonuses.value(result, "hp"))
	result["armor_class"] = maxi(0, Bonuses.value(result, "ac"))
	result["initiative_base"] = Bonuses.value(result, "ability_mod:dex")
	result["initiative"] = Bonuses.value(result, "initiative")
	result["speed"] = maxi(0, Bonuses.value(result, "speed"))
	return result


static func _normalize_ability_bonuses(value: Variant) -> Dictionary:
	var bonuses: Dictionary = {}
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		bonuses[ability] = clampi(
			int((value as Dictionary).get(ability, 0))
			if value is Dictionary else 0, -30, 30
		)
	return bonuses


static func _normalize_spell_slot_bonuses(value: Variant) -> Array:
	var result: Array = []
	for index: int in range(10):
		var bonus: int = 0
		if value is Array and index < (value as Array).size():
			bonus = clampi(int((value as Array)[index]), -99, 99)
		result.append(bonus)
	return result


static func _normalize_spell_slots(value: Variant) -> Array:
	var result: Array = []
	for i: int in range(10):
		result.append(maxi(0, int((value as Array)[i])) if value is Array and (value as Array).size() > i else 0)
	return result


func _normalize_abilities(value: Variant, stat: Dictionary) -> Dictionary:
	var abilities: Dictionary = CreatureRules.monster_abilities(stat)
	if value is Dictionary:
		for ability: String in abilities.keys():
			abilities[ability] = clampi(
				int((value as Dictionary).get(ability, abilities[ability])), 1, 30
			)
	return abilities


func _default_miniature_id(stat: Dictionary) -> String:
	if not String(stat.get("default_miniature_id", "")).is_empty():
		return String(stat.default_miniature_id)
	var name := String(stat.get("name", "")).strip_edges()
	var source := String(stat.get("source", "")).strip_edges()
	var file := FileAccess.open("res://vtt/data/miniature_bestiary.json", FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return ""
	var entries: Variant = (parsed as Dictionary).get("entries", {})
	if not entries is Dictionary:
		return ""
	for row_value: Variant in (entries as Dictionary).values():
		if not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		var editions: Variant = row.get("editions", {})
		if not editions is Dictionary:
			continue
		for edition_value: Variant in (editions as Dictionary).values():
			if not edition_value is Dictionary:
				continue
			var edition: Dictionary = edition_value as Dictionary
			if (
				String(edition.get("name", "")).nocasecmp_to(name) == 0
				and String(edition.get("source", "")).nocasecmp_to(source) == 0
			):
				return String(row.get("miniature_key", "")).get_file().trim_suffix(".pck")
	return ""


func _default_hp(stat_block: Dictionary) -> int:
	var hp_value: Variant = stat_block.get("hp", {})
	if hp_value is Dictionary:
		var hp: Dictionary = hp_value as Dictionary
		if hp.has("average"):
			return maxi(1, int(hp.get("average", 1)))
		if hp.has("special"):
			var special := String(hp.get("special", ""))
			var regex := RegEx.new()
			if regex.compile("\\d+") == OK:
				var hit := regex.search(special)
				if hit != null:
					return maxi(1, int(hit.get_string()))
	return 1


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
