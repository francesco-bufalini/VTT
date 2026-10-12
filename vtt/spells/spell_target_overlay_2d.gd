extends Control
# Screen-space spell targeting HUD for Godot's top-down view.
# Draw in the board UI layer above the 2D token portraits but below
# creature sheets, dialogs, and menus; never intercept mouse events.

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
	# TopDownTokenOverlay draws at -50. Gameplay HUD must stay behind
	# regular UI controls (z=0) and the creature sheet (z=30).
	z_index = -30


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
	_collect_post_cast_areas()
	var visible_now: bool = not _areas.is_empty() or (
		spell != null and is_instance_valid(spell) and bool(spell.call("is_targeting"))
	)
	if visible_now or _was_visible:
		queue_redraw()
	_was_visible = visible_now


func _world_point(point: Vector3) -> Vector2:
	# Render on the same projected floor as the 2D token icons.
	var floor_y: float = float(camera.call("get_top_down_level")) if camera.has_method("get_top_down_level") else point.y
	return camera.unproject_position(Vector3(point.x, floor_y, point.z))


func _circle_polygon(center: Vector3, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in range(64):
		var angle: float = TAU * float(index) / 64.0
		result.append(_world_point(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)))
	return result


func _shape_polygon(start: Vector3, end: Vector3, shape: String, line_width: float = -1.0, style: String = "") -> PackedVector2Array:
	var radius: float = maxf(Vector2(end.x - start.x, end.z - start.z).length(), 0.01)
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
	var half_width: float = line_width * 0.5 if line_width > 0.0 else float(measure.call("_aoe_line_radius", style))
	if shape == "cone":
		# D&D cone: the far edge is as wide as the cone's length.
		half_width = axis.length() * 0.5
		var wedge := PackedVector2Array()
		wedge.append(_world_point(start))
		for lateral: float in [-half_width, half_width]:
			var p: Vector2 = Vector2(end.x, end.z) + perpendicular * lateral
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
	fill.a = color.a * 0.14
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
			"width": float(data.get("line_width_world", -1.0)),
			"style": String(data.get("style", ""))
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
			float(area.get("width", -1.0)),
			String(area.get("style", ""))
		)
		if Geometry2D.is_point_in_polygon(point, polygon):
			return bool(measure.call("_remove_post_cast_spell_root", area.get("root")))
	return false


func _is_internal_token_name(candidate: String) -> bool:
	var normalized: String = candidate.strip_edges().to_lower()
	if normalized.is_empty() or normalized in ["token", "creature", "characterbody3d"]:
		return true
	if normalized.begins_with("@"):
		return true
	for prefix: String in ["token_", "token@", "token-", "characterbody3d", "dnd_token_"]:
		if normalized.begins_with(prefix):
			return true
	return false


func _target_display_name(token: Node3D) -> String:
	if token == null or not is_instance_valid(token):
		return "Creatura senza nome"

	# The token's actual displayed name is the first choice. Node.name
	# commonly contains the Godot node identifier or the literal "Token".
	var visible_name: String = ""
	if token.has_method("get_display_name"):
		visible_name = String(token.call("get_display_name")).strip_edges()
	if not _is_internal_token_name(visible_name):
		return visible_name

	# A linked sheet can be renamed independently from the node's identifier.
	# Its lightweight name index avoids loading/normalizing full records.
	var creature_id: String = String(token.get_meta("creature_id", "")).strip_edges()
	if not creature_id.is_empty() and board != null and is_instance_valid(board):
		var sheets: Node = board.get_node_or_null("CreatureArea")
		if sheets != null and sheets.has_method("get_owned_creature_name_index"):
			var index_value: Variant = sheets.call("get_owned_creature_name_index")
			if index_value is Dictionary:
				var sheet_name: String = String((index_value as Dictionary).get(creature_id, "")).strip_edges()
				if not _is_internal_token_name(sheet_name):
					return sheet_name

	# Remote-owned creatures can lack a local sheet but retain synchronized
	# character/monster names as metadata.
	for key: String in ["player_character_name", "master_creature_name"]:
		var metadata_name: String = String(token.get_meta(key, "")).strip_edges()
		if not _is_internal_token_name(metadata_name):
			return metadata_name

	var node_name: String = String(token.name).strip_edges()
	if not _is_internal_token_name(node_name):
		return node_name
	return "Creatura senza nome"


func _target_names(start: Vector3, end: Vector3, shape: String, width: float, style: String = "") -> Array[String]:
	if spell == null or not is_instance_valid(spell):
		return []
	var signature: String = "%s|%s|%s|%s|%s" % [str(start), str(end), shape, str(width), style]
	# Include display names as well as positions in the cache key: renaming a
	# token must immediately refresh the affected list without moving it.
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if node is Node3D and is_instance_valid(node):
			var token: Node3D = node as Node3D
			signature += "|%d:%s:%s" % [
				token.get_instance_id(),
				str(token.global_position),
				_target_display_name(token)
			]
	if _cached_signature == signature:
		return _cached_targets
	_cached_signature = signature
	_cached_targets.clear()
	# Query the same measurement geometry used by the actual red token
	# highlights; do not approximate the game's geometry from the drawing.
	var values: Variant = measure.call(
		"spell_geometry_affected_tokens", start, end, shape, style, width
	)
	if values is Array:
		for item: Variant in values:
			if item is Node3D and is_instance_valid(item):
				# Do not deduplicate by name: two goblins are still two targets.
				_cached_targets.append(_target_display_name(item as Node3D))
	return _cached_targets

func _draw_target_list(names: Array[String], area_label: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 15
	var max_lines: int = mini(names.size(), 11)
	var panel_width: float = 252.0
	var panel_height: float = float(max_lines + 2 + (1 if names.size() > max_lines else 0)) * 23.0 + 14.0
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
			String(data.get("shape", "sphere")), float(data.get("width", -1.0)),
			String(data.get("style", ""))
		)
		_draw_area(points, Color(1.0, 0.54, 0.18, 0.94))
		hover_area = data
	# Keep confirmed Magic Missile rays visible between successive picks.
	# The hovered ray is drawn from the 3D spell preview below.
	if bool(spell.call("is_targeting")) and String(spell.get("_targeting_phase")) == "multi_target_tokens":
		var caster: Node3D = spell.get("_pending_caster") as Node3D
		if caster != null and is_instance_valid(caster):
			var center: Vector2 = _world_point(caster.global_position)
			for value: Variant in spell.get("_pending_targets"):
				if value is Node3D and is_instance_valid(value):
					var target: Node3D = value as Node3D
					draw_line(center, _world_point(target.global_position), Color(0.32, 0.96, 1.0, 0.95), 3.0, true)
			for value: Variant in spell.get("_pending_target_points"):
				if value is Vector3:
					draw_line(center, _world_point(value), Color(0.32, 0.96, 1.0, 0.95), 3.0, true)
	var preview: MeshInstance3D = measure.get("_spell_preview") as MeshInstance3D
	if preview != null and is_instance_valid(preview) and preview.visible and bool(spell.call("is_targeting")):
		var start: Vector3 = measure.get("_spell_preview_start")
		var end: Vector3 = measure.get("_spell_preview_end")
		var shape: String = String(measure.get("_spell_preview_shape"))
		var width: float = float(measure.get("_spell_preview_line_width"))
		_draw_area(_shape_polygon(start, end, shape, width, String(measure.get("_spell_preview_style"))), Color(1.0, 0.72, 0.20, 1.0))
		if shape != "line":
			_draw_target_list(
				_target_names(start, end, shape, width, String(measure.get("_spell_preview_style"))),
				"Nell'area"
			)
		else:
			var names: Array[String] = []
			var position: Vector2 = get_viewport().get_mouse_position()
			var mode: String = String(spell.get("_targeting_phase"))
			var pending_spell: Dictionary = spell.call("_pending_spell")
			var target_data: Dictionary = {}
			if mode in ["target_token", "multi_target_tokens"]:
				target_data = spell.call("_target_or_point_data", position, pending_spell)
			elif mode in ["transform_target", "transform_multi_targets", "resize_target"]:
				target_data = spell.call("_transformation_target_data", position, pending_spell)
			elif mode in ["chain_primary", "chain_secondary"]:
				target_data = spell.call("_target_token_data", position, pending_spell)
			var hovered_token: Node3D = null
			if bool(target_data.get("valid", false)):
				hovered_token = target_data.get("target") as Node3D
				if hovered_token != null and is_instance_valid(hovered_token):
					names.append(_target_display_name(hovered_token))
			if mode == "multi_target_tokens":
				for entry: Node3D in spell.get("_pending_targets"):
					if entry != null and is_instance_valid(entry) and entry != hovered_token:
						names.append(_target_display_name(entry))
			_draw_target_list(names, "Bersagli")
	elif not hover_area.is_empty():
		_draw_target_list(
			_target_names(hover_area.get("start", Vector3.ZERO), hover_area.get("end", Vector3.ZERO),
				String(hover_area.get("shape", "sphere")), float(hover_area.get("width", -1.0)),
				String(hover_area.get("style", ""))),
			"Nell'area"
		)
