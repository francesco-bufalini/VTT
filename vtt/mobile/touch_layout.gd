extends RefCounted
## Presentation-only touch rules. Existing controls keep their signals and data.
const TARGET := 48.0

static func style_control(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, TARGET)
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, TARGET)
		button.add_theme_font_size_override("font_size", 18)
		if button is OptionButton:
			button.fit_to_longest_item = false
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size.y = TARGET
		field.add_theme_font_size_override("font_size", 18)
		field.virtual_keyboard_enabled = true
	if node is SpinBox:
		var number := node as SpinBox
		number.custom_minimum_size.y = TARGET
		number.custom_minimum_size.x = maxf(number.custom_minimum_size.x, 80)
		number.get_line_edit().add_theme_font_size_override("font_size", 18)
		number.get_line_edit().virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	if node is Label:
		var caption := node as Label
		caption.add_theme_font_size_override("font_size", maxi(16, caption.get_theme_font_size("font_size")))
	if node is RichTextLabel:
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
		node.follow_focus = true

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

# Static Info fields can wrap without cloning controls or rebuilding the record.
static func wrap_fields(root: Node) -> void:
	if root.get_script() != null:
		return
	for original: Node in root.get_children():
		var child := original
		if original is HBoxContainer and original.get_script() == null:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 12)
			flow.add_theme_constant_override("v_separation", 12)
			child = replace_box(original, flow)
		wrap_fields(child)
	if root is HFlowContainer:
		var children := root.get_children()
		var index := 0
		while index < children.size() - 1:
			var caption := children[index] as Label
			var field := children[index + 1] as Control
			if caption != null and (field is LineEdit or field is OptionButton or field is SpinBox):
				var group := VBoxContainer.new()
				group.add_theme_constant_override("separation", 4)
				group.custom_minimum_size.x = clampf(field.custom_minimum_size.x, 130, 240)
				group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				root.add_child(group)
				root.move_child(group, caption.get_index())
				caption.reparent(group, false)
				field.reparent(group, false)
				field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				index += 2
			else:
				index += 1
