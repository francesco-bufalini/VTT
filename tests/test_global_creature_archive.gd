extends SceneTree

const Storage = preload("res://vtt/creature_local_storage.gd")
const Archive = preload("res://vtt/creature_archive.gd")
const Owner = preload("res://vtt/creature_owner.gd")

class DummyCampaign extends Node:
	var selected_campaign_group_id := "campaign_A"
	var active_campaign_id := "scenario_A"

class DummyScene extends Node:
	func get_embedded_creature_records() -> Array[Dictionary]:
		return [{"kind": "monster", "id": "baked-1", "name": "Baked guardian",
			"stat_block": {"name": "Baked guardian", "hp": {"average": 12}}}]

func _initialize() -> void:
	call_deferred("_run")

func _write_json(path: String, data: Dictionary) -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data))
	file.close()

func _run() -> void:
	var dir := "user://tests/global_archive_%d" % Time.get_ticks_usec()
	var unified := dir.path_join("creatures.json")
	var old_characters := dir.path_join("legacy_characters")
	var old_monsters := dir.path_join("legacy_monsters")
	var local_owner := Owner.local_id()
	var character_a := {"id": "same-id", "name": "First", "owner_id": local_owner,
		"transfer_revision": 0}
	var character_b := character_a.duplicate(true)
	character_b["name"] = "Second"
	var monster := {"id": "same-id", "name": "Monster", "owner_id": local_owner,
		"transfer_revision": 0, "stat_block": {"name": "Monster", "hp": {"average": 5}}}
	_write_json(old_characters.path_join("default.json"), {"version": 3, "characters": [character_a]})
	_write_json(old_characters.path_join("campaign_A.json"), {"version": 3, "characters": [character_b]})
	_write_json(old_monsters.path_join("scenario_A.json"), {"version": 2, "creatures": [monster]})
	var storage := Storage.new()
	storage.path = unified
	storage.migration_sources = [
		{"dir": old_characters, "key": "characters", "kind": "character"},
		{"dir": old_monsters, "key": "creatures", "kind": "monster"}
	]
	var rows: Array[Dictionary] = storage.list_records()
	assert(rows.size() == 3, "All old scopes and kinds must migrate, without losing conflicts")
	var ids := {}
	for row: Dictionary in rows:
		assert(not ids.has(String(row["id"])), "IDs must be globally unique")
		ids[String(row["id"])] = true
	assert(FileAccess.file_exists(unified), "First access must materialize the global archive")
	var originals := FileAccess.get_file_as_string(old_characters.path_join("default.json"))
	assert(not originals.is_empty(), "Migration must keep original files")
	var character_rows := storage.list_records("character")
	assert(character_rows.size() == 2)
	var deleted_id := String(character_rows[0]["id"])
	character_rows.remove_at(0)
	assert(storage.save_records("character", character_rows) == OK)
	assert(storage.list_records().size() == 2, "Removing a character must not remove a monster")
	var reloaded := Storage.new()
	reloaded.path = unified
	reloaded.migration_sources = storage.migration_sources
	assert(reloaded.list_records("character").size() == 1, "Deleted sheets must not be reimported from old scopes")
	assert(String(reloaded.list_records("character")[0]["id"]) != deleted_id)
	# Stale revisions must fail even when another creature kind shares the file.
	var current: Dictionary = reloaded.list_records("character")[0]
	current["transfer_revision"] = 2
	assert(reloaded.upsert(current) == OK)
	var stale := current.duplicate(true)
	stale["transfer_revision"] = 0
	assert(reloaded.upsert(stale) == ERR_UNAUTHORIZED)
	var remote := current.duplicate(true)
	remote["owner_id"] = "remote-owner-0123456789"
	remote["transfer_revision"] = 3
	assert(reloaded.upsert(remote, true) == OK)
	assert(reloaded.list_records("monster").size() == 1)
	assert(reloaded.delete_record(current) == ERR_UNAUTHORIZED, "Local deletion cannot touch transferred sheets")
	# Switching campaigns must have no influence on local creatures.
	var campaign := DummyCampaign.new()
	root.add_child(campaign)
	var archive := Archive.new()
	archive.setup(campaign)
	archive._storage.path = unified
	archive._characters.archive_path = unified
	archive._monsters.archive_path = unified
	assert(archive.list_owned().size() == 1)
	campaign.selected_campaign_group_id = "campaign_B"
	campaign.active_campaign_id = "scenario_B"
	assert(archive.list_owned().size() == 1)
	# Scene records are opt-in, read-only and never exposed by list_owned().
	var scene := DummyScene.new()
	root.add_child(scene)
	var embedded := archive.scene_records_from(scene)
	assert(embedded.size() == 1)
	assert(embedded[0].get("_storage_origin") == "scene")
	assert(archive.save(embedded[0]) == ERR_UNAUTHORIZED)
	assert(archive.list_owned().size() == 1)
	assert(reloaded.list_records().size() == 2)
	# A damaged global archive must not be silently replaced with an empty one.
	var broken := Storage.new()
	broken.path = dir.path_join("broken.json")
	_write_json(broken.path, {"version": 42, "creatures": []})
	assert(broken.upsert({"kind": "monster", "id": "x"}) == ERR_FILE_CORRUPT)
	assert(JSON.parse_string(FileAccess.get_file_as_string(broken.path)).get("version") == 42)
	scene.free()
	campaign.free()
	for filename: String in ["default.json", "campaign_A.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_characters.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_monsters.path_join("scenario_A.json")))
	for filename: String in ["creatures.json", "broken.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_characters))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_monsters))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	print("PASS: global archive migration, conflicts, campaign independence, ownership and scene hook")
	quit()
