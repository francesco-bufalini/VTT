extends SceneTree
const Capture = preload("res://network/mobile_map_capture.gd")
const Snapshot = preload("res://vtt/mobile/map_snapshot_view.gd")
const Spells = preload("res://vtt/spells/spell_system.gd")
const Measurement = preload("res://measurement_tool.gd")

class Board:
	extends Node3D
	var cell_size := 1.0
	var _ui_owns_mouse := false
	var affected: Array = []
	func set_affected_token_highlight(tokens: Array) -> void:
		affected = tokens.duplicate()
	func clear_token_selection() -> void:
		pass
	func is_2d_view_enabled() -> bool:
		return false

func _initialize() -> void:
	call_deferred("run")

func touch(view: Control, index: int, pressed: bool, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = point + view.global_position
	assert(view.handle_screen_input(event))

func drag(view: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point + view.global_position
	assert(view.handle_screen_input(event))

func run() -> void:
	assert(Capture.field_for_range(120) == 240)
	assert(Capture.field_for_range(0) == 20 and Capture.field_for_range(10000) == 1500)
	var view := Snapshot.new()
	root.add_child(view)
	view.size = Vector2(400, 400)
	var image := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	image.fill(Color.DARK_GREEN)
	assert(view.load_snapshot({"format": "webp", "image": Marshalls.raw_to_base64(image.save_webp_to_buffer()),
		"token_id": "caster", "field_feet": 240, "markers": [{"id": "target", "x": 600, "y": 512, "radius": 20}]}))
	var taps: Array = []
	view.map_tapped.connect(func(pixel: Vector2, id: String) -> void: taps.append([pixel, id]))
	touch(view, 0, true, Vector2(120, 200))
	touch(view, 1, true, Vector2(280, 200))
	drag(view, 0, Vector2(40, 200))
	drag(view, 1, Vector2(360, 200))
	touch(view, 1, false, Vector2(360, 200))
	touch(view, 0, false, Vector2(40, 200))
	assert(view.zoom > 1.5 and taps.is_empty(), "Pinch must zoom without selecting")
	touch(view, 0, true, Vector2(200, 200))
	drag(view, 0, Vector2(170, 220))
	touch(view, 0, false, Vector2(170, 220))
	assert(taps.is_empty(), "Pan must not select a token")
	var target := view.image_to_local(Vector2(600, 512))
	touch(view, 0, true, target)
	touch(view, 0, false, target)
	assert(taps.size() == 1 and taps[0][1] == "target" and taps[0][0].distance_to(Vector2(600, 512)) < 0.01)
	view.free()
	print("PASS: exact doubled range, limits, pinch/pan without activation, stable selection after zoom")
	var board := Board.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var measure := Measurement.new()
	measure.name = "MeasurementTool"
	board.add_child(measure)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.position = Vector3(0, 20, 20)
	camera.look_at(Vector3.ZERO)
	var token_scene := load("res://token.tscn")
	var caster: CharacterBody3D = token_scene.instantiate()
	var victim: CharacterBody3D = token_scene.instantiate()
	board.add_child(caster)
	board.add_child(victim)
	caster.position = Vector3(0.5, 1, 0.5)
	victim.position = Vector3(3.5, 1, 0.5)
	var spells := Spells.new()
	spells.name = "SpellSystem"
	board.add_child(spells)
	spells.setup(board)
	await process_frame
	await process_frame
	var camera_before := camera.transform
	var started: Dictionary = spells.begin_remote_spell(caster, "mobile-owner", {"spell_id": "magic_missile", "slot_level": 1})
	assert(started.ok and started.targeting.active and started.targeting.range_feet == 120)
	var denied: Dictionary = spells.remote_target_input(caster, "other-owner", victim, {}, "select")
	assert(not denied.ok)
	var selected: Dictionary = spells.remote_target_input(caster, "mobile-owner", victim, {}, "select")
	assert(selected.ok and selected.targeting.selected_ids.size() == 1, "Snapshot target must reach the native spell lifecycle")
	var cancelled: Dictionary = spells.remote_target_input(caster, "mobile-owner", null, {}, "cancel")
	assert(cancelled.ok and not cancelled.targeting.active and cancelled.targeting.outcome == "cancelled")
	assert(board.affected.is_empty() and camera.transform == camera_before)
	started = spells.begin_remote_spell(caster, "mobile-owner", {"spell_id": "magic_missile", "slot_level": 1})
	for i: int in range(3):
		selected = spells.remote_target_input(caster, "mobile-owner", victim, {}, "select")
	assert(not selected.targeting.active and selected.targeting.outcome == "completed", "Native repeat-target spell must complete remotely")
	assert(camera.transform == camera_before)
	started = spells.begin_remote_spell(caster, "mobile-owner", {"spell_id": "fireball", "slot_level": 3})
	assert(started.ok and started.targeting.phase == "point")
	selected = spells.remote_target_input(caster, "mobile-owner", null,
		{"valid": true, "point": Vector3(3.5, 0, 0.5), "normal": Vector3.UP, "in_air": false}, "select")
	assert(selected.ok and selected.targeting.phase != "point", "Snapshot coordinates must enter the native AoE resolution")
	spells.remote_target_input(caster, "mobile-owner", null, {}, "cancel")
	print("PASS: native remote spell selection, ownership, cancellation cleanup, repeated targets, camera preservation")
	board.queue_free()
	await process_frame
	quit()
