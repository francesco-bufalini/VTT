extends Control
# Screen-space spell targeting HUD for Godot's top-down view.
# Drawing in the UI CanvasLayer keeps all outlines above token sprites,
# buildings and the 3D picking volumes, without intercepting mouse events.

var board: Node3D
var spell: Node
var measure: Node3D
var camera: Camera3D
var _areas: Array[Dictionary] = []
var _was_visible: bool = false
var _cached_signature: String = ""
var _cached_targets: Array[String] = []


func setup(root: Node3D, spell_system: Node, measurement: Node3D, view_camera: Camera3D) -> void:
	board = root
	spell = spell_system
	measure = measurement
	camera = view_camera
	name = "SpellTargetOverlay2D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80


func _is_active() -> bool:
	return (
		board != null and is_instance_valid(board)
		and board.has_method("is_2d_view_enabled")
		and bool(board.call("is_2d_view_enabled"))
		and camera != null and is_instance_valid(camera)
		and measure != null and is_instance_valid(measure)
	)


func _process(_delta: float) -> void:
	if not _is_active():
		if _was_visible:
			_was_visible = false
			queue_redraw()
		return
	_was_visible = true
	_collect_post_cast_areas()
	queue_redraw()


func _world_point(point: Vector3) -> Vector2:
	return camera.unproject_position(point)


func _circle_polygon(center: Vector3, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in range(64):
		var angle: float = TAU * float(index) / 64.0
		result.append(_world_point(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)))
	return result


func _shape_polygon(start: Vector3, end: Vector3, shape: String, line_width: float = -1.0) -> PackedVector2Array:
	var radius: float = maxf(start.distance_to(end), 0.01)
	if shape in ["sphere", "cylinder"]:
		return _circle_polygon(start, radius)
	if shape in ["cube", "flat_square"]:
		var square := PackedVector2Array()
		for offset: Vector3 in [
			Vector3(-radius, 0, -radius), Vector3(radius, 0, -radius),
			Vector3(radius, 0, radius), Vector3(-radius, 0, radius)
		]:
			square.append(_world_point(start + offset))
		return square
	var axis := Vector2(end.x - start.x, end.z - start.z)
	if axis.length_squared() < 0.00001:
		return _circle_polygon(start, maxf(line_width, 0.15))
	var perpendicular: Vector2 = Vector2(-axis.y, axis.x).normalized()
	var half_width: float = maxf(line_width, 0.2) * 0.5
	if shape == "cone":
		half_width = axis.length() * 0.5
		var wedge := PackedVector2Array()
		wedge.append(_world_point(start))
		for i: int in range(17):
			var step: float = float(i) / 16.0
			var lateral: float = (step * 2.0 - 1.0) * half_width
			var forward: float = axis.length() * sqrt(maxf(0.0, 1.0 - pow(lateral / (half_width * 2.0), 2.0)))
			var p: Vector2 = Vector2(start.x, start.z) + axis.normalized() * forward + perpendicular * lateral
			wedge.append(_world_point(Vector3(p.x, end.y, p.y)))
		return wedge
	var rectangle := PackedVector2Array()
	for p: Vector2 in [
		Vector2(start.x, start.z) - perpendicular * half_width,
		Vector2(end.x, end.z) - perpendicular * half_width,
		Vector2(end.x, end.z) + perpendicular * half_width,
		Vector2(start.x, start.z) + perpendicular * half_width
	]:
		rectangle.append(_world_point(Vector3(p.x, start.y, p.y)))
	return rectangle


func _draw_area(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var fill: Color = color
	fill.a = 0.16
	draw_colored_polygon(points, fill)
	var border := PackedVector2Array(points)
	border.append(points[0])
	draw_polyline(border, color, 2.6, true)


func _array_vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		var xyz: Array = value as Array
		return Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	return Vector3.ZERO


func _collect_post_cast_areas() -> void:
	_areas.clear()
	var held_value: Variant = measure.get("_held_spell_aoes")
	if held_value is Array:
		for item: Variant in held_value:
			if not item is Node3D:
				continue
			var root: Node3D = item as Node3D
			if not is_instance_valid(root) or not root.has_meta("spell_overlay_2d"):
				continue
			var data_value: Variant = root.get_meta("spell_overlay_2d")
			if not data_value is Dictionary:
				continue
			var data: Dictionary = (data_value as Dictionary).duplicate()
			data["root"] = root
			_areas.append(data)
	var persistent_value: Variant = measure.get("persistent_aoes")
	var roots_value: Variant = measure.get("_aoe_nodes")
	if not persistent_value is Array or not roots_value is Array:
		return
	var entries: Array = persistent_value as Array
	var roots: Array = roots_value as Array
	for index: int in range(mini(entries.size(), roots.size())):
		if not entries[index] is Dictionary or not roots[index] is Node3D:
			continue
		var data: Dictionary = entries[index] as Dictionary
		if not bool(data.get("spell_click_to_remove", false)):
			continue
		var root: Node3D = roots[index] as Node3D
		if not is_instance_valid(root):
			continue
		_areas.append({
			"root": root,
			"start": _array_vector3(data.get("start")),
			"end": _array_vector3(data.get("end")),
			"shape": String(data.get("shape", "sphere")),
			"width": float(data.get("line_width_world", -1.0))
		})


func remove_area_at_screen(point: Vector2) -> bool:
	if not _is_active():
		return false
	_collect_post_cast_areas()
	for index: int in range(_areas.size() - 1, -1, -1):
		var area: Dictionary = _areas[index]
		var polygon: PackedVector2Array = _shape_polygon(
			area.get("start", Vector3.ZERO),
			area.get("end", Vector3.ZERO),
			String(area.get("shape", "sphere")),
			float(area.get("width", -1.0))
		)
		if Geometry2D.is_point_in_polygon(point, polygon):
			return bool(measure.call("_remove_post_cast_spell_root", area.get("root")))
	return false


func _target_names(start: Vector3, end: Vector3, shape: String, width: float) -> Array[String]:
	if spell == null or not is_instance_valid(spell):
		return []
	var signature: String = "%s|%s|%s|%s" % [str(start), str(end), shape, str(width)]
	if _cached_signature == signature:
		return _cached_targets
	_cached_signature = signature
	_cached_targets.clear()
	var target_data: Dictionary = {
		"aoe_shape": shape,
		"aoe_radius_feet": start.distance_to(end) * 5.0 / maxf(float(board.get("cell_size")), 0.001),
		"aoe_line_width_feet": width * 5.0 / maxf(float(board.get("cell_size")), 0.001)
	}
	var values: Variant = spell.call("_spell_targets_in_geometry", start, end, target_data, null)
	if values is Array:
		for item: Variant in values:
			if item is Node3D and is_instance_valid(item):
				var token: Node3D = item as Node3D
				if not token.name in _cached_targets:
					_cached_targets.append(String(token.name))
	return _cached_targets


func _draw_target_list(names: Array[String], area_label: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 15
	var max_lines: int = mini(names.size(), 11)
	var panel_width: float = 252.0
	var panel_height: float = float(max_lines + 2) * 23.0 + 14.0
	var origin: Vector2 = Vector2(maxf(size.x - panel_width - 18.0, 8.0), 132.0)
	draw_rect(Rect2(origin, Vector2(panel_width, panel_height)), Color(0.025, 0.04, 0.07, 0.86), true)
	draw_rect(Rect2(origin, Vector2(panel_width, panel_height)), Color(0.38, 0.68, 1.0, 0.9), false, 1.5)
	draw_string(font, origin + Vector2(12, 25), area_label + " (" + str(names.size()) + ")", HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20, font_size, Color(0.73, 0.88, 1.0))
	if names.is_empty():
		draw_string(font, origin + Vector2(12, 51), "Nessun bersaglio", HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20, font_size, Color.WHITE)
	else:
		for index: int in range(max_lines):
			draw_string(font, origin + Vector2(12, 51 + index * 23), "• " + names[index], HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20, font_size, Color.WHITE)
		if names.size() > max_lines:
			draw_string(font, origin + Vector2(12, 51 + max_lines * 23), "…", HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20, font_size, Color.WHITE)


func _draw() -> void:
	if not _is_active():
		return
	var range_mesh: MeshInstance3D = measure.get("_spell_range_preview") as MeshInstance3D
	if range_mesh != null and is_instance_valid(range_mesh) and range_mesh.visible and bool(spell.call("is_targeting")):
		var range_center: Vector3 = measure.get("_spell_range_center")
		var radius: float = float(measure.get("_spell_range_radius"))
		if radius > 0.0:
			_draw_area(_circle_polygon(range_center, radius), Color(0.23, 0.64, 1.0, 0.83))
	var hover_area: Dictionary = {}
	for data: Dictionary in _areas:
		var points: PackedVector2Array = _shape_polygon(
			data.get("start", Vector3.ZERO), data.get("end", Vector3.ZERO),
			String(data.get("shape", "sphere")), float(data.get("width", -1.0))
		)
		_draw_area(points, Color(1.0, 0.54, 0.18, 0.94))
		hover_area = data
	var preview: MeshInstance3D = measure.get("_spell_preview") as MeshInstance3D
	if preview != null and is_instance_valid(preview) and preview.visible and bool(spell.call("is_targeting")):
		var start: Vector3 = measure.get("_spell_preview_start")
		var end: Vector3 = measure.get("_spell_preview_end")
		var shape: String = String(measure.get("_spell_preview_shape"))
		var width: float = float(measure.get("_spell_preview_line_width"))
		_draw_area(_shape_polygon(start, end, shape, width), Color(1.0, 0.72, 0.20, 1.0))
		if shape != "line":
			_draw_target_list(_target_names(start, end, shape, width), "Nell'area")
		else:
			var names: Array[String] = []
			var position: Vector2 = get_viewport().get_mouse_position()
			var token_value: Variant = spell.call("_token_at_screen", position)
			if token_value is Node3D:
				var token: Node3D = token_value as Node3D
				if is_instance_valid(token):
					names.append(String(token.name))
			_draw_target_list(names, "Bersagli")
	elif not hover_area.is_empty():
		_draw_target_list(
			_target_names(hover_area.get("start", Vector3.ZERO), hover_area.get("end", Vector3.ZERO),
				String(hover_area.get("shape", "sphere")), float(hover_area.get("width", -1.0))),
			"Nell'area"
		)
