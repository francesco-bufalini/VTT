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
	# First opening on a short game viewport must show both native footer
	# buttons, rather than clipping Confirm below the window.
	var previous_size: Vector2i = root.size
	root.size = Vector2i(860, 560)
	await process_frame
	var dialog_image_path := "user://map_image_first_open_test.png"
	assert(image.save_png(dialog_image_path) == OK)
	controller.call("_on_image_selected", ProjectSettings.globalize_path(dialog_image_path))
	var calibration: ConfirmationDialog = controller.get("_settings") as ConfirmationDialog
	assert(calibration.visible and calibration.get_ok_button().visible
		and calibration.get_cancel_button().visible,
		"First import must expose its native Confirm/Cancel buttons")
	assert(calibration.get_node_or_null("DialogScrollBody") is ScrollContainer,
		"Oversized calibration controls must scroll instead of clipping the footer")
	for _frame: int in range(3):
		await process_frame
		var button_rect: Rect2 = calibration.get_ok_button().get_global_rect()
		assert(button_rect.end.y <= calibration.size.y,
			"Confirm must remain inside the calibration dialog")
		assert(calibration.position.y + button_rect.end.y <= root.get_visible_rect().size.y,
			"Confirm must be reachable within the game viewport")
	calibration.hide()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dialog_image_path))
	root.size = previous_size
	await process_frame

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
	var overlay: MeshInstance3D = root_plane.get_node("SurfaceGrid") as MeshInstance3D
	assert(overlay != null and overlay.mesh is ArrayMesh,
		"Both 2D and 3D must render the image's top-face-only grid")
	var line_arrays: Array = overlay.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = line_arrays[Mesh.ARRAY_VERTEX]
	assert(vertices.size() > 8 and vertices.size() % 2 == 0)
	for vertex: Vector3 in vertices:
		assert(is_equal_approx(vertex.y, 1.009),
			"Grid lines must touch the image top, never the cube sides")
		assert(vertex.x >= -3.01 and vertex.x <= 4.99
			and vertex.z >= -3.99 and vertex.z <= 2.01,
			"Grid must be clipped to the image footprint")
	# X=7 is a global grid boundary; the image offset must not move it.
	var aligned_line := false
	for vertex: Vector3 in vertices:
		if is_equal_approx(vertex.x, -3.0):
			aligned_line = true
	assert(aligned_line,
		"Surface grid must follow world grid coordinates despite image offset")
	var grid: Node3D = board.get_node("VolumetricGrid") as Node3D
	assert(bool(controller.call(
		"overlaps_image_support_cell", Vector3(8.5, 2.5, 10.5), 1.0
	)))
	assert(not bool(controller.call(
		"overlaps_image_support_cell", Vector3(30.5, 2.5, 30.5), 1.0
	)))
	grid.set("_active_occupied", {
		Vector3i(8, 2, 10): true,
		Vector3i(30, 2, 30): true
	})
	grid.call("_update_multimesh_instances")
	var instance_data: MultiMesh = grid.get("_multimesh") as MultiMesh
	assert(instance_data.instance_count == 1,
		"Cube wireframes on image supports must be suppressed in 3D")
	grid.visible = false
	assert(not overlay.visible, "Hiding the tactical grid hides the surface grid")
	grid.visible = true
	assert(overlay.visible, "Showing the tactical grid restores the surface grid")
	grid.call("mark_map_dirty")

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
	print("PASS: first-open popup footer, flat 3D image grid, collisions, undo and save")
	quit()
