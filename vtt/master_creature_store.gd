extends RefCounted

const CreatureRules = preload("res://vtt/creature_rules.gd")
const CreatureOwner = preload("res://vtt/creature_owner.gd")

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
						if not allow_transfer and (not CreatureOwner.is_owner(stored) or String(candidate.get("owner_id", "")) != String(stored.get("owner_id", CreatureOwner.local_id()))):
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
		"current_hp": hp,
		"armor_class": CreatureRules.monster_armor_class(stat_block),
		"abilities": CreatureRules.monster_abilities(stat_block),
		"owner_id": CreatureOwner.local_id(),
		"default_miniature_id": _default_miniature_id(stat_block),
		"stat_block": stat_block.duplicate(true),
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
		"current_hp": int(value.get("current_hp", fallback_hp)),
		"stat_block": stat_block,
		"conditions": value.get("conditions", []).duplicate() if value.get("conditions", []) is Array else [],
		"transfer_revision": maxi(0, int(value.get("transfer_revision", 0))),
		"owner_id": String(value.get("owner_id", CreatureOwner.local_id())),
		"default_miniature_id": String(value.get("default_miniature_id", _default_miniature_id(stat_block))),
		"armor_class": maxi(0, int(value.get("armor_class", CreatureRules.monster_armor_class(stat_block)))),
		"abilities": _normalize_abilities(value.get("abilities", {}), stat_block),
		"linked_token_sync_id": String(
			value.get("linked_token_sync_id", "")
		),
		"linked_token_name": String(value.get("linked_token_name", ""))
	}
	if String(result["id"]).is_empty():
		var now := int(Time.get_unix_time_from_system())
		var unique := int(Time.get_ticks_usec())
		result["id"] = "master_creature_%d_%d" % [now, unique]
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
