extends SceneTree
const Store = preload("res://network/pwa_backup_store.gd")
var store := Store.new()
var owner := "ab".repeat(16)
var secret := "cd".repeat(32)
var fixture_root := "user://pwa_backup_store_test_%d" % Time.get_ticks_usec()
func _initialize() -> void:
	call_deferred("run")
func call_store(route: String, payload: Dictionary) -> Dictionary:
	return store.handle(route, JSON.stringify(payload).to_utf8_buffer())
func publish(delta: Dictionary, base: String = "") -> Dictionary:
	var text := JSON.stringify(delta)
	var request := {"owner": owner, "key": secret, "upload": Crypto.new().generate_random_bytes(16).hex_encode(),
		"base": base, "size": text.to_utf8_buffer().size(), "parts": 1, "sha256": text.sha256_text(),
		"index": 0, "data": Marshalls.raw_to_base64(text.to_utf8_buffer())}
	var uploaded := call_store("chunk", request)
	if uploaded.status != 200:
		return uploaded
	return call_store("commit", request)
func delta(revision: int = 1) -> Dictionary:
	return {"version": 1, "upserts": [{"record": {"scope": "default", "type": "creature", "id": "one",
		"revision": revision, "updatedAt": 1, "data": {"name": "Lyria", "owner_id": owner}}, "hash": "ef".repeat(32)}],
		"deletes": [], "blobs": [], "blob_digests": [], "outbox": [], "outbox_hash": "[]".sha256_text()}
func cleanup(path: String) -> void:
	assert(path == fixture_root or path.begins_with(fixture_root + "/"))
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
	for name in DirAccess.get_directories_at(path):
		cleanup(path.path_join(name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func run() -> void:
	store.root_path = fixture_root
	var auth := {"owner": owner, "key": secret}
	assert(call_store("manifest", auth).data.records.is_empty())
	assert(call_store("manifest", {"owner": "../escape", "key": secret}).status == 400)
	var first := publish(delta())
	assert(first.status == 200, str(first))
	var manifest := call_store("manifest", auth)
	assert(manifest.status == 200 and manifest.data.records.size() == 1)
	assert(call_store("manifest", {"owner": owner, "key": "00".repeat(32)}).status == 403)
	assert(call_store("download", auth).status == 404)
	var old_generation: String = manifest.data.generation
	assert(publish(delta(2), "").status == 409, "Stale clients cannot overwrite the latest backup")
	var invalid := delta(2)
	invalid.blobs = [{"digest": "00".repeat(32), "mime": "text/plain", "base64": Marshalls.raw_to_base64("corrupt".to_utf8_buffer())}]
	assert(publish(invalid, old_generation).status == 400)
	assert(call_store("manifest", auth).data.generation == old_generation)
	var empty := delta()
	empty.upserts = []
	empty.deletes = [["default", "creature", "one"]]
	assert(publish(empty, old_generation).status == 409)
	assert(call_store("manifest", auth).data.generation == old_generation)
	for revision in range(2, 14):
		var current: Dictionary = call_store("manifest", auth).data
		var result := publish(delta(revision), current.generation)
		assert(result.status == 200, str(result))
	var folder := fixture_root.path_join(owner)
	var files := DirAccess.get_files_at(folder)
	var backups := 0
	for filename: String in files:
		if filename.begins_with("backup-"):
			backups += 1
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(filename)))
			assert(saved is Dictionary and saved.format == "vtt-pwa-backup")
			assert(not JSON.stringify(saved).contains(secret))
	assert(backups == Store.VERSIONS)
	var valid_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("index.json")))
	var damaged := FileAccess.open(folder.path_join(valid_index.file), FileAccess.WRITE)
	damaged.store_string("damaged")
	damaged.close()
	assert(call_store("manifest", auth).status == 500, "Never report a damaged backup as current")
	cleanup(fixture_root)
	print("PASS: durable PWA backups, credentials, stale/invalid/empty protection and version retention")
	quit()
