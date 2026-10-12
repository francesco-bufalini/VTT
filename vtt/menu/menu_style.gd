extends RefCounted
## Visual primitives for all front-end campaign menus.
## Original fantasy styling; no licensed D&D artwork or marks are embedded.

const GOLD := Color(0.89, 0.70, 0.42, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.87, 0.64, 1.0)
const PARCHMENT := Color(0.95, 0.89, 0.77, 1.0)
const MUTED := Color(0.77, 0.72, 0.64, 1.0)
const BURGUNDY := Color(0.37, 0.12, 0.17, 1.0)


static func medieval_title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Palatino Linotype",
		"Book Antiqua",
		"Garamond",
		"Georgia",
		"Noto Serif"
	])
	font.font_weight = 700
	return font


static func menu_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Segoe UI",
		"Noto Sans",
		"DejaVu Sans"
	])
	return font


static func apply_title_style(label: Label, font_size: int = 48) -> void:
	label.add_theme_font_override("font", medieval_title_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PARCHMENT)
	label.add_theme_color_override(
		"font_outline_color",
		Color(0.08, 0.055, 0.055, 1.0)
	)
	label.add_theme_constant_override("outline_size", 3)


static func apply_menu_label_style(
	label: Label,
	font_size: int = 18
) -> void:
	label.add_theme_font_override("font", menu_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PARCHMENT)


static func menu_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.105, 0.105, 0.95)
	style.border_color = Color(0.70, 0.51, 0.29, 0.92)
	style.border_width_left = 1
	style.border_width_top = 2
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	style.shadow_size = 14
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
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func menu_button(
	label_text: String,
	minimum_size: Vector2 = Vector2(180, 44)
) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", menu_font())
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", GOLD_BRIGHT)
	button.add_theme_color_override(
		"font_disabled_color",
		Color(0.62, 0.59, 0.54, 1.0)
	)
	button.add_theme_stylebox_override(
		"normal",
		button_style(
			Color(0.18, 0.14, 0.145, 0.98),
			Color(0.46, 0.34, 0.23, 0.94)
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		button_style(
			Color(0.35, 0.17, 0.20, 1.0),
			GOLD
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		button_style(
			Color(0.43, 0.18, 0.22, 1.0),
			GOLD_BRIGHT
		)
	)
	var focus := button_style(Color(0, 0, 0, 0), GOLD_BRIGHT)
	focus.border_width_left = 2
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2
	button.add_theme_stylebox_override("focus", focus)
	return button
