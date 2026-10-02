extends RefCounted

static func medieval_title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Old English Text MT",
		"UnifrakturCook",
		"UnifrakturMaguntia",
		"Luminari",
		"Georgia"
	])
	font.font_weight = 600
	return font


static func menu_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Palatino Linotype",
		"Book Antiqua",
		"Palatino",
		"Georgia"
	])
	return font


static func apply_title_style(label: Label, font_size: int = 48) -> void:
	label.add_theme_font_override("font", medieval_title_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override(
		"font_color",
		Color(0.94, 0.85, 0.64)
	)
	label.add_theme_color_override(
		"font_outline_color",
		Color(0.055, 0.035, 0.025, 1.0)
	)
	label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.88)
	)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)


static func apply_menu_label_style(
	label: Label,
	font_size: int = 18
) -> void:
	label.add_theme_font_override("font", menu_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override(
		"font_color",
		Color(0.90, 0.84, 0.71)
	)


static func menu_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.027, 0.035, 0.72)
	style.border_color = Color(0.56, 0.43, 0.24, 0.62)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.52)
	style.shadow_size = 12
	return style


static func button_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	return style


static func menu_button(
	label_text: String,
	minimum_size: Vector2 = Vector2(180, 40)
) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = minimum_size
	button.add_theme_font_override("font", menu_font())
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override(
		"font_color",
		Color(0.90, 0.84, 0.71)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(1.0, 0.92, 0.72)
	)
	button.add_theme_stylebox_override(
		"normal",
		button_style(
			Color(0.075, 0.072, 0.074, 0.86),
			Color(0.40, 0.31, 0.18, 0.74)
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		button_style(
			Color(0.15, 0.115, 0.075, 0.94),
			Color(0.78, 0.57, 0.27, 0.92)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		button_style(
			Color(0.20, 0.135, 0.075, 0.98),
			Color(0.93, 0.70, 0.34, 1.0)
		)
	)
	return button
