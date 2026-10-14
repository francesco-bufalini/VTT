extends Control
const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
# Screen-space spell targeting HUD for Godot's top-down view.
# Draw in the board UI layer above the 2D token portraits but below
# creature sheets, dialogs, and menus; never intercept mouse events.

var _mobile_projection: Dictionary = {}
var board: Node3D
var spell: Node
var measure: Node3D
var camera: Camera3D
var _areas: Array[Dictionary] = []
var _was_visible: bool = false
var _cached_signature: String = ""
var _cached_targets: Array[String] = []
var _area_sidebar: PanelContainer
var _area_rows: VBoxContainer
var _sidebar_signature := ""
var _sidebar_elapsed := 0.0


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
	_build_area_sidebar()


func _is_active() -> bool:
	# The HUD target list belongs to both camera modes; only the projected
	# contour drawing below is restricted to the top-down 2D view.
	return (
		board != null and is_instance_valid(board)
		and camera != null and is_instance_valid(camera)
		and measure != null and is_instance_valid(measure)
	)


func _is_2d_view() -> bool:
	return board.has_method("is_2d_view_enabled") and bool(board.call("is_2d_view_enabled"))


func _process(_delta: float) -> void:
	if not _is_active():
		if _was_visible:
			_was_visible = false
			queue_redraw()
		return
	_collect_post_cast_areas()
	_sidebar_elapsed += _delta
	if _sidebar_elapsed >= 0.15:
		_sidebar_elapsed = 0.0
		_refresh_area_sidebar()
	var visible_now: bool = not _areas.is_empty() or (
		spell != null and is_instance_valid(spell) and bool(spell.call("is_targeting"))
	)
	if visible_now or _was_visible:
		queue_redraw()
	_was_visible = visible_now


func _world_point(point: Vector3) -> Vector2:
	if not _mobile_projection.is_empty():
		var scale_factor: float = float(_mobile_projection.height) / float(_mobile_projection.size)
		return Vector2(float(_mobile_projection.width) * 0.5 + (point.x - float(_mobile_projection.x)) * scale_factor,
			float(_mobile_projection.height) * 0.5 + (point.z - float(_mobile_projection.z)) * scale_factor)
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
	var geometry: Dictionary = {}
	if measure.has_method("_aoe_geometry"):
		geometry = measure.call("_aoe_geometry", start, end, shape, style, line_width)
		radius = float(geometry.get("radius", geometry.get("reach", radius)))
		if shape in ["cube", "flat_square"]:
			var extent: Vector3 = geometry.get("size", Vector3.ONE)
			radius = extent.x * 0.5
	if shape in ["sphere", "cylinder"]:
		return _circle_polygon(geometry.get("position", start), radius)
	if shape in ["cube", "flat_square"]:
		var square := PackedVector2Array()
		for offset: Vector3 in [
			Vector3(-radius, 0, -radius), Vector3(radius, 0, -radius),
			Vector3(radius, 0, radius), Vector3(-radius, 0, radius)
		]:
			square.append(_world_point(start + offset))
		return square
	if not geometry.is_empty() and shape in ["cone", "line"]:
		var basis: Basis = geometry.get("basis", Basis.IDENTITY)
		var center: Vector3 = geometry.get("position", start)
		var half_axis: Vector3 = basis * Vector3.UP * float(geometry.get("height", 1.0)) * 0.5
		start = center - half_axis
		end = center + half_axis
	var axis := Vector2(end.x - start.x, end.z - start.z)
	if axis.length_squared() < 0.00001:
		return _circle_polygon(start, radius if not geometry.is_empty() else maxf(line_width, 0.15))
	var perpendicular: Vector2 = Vector2(-axis.y, axis.x).normalized()
	var half_width: float = line_width * 0.5 if line_width > 0.0 else float(measure.call("_aoe_line_radius", style))
	if not geometry.is_empty():
		half_width = float(geometry.get("radius", half_width))
	if shape == "cone":
		# D&D cone: the far edge is as wide as the cone's length.
		half_width = float(geometry.get("radius", axis.length() * 0.5))
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
		if String(data.get("shape", "")) not in ["sphere", "cube", "cone", "line", "cylinder", "flat_square"]:
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
			"style": String(data.get("style", "")),
			"color": measure.call("_deserialize_aoe_color", data.get("color", {})),
			"removable_spell": bool(data.get("spell_click_to_remove", false))
		})


func remove_area_at_screen(point: Vector2) -> bool:
	if not _is_active():
		return false
	_collect_post_cast_areas()
	for index: int in range(_areas.size() - 1, -1, -1):
		var area: Dictionary = _areas[index]
		if not bool(area.get("removable_spell", area.get("root").has_meta("spell_overlay_2d"))):
			continue
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
	# Godot also automatically renames duplicate nodes Token2, Token3, etc.
	if normalized.begins_with("token") and normalized.substr(5).is_valid_int():
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
			signature += str(token.get("token_height_cells"))
			if token.has_method("get_footprint_cells"):
				signature += str(token.call("get_footprint_cells"))
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

# Read the same tactical token distance as the cast eligibility checks,
# not the planar contour (which would include wrong elevations).
func _range_target_names() -> Array[String]:
	var names: Array[String] = []
	if spell == null or not is_instance_valid(spell) or not bool(spell.call("is_targeting")):
		return names
	var caster: Node3D = spell.get("_pending_caster") as Node3D
	if caster == null or not is_instance_valid(caster):
		return names
	var spell_data: Dictionary = spell.call("_pending_spell")
	var range_feet: float = float(spell.call("_effective_spell_range_feet", spell_data, caster))
	var origin: Node3D = caster
	if String(spell.get("_targeting_phase")) == "chain_secondary":
		var primary: Node3D = spell.get("_pending_chain_primary") as Node3D
		if primary != null and is_instance_valid(primary):
			origin = primary
			range_feet = float(spell_data.get("secondary_range_feet", 30.0))
	elif String(spell.get("_targeting_phase")) in ["teleport_destination", "teleport_passengers"]:
		range_feet = float(spell_data.get("teleport_distance_feet", range_feet))
	var self_target: bool = String(spell_data.get("range", "")).strip_edges().to_lower().begins_with("self")
	for raw: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not raw is Node3D or not is_instance_valid(raw):
			continue
		var token: Node3D = raw as Node3D
		if not board.is_ancestor_of(token) or (token == origin and not self_target):
			continue
		if float(spell.call("_token_target_distance_feet", origin, token)) <= range_feet + 0.001:
			names.append(_target_display_name(token))
	return names


func _draw_spell_range(center: Vector3, radius: float) -> void:
	var scale: float = maxf(0.001, float(board.get("cell_size")))
	var half_footprint: float = float(measure.get("_spell_range_footprint"))
	if half_footprint < 0.0:
		half_footprint = scale * 0.5
	var vertices: PackedVector2Array = RangeGeometry.rounded_footprint_perimeter(half_footprint, radius)
	var projected := PackedVector2Array()
	for vertex: Vector2 in vertices:
		projected.append(_world_point(Vector3(center.x + vertex.x, center.y, center.z + vertex.y)))
	if projected.size() > 2:
		projected.append(projected[0])
		draw_polyline(projected, Color(0.22, 0.68, 1.0, 0.96), 2.8, true)


func _draw_target_list(names: Array[String], area_label: String, top: float = 132.0) -> float:
	if area_label == "A gittata":
		var radius: float = float(measure.get("_spell_range_radius"))
		area_label += " · %.1f ft" % (maxf(radius, 0.0) * 5.0 / maxf(float(board.get("cell_size")), 0.001))
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 15
	var max_lines: int = mini(names.size(), 11)
	var panel_width: float = 252.0
	var panel_height: float = float(max_lines + 2 + (1 if names.size() > max_lines else 0)) * 23.0 + 14.0
	var origin: Vector2 = Vector2(maxf(size.x - panel_width - 18.0, 8.0), top)
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
	return top + panel_height + 8.0


# Always return a typed array. A conditional expression with an untyped
# [] branch loses Array[String] at runtime when the preview is inactive.
func _range_names_for_hud(active_range: bool) -> Array[String]:
	var names: Array[String] = []
	if active_range:
		names = _range_target_names()
	return names


func _draw() -> void:
	if not _is_active():
		return
	var active_range: bool = (measure.get("_spell_range_active") == true) and bool(spell.call("is_targeting"))
	if _is_2d_view() and active_range:
		var range_center: Vector3 = measure.get("_spell_range_center")
		var radius: float = float(measure.get("_spell_range_radius"))
		if radius > 0.0:
			_draw_spell_range(range_center, radius)
	var hover_area: Dictionary = {}
	for data: Dictionary in _areas:
		if _is_2d_view():
			var points: PackedVector2Array = _shape_polygon(
				data.get("start", Vector3.ZERO), data.get("end", Vector3.ZERO),
				String(data.get("shape", "sphere")), float(data.get("width", -1.0)),
				String(data.get("style", ""))
			)
			_draw_area(points, _area_color(data))
			_draw_dimension_radii(data.get("start", Vector3.ZERO), data.get("end", Vector3.ZERO),
				String(data.get("shape", "sphere")), _area_color(data),
				float(data.get("width", -1.0)), String(data.get("style", "")))
		hover_area = data
	# Keep confirmed Magic Missile rays visible between successive picks.
	# The hovered ray is drawn from the 3D spell preview below.
	if _is_2d_view() and bool(spell.call("is_targeting")) and String(spell.get("_targeting_phase")) == "multi_target_tokens":
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
	var manual: MeshInstance3D = measure.get("_aoe_preview") as MeshInstance3D
	if manual != null and manual.visible:
		var start: Vector3 = measure.get("_start_center")
		var end: Vector3 = measure.get("_end_center")
		var shape: String = String(measure.get("aoe_shape"))
		if _is_2d_view():
			_draw_area(_shape_polygon(start, end, shape), manual.material_override.albedo_color)
			_draw_dimension_radii(start, end, shape, manual.material_override.albedo_color)
	var preview: MeshInstance3D = measure.get("_spell_preview") as MeshInstance3D
	var casting: bool = spell != null and is_instance_valid(spell) and bool(spell.call("is_targeting"))
	var range_list: Array[String] = _range_names_for_hud(active_range)
	if preview != null and is_instance_valid(preview) and preview.visible and casting:
		var start: Vector3 = measure.get("_spell_preview_start")
		var end: Vector3 = measure.get("_spell_preview_end")
		var shape: String = String(measure.get("_spell_preview_shape"))
		var width: float = float(measure.get("_spell_preview_line_width"))
		var style: String = String(measure.get("_spell_preview_style"))
		if _is_2d_view():
			var preview_color: Color = (preview.material_override as StandardMaterial3D).albedo_color
			preview_color.a = 1.0
			_draw_area(_shape_polygon(start, end, shape, width, style), preview_color)
			_draw_dimension_radii(start, end, shape, preview_color, width, style)
		if shape != "line" or String(spell.call("_pending_spell").get("aoe_shape", "")) == "line":
			var next_y: float = _draw_target_list(_target_names(start, end, shape, width, style), "Nell'area")
			if active_range:
				_draw_target_list(range_list, "A gittata", next_y)
			return
	# Token-targeting spells don't always create an AoE preview mesh.
	# Keep their affected-token HUD available in both camera modes.
	if casting:
		var mode: String = String(spell.get("_targeting_phase"))
		if mode in [
			"target_token", "multi_target_tokens", "transform_target",
			"transform_multi_targets", "resize_target",
			"chain_primary", "chain_secondary"
		]:
			var names: Array[String] = []
			var position: Vector2 = (
				get_viewport().get_visible_rect().size * 0.5
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else get_viewport().get_mouse_position()
			)
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
			var next_y: float = _draw_target_list(names, "Bersagli")
			if active_range:
				_draw_target_list(range_list, "A gittata", next_y)
			return
	var next_y: float = 132.0
	if not hover_area.is_empty() and _area_sidebar == null:
		next_y = _draw_target_list(
			_target_names(hover_area.get("start", Vector3.ZERO), hover_area.get("end", Vector3.ZERO),
				String(hover_area.get("shape", "sphere")), float(hover_area.get("width", -1.0)),
				String(hover_area.get("style", ""))),
			"Nell'area"
		)
	if active_range:
		_draw_target_list(range_list, "A gittata", next_y)


func _build_area_sidebar() -> void:
	_area_sidebar = PanelContainer.new()
	_area_sidebar.name = "AreaDimensionsSidebar"
	_area_sidebar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_area_sidebar.position = Vector2(12, 112)
	_area_sidebar.custom_minimum_size = Vector2(275, 0)
	_area_sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.07, 0.9)
	background.set_content_margin_all(10)
	background.set_corner_radius_all(6)
	_area_sidebar.add_theme_stylebox_override("panel", background)
	add_child(_area_sidebar)
	var body := VBoxContainer.new()
	_area_sidebar.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text = "AREE · DIMENSIONI E CREATURE"
	heading.add_theme_font_size_override("font_size", 14)
	header.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.name = "AreasScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	body.add_child(scroll)
	var collapse := Button.new()
	collapse.text = "-"
	collapse.tooltip_text = "Mostra o nascondi l'elenco delle aree"
	header.add_child(collapse)
	collapse.pressed.connect(func() -> void:
		scroll.visible = not scroll.visible
		collapse.text = "-" if scroll.visible else "+"
		_sidebar_signature = ""
		_area_sidebar.reset_size()
	)
	_area_rows = VBoxContainer.new()
	_area_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_area_rows)
	_area_sidebar.hide()


func _area_color(data: Dictionary) -> Color:
	var tint: Color = data.get("color", Color(0, 0, 0, -1))
	if tint.a < 0.0:
		tint = measure.call("_spell_style_color", String(data.get("style", "")))
	tint.a = 0.94
	return tint


func _sidebar_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = _areas.duplicate()
	var fixed: Variant = measure.get("_spell_fixed_previews")
	if fixed is Array:
		for preview: Variant in fixed:
			if preview is MeshInstance3D and is_instance_valid(preview) and preview.has_meta("area_dimensions"):
				result.append((preview.get_meta("area_dimensions") as Dictionary).duplicate())
	for spec: Dictionary in [
		{"node": "_aoe_preview", "start": "_start_center", "end": "_end_center", "shape": "aoe_shape", "manual": true},
		{"node": "_spell_preview", "start": "_spell_preview_start", "end": "_spell_preview_end", "shape": "_spell_preview_shape", "manual": false}
	]:
		var visual: MeshInstance3D = measure.get(spec["node"]) as MeshInstance3D
		if visual == null or not is_instance_valid(visual) or not visual.visible:
			continue
		var data := {"start": measure.get(spec["start"]), "end": measure.get(spec["end"]),
			"shape": String(measure.get(spec["shape"])), "preview": true,
			"color": (visual.material_override as StandardMaterial3D).albedo_color,
			"spell_preview": not bool(spec["manual"])}
		if not bool(spec["manual"]):
			data["style"] = String(measure.get("_spell_preview_style"))
			data["width"] = float(measure.get("_spell_preview_line_width"))
		result.push_front(data)
	return result


func _area_target_names(data: Dictionary) -> Array[String]:
	if bool(data.get("spell_preview", false)):
		return _target_names(data["start"], data["end"], String(data["shape"]),
			float(data.get("width", -1.0)), String(data.get("style", "")))
	var result: Array[String] = []
	var tokens: Array = measure.call("area_affected_tokens", data["start"], data["end"],
		String(data["shape"]), String(data.get("style", "")), float(data.get("width", -1.0)))
	for token: Node3D in tokens:
		result.append(_target_display_name(token))
	return result


func _refresh_area_sidebar() -> void:
	if _area_sidebar == null:
		return
	var entries: Array[Dictionary] = _sidebar_entries()
	_area_sidebar.visible = not entries.is_empty()
	var scroll := _area_rows.get_parent() as ScrollContainer
	if not scroll.visible:
		return
	scroll.custom_minimum_size = Vector2(minf(275.0, maxf(140.0, size.x - 44.0)),
		minf(440.0, maxf(60.0, size.y - 190.0)))
	var signature: String = str(size) + JSON.stringify(entries)
	for token: Node in get_tree().get_nodes_in_group("dnd_token"):
		if token is Node3D and board.is_ancestor_of(token):
			signature += str(token.get_instance_id()) + str(token.global_position) + _target_display_name(token)
			signature += str(token.get("token_height_cells"))
			if token.has_method("get_footprint_cells"):
				signature += str(token.call("get_footprint_cells"))
	if signature == _sidebar_signature:
		return
	_sidebar_signature = signature
	var previous_scroll: int = scroll.scroll_vertical
	for child: Node in _area_rows.get_children():
		_area_rows.remove_child(child)
		child.queue_free()
	var counts: Dictionary = {}
	for data: Dictionary in entries:
		var shape: String = String(data["shape"])
		counts[shape] = int(counts.get(shape, 0)) + 1
		var title := Label.new()
		var shape_name: String = {"sphere": "Sfera", "cube": "Cubo", "cone": "Cono",
			"line": "Linea", "cylinder": "Cilindro", "flat_square": "Quadrato"}.get(shape, shape)
		title.text = "● %s %d%s" % [shape_name, counts[shape], " · anteprima" if bool(data.get("preview", false)) else ""]
		title.add_theme_color_override("font_color", _area_color(data))
		_area_rows.add_child(title)
		var dimensions := Label.new()
		dimensions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dimensions.text = measure.call("aoe_dimensions_description", data["start"], data["end"],
			shape, String(data.get("style", "")), float(data.get("width", -1.0)))
		_area_rows.add_child(dimensions)
		var names: Array[String] = _area_target_names(data)
		var targets := Label.new()
		targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		targets.text = ("%s (%d)" % ["Attraversate" if shape == "line" else "Nell'area", names.size()])
		for target: String in names:
			targets.text += "\n• " + target
		if names.is_empty():
			targets.text += "\nNessuna creatura"
		_area_rows.add_child(targets)
	scroll.set_deferred("scroll_vertical", previous_scroll)


func _draw_dimension_radii(start: Vector3, end: Vector3, shape: String, tint: Color, width: float = -1.0, style: String = "") -> void:
	if not measure.has_method("_aoe_geometry"):
		return
	var geometry: Dictionary = measure.call("_aoe_geometry", start, end, shape, style, width)
	var points: PackedVector3Array = RangeGeometry.dimension_radii_points(geometry)
	var transform := Transform3D(geometry.get("basis", Basis.IDENTITY), geometry.get("position", start))
	var color: Color = tint
	color.a = 0.94
	for index: int in range(0, points.size(), 2):
		var first: Vector2 = _world_point(transform * points[index])
		var last: Vector2 = _world_point(transform * points[index + 1])
		if first.distance_squared_to(last) > 0.1:
			draw_line(first, last, color, 2.6, true)

# Reuse desktop geometry without moving cameras or recapturing the map.
func mobile_preview_contour(projection: Dictionary) -> Array:
	var mesh: MeshInstance3D = measure.get("_spell_preview")
	if not is_instance_valid(mesh) or not mesh.visible:
		return []
	_mobile_projection = projection
	var polygon := _shape_polygon(measure.get("_spell_preview_start"), measure.get("_spell_preview_end"),
		String(measure.get("_spell_preview_shape")), float(measure.get("_spell_preview_line_width")), String(measure.get("_spell_preview_style")))
	_mobile_projection = {}
	var result: Array = []
	for point: Vector2 in polygon:
		result.append([point.x, point.y])
	return result
