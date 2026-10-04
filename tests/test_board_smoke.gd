extends SceneTree

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

	# Load after the SceneTree autoloads are registered in command-line tests.
	var sync: Node = load("res://network/board_sync.gd").new()
	sync.name = "BoardSync"
	arena.add_child(sync)
	sync.setup(arena, TokenScene, tokens_root, measure)

	var token: CharacterBody3D = TokenScene.instantiate()
	token.visual_asset_path = "res://assets/tokens/test/test_token_visual.tscn"
	tokens_root.add_child(token)
	token.position = Vector3(2.0, 1.0, 2.0)
	token.set_flying(true)
	token.set_display_name("Agent Smoke Token")
	var stable_token_id: String = token.get_token_id()
	if stable_token_id.is_empty():
		_fail("token did not receive a stable token_id")
		return
	if token.get_effective_party_id() != "Default":
		_fail("empty party did not resolve to Default")
		return
	token.set_party_id("Eroi")

	# Every displayed condition must expose a real emoji/icon.
	for definition_value: Variant in token.get_condition_definitions():
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		var icon := String(definition.get("icon", ""))
		if icon.is_empty() or icon.begins_with("["):
			_fail(
				"condition is missing emoji icon: %s"
				% JSON.stringify(definition)
			)
			return

	if not token.are_condition_visuals_visible():
		_fail("condition visuals should be enabled by default")
		return
	token.set_condition("poisoned", true)
	token.set_condition_visuals_visible(false)
	if token.are_condition_visuals_visible():
		_fail("condition visual toggle did not hide token visuals")
		return
	var ring_root := token.get_node_or_null("ConditionRings")
	if ring_root != null and ring_root.get_child_count() != 0:
		_fail("condition rings remained visible after toggle off")
		return
	token.set_condition_visuals_visible(true)
	if not token.are_condition_visuals_visible():
		_fail("condition visual toggle did not restore token visuals")
		return

	var condition_parts: PackedStringArray = token.get_active_condition_display_parts()
	if not ("☠️ Avvelenato" in condition_parts):
		_fail("named poisoned condition is missing from shared badge data")
		return

	var snapshot: Dictionary = JSON.parse_string(
		JSON.stringify(sync.create_snapshot())
	)
	if snapshot.is_empty():
		_fail("snapshot creation returned empty")
		return
	if not sync.valid_snapshot(snapshot):
		_fail("fresh snapshot failed validation: %s" % JSON.stringify(snapshot))
		return
	if snapshot.objects.size() != 1:
		_fail("expected exactly one serialized token")
		return
	var serialized_token: Dictionary = snapshot.objects[0]
	if String(serialized_token.get("token_id", "")) != stable_token_id:
		_fail("stable token_id was not serialized")
		return
	if String(serialized_token.get("id", "")) != stable_token_id:
		_fail("board sync id did not use stable token_id")
		return
	if String(serialized_token.get("party_id", "")) != "Eroi":
		_fail("token party was not serialized")
		return
	token.set_party_id("")
	if not sync.apply_snapshot(snapshot):
		_fail("snapshot round-trip failed")
		return
	if token.get_token_id() != stable_token_id:
		_fail("stable token_id changed during snapshot restore")
		return
	if token.get_party_id() != "Eroi":
		_fail("token party was not restored")
		return

	arena.queue_free()
	await process_frame
	print("PASS: lightweight board/token/snapshot arena")
	quit()
