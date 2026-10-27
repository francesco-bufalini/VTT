extends RefCounted
## Durable recovery copies owned by PwaHost. Public operations are serialized
## on background workers; never call this disk/JSON API from the game frame.
const ROOT := "user://pwa_backups"
const CHUNK_BYTES := 64 * 1024
const MAX_BYTES := 128 * 1024 * 1024
const VERSIONS := 10
var root_path := ROOT
var _mutex := Mutex.new()
var _uploads: Dictionary = {}

func handle(route: String, body: PackedByteArray) -> Dictionary:
	_mutex.lock()
	var result := _handle(route, body)
	_mutex.unlock()
	return result

func _result(code: int, data: Dictionary) -> Dictionary:
	return {"status": code, "data": data}

func _error(code: int, message: String) -> Dictionary:
	return _result(code, {"error": message})

func _hex(value: Variant, length: int) -> bool:
	return value is String and value.length() == length and value.is_valid_hex_number() and value == value.to_lower()

func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _folder(owner: String) -> String:
	return root_path.path_join(owner)

func _index(owner: String) -> Dictionary:
	var path := _folder(owner).path_join("index.json")
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or not _hex(value.get("key_hash"), 64) or not _hex(value.get("generation"), 64) or \
		not value.get("records") is Array or not value.get("blobs") is Array or not value.get("history") is Array or \
		not _hex(value.get("outbox_hash"), 64) or not value.get("saved_at") is String:
		return {"invalid": true}
	var filename: String = str(value.get("file", ""))
	if filename != filename.get_file() or not filename.begins_with("backup-") or not filename.ends_with(".json"):
		return {"invalid": true}
	for old_file: Variant in value.history:
		if not old_file is String or old_file != old_file.get_file() or not old_file.begins_with("backup-") or not old_file.ends_with(".json"):
			return {"invalid": true}
	for record: Variant in value.records:
		if not record is Dictionary or _record_key(record.get("key")).is_empty() or not _hex(record.get("hash"), 64):
			return {"invalid": true}
	for digest: Variant in value.blobs:
		if not _hex(digest, 64):
			return {"invalid": true}
	return value

func _atomic(path: String, text: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if err != OK:
		return err
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	err = file.get_error()
	file.close()
	if err != OK:
		return err
	if FileAccess.get_file_as_string(path + ".tmp") != text:
		return ERR_FILE_CORRUPT
	return DirAccess.rename_absolute(absolute + ".tmp", absolute)

func _expire() -> void:
	var partials := root_path.path_join(".uploads")
	var filenames := DirAccess.get_files_at(partials) if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(partials)) else PackedStringArray()
	for filename: String in filenames:
		var ids := filename.trim_suffix(".part").split("_")
		if filename.ends_with(".part") and ids.size() == 2 and _hex(ids[0], 32) and _hex(ids[1], 32):
			var path := partials.path_join(filename)
			if FileAccess.get_modified_time(path) < int(Time.get_unix_time_from_system()) - 15 * 60:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var cutoff := Time.get_ticks_msec() - 15 * 60 * 1000
	for id: String in _uploads.keys():
		if int(_uploads[id].seen) < cutoff:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_uploads[id].path))
			_uploads.erase(id)

func _handle(route: String, body: PackedByteArray) -> Dictionary:
	if route not in ["manifest", "chunk", "commit"]:
		return _error(404, "unknown_backup_operation")
	if body.size() > 100000:
		return _error(413, "backup_chunk_too_large")
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return _error(400, "invalid_backup_json")
	var request: Dictionary = parsed
	if not _hex(request.get("owner"), 32) or not _hex(request.get("key"), 64):
		return _error(400, "invalid_backup_identity")
	var owner: String = request.owner
	var key_hash: String = request.key.sha256_text()
	var index := _index(owner)
	if index.get("invalid", false):
		return _error(500, "backup_index_damaged_previous_files_preserved")
	if not index.is_empty() and index.key_hash != key_hash:
		return _error(403, "backup_device_credential_mismatch")
	if route == "manifest":
		if not index.is_empty() and FileAccess.get_sha256(_folder(owner).path_join(index.file)) != index.generation:
			return _error(500, "backup_archive_damaged_previous_files_preserved")
		return _result(200, {"generation": index.get("generation", ""),
			"records": index.get("records", []), "blobs": index.get("blobs", []),
			"outbox_hash": index.get("outbox_hash", ""), "saved_at": index.get("saved_at", "")})
	if not _hex(request.get("upload"), 32) or not _hex(request.get("sha256"), 64) or \
		not request.get("base", null) is String:
		return _error(400, "invalid_backup_upload")
	var size := int(request.get("size", 0))
	var parts := int(request.get("parts", 0))
	if size < 1 or size > MAX_BYTES or parts != int(ceil(float(size) / CHUNK_BYTES)):
		return _error(413, "invalid_backup_size")
	if request.base != index.get("generation", ""):
		return _error(409, "backup_generation_changed_retry")
	_expire()
	var id: String = owner + "_" + request.upload
	if route == "chunk":
		var position := int(request.get("index", -1))
		var encoded: Variant = request.get("data")
		if position < 0 or position >= parts or not encoded is String or encoded.length() > 87400:
			return _error(400, "invalid_backup_chunk")
		var bytes := Marshalls.base64_to_raw(encoded)
		if bytes.size() != mini(CHUNK_BYTES, size - position * CHUNK_BYTES) or Marshalls.raw_to_base64(bytes) != encoded:
			return _error(400, "invalid_backup_chunk_encoding")
		if not _uploads.has(id):
			if position != 0:
				return _error(409, "backup_upload_not_started")
			# A failed attempt may be replaced only for the same authorized device.
			for other: String in _uploads.keys():
				if _uploads[other].owner == owner:
					if _uploads[other].key_hash != key_hash:
						return _error(403, "backup_device_credential_mismatch")
					DirAccess.remove_absolute(ProjectSettings.globalize_path(_uploads[other].path))
					_uploads.erase(other)
			if _uploads.size() >= 4:
				return _error(429, "backup_queue_full")
			var path := root_path.path_join(".uploads").path_join(id + ".part")
			var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
			if err != OK:
				return _error(500, "backup_storage_unavailable")
			var fresh := FileAccess.open(path, FileAccess.WRITE)
			if fresh == null:
				return _error(500, "backup_storage_unavailable")
			fresh.close()
			_uploads[id] = {"owner": owner, "key_hash": key_hash, "base": request.base,
				"size": size, "parts": parts, "sha256": request.sha256, "next": 0,
				"path": path, "seen": Time.get_ticks_msec()}
		var pending: Dictionary = _uploads[id]
		if not _matches(pending, request, key_hash):
			return _error(409, "backup_upload_collision")
		var file := FileAccess.open(pending.path, FileAccess.READ_WRITE)
		if file == null:
			return _error(500, "backup_partial_file_unavailable")
		if position < int(pending.next):
			file.seek(position * CHUNK_BYTES)
			var same := file.get_buffer(bytes.size()) == bytes
			file.close()
			return _result(200, {"accepted": position}) if same else _error(409, "backup_chunk_mismatch")
		if position != int(pending.next) or file.get_length() != position * CHUNK_BYTES:
			file.close()
			return _error(409, "backup_chunk_out_of_order")
		file.seek_end()
		file.store_buffer(bytes)
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			return _error(500, "backup_write_failed")
		pending.next = position + 1
		pending.seen = Time.get_ticks_msec()
		return _result(200, {"accepted": position})
	if not _uploads.has(id):
		return _error(409, "backup_upload_not_started")
	var pending: Dictionary = _uploads[id]
	if not _matches(pending, request, key_hash) or pending.next != parts:
		return _error(409, "backup_upload_incomplete")
	var bytes := FileAccess.get_file_as_bytes(pending.path)
	if bytes.size() != size or _sha(bytes) != request.sha256:
		return _error(400, "backup_checksum_mismatch")
	var delta: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not delta is Dictionary:
		return _error(400, "invalid_backup_delta")
	var result := _commit(owner, key_hash, index, delta)
	if result.status == 200:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending.path))
		_uploads.erase(id)
	return result

func _matches(pending: Dictionary, request: Dictionary, key_hash: String) -> bool:
	return pending.key_hash == key_hash and pending.base == request.base and pending.size == request.size and \
		pending.parts == request.parts and pending.sha256 == request.sha256

func _record_key(value: Variant) -> String:
	if not value is Array or value.size() != 3:
		return ""
	for part: Variant in value:
		if not part is String or part.is_empty() or part.length() > 256:
			return ""
	return JSON.stringify(value)

func _commit(owner: String, key_hash: String, index: Dictionary, delta: Dictionary) -> Dictionary:
	if delta.get("version") != 1 or not delta.get("upserts") is Array or not delta.get("deletes") is Array or \
		not delta.get("blobs") is Array or not delta.get("blob_digests") is Array or \
		not delta.get("outbox") is Array or not _hex(delta.get("outbox_hash"), 64):
		return _error(400, "invalid_backup_delta")
	var previous: Dictionary = {"records": [], "blobs": []}
	if not index.is_empty():
		var text := FileAccess.get_file_as_string(_folder(owner).path_join(index.file))
		if text.sha256_text() != index.generation:
			return _error(500, "backup_archive_damaged_previous_files_preserved")
		var parsed: Variant = JSON.parse_string(text)
		if not parsed is Dictionary or not parsed.get("records") is Array or not parsed.get("blobs") is Array:
			return _error(500, "backup_archive_damaged_previous_files_preserved")
		previous = parsed
	var records := {}
	var hashes := {}
	for row: Dictionary in previous.records:
		records[JSON.stringify([row.scope, row.type, row.id])] = row
	for item: Dictionary in index.get("records", []):
		hashes[JSON.stringify(item.key)] = item.hash
	var changed_keys := {}
	for value: Variant in delta.deletes:
		var id := _record_key(value)
		if id.is_empty() or changed_keys.has(id):
			return _error(400, "invalid_backup_record_key")
		changed_keys[id] = true
		records.erase(id)
		hashes.erase(id)
	for value: Variant in delta.upserts:
		if not value is Dictionary or not value.get("record") is Dictionary or not _hex(value.get("hash"), 64):
			return _error(400, "invalid_backup_record")
		var row: Dictionary = value.record
		var id := _record_key([row.get("scope"), row.get("type"), row.get("id")])
		if not (row.get("revision") is int or row.get("revision") is float):
			return _error(400, "invalid_backup_record_revision")
		var revision: float = float(row.get("revision", 0))
		if id.is_empty() or changed_keys.has(id) or not row.has("data") or revision < 1 or revision >= 9007199254740991.0 or revision != floor(revision):
			return _error(400, "invalid_backup_record")
		changed_keys[id] = true
		records[id] = row
		hashes[id] = value.hash
	if records.is_empty():
		return _error(409, "empty_backup_previous_copy_preserved")
	var blobs := {}
	for item: Dictionary in previous.blobs:
		blobs[item.digest] = item
	for value: Variant in delta.blobs:
		if not value is Dictionary or not _hex(value.get("digest"), 64) or not value.get("base64") is String or not value.get("mime") is String:
			return _error(400, "invalid_backup_attachment")
		var raw := Marshalls.base64_to_raw(value.base64)
		if _sha(raw) != value.digest or Marshalls.raw_to_base64(raw) != value.base64:
			return _error(400, "backup_attachment_checksum_mismatch")
		blobs[value.digest] = value
	var retained := {}
	for digest: Variant in delta.blob_digests:
		if not _hex(digest, 64) or not blobs.has(digest) or retained.has(digest):
			return _error(400, "backup_attachment_missing_or_duplicate")
		retained[digest] = blobs[digest]
	for row: Dictionary in records.values():
		if row.has("digest") and not retained.has(row.digest):
			return _error(400, "backup_attachment_reference_missing")
	var action_ids := {}
	for action: Variant in delta.outbox:
		if not action is Dictionary or _record_key([action.get("id"), action.get("scope"), action.get("action")]).is_empty() or action_ids.has(action.id):
			return _error(400, "invalid_backup_outbox")
		action_ids[action.id] = true
	var saved_at := Time.get_datetime_string_from_system(true) + "Z"
	var archive := JSON.stringify({"format": "vtt-pwa-backup", "version": 1,
		"createdAt": saved_at, "owner_id": owner, "records": records.values(),
		"blobs": retained.values(), "outbox": delta.outbox})
	if archive.to_utf8_buffer().size() > MAX_BYTES:
		return _error(413, "backup_archive_too_large")
	var generation := archive.sha256_text()
	var filename := "backup-%016d-%s-%s.json" % [int(Time.get_unix_time_from_system() * 1000), generation.left(16), Crypto.new().generate_random_bytes(4).hex_encode()]
	var folder := _folder(owner)
	if FileAccess.file_exists(folder.path_join(filename)) or _atomic(folder.path_join(filename), archive) != OK:
		return _error(500, "backup_archive_write_failed")
	var manifest_records := []
	for row: Dictionary in records.values():
		var key := [row.scope, row.type, row.id]
		manifest_records.append({"key": key, "hash": hashes[JSON.stringify(key)]})
	var history: Array = index.get("history", []).duplicate()
	history.push_front(filename)
	var keep := history.slice(0, VERSIONS)
	var metadata := {"key_hash": key_hash, "generation": generation, "file": filename,
		"history": keep, "records": manifest_records, "blobs": retained.keys(),
		"outbox_hash": delta.outbox_hash, "saved_at": saved_at}
	if _atomic(folder.path_join("index.json"), JSON.stringify(metadata)) != OK:
		return _error(500, "backup_index_write_failed")
	for expired: String in history.slice(VERSIONS):
		if expired == expired.get_file() and expired.begins_with("backup-") and expired.ends_with(".json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(expired)))
	return _result(200, {"generation": generation, "saved_at": saved_at})
