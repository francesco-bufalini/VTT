extends Control

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_hover_panel = PanelContainer.new()
	_hover_panel.z_index = 20
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_panel)
	_hover_text = Label.new()
	_hover_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_text.add_theme_font_size_override("font_size", 16)
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
	badge.z_index = 10
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
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.add_child(portrait)

	var name_label: Label = Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	name_label.add_theme_color_override("font_outline_color", Color(0.07, 0.08, 0.11, 0.95))
	name_label.add_theme_constant_override("outline_size", 5)
	badge.add_child(name_label)

	# Screen-space conditions must not be clipped when the camera changes
	# elevation. World-space rings may be behind the current slice plane.
	var conditions_label: Label = Label.new()
	conditions_label.name = "Conditions"
	conditions_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conditions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conditions_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conditions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conditions_label.add_theme_font_size_override("font_size", 17)
	conditions_label.add_theme_color_override(
		"font_color", Color(1.0, 0.86, 0.46)
	)
	conditions_label.add_theme_color_override(
		"font_outline_color", Color(0.07, 0.08, 0.11, 0.98)
	)
	conditions_label.add_theme_constant_override("outline_size", 5)
	conditions_label.visible = false
	badge.add_child(conditions_label)

	var height_label: Label = Label.new()
	height_label.name = "Height"
	height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	height_label.add_theme_color_override("font_color", Color.WHITE)
	height_label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	height_label.add_theme_constant_override("shadow_offset_x", 1)
	height_label.add_theme_constant_override("shadow_offset_y", 1)
	badge.add_child(height_label)
	return badge


# Tactical elevation is expressed in whole grid squares, not arbitrary
# physics fractions: a square corresponds to 5 ft (conventionally 1.5 m).
func _difference_cells(delta_y: float) -> int:
	return roundi(delta_y / maxf(cell_size, 0.001))


func _format_difference(delta_y: float) -> String:
	var squares: int = _difference_cells(delta_y)
	var meters_text: String = ("%+.1f" % (float(squares) * 1.5)).trim_suffix(".0")
	return "%s m · %+d ft · %+d quadretti" % [
		meters_text,
		squares * 5,
		squares
	]


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
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	if (
		screen_position.x < -100.0
		or screen_position.x > view_size.x + 100.0
		or screen_position.y < -100.0
		or screen_position.y > view_size.y + 100.0
	):
		badge.hide()
		return

	badge.show()
	var footprint: float = 1.0
	if token.has_method("get_footprint_cells"):
		footprint = maxf(float(token.call("get_footprint_cells")), 0.5)
	var icon_size: float = clampf(
		footprint * cell_size * view_size.y / maxf(camera.size, 0.01),
		16.0,
		180.0
	)
	badge.position = screen_position - Vector2.ONE * icon_size * 0.5

	var portrait: TextureRect = badge.get_node("Portrait") as TextureRect
	portrait.position = Vector2.ZERO
	portrait.size = Vector2.ONE * icon_size
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
	selection.size = Vector2.ONE * (icon_size + 10.0)
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
	name_label.size = Vector2(maxf(icon_size * 2.0, 220.0), 30.0)
	name_label.position = Vector2(
		(icon_size - name_label.size.x) * 0.5,
		-36.0
	)

	var conditions_label: Label = badge.get_node("Conditions") as Label
	var condition_parts := PackedStringArray()
	var show_conditions: bool = (
		not token.has_method("are_condition_visuals_visible")
		or bool(token.call("are_condition_visuals_visible"))
	)
	if show_conditions and token.has_method("get_active_condition_display_parts"):
		var active_parts: Variant = token.call("get_active_condition_display_parts")
		if active_parts is PackedStringArray:
			condition_parts = active_parts
	var conditions_text: String = "  ·  ".join(condition_parts)
	conditions_label.visible = not condition_parts.is_empty()
	if conditions_label.visible:
		# Reflow only when the content or icon size changes: updating hundreds
		# of tactical badges every frame must not re-layout their text.
		var text_width: float = clampf(icon_size * 3.0, 240.0, 360.0)
		if (
			conditions_label.text != conditions_text
			or not is_equal_approx(conditions_label.size.x, text_width)
		):
			conditions_label.text = conditions_text
			conditions_label.size = Vector2(text_width, 512.0)
			var lines: int = maxi(1, conditions_label.get_line_count())
			conditions_label.size.y = float(lines) * 25.0 + 6.0
		# Grow upward instead of covering the name or portrait.
		conditions_label.position = Vector2(
			(icon_size - text_width) * 0.5,
			name_label.position.y - conditions_label.size.y - 2.0
		)
	elif not conditions_label.text.is_empty():
		conditions_label.text = ""

	var base_y: float = token.global_position.y - (
		float(token.get("token_height_cells")) * float(token.get("cell_size")) * 0.5
	)
	var delta: float = base_y - floor_y
	var height_label: Label = badge.get_node("Height") as Label
	height_label.position = Vector2(icon_size + 6.0, icon_size * 0.3)
	height_label.add_theme_font_size_override("font_size", 16)
	height_label.text = _format_difference(delta)
	height_label.visible = _difference_cells(delta) != 0


func _update_hover(floor_y: float) -> void:
	_hover_panel.hide()
	if levels == null or not is_instance_valid(levels):
		return
	if bool(board_root.get("_ui_owns_mouse")):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and not is_ancestor_of(hovered):
		return

	var mouse: Vector2 = get_viewport().get_mouse_position()
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
