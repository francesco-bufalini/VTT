extends RefCounted

# A document is a homebrew definition (name and text), referenced by ordinary
# inventory rows. Style and date are properties of each owned copy, not the
# shared catalog definition. Documents live in user://homebrew like other brew.
const Catalog = preload("res://vtt/content_catalog.gd")
const ROOT_DIR := "user://homebrew/documents"
const SOURCE := "VTTDOC"
const OWN_PREFIX := "homebrew:vttdoc:documents:"
const MAX_TITLE := 160
const MAX_TEXT := 3500


static func is_document(entry: Dictionary) -> bool:
	return String(entry.get("category", "")) == "documents" or String(entry.get("id", "")).contains(":documents:")


static func definition_for(item: Dictionary) -> Dictionary:
	var identifier: String = String(item.get("id", ""))
	for definition: Dictionary in Catalog.merge("documents", []):
		if String(definition.get("id", "")) == identifier:
			return definition
	return item.duplicate(true)


static func create_document(name: String = "Nuovo documento", description: String = "", legacy_key: String = "") -> Dictionary:
	var local_id: String = "doc_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if not legacy_key.is_empty():
		local_id = "doc_" + legacy_key.sha256_text().substr(0, 28)
	var document_id: String = OWN_PREFIX + local_id
	var file_path: String = ROOT_DIR.path_join(local_id + ".json")
	if not FileAccess.file_exists(file_path):
		if not _write_native(file_path, local_id, name, description):
			return {}
	Catalog.reload_homebrew()
	return {
		"id": document_id,
		"name": name.substr(0, MAX_TITLE),
		"source": SOURCE,
		"category": "documents",
		"quantity": 1,
		"equipped_slots": [],
		"instance_overrides": {},
		"added_at": int(Time.get_unix_time_from_system()),
		"display_style": "pergamena",
		"instance_id": "owned_doc_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	}


static func legacy_id(note: Dictionary) -> String:
	var key: String = String(note.get("id", ""))
	if key.is_empty():
		key = JSON.stringify(note)
	return OWN_PREFIX + "doc_" + key.sha256_text().substr(0, 28)


static func from_legacy(note: Dictionary) -> Dictionary:
	var key: String = String(note.get("id", ""))
	if key.is_empty():
		key = JSON.stringify(note)
	var item: Dictionary = create_document(
		String(note.get("title", "Documento")),
		String(note.get("text", "")),
		key
	)
	if item.is_empty():
		return {}
	item["added_at"] = int(note.get("added_at", note.get("created_at", Time.get_unix_time_from_system())))
	item["display_style"] = "lettera" if String(note.get("style", "")) == "lettera" else "pergamena"
	return item


static func update_definition(item: Dictionary, name: String, description: String) -> bool:
	var identifier: String = String(item.get("id", ""))
	var title: String = name.strip_edges().substr(0, MAX_TITLE)
	if title.is_empty():
		title = "Senza titolo"
	var body: String = description.substr(0, MAX_TEXT)
	var path: String = ""
	var payload: Dictionary = {}
	if identifier.begins_with(OWN_PREFIX):
		var local_id: String = identifier.trim_prefix(OWN_PREFIX)
		if local_id.is_empty() or "/" in local_id or "\\" in local_id:
			return false
		path = ROOT_DIR.path_join(local_id + ".json")
		if FileAccess.file_exists(path):
			payload = _native_package(local_id, title, body)
		else:
			# A separately installed pack can also use this source prefix.
			# Preserve that pack and create a local override instead.
			path = ""
	if path.is_empty():
		# A document supplied by another homebrew pack is edited through a
		# local override: its original file and stable ID remain untouched.
		if identifier.is_empty():
			return false
		var local_id: String = "edit_" + identifier.sha256_text().substr(0, 28)
		path = ROOT_DIR.path_join("_overrides").path_join(local_id + ".json")
		payload = {
			"schema_version": 1,
			"namespace": "docedit",
			"entries": [{
				"category": "documents",
				"id": local_id,
				"name": title,
				"source": String(item.get("source", SOURCE)),
				"overrides": identifier,
				"data": {"description": body}
			}]
		}
	if not _write_json(path, payload):
		return false
	Catalog.reload_homebrew()
	return true


static func _native_package(local_id: String, name: String, description: String) -> Dictionary:
	return {
		"_meta": {
			"sources": [{
				"json": SOURCE,
				"full": "Documenti del VTT",
				"abbreviation": SOURCE
			}]
		},
		"document": [{
			"id": local_id,
			"name": name.substr(0, MAX_TITLE),
			"source": SOURCE,
			"description": description.substr(0, MAX_TEXT)
		}]
	}


static func _write_native(path: String, local_id: String, name: String, description: String) -> bool:
	return _write_json(path, _native_package(local_id, name, description))


static func _write_json(path: String, payload: Dictionary) -> bool:
	var err: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if err != OK:
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK
