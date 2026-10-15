extends RefCounted

# Inbound inventory gifts survive a closed sheet/app. Delivery IDs remain
# in a bounded seen history after pickup so UDP retries never duplicate items.
const PATH := "user://received_items.json"
const MAX_PENDING := 200
const MAX_SEEN := 500


static func _state() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {"pending": [], "seen": []}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if raw is Dictionary and raw.get("pending") is Array and raw.get("seen") is Array:
		return raw
	return {"pending": [], "seen": []}


static func pending() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Variant in _state().get("pending", []):
		if raw is Dictionary:
			rows.append((raw as Dictionary).duplicate(true))
	return rows


static func receive(transfer: Dictionary) -> bool:
	var id: String = String(transfer.get("id", ""))
	if id.is_empty() or id.length() > 120 or not transfer.get("item") is Dictionary:
		return false
	if not transfer.get("definitions", []) is Array:
		return false
	var saved: Dictionary = transfer.get("item", {})
	if String(saved.get("id", "")).is_empty() or String(saved.get("name", "")).is_empty():
		return false
	var doc := _state()
	var seen: Array = doc["seen"]
	if id in seen:
		return true
	var rows: Array = doc["pending"]
	if rows.size() >= MAX_PENDING:
		return false # Never silently discard an uncollected gift.
	rows.append(transfer.duplicate(true))
	seen.append(id)
	while seen.size() > MAX_SEEN:
		seen.remove_at(0)
	return _write(doc)


static func take_all() -> Array[Dictionary]:
	var doc := _state()
	var items: Array[Dictionary] = pending()
	if items.is_empty():
		return items
	doc["pending"] = []
	return items if _write(doc) else []


static func requeue(transfer: Dictionary) -> bool:
	var doc := _state()
	var rows: Array = doc["pending"]
	var id: String = String(transfer.get("id", ""))
	for existing: Variant in rows:
		if existing is Dictionary and String(existing.get("id", "")) == id:
			return true
	if rows.size() >= MAX_PENDING:
		return false
	rows.append(transfer.duplicate(true))
	return _write(doc)


static func _write(doc: Dictionary) -> bool:
	var path: String = ProjectSettings.globalize_path(PATH)
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(doc, "  "))
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp)
		return false
	var moved: Error = DirAccess.rename_absolute(temp, path)
	if moved == OK:
		return true
	if not FileAccess.file_exists(path):
		DirAccess.remove_absolute(temp)
		return false
	var backup: String = path + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if DirAccess.rename_absolute(path, backup) != OK:
		DirAccess.remove_absolute(temp)
		return false
	moved = DirAccess.rename_absolute(temp, path)
	if moved != OK:
		DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temp)
		return false
	DirAccess.remove_absolute(backup)
	return true
