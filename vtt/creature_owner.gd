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


static func public_identity(record: Dictionary) -> Dictionary:
	return {
		"creature_id": String(record.get("id", "")),
		"owner_id": String(record.get("owner_id", local_id())),
		"default_miniature_id": String(
			record.get("default_miniature_id", "")
		)
	}
