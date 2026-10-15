extends RefCounted

const PATH := "user://received_documents.json"
const MAX_DOCUMENTS := 200


static func pending() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return result
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if value is Array:
		for raw: Variant in value:
			if raw is Dictionary:
				result.append((raw as Dictionary).duplicate(true))
	return result


static func receive(document: Dictionary) -> bool:
	# A damaged inbox must remain recoverable, never be replaced by [] plus
	# the newest packet. Let the sender retry without acknowledging it.
	if FileAccess.file_exists(PATH):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(PATH)) != OK or not parser.data is Array:
			return false
	var rows: Array[Dictionary] = pending()
	var id: String = String(document.get("id", ""))
	if id.is_empty():
		return false
	for row: Dictionary in rows:
		if String(row.get("id", "")) == id:
			return true
	if rows.size() >= MAX_DOCUMENTS:
		return false # Never evict an acknowledged delivery to accept a new one.
	rows.append(document.duplicate(true))
	return _write(rows)


# Called only with an inventory that has successfully reached the archive.
# Until then the inbox remains the durable owner of each delivery.
static func acknowledge_inventory(inventory: Array) -> bool:
	var documents = load("res://vtt/document_homebrew.gd")
	var owned: Dictionary = {}
	for item: Variant in inventory:
		if item is Dictionary:
			owned[String(item.get("id", ""))] = true
	var rows: Array[Dictionary] = pending()
	var retained: Array[Dictionary] = []
	for note: Dictionary in rows:
		if not owned.has(documents.legacy_id(note)):
			retained.append(note)
	return retained.size() == rows.size() or _write(retained)


static func take_all() -> Array[Dictionary]:
	var rows: Array[Dictionary] = pending()
	if rows.is_empty():
		return rows
	if not _write([]):
		return []
	return rows


static func _write(documents: Array[Dictionary]) -> bool:
	var temporary: String = PATH + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(documents, "  "))
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	var temp_path: String = ProjectSettings.globalize_path(temporary)
	var final_path: String = ProjectSettings.globalize_path(PATH)
	var moved: Error = DirAccess.rename_absolute(temp_path, final_path)
	if moved == OK:
		return true
	# On Windows an existing inbox may not be replaceable directly. Keep
	# the previous file recoverable until the new version is in place.
	if not FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(temp_path)
		return false
	var backup: String = final_path + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if DirAccess.rename_absolute(final_path, backup) != OK:
		DirAccess.remove_absolute(temp_path)
		return false
	moved = DirAccess.rename_absolute(temp_path, final_path)
	if moved != OK:
		DirAccess.rename_absolute(backup, final_path)
		DirAccess.remove_absolute(temp_path)
		return false
	DirAccess.remove_absolute(backup)
	return true
