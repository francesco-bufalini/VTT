extends RefCounted

# Share one layout policy for all Godot dialogs, including native desktop
# windows and embedded game subwindows. Coordinates differ between modes:
# embedded positions are viewport-local, native positions are screen-absolute.


static func _root_bounds(dialog: Window) -> Vector2i:
	return dialog.get_tree().root.size


static func _touch(dialog: Window) -> bool:
	return OS.has_feature("mobile") or dialog.get_tree().root.has_meta("vtt_touch_layout")


# The root is the actual VTT window, not a stretched in-game viewport.
# In native mode Window.position is measured from the desktop origin; for
# embedded windows it is relative to the enclosing viewport.
static func _centered_popup_position(
	root_position: Vector2i, root_size: Vector2i,
	popup_size: Vector2i, embedded: bool
) -> Vector2i:
	var origin: Vector2i = Vector2i.ZERO if embedded else root_position
	return origin + (root_size - popup_size) / 2


static func _fit_window(dialog: Window, preferred_size: Vector2i, ratio: float, touch: bool) -> void:
	var root: Window = dialog.get_tree().root
	var available: Vector2i = root.size
	var margin: int = 12 if touch else 24
	var allowed: Vector2i = Vector2i(Vector2(available) * clampf(ratio, 0.1, 1.0))
	allowed = allowed.min(available - Vector2i(margin, margin)).max(Vector2i(1, 1))
	dialog.min_size = Vector2i.ZERO
	dialog.max_size = allowed
	if touch:
		dialog.size = preferred_size.min(allowed).max(Vector2i(1, 1))
	else:
		dialog.size = dialog.size.min(allowed).max(Vector2i(1, 1))
	dialog.position = _centered_popup_position(
		root.position, available, dialog.size, dialog.is_embedded()
	)


static func popup(
	dialog: Window,
	preferred_size: Vector2i,
	fallback_ratio: float = 0.92
) -> void:
	if dialog == null or not is_instance_valid(dialog) or not dialog.is_inside_tree():
		return
	if dialog is AcceptDialog:
		var accept: AcceptDialog = dialog as AcceptDialog
		accept.add_theme_constant_override("buttons_min_width", 100)
		accept.add_theme_constant_override("buttons_min_height", 34)
		_keep_body_within_viewport(accept, fallback_ratio)
	var touch: bool = _touch(dialog)
	if touch:
		preload("res://vtt/mobile/touch_layout.gd").fit_dialog(dialog)
	dialog.wrap_controls = not touch
	dialog.child_controls_changed()
	dialog.reset_size()
	dialog.popup_centered_clamped(preferred_size, fallback_ratio)
	_fit_window(dialog, preferred_size, fallback_ratio, touch)
	_check_first_frame_layout(dialog, preferred_size, fallback_ratio)


# Resize an already open modal (e.g. toggling document edit mode) without
# closing it or stealing keyboard focus.
# Context menus use a cursor position, not a centered position. Clamp the
# opened menu after Godot knows its true size, in the same coordinates as
# native/embedded dialogs (including near the right and bottom edges).
static func popup_menu(menu: PopupMenu, viewport_point: Vector2i) -> void:
	if menu == null or not is_instance_valid(menu) or not menu.is_inside_tree():
		return
	var root: Window = menu.get_tree().root
	menu.max_size = (root.size - Vector2i(16, 16)).max(Vector2i(1, 1))
	menu.popup()
	_fit_popup_menu(menu, viewport_point)
	_refit_popup_menu(menu, viewport_point)


static func _fit_popup_menu(menu: PopupMenu, viewport_point: Vector2i) -> void:
	if not is_instance_valid(menu) or not menu.visible:
		return
	var root: Window = menu.get_tree().root
	var origin: Vector2i = Vector2i.ZERO if menu.is_embedded() else root.position
	var minimum: Vector2i = origin + Vector2i(8, 8)
	var maximum: Vector2i = origin + root.size - menu.size - Vector2i(8, 8)
	menu.position = Vector2i(
		clampi(viewport_point.x + origin.x, minimum.x, maxi(minimum.x, maximum.x)),
		clampi(viewport_point.y + origin.y, minimum.y, maxi(minimum.y, maximum.y))
	)


static func _refit_popup_menu(menu: PopupMenu, viewport_point: Vector2i) -> void:
	await menu.get_tree().process_frame
	if is_instance_valid(menu) and menu.visible:
		_fit_popup_menu(menu, viewport_point)


static func resize_visible(
	dialog: Window, preferred_size: Vector2i, fallback_ratio: float = 0.92
) -> void:
	if dialog == null or not is_instance_valid(dialog) or not dialog.visible:
		return
	dialog.size = preferred_size
	_fit_window(dialog, preferred_size, fallback_ratio, _touch(dialog))


static func _keep_body_within_viewport(dialog: AcceptDialog, ratio: float) -> void:
	var available: Vector2i = Vector2i(_root_bounds(dialog) * ratio)
	dialog.min_size = dialog.min_size.min(available)
	# Keep the platform's native Confirm/Cancel footer usable; only the body
	# should scroll if the content does not fit.
	var children: Array[Control] = []
	for child: Node in dialog.get_children():
		if child is Control:
			children.append(child)
	if children.size() != 1 or children[0] is ScrollContainer:
		return
	var body: Control = children[0]
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	scroll.name = "DialogScrollBody"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.remove_child(body)
	dialog.add_child(scroll)
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# A new dialog's text and footer may not have their final size at first popup.
# Re-clamp on subsequent frames with the SAME coordinate system as the opener.
static func _check_first_frame_layout(
	dialog: Window, preferred_size: Vector2i, fallback_ratio: float
) -> void:
	var tree: SceneTree = dialog.get_tree()
	await tree.process_frame
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	var touch: bool = _touch(dialog)
	_fit_window(dialog, preferred_size, fallback_ratio, touch)
	if touch:
		await tree.process_frame
		if is_instance_valid(dialog) and dialog.visible:
			_fit_window(dialog, preferred_size, fallback_ratio, touch)
