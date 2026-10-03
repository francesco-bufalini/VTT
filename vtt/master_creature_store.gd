extends RefCounted

const ROOT_DIR := "user://master_creatures"
const FILE_VERSION := 1

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


func list_creatures() -> Array[Dictionary]:
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
			result.append(normalize_creature(item as Dictionary))
	return result


func save_creatures(creatures: Array[Dictionary]) -> Error:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT_DIR)
	)
	var payload := {
		"version": FILE_VERSION,
		"scope": scope_id(),
		"creatures": creatures
	}
	var file := FileAccess.open(_file_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "  "))
	var error := file.get_error()
	file.close()
	return error


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
