extends RefCounted

# One layout policy for native AcceptDialog/ConfirmationDialog popups.
# In particular, do not force a smaller window after the first frame: that
# cuts off the native confirmation row when children were measured late.
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
	var touch := OS.has_feature("mobile") or dialog.get_tree().root.has_meta("vtt_touch_layout")
	if touch:
		preload("res://vtt/mobile/touch_layout.gd").fit_dialog(dialog)
	dialog.wrap_controls = not touch
	if touch:
		# Native buttons and delayed Control measurements cannot force an
		# embedded Android/window popup beyond the visible touchscreen.
		var bounds := Vector2i(dialog.get_tree().root.get_visible_rect().size)
		dialog.max_size = (bounds - Vector2i(12, 12)).max(Vector2i(1, 1))
	dialog.child_controls_changed()
	dialog.reset_size()
	dialog.popup_centered_clamped(preferred_size, fallback_ratio)
	_check_first_frame_layout(dialog)


static func _keep_body_within_viewport(dialog: AcceptDialog, ratio: float) -> void:
	var available := Vector2i(dialog.get_parent().get_viewport().get_visible_rect().size * ratio)
	dialog.min_size = dialog.min_size.min(available)
	# AcceptDialog lays out the native buttons outside its custom body. A tall
	# body must scroll; growing the entire window pushes Confirm off-screen.
	var children: Array[Control] = []
	for child: Node in dialog.get_children():
		if child is Control:
			children.append(child)
	if children.size() != 1 or not children[0] is Control or children[0] is ScrollContainer:
		return
	var body := children[0] as Control
	# Reserve the native footer before the first measurement. Content may
	# grow later (wrapped text, downloaded data); it must grow inside a
	# scrollable body rather than pushing Confirm beyond the viewport.
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	scroll.name = "DialogScrollBody"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.remove_child(body)
	dialog.add_child(scroll)
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _check_first_frame_layout(dialog: Window) -> void:
	var tree: SceneTree = dialog.get_tree()
	await tree.process_frame
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	# Late content measurement must never grow popups outside the viewport.
	# DialogScrollBody can scroll; keep native action buttons on screen.
	var available := Vector2i(dialog.get_parent().get_viewport().get_visible_rect().size)
	var touch := OS.has_feature("mobile") or tree.root.has_meta("vtt_touch_layout")
	var margin := Vector2i(12, 12) if touch else Vector2i(24, 24)
	dialog.min_size = Vector2i.ZERO
	var allowed := (available - margin).max(Vector2i(1, 1))
	if touch:
		dialog.max_size = allowed
	dialog.size = dialog.size.min(allowed)
	dialog.position = (available - dialog.size) / 2
	# The native confirmation row can get a second size pass. Keep the
	# visible popup constrained without altering a user's desktop layout.
	if touch:
		await tree.process_frame
		if is_instance_valid(dialog) and dialog.visible:
			dialog.size = dialog.size.min(allowed)
			dialog.position = (available - dialog.size) / 2
