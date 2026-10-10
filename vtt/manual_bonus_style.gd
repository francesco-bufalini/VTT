extends RefCounted

# Amber framed values are deliberate manual compensation for unsupported
# automatic rules (equipment, feats, temporary effects, special resources).
static func decorate(spin: SpinBox) -> void:
	if spin == null:
		return
	# The sign belongs to the highlighted bonus field, not to the formula.
	# Negative values already render '-' and can be entered directly.
	spin.prefix = "+" if spin.value >= 0.0 else ""
	spin.value_changed.connect(func(value: float) -> void:
		spin.prefix = "+" if value >= 0.0 else ""
	)
	var field: LineEdit = spin.get_line_edit()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.25, 0.20, 0.13, 0.96)
	normal.border_color = Color(0.89, 0.66, 0.31, 0.94)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(3)
	field.add_theme_stylebox_override("normal", normal)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Color(1.0, 0.84, 0.43, 1.0)
	focused.set_border_width_all(2)
	field.add_theme_stylebox_override("focus", focused)
	field.add_theme_color_override("font_color", Color(1.0, 0.88, 0.63))
	field.add_theme_color_override("font_selected_color", Color(0.1, 0.1, 0.1))
	field.add_theme_font_size_override("font_size", 13)


# Shared formula typography: the parenthesis glyph and each SpinBox
# occupy the same 36 px high visual row, even in wrapping containers.
static func add_formula_label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.y = 36.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 30 if value in ["(", ")"] else 18)
	parent.add_child(label)
	return label
