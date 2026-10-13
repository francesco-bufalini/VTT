extends RefCounted

# Local installation identity. Never use display names as permission keys.
# Not a security credential: the VTT LAN transport is not authenticated.
const ID_PATH := "user://creature_owner_id.txt"

static func local_id() -> String:
	if FileAccess.file_exists(ID_PATH):
		var file := FileAccess.open(ID_PATH, FileAccess.READ)
		if file != null:
			var saved := file.get_as_text().strip_edges()
			file.close()
			if saved.length() >= 16:
				return saved
	var crypto := Crypto.new()
	var fresh := crypto.generate_random_bytes(16).hex_encode()
	var file := FileAccess.open(ID_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(fresh)
		file.close()
	return fresh


static func is_owner(record: Dictionary) -> bool:
	var owner := String(record.get("owner_id", "")).strip_edges()
	return owner.is_empty() or owner == local_id()


static func can_edit(record: Dictionary, persisted: Dictionary) -> bool:
	# A sheet cached before an ownership round-trip cannot overwrite or
	# delete the newer sheet, even when the local owner ID matches again.
	return is_owner(record) and (
		persisted.is_empty() or (
			is_owner(persisted)
			and int(record.get("transfer_revision", 0)) == int(persisted.get("transfer_revision", 0))
		)
	)


static func public_identity(record: Dictionary) -> Dictionary:
	return {
		"creature_id": String(record.get("id", "")),
		"owner_id": String(record.get("owner_id", local_id())),
		"default_miniature_id": String(
			record.get("default_miniature_id", "")
		)
	}

# Preserve records transferred away from this installation. A conflicting
# stale local record must not overwrite the persisted owner or revision.
static func merge_transferred_records(merged: Array[Dictionary], saved_value: Variant, allow_transfer: bool) -> Error:
	if not saved_value is Array:
		return OK
	for raw: Variant in saved_value as Array:
		if not raw is Dictionary:
			continue
		var stored: Dictionary = raw as Dictionary
		for candidate: Dictionary in merged:
			if String(candidate.get("id", "")) != String(stored.get("id", "")):
				continue
			if not allow_transfer and (not can_edit(candidate, stored) or String(candidate.get("owner_id", "")) != String(stored.get("owner_id", local_id()))):
				return ERR_UNAUTHORIZED
		if is_owner(stored):
			continue
		var exists := false
		for visible: Dictionary in merged:
			if String(visible.get("id", "")) == String(stored.get("id", "")):
				exists = true
				break
		if not exists:
			merged.append(stored.duplicate(true))
	return OK



# Both creature archives use the same stable campaign/scenario filename scope.
static func storage_scope_id(campaign_manager: Node) -> String:
	if campaign_manager != null and is_instance_valid(campaign_manager):
		var campaign_group_id: String = String(
			campaign_manager.get("selected_campaign_group_id")
		).strip_edges()
		if not campaign_group_id.is_empty():
			return "campaign_" + _safe_id(campaign_group_id)

		var active_campaign_id: String = String(
			campaign_manager.get("active_campaign_id")
		).strip_edges()
		if not active_campaign_id.is_empty():
			return "scenario_" + _safe_id(active_campaign_id)

	return "default"


static func _safe_id(value: String) -> String:
	var result := ""
	for character: String in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		elif character in ["-", "_"]:
			result += character
		else:
			result += "_"
	return result
