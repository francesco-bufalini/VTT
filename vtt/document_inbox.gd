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
	var rows: Array[Dictionary] = pending()
	var id: String = String(document.get("id", ""))
	if id.is_empty():
		return false
	for row: Dictionary in rows:
		if String(row.get("id", "")) == id:
			return true
	rows.append(document.duplicate(true))
	while rows.size() > MAX_DOCUMENTS:
		rows.remove_at(0)
	return _write(rows)


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
