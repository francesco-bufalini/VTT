extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var archive = preload("res://vtt/creature_archive.gd").new()
	archive.setup()
	archive._storage.path = "user://test_creature_json_import_%d.json" % Time.get_ticks_usec()
	var sheet = preload("res://vtt/creature_area.gd").new()
	sheet._archive = archive
	var paths := OS.get_cmdline_user_args()
	var fixture := "user://test_creature_json_fixture.json"
	if paths.is_empty():
		var file := FileAccess.open(fixture, FileAccess.WRITE)
		file.store_string(JSON.stringify({"format": "vtt_creature_export_v1", "version": 1, "creature": {"id": "legacy_id", "kind": "character", "name": "Legacy", "abilities": {"str": 12, "dex": 14, "con": 16, "int": 11, "wis": 18, "cha": 10}}}))
		file.close()
		paths.append(fixture)
	for path: String in paths:
		var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(sheet._import_export_path(path) == OK)
		var matches: Array[Dictionary] = []
		for record: Dictionary in archive.list_owned():
			if record.name == payload.creature.name:
				matches.append(record)
		assert(matches.size() == 1)
		assert(matches[0].id != payload.creature.id)
		for ability: String in payload.creature.abilities:
			assert(int(matches[0].abilities[ability]) == int(payload.creature.abilities[ability]))
		assert(matches[0].linked_token_sync_id == "")
		assert(matches[0].owner_id == preload("res://vtt/creature_owner.gd").local_id())
	assert(sheet._import_export_path("res://project.godot") == ERR_INVALID_DATA)
	for key: String in ["identity", "physique", "progression", "talents", "biography"]:
		assert(preload("res://vtt/creature_sheet_style.gd").icon("info_" + key) != null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive._storage.path))
	if FileAccess.file_exists(fixture):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	sheet.free()
	print("PASS: legacy creature JSON import, independent IDs, abilities, ownership and Info icons")
	quit()
