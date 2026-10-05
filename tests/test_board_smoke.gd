extends SceneTree

const InitiativeTracker = preload("res://vtt/initiative_tracker.gd")
const MeasurementTool = preload("res://measurement_tool.gd")
const TokenScene = preload("res://token.tscn")


class HealthAreaMock extends Node:
	var entries: Array[Dictionary] = []

	func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
		return entries.duplicate(true)


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

	var local_camera := Camera3D.new()
	local_camera.name = "Camera3D"
	local_camera.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(11.0, 7.0, -3.0)
	)
	arena.add_child(local_camera)

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
		var condition_id := String(definition.get("id", ""))
		if condition_id == "flying":
			_fail("Flying must not be exposed as a token condition")
			return
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
	if snapshot.has("camera"):
		_fail("camera/view must remain local and must not be serialized")
		return
	if not sync.valid_snapshot(snapshot):
		_fail("fresh snapshot failed validation: %s" % JSON.stringify(snapshot))
		return
	if not bool(sync.call("is_auto_sync_enabled")):
		_fail("automatic synchronization should be enabled by default")
		return
	var snapshot_with_camera := snapshot.duplicate(true)
	snapshot_with_camera["camera"] = {
		"basis": [
			{"x": 1.0, "y": 0.0, "z": 0.0},
			{"x": 0.0, "y": 1.0, "z": 0.0},
			{"x": 0.0, "y": 0.0, "z": 1.0}
		],
		"origin": {"x": 5.0, "y": 7.0, "z": 9.0}
	}
	if not sync.valid_snapshot(snapshot_with_camera):
		_fail("snapshot with synchronized camera failed validation")
		return
	var state_signature := String(
		sync.call("_snapshot_signature", snapshot)
	)
	var camera_signature := String(
		sync.call("_snapshot_signature", snapshot_with_camera)
	)
	if state_signature != camera_signature:
		_fail("camera-only movement must not trigger automatic map sync")
		return

	var camera_before_sync := local_camera.global_transform
	if not sync.apply_snapshot(snapshot_with_camera):
		_fail("legacy snapshot containing camera failed to apply")
		return
	if not local_camera.global_transform.is_equal_approx(camera_before_sync):
		_fail("incoming camera/view changed the local camera")
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

	# Token-editor fields must all participate in the snapshot signature and
	# survive a manual snapshot round trip.
	var before_editor_signature := String(
		sync.call("_snapshot_signature", sync.create_snapshot())
	)
	# Match the real "Modifica token" path: resizing first stores the previous
	# appearance in transformation_history. The history is JSON-encoded on the
	# wire, so integer rotation fields may be decoded as numeric floats.
	token.push_transformation_state()
	token.set_size_category("Large", 2.0, false)
	token.set_reach_feet(15.0, true)
	token.set_party_id("Mostri")
	token.set_conditions(["prone", "poisoned"])
	# "Applica" explicitly promotes the just-edited local appearance.
	sync.call("mark_token_appearance_locally_edited", token)
	var editor_snapshot: Dictionary = JSON.parse_string(
		JSON.stringify(sync.create_snapshot())
	)
	if not sync.valid_snapshot(editor_snapshot):
		_fail("token-editor snapshot failed validation")
		return
	var after_editor_signature := String(
		sync.call("_snapshot_signature", editor_snapshot)
	)
	if before_editor_signature == after_editor_signature:
		_fail("token-editor changes did not dirty automatic sync state")
		return

	var edited_token: Dictionary = editor_snapshot.objects[0]
	if String(edited_token.get("size_name", "")) != "Large":
		_fail("edited token size was not serialized")
		return
	var edited_revision := int(
		edited_token.get("appearance_revision", 0)
	)
	if edited_revision <= 0:
		_fail("explicit token edit did not advance appearance revision")
		return
	if not is_equal_approx(float(edited_token.get("footprint", 0.0)), 2.0):
		_fail("edited token footprint was not serialized")
		return
	if not is_equal_approx(float(edited_token.get("reach_feet", 0.0)), 15.0):
		_fail("edited token reach was not serialized")
		return
	if String(edited_token.get("party_id", "")) != "Mostri":
		_fail("edited token party was not serialized")
		return
	var edited_conditions: Array = edited_token.get("conditions", [])
	if not ("prone" in edited_conditions and "poisoned" in edited_conditions):
		_fail("edited token conditions were not serialized")
		return
	var edited_history: Array = edited_token.get(
		"transformation_history",
		[]
	)
	if edited_history.size() != 1:
		_fail("token resize did not serialize transformation history")
		return

	# Reproduce X -> Y -> Y moves -> Y broadcasts. Y may represent the same
	# token through a different local asset/profile state; movement must never
	# resurrect that local/default appearance.
	var peer_token: CharacterBody3D = TokenScene.instantiate()
	peer_token.visual_asset_path = "res://assets/tokens/test/test_token_visual.tscn"
	tokens_root.add_child(peer_token)
	peer_token.remove_from_group("dnd_token")
	peer_token.set_size_category("Medium", 1.0, false)
	peer_token.set_reach_feet(5.0, true)
	sync.call("_apply_node_data", peer_token, edited_token)
	var peer_after_receive: Dictionary = sync.call(
		"_serialize_node",
		peer_token,
		"dnd_token"
	)
	for appearance_key: String in [
		"size_name",
		"footprint",
		"reach_feet",
		"visual_asset",
		"visual_native_footprint",
		"visual_front_quarter_turns",
		"visual_pitch_steps",
		"transformation_history"
	]:
		if peer_after_receive.get(appearance_key) != edited_token.get(appearance_key):
			_fail(
				"peer did not preserve received appearance field: %s"
				% appearance_key
			)
			return

	# Simulate a peer-local asset/profile remount that corrupts only the
	# visual native footprint. This used to make a Large token render Medium
	# while its collider stayed Large, then poison the next full-map snapshot.
	peer_token.set(
		"_visual_native_footprint_cells",
		float(edited_token.get("footprint", 2.0))
	)
	peer_token.call(
		"set_token_size",
		float(edited_token.get("footprint", 2.0))
	)
	peer_token.global_position += Vector3(1.0, 0.0, 0.0)
	var peer_after_move: Dictionary = sync.call(
		"_serialize_node",
		peer_token,
		"dnd_token"
	)
	for appearance_key: String in [
		"size_name",
		"footprint",
		"reach_feet",
		"visual_asset",
		"visual_native_footprint",
		"visual_front_quarter_turns",
		"visual_pitch_steps",
		"transformation_history"
	]:
		if peer_after_move.get(appearance_key) != edited_token.get(appearance_key):
			_fail(
				"peer movement reverted authoritative appearance field: %s"
				% appearance_key
			)
			return

	# A late/stale full-scene snapshot must not overwrite a newer appearance.
	var stale_token: Dictionary = edited_token.duplicate(true)
	stale_token["appearance_revision"] = maxi(edited_revision - 1, 0)
	stale_token["size_name"] = "Medium"
	stale_token["footprint"] = 1.0
	stale_token["visual_native_footprint"] = 1.0
	sync.call("_apply_node_data", peer_token, stale_token)
	var after_stale: Dictionary = sync.call(
		"_serialize_node",
		peer_token,
		"dnd_token"
	)
	if int(after_stale.get("appearance_revision", -1)) != edited_revision:
		_fail("stale snapshot replaced the newer appearance revision")
		return
	if String(after_stale.get("size_name", "")) != "Large":
		_fail("stale snapshot reverted token size")
		return
	if not is_equal_approx(float(after_stale.get("footprint", 0.0)), 2.0):
		_fail("stale snapshot reverted token footprint")
		return
	# An explicit local edit is the only operation allowed to replace the
	# received appearance authority.
	sync.call("mark_token_appearance_locally_edited", peer_token)
	var peer_after_explicit_edit: Dictionary = sync.call(
		"_serialize_node",
		peer_token,
		"dnd_token"
	)
	if int(
		peer_after_explicit_edit.get("appearance_revision", 0)
	) <= edited_revision:
		_fail("explicit local edit did not advance peer appearance revision")
		return
	if is_equal_approx(
		float(peer_after_explicit_edit.get("visual_native_footprint", 0.0)),
		float(edited_token.get("visual_native_footprint", 0.0))
	):
		_fail("explicit local appearance edit did not replace received authority")
		return
	peer_token.queue_free()

	token.set_size_category("Medium", 1.0, false)
	token.set_reach_feet(5.0, true)
	token.set_party_id("")
	token.set_conditions([])
	if not sync.apply_snapshot(editor_snapshot):
		_fail("token-editor snapshot round-trip failed")
		return
	if token.get_size_name() != "Large":
		_fail("edited token size was not restored")
		return
	if not is_equal_approx(float(token.get_footprint_cells()), 2.0):
		_fail("edited token footprint was not restored")
		return
	if not is_equal_approx(float(token.get_reach_feet()), 15.0):
		_fail("edited token reach was not restored")
		return
	if token.get_party_id() != "Mostri":
		_fail("edited token party was not restored")
		return
	if not token.has_condition("prone") or not token.has_condition("poisoned"):
		_fail("edited token conditions were not restored")
		return

	# Health bars are partial, owner-scoped state. Only sheets owned by this
	# client contribute entries, and only percentage is transmitted.
	var player_health := HealthAreaMock.new()
	player_health.name = "PlayerArea"
	arena.add_child(player_health)
	var master_health := HealthAreaMock.new()
	master_health.name = "MasterArea"
	arena.add_child(master_health)

	var master_token: CharacterBody3D = TokenScene.instantiate()
	master_token.visual_asset_path = (
		"res://assets/tokens/test/test_token_visual.tscn"
	)
	tokens_root.add_child(master_token)
	master_token.set_token_id("token_health_master")
	master_token.position = Vector3(4.0, 1.0, 2.0)

	player_health.entries = [{
		"token_id": stable_token_id,
		"percent": 37.5
	}]
	master_health.entries = [{
		"token_id": master_token.get_token_id(),
		"percent": 62.25
	}]
	var health_snapshot: Dictionary = JSON.parse_string(
		JSON.stringify(sync.create_snapshot())
	)
	if not sync.valid_snapshot(health_snapshot):
		_fail("health-bar snapshot failed validation")
		return
	var health_entries: Array = health_snapshot.get("health_bars", [])
	if health_entries.size() != 2:
		_fail("owned player/master health bars were not both serialized")
		return
	for entry_value: Variant in health_entries:
		if not entry_value is Dictionary:
			_fail("health-bar entry is not a dictionary")
			return
		var entry := entry_value as Dictionary
		if (
			entry.has("current")
			or entry.has("max")
			or entry.has("current_hp")
			or entry.has("max_hp")
		):
			_fail("health sync leaked absolute hit points")
			return
		if not entry.has("token_id") or not entry.has("percent"):
			_fail("health sync entry is missing token_id/percent")
			return

	# On a receiving client, supplied entries update the visual bar only.
	# Missing entries must never clear or alter another user's token bar.
	player_health.entries = []
	master_health.entries = []
	token.clear_player_hit_points()
	master_token.clear_master_hit_points()
	sync.call(
		"_apply_partial_health_bars",
		health_snapshot.get("health_bars", [])
	)
	var player_hp: Dictionary = token.get_player_hit_points()
	var master_hp: Dictionary = master_token.get_player_hit_points()
	if (
		not is_equal_approx(
			float(player_hp.get("current", 0))
			/ maxf(float(player_hp.get("max", 1)), 1.0),
			0.375
		)
		or not is_equal_approx(
			float(master_hp.get("current", 0))
			/ maxf(float(master_hp.get("max", 1)), 1.0),
			0.6225
		)
	):
		_fail("received health percentages were not applied to bars")
		return
	if bool(token.get("_hp_bar_show_percentage")):
		_fail("synced player health bar exposed numeric percentage")
		return
	if bool(master_token.get("_hp_bar_show_percentage")):
		_fail("synced master health bar exposed numeric percentage")
		return

	# A locally-owned sheet wins for its token; an incoming peer cannot tell
	# this client how to render a bar it owns.
	token.set_player_hit_points(80, 100)
	player_health.entries = [{
		"token_id": stable_token_id,
		"percent": 80.0
	}]
	sync.call("_apply_partial_health_bars", [
		{"token_id": stable_token_id, "percent": 5.0},
		{"token_id": master_token.get_token_id(), "percent": 30.0}
	])
	player_hp = token.get_player_hit_points()
	master_hp = master_token.get_player_hit_points()
	if int(player_hp.get("current", 0)) != 80:
		_fail("remote health update overwrote locally-owned player bar")
		return
	if not is_equal_approx(
		float(master_hp.get("current", 0))
		/ maxf(float(master_hp.get("max", 1)), 1.0),
		0.30
	):
		_fail("unowned remote health bar did not update")
		return

	# The remote/master bar is visible locally, but this client does not own
	# its sheet: it must not be rebroadcast in the next full-map sync.
	var partial_snapshot: Dictionary = sync.create_snapshot()
	var partial_health: Array = partial_snapshot.get("health_bars", [])
	if partial_health.size() != 1:
		_fail("snapshot rebroadcast an unowned remote health bar")
		return
	if String(
		(partial_health[0] as Dictionary).get("token_id", "")
	) != stable_token_id:
		_fail("snapshot health ownership selected the wrong token")
		return

	master_token.queue_free()
	arena.queue_free()
	await process_frame
	print("PASS: lightweight board/token/snapshot arena")
	quit()
