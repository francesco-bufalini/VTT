extends SceneTree

const TokenScene = preload("res://token.tscn")
const CameraController = preload("res://camera_controller.gd")
const InitiativeTracker = preload("res://vtt/initiative_tracker.gd")
const MeasurementTool = preload("res://measurement_tool.gd")

class Board extends Node3D:
	var cell_size: float = 1.0
	var token_list: Node = null
	var camera: Camera3D

	func focus_camera_on_token(token: CharacterBody3D) -> void:
		camera.call("focus_on_token", token)

var turn_notifications: int = 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("Camera sync: " + message)
		quit(1)
	return condition

func run() -> void:
	var board := Board.new()
	root.add_child(board)
	var tokens := Node3D.new()
	board.add_child(tokens)
	var camera: Camera3D = CameraController.new()
	camera.name = "Camera3D"
	board.camera = camera
	board.add_child(camera)
	camera.set_process(false)
	var measure: Node3D = MeasurementTool.new()
	board.add_child(measure)
	var tracker: Node = InitiativeTracker.new()
	tracker.name = "InitiativeTracker"
	tracker.board_root = board
	board.add_child(tracker)
	tracker.turn_changed.connect(func(_id: String, _round: int, _turn: int) -> void: turn_notifications += 1)
	var sync: Node = load("res://network/board_sync.gd").new()
	board.add_child(sync)
	# No network discovery/listening: exercise the receiver's production apply path.
	sync.board_root = board
	sync.token_scene = TokenScene
	sync.tokens_root = tokens
	sync.measurement_tool = measure
	sync.set_process(false)
	var entries: Array[Dictionary] = []
	for index in range(2):
		var token: CharacterBody3D = TokenScene.instantiate()
		token.visual_asset_path = "res://assets/tokens/test/test_token_visual.tscn"
		tokens.add_child(token)
		token.set_flying(true)
		token.position = Vector3(index * 8, 2, 3)
		entries.append({"id": "initiative_%d" % index, "name": "Token %d" % index, "token_id": token.get_token_id()})
	var state := {"version": 1, "active": true, "entries": entries, "active_index": 0, "round": 1, "turn_count": 0, "next_entry_id": 3}
	tracker.load_state(state)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	if not _check(sync.valid_snapshot(snapshot), "fixture snapshot invalid"):
		return
	var expected := Transform3D(Basis.from_euler(Vector3(-0.3, 0.8, 0)), Vector3(41, 27, -19))
	camera.global_transform = expected
	for automatic in [true, false]:
		sync.set_auto_sync_enabled(automatic)
		for attempt in range(3):
			if not _check(sync.apply_snapshot(snapshot), "incoming snapshot rejected"):
				return
			await process_frame
			if not _check(camera.global_transform.is_equal_approx(expected), "repeated active-combat snapshot moved free camera (auto=%s)" % automatic):
				return
	# A remote turn must update combat state/signals without taking local view control.
	var notifications_before := turn_notifications
	snapshot.initiative.active_index = 1
	snapshot.initiative.turn_count = 1
	if not _check(sync.apply_snapshot(snapshot), "changed remote turn rejected"):
		return
	if not _check(tracker.active_index == 1 and turn_notifications > notifications_before, "remote turn was not applied/notified"):
		return
	if not _check(camera.global_transform.is_equal_approx(expected), "remote turn took control of local camera"):
		return
	# Explicit local turn navigation and the eye command must still focus normally.
	tracker.next_turn()
	if not _check(not camera.global_transform.is_equal_approx(expected), "local next-turn focus stopped working"):
		return
	camera.global_transform = expected
	tracker.previous_turn()
	if not _check(not camera.global_transform.is_equal_approx(expected), "local previous-turn focus stopped working"):
		return
	camera.global_transform = expected
	board.focus_camera_on_token(tokens.get_child(0))
	if not _check(not camera.global_transform.is_equal_approx(expected), "explicit eye focus stopped working"):
		return
	# Incoming state must not silently exit first person either.
	camera.call("enter_first_person", tokens.get_child(0))
	sync.apply_snapshot(snapshot)
	if not _check(camera.call("is_first_person"), "incoming snapshot exited first person"):
		return
	board.queue_free()
	await process_frame
	print("PASS: active-combat snapshots preserve local camera with auto-sync on/off; local focus and turn notifications work")
	quit()
