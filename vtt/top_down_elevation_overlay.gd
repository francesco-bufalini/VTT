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
	_hover_text.add_theme_font_size_override("font_size", 13)
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
	var badge: Control = Control.new()
	badge.z_index = 10
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.color = Color(0.08, 0.11, 0.15, 0.94)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(background)

	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.add_child(portrait)

	var fallback: Label = Label.new()
	fallback.name = "Fallback"
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(fallback)

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


func _format_difference(delta_y: float) -> String:
	var squares: float = delta_y / cell_size
	var feet: float = squares * 5.0
	var meters: float = feet * 0.3048
	var cells_text: String = "%+.0f" % squares
	if absf(squares - roundf(squares)) > 0.05:
		cells_text = "%+.1f" % squares
	return "%+.2f m · %+.1f ft · %s quadretti" % [
		meters,
		feet,
		cells_text
	]


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
	var background: ColorRect = badge.get_node("Background") as ColorRect
	var portrait: TextureRect = badge.get_node("Portrait") as TextureRect
	var fallback: Label = badge.get_node("Fallback") as Label
	for graphic: Control in [background, portrait, fallback]:
		graphic.position = Vector2.ZERO
		graphic.size = Vector2.ONE * icon_size
	background.color = Color(0.09, 0.13, 0.20, 0.94)

	var texture: Texture2D = null
	if token.has_method("get_top_down_icon_texture"):
		texture = token.call("get_top_down_icon_texture") as Texture2D
	portrait.texture = texture
	portrait.visible = texture != null
	fallback.visible = texture == null
	if texture == null:
		var display_name: String = String(token.get("token_display_name"))
		if display_name.is_empty():
			display_name = token.name
		fallback.text = display_name.left(2).to_upper()
		fallback.add_theme_font_size_override(
			"font_size",
			maxi(10, mini(24, int(icon_size * 0.42)))
		)

	var base_y: float = token.global_position.y - (
		float(token.get("token_height_cells")) * float(token.get("cell_size")) * 0.5
	)
	var delta: float = base_y - floor_y
	var height_label: Label = badge.get_node("Height") as Label
	height_label.position = Vector2(icon_size + 6.0, icon_size * 0.3)
	height_label.add_theme_font_size_override("font_size", 12)
	height_label.text = _format_difference(delta)
	height_label.visible = absf(delta) >= cell_size * 0.1


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
	var result_value: Variant = levels.call(
		"get_lower_square_surface",
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
	if delta >= -cell_size * 0.1:
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
