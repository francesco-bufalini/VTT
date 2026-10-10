extends Control

const TopDownElevationLevels = preload("res://vtt/top_down_elevation_levels.gd")

# Screen-space tactical proxies stay visible even when their 3D miniatures
# lie above or below the currently sliced map floor.
var board_root: Node3D
var camera: Camera3D
var levels: Node3D
var tokens_root: Node3D
var cell_size: float = 1.0
var _badges: Dictionary = {}
var _hover_panel: PanelContainer
var _hover_text: Label


func setup(board: Node3D, level_probe: Node3D) -> void:
	board_root = board
	levels = level_probe
	camera = board.get_node_or_null("Camera3D") as Camera3D
	tokens_root = board.get_node_or_null("Tokens") as Node3D
	cell_size = maxf(float(board.get("cell_size")), 0.001)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tactical graphics stay underneath every sheet/dialog sharing the UI layer.
	# Even elevated token labels must remain behind any character sheet.
	z_index = -50
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_hover_panel = PanelContainer.new()
	_hover_panel.z_index = 1
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_panel)
	_hover_text = Label.new()
	_hover_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_text.add_theme_font_size_override("font_size", 17)
	_hover_panel.add_child(_hover_text)
	_hover_panel.hide()


func set_2d_active(enabled: bool) -> void:
	visible = enabled
	if not enabled:
		_hover_panel.hide()
		for badge_value: Variant in _badges.values():
			if badge_value is Control:
				(badge_value as Control).hide()


func _new_badge() -> Control:
	# No opaque tile or initials: bestiary portraits keep their own alpha,
	# while tokens without portraits show their real 3D miniatures below.
	var badge: Control = Control.new()
	badge.z_index = 0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

	var selection: Panel = Panel.new()
	selection.name = "SelectionRing"
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style: StyleBoxFlat = StyleBoxFlat.new()
	ring_style.bg_color = Color.TRANSPARENT
	ring_style.draw_center = false
	ring_style.border_color = Color(0.33, 0.85, 0.69, 0.96)
	ring_style.set_border_width_all(3)
	ring_style.set_corner_radius_all(100)
	selection.add_theme_stylebox_override("panel", ring_style)
	selection.visible = false
	badge.add_child(selection)

	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	badge.add_child(portrait)

	var name_label: Label = Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	name_label.add_theme_color_override("font_outline_color", Color(0.07, 0.08, 0.11, 0.95))
	name_label.add_theme_constant_override("outline_size", 5)
	badge.add_child(name_label)

	# Screen-space status replicates the compact 3D tactical strip and
	# stays visible independently from 3D camera near-plane slicing.
	var status_background: Panel = Panel.new()
	status_background.name = "StatusBackground"
	status_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.05, 0.86)
	style.border_color = Color(0.72, 0.48, 0.20, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	status_background.add_theme_stylebox_override("panel", style)
	status_background.hide()
	badge.add_child(status_background)

	var conditions_label: Label = Label.new()
	conditions_label.name = "Conditions"
	conditions_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conditions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conditions_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conditions_label.clip_text = true
	conditions_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	conditions_label.add_theme_font_size_override("font_size", 13)
	conditions_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.73))
	conditions_label.add_theme_color_override("font_outline_color", Color(0.07, 0.08, 0.11, 0.98))
	conditions_label.add_theme_constant_override("outline_size", 2)
	conditions_label.hide()
	badge.add_child(conditions_label)

	var height_label: Label = Label.new()
	height_label.name = "Height"
	height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No opaque background: the original discreet text remains legible above
	# neighbouring token portraits but below the actual character sheet.
	height_label.z_index = 25
	height_label.add_theme_color_override("font_color", Color.WHITE)
	height_label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	height_label.add_theme_constant_override("shadow_offset_x", 1)
	height_label.add_theme_constant_override("shadow_offset_y", 1)
	badge.add_child(height_label)

	# A small heading tab sits underneath the portrait, rather than on top.
	var facing := Polygon2D.new()
	facing.name = "FacingArrow"
	facing.polygon = PackedVector2Array([
		Vector2(0.0, -9.0), Vector2(6.0, 7.0), Vector2(-6.0, 7.0)
	])
	facing.color = Color(0.60, 0.83, 0.81, 0.82)
	facing.z_index = -1
	badge.add_child(facing)
	return badge


# Tactical elevation is expressed in whole grid squares, not arbitrary
# physics fractions: a square corresponds to 5 ft (conventionally 1.5 m).
func _difference_cells(delta_y: float) -> int:
	var unit := maxf(cell_size, 0.001)
	# A collidable floor face may be half a voxel below its tactical level.
	# Rounding -0.5 away from zero used to produce a false "-1 □" hover.
	if absf(delta_y) < unit * 0.65:
		return 0
	return roundi(delta_y / unit)


func _format_difference(delta_y: float) -> String:
	# The unit is always tactical grid squares; omit metres and feet.
	return "%+d □" % _difference_cells(delta_y)


# Render a transparent thumbnail of the original 3D miniature for
# creatures without a bestiary token. The slice camera may clip their
# world-space meshes, so relying on the scene's 3D draw is not sufficient.
# A static SubViewport updates only when the token's visual identity changes.
func _miniature_preview_signature(token: CharacterBody3D) -> String:
	var imported: Node = token.get_node_or_null("Visuals/ImportedVisual")
	var imported_id: int = imported.get_instance_id() if imported != null else 0
	var visuals: Node3D = token.get_node_or_null("Visuals") as Node3D
	var visual_transform: Transform3D = (
		visuals.transform if visuals != null else Transform3D.IDENTITY
	)
	return "%s|%s|%d|%s|%s|%s|%s|%s|%s" % [
		str(token.get("visual_asset_path")),
		str(token.get("token_pack_id")),
		imported_id,
		str(token.get("visual_front_quarter_turns")),
		str(token.get("visual_pitch_steps")),
		str(token.get("token_height_cells")),
		str(token.get("cell_size")),
		str(token.call("get_footprint_cells"))
		if token.has_method("get_footprint_cells") else "1.0",
		str(visual_transform)
	]


func _remove_miniature_preview(badge: Control) -> void:
	var existing: Node = badge.get_node_or_null("MiniaturePreview")
	if existing != null:
		badge.remove_child(existing)
		existing.queue_free()
	badge.remove_meta("preview_signature")


func _miniature_preview_texture(
	badge: Control,
	token: CharacterBody3D
) -> Texture2D:
	var source_visuals: Node3D = token.get_node_or_null("Visuals") as Node3D
	if source_visuals == null:
		return null
	var signature: String = _miniature_preview_signature(token)
	var viewport: SubViewport = (
		badge.get_node_or_null("MiniaturePreview") as SubViewport
	)
	if viewport != null and str(badge.get_meta("preview_signature", "")) == signature:
		return viewport.get_texture()
	_remove_miniature_preview(badge)

	viewport = SubViewport.new()
	viewport.name = "MiniaturePreview"
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	badge.add_child(viewport)

	var model: Node3D = source_visuals.duplicate(0) as Node3D
	if model == null:
		_remove_miniature_preview(badge)
		return null
	model.name = "Model"
	viewport.add_child(model)

	var height: float = maxf(
		float(token.get("token_height_cells")) * float(token.get("cell_size")),
		0.5
	)
	var width: float = maxf(
		float(token.call("get_footprint_cells")) * float(token.get("cell_size")),
		0.5
	) if token.has_method("get_footprint_cells") else height
	var preview_camera: Camera3D = Camera3D.new()
	preview_camera.name = "PortraitCamera"
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size = maxf(height * 1.65, width * 1.95)
	preview_camera.near = 0.05
	preview_camera.far = 500.0
	viewport.add_child(preview_camera)
	preview_camera.position = Vector3(
		width * 1.1, height * 1.7, width * 1.65
	)
	preview_camera.look_at(Vector3.ZERO, Vector3.UP)
	preview_camera.current = true

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "PortraitLight"
	light.light_energy = 1.8
	light.shadow_enabled = false
	viewport.add_child(light)
	light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)

	badge.set_meta("preview_signature", signature)
	return viewport.get_texture()


# Size in screen pixels is computed from projected world-space grid cells.
# No pixel clamps: zoom must never decouple a portrait from its footprint.
# The separate axes also account for tilted orthographic 2D cameras.
static func token_icon_extent_pixels(
	view_camera: Camera3D,
	world_center: Vector3,
	footprint_world: float
) -> Vector2:
	var center: Vector2 = view_camera.unproject_position(world_center)
	var projected_x: Vector2 = view_camera.unproject_position(
		world_center + Vector3.RIGHT * footprint_world
	)
	var projected_z: Vector2 = view_camera.unproject_position(
		world_center + Vector3.BACK * footprint_world
	)
	return Vector2(
		maxf(center.distance_to(projected_x), 0.001),
		maxf(center.distance_to(projected_z), 0.001)
	)


func _render_token_badge(token: CharacterBody3D, floor_y: float) -> void:
	var token_key: int = token.get_instance_id()
	var badge: Control = _badges.get(token_key) as Control
	if badge == null:
		badge = _new_badge()
		_badges[token_key] = badge

	var projected: Vector3 = Vector3(
		token.global_position.x,
		floor_y,
		token.global_position.z
	)
	if camera.is_position_behind(projected):
		badge.hide()
		return
	var screen_position: Vector2 = camera.unproject_position(projected)
	var footprint: float = 1.0
	if token.has_method("get_footprint_cells"):
		footprint = maxf(float(token.call("get_footprint_cells")), 1.0)
	var icon_extent: Vector2 = token_icon_extent_pixels(
		camera, projected, footprint * cell_size
	)
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var half_extent: Vector2 = icon_extent * 0.5
	if (
		screen_position.x + half_extent.x < 0.0
		or screen_position.x - half_extent.x > view_size.x
		or screen_position.y + half_extent.y < 0.0
		or screen_position.y - half_extent.y > view_size.y
	):
		badge.hide()
		return

	badge.show()
	badge.position = screen_position - half_extent

	var portrait: TextureRect = badge.get_node("Portrait") as TextureRect
	portrait.position = Vector2.ZERO
	portrait.size = icon_extent
	var texture: Texture2D = null
	if token.has_method("get_top_down_icon_texture"):
		texture = token.call("get_top_down_icon_texture") as Texture2D
	if texture != null:
		# Use the original transparent, round bestiary token unchanged.
		if badge.get_node_or_null("MiniaturePreview") != null:
			_remove_miniature_preview(badge)
	else:
		# No letters or colored squares: show the actual 3D model.
		texture = _miniature_preview_texture(badge, token)
	portrait.texture = texture
	portrait.visible = texture != null

	var selection: Panel = badge.get_node("SelectionRing") as Panel
	selection.position = Vector2(-5.0, -5.0)
	selection.size = icon_extent + Vector2.ONE * 10.0
	selection.visible = (
		token.has_method("is_selected")
		and bool(token.call("is_selected"))
	)

	# The 2D label replaces only the clipped world-space name, not the
	# miniatures or their 3D identity. Always display the full name.
	var name_label: Label = badge.get_node("Name") as Label
	var display_name: String = token.name
	if token.has_method("get_display_name"):
		var provided_name: String = String(token.call("get_display_name")).strip_edges()
		if not provided_name.is_empty():
			display_name = provided_name
	name_label.text = display_name
	name_label.size = Vector2(maxf(icon_extent.x * 2.0, 180.0), 30.0)
	name_label.position = Vector2(
		(icon_extent.x - name_label.size.x) * 0.5,
		-57.0
	)

	var conditions_label: Label = badge.get_node("Conditions") as Label
	var status_background: Panel = badge.get_node("StatusBackground") as Panel
	var status_icons := PackedStringArray()
	var status_descriptions := PackedStringArray()
	# Flanked is a derived combat state, not a manual 5e condition.
	if bool(token.get_meta("flanked", false)):
		status_icons.append("⚔")
		status_descriptions.append("Affiancato")
	# Use only condition icons in the tactical strip. Full names are much too
	# wide at ordinary zoom and used to cover several squares of the map.
	var show_manual_conditions: bool = true
	if token.has_method("are_condition_visuals_visible"):
		show_manual_conditions = bool(token.call("are_condition_visuals_visible"))
	if show_manual_conditions and token.has_method("get_active_condition_display_parts"):
		var active_parts: Variant = token.call("get_active_condition_display_parts")
		if active_parts is PackedStringArray:
			for part: String in active_parts:
				var normalized: String = part.strip_edges()
				if normalized.is_empty():
					continue
				var split_position: int = normalized.find(" ")
				var icon_text: String = (
					normalized.substr(0, split_position)
					if split_position > 0 else normalized
				)
				status_icons.append(icon_text)
				status_descriptions.append(normalized)
	var has_status: bool = not status_icons.is_empty()
	conditions_label.visible = has_status
	status_background.visible = has_status
	if has_status:
		var status_text: String = " ".join(status_icons)
		var status_font: Font = conditions_label.get_theme_font("font")
		var text_width: float = status_font.get_string_size(
			status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13
		).x
		var width_px: float = clampf(text_width + 12.0, 36.0, 176.0)
		var offset_x: float = (icon_extent.x - width_px) * 0.5
		status_background.position = Vector2(offset_x, -24.0)
		status_background.size = Vector2(width_px, 20.0)
		conditions_label.position = status_background.position
		conditions_label.size = status_background.size
		conditions_label.tooltip_text = "\n".join(status_descriptions)
		if conditions_label.text != status_text:
			conditions_label.text = status_text
	elif not conditions_label.text.is_empty():
		conditions_label.text = ""

	# Show the elevation of the free square supporting the token's feet,
	# rather than the body's lowest occupied square.
	var support_y: float = TopDownElevationLevels.token_support_air_level(
		token, cell_size
	)
	var delta: float = support_y - floor_y
	var height_label: Label = badge.get_node("Height") as Label
	# Restore the small, unboxed elevation label used before. Its z-index
	# protects it from the token on the right without covering character UI.
	height_label.position = Vector2(icon_extent.x - 2.0, icon_extent.y * 0.28)
	height_label.add_theme_font_size_override("font_size", 13)
	height_label.text = _format_difference(delta)
	height_label.visible = _difference_cells(delta) != 0

	var facing: Polygon2D = badge.get_node("FacingArrow") as Polygon2D
	var projected_forward: Vector3 = -token.global_transform.basis.z.normalized()
	var forward_screen: Vector2 = camera.unproject_position(projected + projected_forward * cell_size) - screen_position
	if forward_screen.length_squared() >= 1.0:
		forward_screen = forward_screen.normalized()
		facing.position = icon_extent * 0.5 + forward_screen * icon_extent * 0.48
		facing.rotation = forward_screen.angle() + PI * 0.5
		facing.visible = true
	else:
		facing.hide()


func _update_hover(floor_y: float) -> void:
	_hover_panel.hide()
	if levels == null or not is_instance_valid(levels):
		return
	var ui_mouse_owner: Variant = board_root.get("_ui_owns_mouse")
	if ui_mouse_owner is bool and ui_mouse_owner:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and not is_ancestor_of(hovered):
		return

	var mouse: Vector2 = get_viewport().get_mouse_position()
	# A 2D token icon is the visible object under the cursor. Its elevation
	# already has a badge: never replace it with the floor underneath.
	if board_root.has_method("_raycast_token_from_screen"):
		var token_hit: Variant = board_root.call(
			"_raycast_token_from_screen", mouse, true
		)
		if token_hit is Dictionary and not (token_hit as Dictionary).is_empty():
			return
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var direction: Vector3 = camera.project_ray_normal(mouse)
	if absf(direction.y) <= 0.00001:
		return
	var distance: float = (floor_y - origin.y) / direction.y
	if distance <= 0.0:
		return
	var world_point: Vector3 = origin + direction * distance
	# Sample the topmost surface visible on this camera floor first.
	# Only show a negative height when that square is genuinely lower.
	var result_value: Variant = levels.call(
		"get_visible_square_surface",
		world_point,
		floor_y
	)
	if not result_value is Dictionary:
		return
	var result: Dictionary = result_value as Dictionary
	if result.is_empty():
		return
	var lower_y: float = float(result.get("level", floor_y))
	var delta: float = lower_y - floor_y
	if _difference_cells(delta) >= 0:
		return
	_hover_text.text = _format_difference(delta)
	_hover_panel.show()
	_hover_panel.reset_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_hover_panel.position = Vector2(
		minf(mouse.x + 16.0, viewport_size.x - _hover_panel.size.x - 8.0),
		minf(mouse.y + 16.0, viewport_size.y - _hover_panel.size.y - 8.0)
	)


# Engagement arrows use the same cached world-space segments as the 3D
# renderer. Screen-space drawing bypasses the orthographic slice clipping.
func _draw() -> void:
	if not visible or camera == null or board_root == null:
		return
	var flanking: Node = board_root.get("flanking_system") as Node
	if flanking == null or not flanking.has_method("get_screen_reach_visuals"):
		return
	var visuals: Dictionary = flanking.call("get_screen_reach_visuals")
	_draw_engagement_segments(visuals.get("arrows", []), false)
	_draw_engagement_segments(visuals.get("mutual_markers", []), true)


func _draw_engagement_segments(segments: Variant, mutual: bool) -> void:
	if not segments is Array:
		return
	var points: Array = segments as Array
	var floor_y: float = float(camera.call("get_top_down_level"))
	var tint: Color = Color(0.40, 0.92, 0.72, 0.94) if mutual else Color(0.20, 0.82, 0.78, 0.88)
	for index: int in range(0, points.size() - 1, 2):
		if not points[index] is Vector3 or not points[index + 1] is Vector3:
			continue
		var start_world: Vector3 = points[index]
		var end_world: Vector3 = points[index + 1]
		# Project on the visible floor plane: the X/Z engagement geometry
		# is unchanged and remains legible at any current slice elevation.
		var screen_start: Vector2 = project_engagement_point(start_world, floor_y)
		var screen_end: Vector2 = project_engagement_point(end_world, floor_y)
		var delta: Vector2 = screen_end - screen_start
		if delta.length_squared() < 16.0:
			continue
		var direction: Vector2 = delta.normalized()
		var sideways: Vector2 = Vector2(-direction.y, direction.x)
		draw_line(screen_start, screen_end, Color(0.015, 0.09, 0.085, 0.92), 5.0, true)
		draw_line(screen_start, screen_end, tint, 2.6, true)
		var tips: Array[Vector2] = [screen_end]
		if mutual:
			tips.push_front(screen_start)
		for tip: Vector2 in tips:
			var toward: Vector2 = -direction if mutual and tip == screen_start else direction
			draw_colored_polygon(PackedVector2Array([
				tip,
				tip - toward * 11.0 + sideways * 5.0,
				tip - toward * 11.0 - sideways * 5.0
			]), tint)


func project_engagement_point(point: Vector3, floor_y: float) -> Vector2:
	# Token badges and reach arrows must share the visible floor even when
	# the camera is tilted or the creatures occupy different elevations.
	return camera.unproject_position(Vector3(point.x, floor_y, point.z))


func _process(_delta: float) -> void:
	if not visible or camera == null or not is_instance_valid(camera):
		return
	if not camera.has_method("get_top_down_level"):
		return
	var floor_y: float = float(camera.call("get_top_down_level"))
	var active_keys: Dictionary = {}
	if tokens_root != null and is_instance_valid(tokens_root):
		for node: Node in tokens_root.get_children():
			if not node is CharacterBody3D or not node.is_in_group("dnd_token"):
				continue
			var token: CharacterBody3D = node as CharacterBody3D
			var key: int = token.get_instance_id()
			active_keys[key] = true
			_render_token_badge(token, floor_y)
	for key: Variant in _badges.keys():
		if active_keys.has(key):
			continue
		var badge: Control = _badges[key] as Control
		if badge != null:
			badge.queue_free()
		_badges.erase(key)
	_update_hover(floor_y)
	queue_redraw()
