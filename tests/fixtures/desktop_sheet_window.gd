extends SceneTree
## Interactive smoke fixture. Uses a disposable archive, never personal sheets.
class Board extends Node3D:
	func release_camera_control() -> void: pass
	func capture_camera_control() -> void: pass
	func list_available_miniatures() -> Array[Dictionary]: return []
var path: String
var area: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.title = "VTT Desktop PWA - isolated verification"
	root.size = Vector2i(1440, 960)
	root.gui_embed_subwindows = true
	var board := Board.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	area = load("res://vtt/creature_area.gd").new()
	area._selection_config_path = "user://desktop_web_test_selection.cfg"
	board.add_child(area)
	area.setup(board, ui, false, false)
	path = "user://desktop_window_test_%d.json" % Time.get_ticks_usec()
	area._archive._storage.path = path
	var record: Dictionary = area._archive.create_character()
	record.name = "Lyria · Verifica desktop"
	record.additional_traits = "Scheda sintetica per verificare la transizione desktop."
	record.abilities = {"str": 12, "dex": 16, "con": 14, "int": 18, "wis": 12, "cha": 10}
	record.current_hp = 28
	record.max_hp = 32
	record.max_hp_base = 32
	assert(area._archive.save(record) == OK)
	area._reload()
	area.show_panel()
	get_tree_timeout()

func get_tree_timeout() -> void:
	await create_timer(240).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
