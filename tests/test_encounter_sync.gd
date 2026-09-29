extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var sync: Node = scene.board_sync
	var data: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(data))
	assert(not data.encounter.is_empty())
	scene.encounter.round_number += 1
	assert(sync.apply_snapshot(data))
	assert(scene.encounter.round_number == data.encounter.round_number)
	var again: Dictionary = sync.create_snapshot()
	assert(again.objects.size() == data.objects.size())
	scene.encounter.is_advancing = true
	assert(sync.create_snapshot().is_empty())
	assert(not sync.apply_snapshot(data))
	scene.encounter.is_advancing = false
	scene.queue_free()
	await process_frame
	print("PASS: encounter snapshot and restore, busy-state rejection")
	quit()
