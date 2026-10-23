extends SceneTree
## Browser test transport for synthetic records only. Never used by the app.
const Host = preload("res://vtt/desktop_sheet_host.gd")
const Archive = preload("res://vtt/creature_archive.gd")
const Bridge = preload("res://vtt/desktop_sheet_archive.gd")
const Shell = preload("res://vtt/desktop_creature_sheet.gd")
const Area = preload("res://vtt/creature_area.gd")
class TestHost extends Host:
	var bridge: RefCounted
	var calls: Array = []
	var file_mode := "success"
	var shell: Node
	var file_path: String
	func _handle_http(client: Dictionary, method: String, path: String, headers: Dictionary, body: PackedByteArray) -> void:
		if path == "/__test/rpc" and method == "POST":
			var request: Dictionary = JSON.parse_string(body.get_string_from_utf8())
			var name := String(request.method)
			calls.append(request)
			var result: Dictionary
			if name == "_test_file_mode":
				file_mode = String(request.args.mode)
				result = {"value": true}
			elif name in ["import", "download"]:
				if file_mode == "cancel": result = {"value": {"canceled": true}}
				elif name == "import":
					var file := FileAccess.open(file_path, FileAccess.WRITE)
					file.store_string(JSON.stringify({"format": "vtt_creature_export_v1", "version": 1, "creature": {"id": "old", "kind": "character", "name": "Importata nella scheda web"}}))
					file.close()
					result = shell._import_paths(PackedStringArray([file_path, "res://project.godot"] if file_mode == "partial" else [file_path]))
				else: result = shell._write_export(file_path.get_base_dir().path_join("missing_dir/export.json") if file_mode == "error" else file_path, String(request.args.text))
			elif name in ["ready", "close", "native", "cast"]: result = {"value": true}
			elif name == "selected": result = {"value": "desktop_browser_fixture"}
			else: result = bridge.dispatch(name, request.get("args", {}))
			result["id"] = request.id
			_answer(client, 200, result)
		elif path == "/__test/calls": _answer(client, 200, {"calls": calls})
		elif path == "/__test/stop":
			_answer(client, 200, {"stopping": true})
			get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
		else: super._handle_http(client, method, path, headers, body)
var host: TestHost
var archive_path: String
var config_path: String

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var archive := Archive.new()
	archive.setup()
	archive_path = "user://desktop_browser_%d.json" % Time.get_ticks_usec()
	config_path = archive_path + ".cfg"
	archive._storage.path = archive_path
	var record: Dictionary = archive.create_character()
	record.id = "desktop_browser_fixture"
	record.name = "Lyria desktop"
	record.max_hp_base = 32
	record.current_hp = 28
	record.abilities = {"str": 12, "dex": 16, "con": 14, "int": 18, "wis": 12, "cha": 10}
	record.additional_traits = "Nota campagna da conservare"
	assert(archive.save(record) == OK)
	host = TestHost.new()
	host.bridge = Bridge.new()
	host.bridge.archive = archive
	host.bridge.settings_path = config_path
	host.shell = Shell.new()
	host.shell.area = Area.new()
	host.shell.area._archive = archive
	host.file_path = archive_path + ".file.json"
	root.add_child(host.shell)
	host.shell.add_child(host.shell.area)
	root.add_child(host)
	assert(host.start() == OK)
	print("DESKTOP_TEST_ORIGIN=" + host.origin())
	await create_timer(150).timeout
	cleanup()
	quit()

func cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path + ".file.json"))

func _finalize() -> void:
	if not archive_path.is_empty(): cleanup()
