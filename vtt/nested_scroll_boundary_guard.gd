extends RefCounted

# Only explicit inner, independently scrolling lists opt into this guard.
# ScrollContainer itself consumes input while moving, but at its upper/lower
# limit it can hand a wheel/pan event to the surrounding sheet. Prevent that
# one case; never intercept normal scrolling inside the list.
static func install(scroll: ScrollContainer) -> void:
	if scroll.has_meta("nested_scroll_boundary_guard"):
		return
	scroll.set_meta("nested_scroll_boundary_guard", true)
	scroll.mouse_force_pass_scroll_events = false
	scroll.gui_input.connect(_on_gui_input.bind(scroll))


static func _at_boundary(bar: ScrollBar, direction: float) -> bool:
	if is_zero_approx(direction):
		return false
	var upper_limit: float = bar.max_value - bar.page
	if upper_limit - bar.min_value <= 1.0:
		# Content fits: let the enclosing sheet scroll normally.
		return false
	if direction < 0.0:
		return bar.value <= bar.min_value + 0.5
	return bar.value >= upper_limit - 0.5


static func _on_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if not scroll.is_visible_in_tree():
		return
	var vertical_direction := 0.0
	var horizontal_direction := 0.0
	if event is InputEventMouseButton:
		var wheel: InputEventMouseButton = event
		if not wheel.pressed:
			return
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				vertical_direction = -1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				vertical_direction = 1.0
			MOUSE_BUTTON_WHEEL_LEFT:
				horizontal_direction = -1.0
			MOUSE_BUTTON_WHEEL_RIGHT:
				horizontal_direction = 1.0
			_:
				return
		if wheel.shift_pressed and horizontal_direction == 0.0:
			horizontal_direction = vertical_direction
			vertical_direction = 0.0
	elif event is InputEventPanGesture:
		var pan: InputEventPanGesture = event
		vertical_direction = pan.delta.y
		horizontal_direction = pan.delta.x
	else:
		return
	# Do not capture a scroll direction that this list cannot perform.
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and _at_boundary(scroll.get_v_scroll_bar(), vertical_direction):
		scroll.accept_event()
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and _at_boundary(scroll.get_h_scroll_bar(), horizontal_direction):
		scroll.accept_event()
