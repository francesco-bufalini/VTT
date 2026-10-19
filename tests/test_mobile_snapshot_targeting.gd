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
	assert(view.zoom == 3.0, "Default view must crop a wide field around the caster")
	view.zoom = 1
	view._clamp_pan()
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
	view.aim_mode = true
	var aims: Array[Vector2] = []
	view.map_aimed.connect(func(pixel: Vector2) -> void: aims.append(pixel))
	touch(view, 0, true, Vector2(180, 180))
	drag(view, 0, Vector2(220, 200))
	touch(view, 0, false, Vector2(220, 200))
	assert(aims.size() == 2 and taps.size() == 1, "Aiming must preview without selecting or casting on release")
	view.show_local_area(Vector2(512, 512), {"area_shape": "sphere", "area_radius_feet": 20})
	assert(view.area_preview.points.size() == 64)
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
	assert(started.targeting.range_feet == 150 and started.targeting.area_radius_feet == 20)
	var projection := {"x": 0.5, "y": 1, "z": 0.5, "size": 60, "width": 1536, "height": 1536}
	var preview: Dictionary = spells.remote_preview_input(caster, "mobile-owner",
		{"valid": true, "point": Vector3(3.5, 0, 0.5), "normal": Vector3.UP, "in_air": false}, projection)
	assert(preview.ok and preview.preview.valid and preview.preview.points.size() == 64)
	assert(spells.is_targeting() and spells._targeting_phase == "point", "Dragging Fireball must not cast")
	var sync: Node = load("res://network/board_sync.gd").new()
	board.add_child(sync)
	sync.board_root = board
	sync.tokens_root = board
	caster.set_meta("creature_owner_id", "mobile-owner")
	var caster_id: String = sync.get_sync_id_for_node(caster)
	sync._mobile_views["preview-test"] = {"projection": projection, "token_id": caster_id, "at": Time.get_ticks_msec()}
	var wire_preview: Dictionary = await sync._handle_mobile_action("preview_spell", {"token_id": caster_id,
		"owner_id": "mobile-owner", "snapshot_id": "preview-test", "pixel": [844.8, 768]})
	assert(wire_preview.ok and wire_preview.preview.valid and wire_preview.preview.points.size() == 64)
	var victim_id: String = sync.get_sync_id_for_node(victim)
	wire_preview = await sync._handle_mobile_action("preview_spell", {"token_id": caster_id,
		"owner_id": "mobile-owner", "snapshot_id": "preview-test", "pixel": [844.8, 768], "target_id": victim_id})
	assert(wire_preview.ok and wire_preview.preview.valid and victim_id in wire_preview.preview.affected_ids,
		"Aiming directly at a token must preview the native area, including its height")
	assert(sync.get_tactical_map_data().mobile_protocol == 3)
	var outside: Dictionary = spells.remote_preview_input(caster, "mobile-owner",
		{"valid": true, "point": Vector3(1000, 0, 0), "normal": Vector3.UP, "in_air": false}, projection)
	assert(outside.ok and not outside.preview.valid, "Out-of-range aim must clear the AoE")
	print("PASS: live Fireball native 20ft contour, range validation and preview without casting")
	var empty_revision: int = sync.get_tactical_map_data().view_revision
	selected = spells.remote_target_input(caster, "mobile-owner", null,
		{"valid": true, "point": Vector3(3.5, 0, 0.5), "normal": Vector3.UP, "in_air": false}, "select")
	assert(selected.ok and selected.targeting.phase != "point", "Snapshot coordinates must enter the native AoE resolution")
	var areas: Array = Capture.project_areas(board, projection)
	assert(areas.size() == 1 and areas[0].points.size() == 64 and victim_id in areas[0].affected_ids,
		"Confirmed Fireball must remain in snapshots with native affected targets")
	assert(sync.get_tactical_map_data().view_revision != empty_revision)
	var remote_status: Dictionary = await sync._handle_mobile_action("spell_status", {
		"token_id": caster_id, "owner_id": "mobile-owner"})
	assert(remote_status.ok and remote_status.targeting.outcome == "completed")
	var denied_status: Dictionary = await sync._handle_mobile_action("spell_status", {
		"token_id": caster_id, "owner_id": "other-owner"})
	assert(denied_status.ok and denied_status.targeting.is_empty(), "Public views refresh without revealing another owner's targeting")
	assert(spells.dismiss_post_cast_visuals())
	assert(Capture.project_areas(board, projection).is_empty(), "Deleted areas must disappear before the next frame")
	assert(sync.get_tactical_map_data().view_revision == empty_revision)
	measure.add_spell_aoe(Vector3(3.5, 1, 0.5), Vector3(5.5, 1, 0.5), "cube", "web")
	var wall: Array[Vector3] = [Vector3.ZERO, Vector3(2, 0, 0), Vector3(2, 0, 2)]
	measure.add_wall_path(wall, 2, 0.2, "fire")
	measure.add_wall_globe(Vector3.ZERO, 2, "force")
	areas = Capture.project_areas(board, projection)
	assert(areas.size() == 4 and areas[0].shape == "cube" and areas[0].points.size() == 4)
	assert(areas[1].shape == "wall_path" and areas[2].shape == "wall_path")
	assert(areas[3].shape == "wall_globe" and areas[3].points.size() == 64)
	assert(areas.all(func(area: Dictionary) -> bool: return not area.has("root")), "Wire projection must never leak native objects")
	print("PASS: public area projection, held/persistent cleanup, walls and cheap authorized status refresh")
	spells.remote_target_input(caster, "mobile-owner", null, {}, "cancel")
	print("PASS: native remote spell selection, ownership, cancellation cleanup, repeated targets, camera preservation")
	board.queue_free()
	await process_frame
	quit()
