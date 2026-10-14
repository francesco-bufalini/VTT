extends RefCounted
## Presentation-only touch rules. Existing controls keep their signals and data.
const TARGET := 48.0

static func style_control(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, TARGET)
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, TARGET)
		button.add_theme_font_size_override("font_size", 16)
		button.clip_text = true
		if button.custom_minimum_size.x > 120:
			button.custom_minimum_size.x = TARGET
		if button is OptionButton:
			button.fit_to_longest_item = false
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size = Vector2(0, TARGET)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", 18)
		field.virtual_keyboard_enabled = true
	if node is SpinBox:
		var number := node as SpinBox
		number.custom_minimum_size.y = TARGET
		# Leave space for multi-digit values and the built-in step arrows.
		number.custom_minimum_size.x = maxf(number.custom_minimum_size.x, 84.0)
		number.get_line_edit().add_theme_font_size_override("font_size", 18)
		number.get_line_edit().virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	if node is Label:
		var caption := node as Label
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		caption.add_theme_font_size_override("font_size", 15)
		# Respect the label's original wrapping and size flags. Forcing every
		# numerical label to wrap made +109 render one digit per line, while
		# making every label expand hid skill names beside their modifiers.
		if caption.autowrap_mode != TextServer.AUTOWRAP_OFF:
			caption.custom_minimum_size.x = 0
	if node is RichTextLabel:
		node.custom_minimum_size.x = 0
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			node.add_theme_font_size_override(key, 18)
	if node is TextEdit:
		node.add_theme_font_size_override("font_size", 18)
	if node is ItemList:
		node.add_theme_font_size_override("font_size", 18)
		node.add_theme_constant_override("v_separation", 16)
	if node is PopupMenu:
		node.add_theme_font_size_override("font_size", 18)
		node.add_theme_constant_override("v_separation", 20)
	if node is ScrollContainer:
		node.scroll_deadzone = 12
		node.follow_focus = false
		node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

static func style_tree(node: Node) -> void:
	style_control(node)
	for child: Node in node.get_children():
		style_tree(child)

static func replace_box(old: Container, replacement: Container) -> Container:
	var parent := old.get_parent()
	var index := old.get_index()
	replacement.name = old.name
	replacement.size_flags_horizontal = old.size_flags_horizontal
	replacement.size_flags_vertical = old.size_flags_vertical
	parent.remove_child(old)
	parent.add_child(replacement)
	parent.move_child(replacement, index)
	for child: Node in old.get_children():
		child.reparent(replacement, false)
	old.queue_free()
	return replacement

static func scroll_body(panel: PanelContainer) -> ScrollContainer:
	var body := panel.get_child(0) as Control
	panel.remove_child(body)
	var scroll := ScrollContainer.new()
	scroll.name = "TouchScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return scroll

# Static field rows stack vertically; controls and their data connections survive.
# Only genuine label + edit rows should stack; nested counter/action rows
# must retain their horizontal grouping on narrow Android screens.
static func _is_field_row(row: HBoxContainer) -> bool:
	var has_caption := false
	var has_field := false
	for child: Node in row.get_children():
		has_caption = has_caption or child is Label
		has_field = has_field or child is LineEdit or child is OptionButton or child is TextEdit
	return has_caption and has_field

static func wrap_fields(root: Node) -> void:
	if root.get_script() != null:
		return
	if root is Control:
		root.custom_minimum_size.x = 0
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for original: Node in root.get_children():
		var child := original
		var labeled_row := original is HBoxContainer and _is_field_row(original as HBoxContainer)
		var physics_flow := original is HFlowContainer and original.name in ["PhysicsFields", "PhysicsMiniatureFlow"]
		if (labeled_row or physics_flow) and original.get_script() == null:
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 5)
			child = replace_box(original, column)
		wrap_fields(child)

static func fit_dialog(dialog: Window) -> void:
	dialog.min_size = Vector2i.ZERO
	if dialog is AcceptDialog:
		dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dialog.get_label().custom_minimum_size.x = 0
	for child: Node in dialog.get_children():
		if child is Control:
			wrap_fields(child)
	style_tree(dialog)

# Deepest scrollable area first; any unused distance continues in its parent.
static func scroll_bars_at(root: Node, at: Vector2) -> Array[ScrollBar]:
	var candidates: Array[Control] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or not control.get_global_rect().has_point(at):
			continue
		var clipped := false
		var parent := control.get_parent()
		while parent != null:
			if parent is Control and parent.clip_contents and not parent.get_global_rect().has_point(at):
				clipped = true
				break
			parent = parent.get_parent()
		if not clipped and (control is ScrollContainer or control is ItemList or control is RichTextLabel or control is TextEdit):
			candidates.append(control)
	candidates.sort_custom(func(a: Control, b: Control) -> bool:
		var az := _effective_z(a)
		var bz := _effective_z(b)
		return az > bz if az != bz else a.get_path().get_name_count() > b.get_path().get_name_count())
	var result: Array[ScrollBar] = []
	for control: Control in candidates:
		if control != candidates[0] and not control.is_ancestor_of(candidates[0]):
			continue
		var bar: ScrollBar = control.get_v_scroll_bar()
		if bar.max_value - bar.page > bar.min_value and not result.has(bar):
			result.append(bar)
	return result

static func scroll_gesture(bars: Array[ScrollBar], distance: float) -> void:
	var remaining := distance
	for bar: ScrollBar in bars:
		if not is_instance_valid(bar):
			continue
		var previous := bar.value
		bar.value = clampf(previous + remaining, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
		remaining -= bar.value - previous
		if absf(remaining) < 0.5:
			break

static func _effective_z(control: Control) -> int:
	var result := 0
	var current: Node = control
	while current != null:
		if current is CanvasItem:
			result += current.z_index
		current = current.get_parent()
	return result
