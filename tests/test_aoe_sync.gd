extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var measure: Node = scene.measurement_tool
	for shape in ["sphere", "cube", "cone", "line", "cylinder"]:
		measure.add_aoe(Vector3(1,2,3), Vector3(4,2,3), shape)
	measure.add_aoe(
		Vector3(2, 0, 2),
		Vector3(6, 0, 2),
		"sphere",
		"cloudkill",
		Color(0.0, 0.0, 0.0, -1.0),
		-1.0,
		10.0,
		"away_from_caster",
		Vector3.ZERO
	)
	assert(measure.serialize_persistent_aoes().size() == 6)
	var data: Array = JSON.parse_string(JSON.stringify(measure.serialize_persistent_aoes()))
	measure.clear_persistent_aoes()
	measure.apply_persistent_aoes(data)
	assert(measure.serialize_persistent_aoes() == data)
	assert(not measure.valid_aoes([{"shape":"sphere", "start":[], "end":[]}]))
	var sync: Node = scene.board_sync
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(snapshot))
	assert(sync.apply_snapshot(snapshot))
	# The transfer must also work above the maximum size of a single UDP packet.
	for i in range(250):
		measure.add_aoe(Vector3(i, 2, 3), Vector3(i + 2, 2, 3), "sphere")
	for i in range(200):
		var token: Node3D = load("res://token.tscn").instantiate()
		scene.tokens_root.add_child(token)
		token.position = Vector3(i + 0.25, 5.0, 0.75)
		token.set_flying(true)
	snapshot = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(JSON.stringify(snapshot).to_utf8_buffer().size() > 65507)
	assert(not sync.apply_snapshot({"version":3}))
	var duplicate: Dictionary = snapshot.duplicate(true)
	if not duplicate.objects.is_empty():
		duplicate.objects.append(duplicate.objects[0])
		assert(not sync.valid_snapshot(duplicate))
	var other: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(other)
	await process_frame
	assert(sync.create_snapshot().objects.size() == snapshot.objects.size())
	assert(other.board_sync.listen(true, "test-key") == OK)
	assert(sync.send_snapshot("127.0.0.1", "test-key") == OK)
	for frame in range(300):
		await create_timer(0.01).timeout
		if other.measurement_tool.serialize_persistent_aoes().size() == 256:
			break
	assert(other.measurement_tool.serialize_persistent_aoes().size() == 256)
	assert(other.tokens_root.get_child_count() == scene.tokens_root.get_child_count())
	assert(other.tokens_root.get_child(0).position == scene.tokens_root.get_child(0).position)
	other.measurement_tool.clear_persistent_aoes()
	assert(sync.send_snapshot("127.0.0.1", "wrong-key") == OK)
	await create_timer(0.4).timeout
	assert(other.measurement_tool.serialize_persistent_aoes().is_empty())
	scene.queue_free()
	other.queue_free()
	await process_frame
	print("PASS: AoE cylinder/movable round-trip, validation, scene isolation, TCP transfer, wrong key rejection")
	quit()


