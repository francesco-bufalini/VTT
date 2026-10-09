extends RefCounted

# Amber framed values are deliberate manual compensation for unsupported
# automatic rules (equipment, feats, temporary effects, special resources).
static func decorate(spin: SpinBox) -> void:
	if spin == null:
		return
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
