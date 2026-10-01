extends SceneTree

const BoardSync = preload("res://network/board_sync.gd")
const InitiativeTracker = preload("res://vtt/initiative_tracker.gd")
const MeasurementTool = preload("res://measurement_tool.gd")
const TokenScene = preload("res://token.tscn")


func _initialize() -> void:
	call_deferred("run")


func _fail(message: String) -> void:
	push_error("Board smoke: " + message)
	quit(1)


func run() -> void:
	var arena: Node3D = load(
		"res://tests/scenes/agent_test_arena.tscn"
	).instantiate()
	root.add_child(arena)

	var tokens_root: Node3D = arena.get_node("Tokens")
	var measure: Node3D = MeasurementTool.new()
	measure.name = "MeasurementTool"
	arena.add_child(measure)

	var initiative: Node = InitiativeTracker.new()
	initiative.name = "InitiativeTracker"
	arena.add_child(initiative)

	var sync: Node = BoardSync.new()
	sync.name = "BoardSync"
	arena.add_child(sync)
	sync.setup(arena, TokenScene, tokens_root, measure)

	var token: CharacterBody3D = TokenScene.instantiate()
	tokens_root.add_child(token)
	token.position = Vector3(2.0, 1.0, 2.0)
	token.set_flying(true)
	token.set_display_name("Agent Smoke Token")

	var snapshot: Dictionary = JSON.parse_string(
		JSON.stringify(sync.create_snapshot())
	)
	if snapshot.is_empty():
		_fail("snapshot creation returned empty")
		return
	if not sync.valid_snapshot(snapshot):
		_fail("fresh snapshot failed validation")
		return
	if snapshot.objects.size() != 1:
		_fail("expected exactly one serialized token")
		return
	if not sync.apply_snapshot(snapshot):
		_fail("snapshot round-trip failed")
		return

	arena.queue_free()
	await process_frame
	print("PASS: lightweight board/token/snapshot arena")
	quit()
