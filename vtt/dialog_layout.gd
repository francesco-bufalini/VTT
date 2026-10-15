extends RefCounted

# Share one layout policy for all native AcceptDialog/ConfirmationDialog popups.
# An embedded subwindow can have a scaled Viewport visible_rect that is much
# larger than the actual physical Root Window. The latter is the usable area.


static func _root_bounds(dialog: Window) -> Vector2i:
	return dialog.get_tree().root.size


static func _touch(dialog: Window) -> bool:
	return OS.has_feature("mobile") or dialog.get_tree().root.has_meta("vtt_touch_layout")


static func _fit_touch_window(dialog: Window, preferred_size: Vector2i) -> void:
	var available: Vector2i = _root_bounds(dialog)
	var allowed: Vector2i = (available - Vector2i(12, 12)).max(Vector2i(1, 1))
	dialog.min_size = Vector2i.ZERO
	dialog.max_size = allowed
	# popup_centered_clamped() centers relative to the *scaled* viewport on
	# embedded mobile clients. Apply the real device/window bounds explicitly.
	dialog.size = preferred_size.min(allowed).max(Vector2i(1, 1))
	dialog.position = (available - dialog.size) / 2


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
	if touch:
		_fit_touch_window(dialog, preferred_size)
	_check_first_frame_layout(dialog, preferred_size)


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


static func _check_first_frame_layout(dialog: Window, preferred_size: Vector2i) -> void:
	var tree: SceneTree = dialog.get_tree()
	await tree.process_frame
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	if _touch(dialog):
		_fit_touch_window(dialog, preferred_size)
		await tree.process_frame
		if is_instance_valid(dialog) and dialog.visible:
			_fit_touch_window(dialog, preferred_size)
		return
	# Desktop windows can measure their contents on the next frame.
	var available: Vector2i = _root_bounds(dialog)
	var allowed: Vector2i = (available - Vector2i(24, 24)).max(Vector2i(1, 1))
	dialog.min_size = Vector2i.ZERO
	dialog.size = dialog.size.min(allowed)
	dialog.position = (available - dialog.size) / 2
