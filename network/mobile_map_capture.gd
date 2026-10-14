extends RefCounted
## One-shot orthographic render in the board world. No desktop camera/UI changes.
const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
const SIZE := Vector2i(1024, 768)

static func capture(board: Node3D, token: Node3D, field_feet: float, attack: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "Il desktop deve essere avviato con la grafica per inviare immagini."}
	var viewport := SubViewport.new()
	viewport.name = "MobileMapCapture"
	viewport.size = SIZE
	viewport.world_3d = board.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	board.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var cell: float = float(board.get("cell_size"))
	var center: Vector3 = token.global_position
	var clearance := 64.0 * cell
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = clampf(field_feet, 20.0, 1500.0) / 5.0 * cell
	camera.position = center + Vector3.UP * clearance
	camera.rotation = Vector3(-PI * 0.5, 0, 0)
	# Match the desktop 2D floor slice, relative to this token's own height.
	camera.near = clearance - 0.12 * cell
	camera.far = clearance + 1000.0 * cell
	camera.current = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "Impossibile acquisire la mappa."}
	var result := {"ok": true, "format": "webp", "width": SIZE.x, "height": SIZE.y,
		"image": Marshalls.raw_to_base64(image.save_webp_to_buffer(true, 0.8)),
		"token_id": "", "field_feet": field_feet, "elevation": center.y,
		"title": String(token.call("get_display_name")), "contours": [], "markers": []}
	var half: float = float(token.call("get_footprint_cells")) * cell * 0.5
	var normal: float = float(attack.get("range_feet", 0))
	var long_range: float = float(attack.get("long_range_feet", 0)) if not bool(attack.get("melee", true)) else 0.0
	if long_range <= normal:
		long_range = 0.0
	for reach: float in [normal, long_range]:
		if reach <= 0.0 or (reach == long_range and long_range <= normal):
			continue
		var points: Array = []
		for point: Vector2 in RangeGeometry.rounded_footprint_perimeter(half, reach / 5.0 * cell):
			var pixel := camera.unproject_position(center + Vector3(point.x, 0, point.y))
			points.append([pixel.x, pixel.y])
		result.contours.append({"points": points, "long": reach == long_range})
	for node: Node in board.get_tree().get_nodes_in_group("dnd_token"):
		if not node is CharacterBody3D or not board.is_ancestor_of(node) or not node.is_visible_in_tree() or node.is_queued_for_deletion():
			continue
		var extent: float = float(node.get("token_height_cells")) * float(node.get("cell_size")) * 0.5
		if node.global_position.y - extent > center.y + 0.12 * cell or node.global_position.y + extent < center.y - cell:
			continue
		var position := camera.unproject_position(Vector3(node.global_position.x, center.y, node.global_position.z))
		var radius: float = float(node.call("get_footprint_cells")) * cell / camera.size * SIZE.y * 0.5
		result.markers.append({"x": position.x, "y": position.y, "radius": radius,
			"name": String(node.call("get_display_name")), "selected": node == token})
	viewport.queue_free()
	return result
