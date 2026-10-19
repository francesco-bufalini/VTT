extends RefCounted
## One-shot orthographic render in the board world. No desktop camera/UI changes.
const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
const SIZE := Vector2i(1536, 1536)
const MIN_FIELD_FEET := 20.0
const MAX_FIELD_FEET := 1500.0
const Elevation = preload("res://vtt/top_down_elevation_levels.gd")
const ElevationOverlay = preload("res://vtt/top_down_elevation_overlay.gd")
const SpellOverlay = preload("res://vtt/spells/spell_target_overlay_2d.gd")

# Project through the desktop geometry owner. The browser receives pixels,
# never a second implementation of spell volumes or affected-token rules.
static func project_areas(board: Node3D, projection: Dictionary) -> Array:
	var measure := board.get_node_or_null("MeasurementTool") as Node3D
	if measure == null:
		return []
	var projector := SpellOverlay.new()
	projector.board = board
	projector.measure = measure
	var areas := projector.mobile_map_areas(projection)
	projector.free()
	return areas

static func _draw_areas(layer: Control, areas: Array) -> void:
	for area: Dictionary in areas:
		var points := PackedVector2Array()
		for point: Array in area.points:
			points.append(Vector2(float(point[0]), float(point[1])))
		if points.size() < 3:
			continue
		var tint := Color(String(area.color))
		layer.draw_colored_polygon(points, Color(tint, 0.18))
		points.append(points[0])
		layer.draw_polyline(points, tint, 4.0, true)

static func field_for_range(range_feet: float) -> float:
	return clampf(range_feet * 2.0, MIN_FIELD_FEET, MAX_FIELD_FEET)

# The orthographic camera clips other floors. Paint desktop-style token
# portraits in a screen-space layer so all elevations remain visible.
static func _add_token_badge(overlay: Control, target: CharacterBody3D, marker: Dictionary) -> void:
	var radius: float = maxf(float(marker.get("radius", 0.0)), 1.0)
	var diameter: float = radius * 2.0
	var badge := Control.new()
	badge.name = "TokenBadge"
	badge.position = Vector2(float(marker.x) - radius, float(marker.y) - radius)
	badge.size = Vector2.ONE * diameter
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(badge)
	var portrait := TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.size = badge.size
	badge.add_child(portrait)
	var texture: Texture2D = null
	if target.has_method("get_top_down_icon_texture"):
		texture = target.call("get_top_down_icon_texture") as Texture2D
	# Captures normally happen in 3D mode; read the bestiary portrait
	# cache directly without switching the live desktop token to 2D.
	if texture == null and target.has_method("get_miniature_identity"):
		var manager: Node = target.get_node_or_null("/root/TokenPackManager")
		if manager != null:
			var url: String = String(manager.call(
				"get_bestiary_token_url", target.call("get_miniature_identity")
			))
			if not url.is_empty():
				texture = manager.call("get_bestiary_texture", url) as Texture2D
				if texture == null:
					manager.call("request_bestiary_texture", url)
	if texture == null:
		# Match the desktop's fallback to a miniature rendered from its
		# actual model, rather than an opaque tile or placeholder initials.
		texture = overlay.call("_miniature_preview_texture", badge, target) as Texture2D
	portrait.texture = texture
	portrait.visible = texture != null

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = String(marker.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	name_label.add_theme_color_override("font_outline_color", Color(0.07, 0.08, 0.11, 0.97))
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.size = Vector2(maxf(diameter * 2.0, 280.0), 42.0)
	name_label.position = Vector2((diameter - name_label.size.x) * 0.5, -49.0)
	badge.add_child(name_label)
	var height_cells: int = int(marker.get("elevation_cells", 0))
	if height_cells != 0:
		var height_label := Label.new()
		height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		height_label.text = "%+d □" % height_cells
		height_label.add_theme_font_size_override("font_size", 29)
		height_label.add_theme_color_override("font_color", Color.WHITE)
		height_label.add_theme_color_override("font_outline_color", Color.BLACK)
		height_label.add_theme_constant_override("outline_size", 5)
		height_label.position = Vector2(diameter + 4.0, diameter * 0.3)
		badge.add_child(height_label)
	if bool(marker.get("selected", false)):
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = Vector2(-4.0, -4.0)
		ring.size = badge.size + Vector2.ONE * 8.0
		var border := StyleBoxFlat.new()
		border.bg_color = Color.TRANSPARENT
		border.draw_center = false
		border.border_color = Color(0.33, 0.85, 0.69, 0.96)
		border.set_border_width_all(3)
		border.set_corner_radius_all(100)
		ring.add_theme_stylebox_override("panel", border)
		badge.add_child(ring)


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
	var scene_camera := board.get_node_or_null("Camera3D") as Camera3D
	var center: Vector3 = token.global_position if token != null else (
		Vector3(scene_camera.global_position.x, 0.0, scene_camera.global_position.z)
		if scene_camera != null else Vector3.ZERO)
	var floor_y := Elevation.token_support_air_level(token, cell) if token != null else 0.0
	var clearance := 64.0 * cell
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = clampf(field_feet, MIN_FIELD_FEET, MAX_FIELD_FEET) / 5.0 * cell
	camera.position = center + Vector3.UP * clearance
	camera.rotation = Vector3(-PI * 0.5, 0, 0)
	# Match the desktop 2D floor slice, relative to this token's own height.
	camera.near = clearance - 0.12 * cell
	camera.far = clearance + 1000.0 * cell
	camera.current = true
	var overlay: Control = ElevationOverlay.new()
	overlay.name = "MobileTokenOverlay"
	overlay.size = Vector2(SIZE)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(overlay)
	var result := {"ok": true, "format": "webp", "width": SIZE.x, "height": SIZE.y,
		"image": "", "token_overlays": true,
		"token_id": "", "field_feet": field_feet, "elevation": center.y,
		"title": String(token.call("get_display_name")) if token != null else "Mappa", "contours": [], "markers": [],
		"_projection": {"x": center.x, "y": center.y, "z": center.z, "size": camera.size, "width": SIZE.x, "height": SIZE.y}}
	result["areas"] = project_areas(board, result._projection)
	result["area_overlays"] = true
	var area_layer := Control.new()
	area_layer.name = "MobileAreaOverlay"
	area_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Below portraits; also bake the areas into the passive Partita image.
	viewport.add_child(area_layer)
	viewport.move_child(area_layer, overlay.get_index())
	area_layer.draw.connect(_draw_areas.bind(area_layer, result.areas))
	area_layer.queue_redraw()
	var half: float = (float(token.call("get_footprint_cells")) if token != null else 1.0) * cell * 0.5
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
	# Include peer-shared targeting ranges on mobile tactical snapshots.
	var shared_attack: Node = board.get_node_or_null("AttackSystem")
	if shared_attack != null and shared_attack.has_method("shared_range_previews"):
		for preview: Dictionary in shared_attack.call("shared_range_previews"):
			var normal_feet := float(preview.get("normal", 0.0))
			var long_feet := float(preview.get("long", 0.0))
			for reach: float in [normal_feet, long_feet]:
				if reach <= 0.0:
					continue
				var points: Array = []
				var source_center: Vector3 = preview["center"]
				for point: Vector2 in RangeGeometry.rounded_footprint_perimeter(
					float(preview["half"]), reach / 5.0 * cell
				):
					var pixel := camera.unproject_position(source_center + Vector3(point.x, 0, point.y))
					points.append([pixel.x, pixel.y])
				result.contours.append({"points": points, "long": reach == long_feet, "shared": true})
	for node: Node in board.get_tree().get_nodes_in_group("dnd_token"):
		if not node is CharacterBody3D or not board.is_ancestor_of(node) or not node.is_visible_in_tree() or node.is_queued_for_deletion():
			continue
		var support_y := Elevation.token_support_air_level(node as Node3D, cell)
		var delta := support_y - floor_y
		var elevation_cells := 0 if absf(delta) < cell * 0.65 else roundi(delta / cell)
		var position := camera.unproject_position(Vector3(node.global_position.x, center.y, node.global_position.z))
		var radius: float = float(node.call("get_footprint_cells")) * cell / camera.size * SIZE.y * 0.5
		result.markers.append({"x": position.x, "y": position.y, "radius": radius,
			"name": String(node.call("get_display_name")), "selected": node == token,
			"id": String(node.call("get_token_id")) if node.has_method("get_token_id") else String(node.get_meta("sync_id", "")),
			"elevation_cells": elevation_cells, "conditions": node.call("get_conditions"),
			"status_text": " · ".join(node.call("get_active_condition_display_parts")) if node.has_method("get_active_condition_display_parts") else "",
			"affected": bool(node.get_meta("mobile_target_selected", false))})
		_add_token_badge(overlay, node as CharacterBody3D, result.markers[-1])
	# Render miniature preview viewports first, then capture the complete
	# orthographic map with 2D portraits, names and relative elevations.
	await RenderingServer.frame_post_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if token != null and not is_instance_valid(token):
		viewport.queue_free()
		return {"ok": false, "error": "Il token non è più presente."}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "Impossibile acquisire la mappa."}
	var encoded := encode_snapshot(image)
	if encoded.is_empty():
		viewport.queue_free()
		return {"ok": false, "error": "Impossibile comprimere lo snapshot."}
	result.image = Marshalls.raw_to_base64(encoded)
	viewport.queue_free()
	return result

# Godot's first WebP argument is LOSSY (false ignores quality). Adapt the
# encoding, never the camera field or pixel geometry used for targeting.
static func encode_snapshot(image: Image) -> PackedByteArray:
	var rgb := image.duplicate() as Image
	rgb.convert(Image.FORMAT_RGB8)
	for quality: float in [0.92, 0.78, 0.60, 0.40, 0.20, 0.0]:
		var encoded := rgb.save_webp_to_buffer(true, quality)
		if not encoded.is_empty() and encoded.size() <= 1300000:
			return encoded
	return PackedByteArray()
