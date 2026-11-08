extends SceneTree

const MapImageController = preload("res://vtt/map_image_controller.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	var sync: Node = board.board_sync
	sync.set_auto_sync_enabled(false)
	sync.listen(false, "map-image-regression")

	var image := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 1.0))
	var record: Dictionary = {
		"id": "map-image-test-1",
		"name": "Test grid",
		"format": "png",
		"image_data": Marshalls.raw_to_base64(image.save_png_to_buffer()),
		"width_cells": 8.0,
		"height_cells": 6.0,
		"offset_x": 0.99,
		"offset_z": -0.99,
		"position": {"x": 10.0, "y": 2.0, "z": 12.0}
	}
	assert(MapImageController.valid_records([record]))
	var controller: Node3D = board.get_node("MapImageController") as Node3D
	assert(controller.call("apply_map_images", [record]))
	var planes: Node3D = controller.get_node("PlacedMapImages") as Node3D
	assert(planes.get_child_count() == 1)
	var root_plane: Node3D = planes.get_child(0) as Node3D
	assert(root_plane.position.is_equal_approx(Vector3(10.0, 2.0, 12.0)))
	var surface: MeshInstance3D = root_plane.get_node("ImageSurface") as MeshInstance3D
	var mesh: PlaneMesh = surface.mesh as PlaneMesh
	assert(mesh.size.is_equal_approx(Vector2(8.0, 6.0)),
		"Scaling an image must also resize its plane in cells")
	assert(surface.position.is_equal_approx(Vector3(0.99, 1.002, -0.99)),
		"Fractional offsets must translate the image against the unchanged grid")
	var body: StaticBody3D = root_plane.get_node("OneCubeSupport") as StaticBody3D
	var shape: BoxShape3D = body.get_node("SupportShape").shape as BoxShape3D
	assert(shape.size.is_equal_approx(Vector3(8, 1, 6)),
		"The image platform must be exactly one cube thick")
	assert(body.position.is_equal_approx(Vector3(0.99, 0.5, -0.99)))

	var original_snapshot: Dictionary = sync.create_snapshot()
	assert(original_snapshot.get("map_images", []).size() == 1)
	assert(sync.valid_snapshot(original_snapshot),
		"The imported picture must survive map snapshot validation")
	var second: Dictionary = record.duplicate(true)
	second.id = "map-image-test-2"
	second.offset_x = -0.75
	second.offset_z = 0.5
	var before: Dictionary = board.begin_undo_transaction()
	assert(controller.call("apply_map_images", [record, second]))
	board.commit_undo_transaction(before)
	assert(board.undo_last_action(), "Undo must restore previous image planes")
	assert(planes.get_child_count() == 1)
	assert(board.redo_last_action(), "Redo must recreate the newly imported plane")
	assert(planes.get_child_count() == 2)

	var restored: Dictionary = sync.create_snapshot()
	assert(controller.call("apply_map_images", []))
	assert(planes.get_child_count() == 0)
	assert(sync.apply_snapshot(restored),
		"Loading a snapshot must restore images and their transforms")
	assert(planes.get_child_count() == 2)

	var invalid: Dictionary = record.duplicate(true)
	invalid.offset_z = 1.0
	assert(not MapImageController.valid_records([invalid]),
		"Shifts greater than 0.99 cubes must be rejected")
	assert(not MapImageController.valid_records([record, record]),
		"Duplicate image identifiers must be rejected")
	var old_snapshot: Dictionary = restored.duplicate(true)
	old_snapshot.erase("map_images")
	assert(sync.valid_snapshot(old_snapshot),
		"Older map saves without images must remain compatible")
	assert(sync.apply_snapshot(old_snapshot))
	assert(planes.get_child_count() == 0)

	board.queue_free()
	await process_frame
	await process_frame
	print("PASS: calibrated map image planes, offsets, collisions, undo and save")
	quit()
