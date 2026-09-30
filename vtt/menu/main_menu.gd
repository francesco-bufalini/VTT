extends Control

const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"
const MENU_BACKGROUND_TEXTURE := (
	"res://assets/menu/background/menu_background.webp"
)

var _options_dialog: AcceptDialog
var _new_campaign_dialog: ConfirmationDialog
var _new_campaign_name: LineEdit



func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_build_image_background()
	_build_vignette()
	_build_title()
	_build_bottom_controls()
	_build_new_campaign_dialog()
	_build_options_dialog()


func _build_image_background() -> void:
	var background := TextureRect.new()
	background.name = "FantasyBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.z_index = -100

	var background_texture: Texture2D = load(MENU_BACKGROUND_TEXTURE)
	if background_texture == null:
		push_error(
			"MainMenu: texture di sfondo non trovata: "
			+ MENU_BACKGROUND_TEXTURE
		)
	else:
		background.texture = background_texture

	add_child(background)
	move_child(background, 0)


func _build_vignette() -> void:
	var overlay := ColorRect.new()
	overlay.name = "CinematicVignette"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= 0.78;
	float edge = smoothstep(0.22, 0.67, length(p));
	float bottom = smoothstep(0.48, 0.95, UV.y);
	float top = 1.0 - smoothstep(0.0, 0.23, UV.y);
	float alpha = clamp(edge * 0.62 + bottom * 0.24 + top * 0.10, 0.0, 0.72);
	COLOR = vec4(0.005, 0.006, 0.010, alpha);
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	overlay.material = shader_material
	add_child(overlay)


func _build_title() -> void:
	var title_margin := MarginContainer.new()
	title_margin.name = "TitleArea"
	title_margin.anchor_left = 0.0
	title_margin.anchor_top = 0.0
	title_margin.anchor_right = 0.0
	title_margin.anchor_bottom = 0.0
	title_margin.offset_left = 34.0
	title_margin.offset_top = 24.0
	title_margin.offset_right = 930.0
	title_margin.offset_bottom = 160.0
	title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_margin)

	var title := Label.new()
	title.name = "GameTitle"
	title.text = "Virtual Table Story Teller"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title.add_theme_font_override("font", _medieval_title_font())
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override(
		"font_color",
		Color(0.94, 0.85, 0.64)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.055, 0.035, 0.025, 1.0)
	)
	title.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.88)
	)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title_margin.add_child(title)


func _medieval_title_font() -> Font:
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


func _menu_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Palatino Linotype",
		"Book Antiqua",
		"Palatino",
		"Georgia"
	])
	return font


func _build_bottom_controls() -> void:
	var controls_anchor := MarginContainer.new()
	controls_anchor.name = "BottomControls"
	controls_anchor.anchor_left = 0.0
	controls_anchor.anchor_top = 1.0
	controls_anchor.anchor_right = 0.0
	controls_anchor.anchor_bottom = 1.0
	controls_anchor.offset_left = 28.0
	controls_anchor.offset_top = -270.0
	controls_anchor.offset_right = 390.0
	controls_anchor.offset_bottom = -28.0
	add_child(controls_anchor)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _menu_panel_style())
	controls_anchor.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var active_button: Button = _menu_button("Campagne attive")
	active_button.pressed.connect(_open_active_campaigns)
	layout.add_child(active_button)

	var new_button: Button = _menu_button("Nuova campagna")
	new_button.pressed.connect(_request_new_campaign)
	layout.add_child(new_button)

	var options_button: Button = _menu_button("Opzioni")
	options_button.pressed.connect(_show_options_placeholder)
	layout.add_child(options_button)

	var exit_button: Button = _menu_button("Esci")
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	layout.add_child(exit_button)


func _menu_panel_style() -> StyleBoxFlat:
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


func _menu_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(300, 40)
	button.add_theme_font_override("font", _menu_font())
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
		_button_style(
			Color(0.075, 0.072, 0.074, 0.86),
			Color(0.40, 0.31, 0.18, 0.74)
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_button_style(
			Color(0.15, 0.115, 0.075, 0.94),
			Color(0.78, 0.57, 0.27, 0.92)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_button_style(
			Color(0.20, 0.135, 0.075, 0.98),
			Color(0.93, 0.70, 0.34, 1.0)
		)
	)
	return button


func _button_style(
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


func _build_new_campaign_dialog() -> void:
	_new_campaign_dialog = ConfirmationDialog.new()
	_new_campaign_dialog.title = "Nuova campagna"
	_new_campaign_dialog.ok_button_text = "Crea campagna"
	_new_campaign_dialog.cancel_button_text = "Annulla"
	_new_campaign_dialog.min_size = Vector2i(440, 210)
	add_child(_new_campaign_dialog)

	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 18
	body.offset_top = 18
	body.offset_right = -18
	body.offset_bottom = -68
	body.add_theme_constant_override("separation", 10)
	_new_campaign_dialog.add_child(body)

	var label := Label.new()
	label.text = "Inserisci il nome della campagna:"
	body.add_child(label)

	_new_campaign_name = LineEdit.new()
	_new_campaign_name.placeholder_text = "Nome campagna"
	_new_campaign_name.max_length = 80
	body.add_child(_new_campaign_name)

	_new_campaign_dialog.confirmed.connect(_confirm_new_campaign)


func _build_options_dialog() -> void:
	_options_dialog = AcceptDialog.new()
	_options_dialog.title = "Opzioni"
	_options_dialog.dialog_text = (
		"Sezione predisposta.\n"
		+ "Audio, grafica e comandi saranno aggiunti successivamente."
	)
	add_child(_options_dialog)


func _open_active_campaigns() -> void:
	get_tree().change_scene_to_file(ACTIVE_CAMPAIGNS_SCENE_PATH)


func _request_new_campaign() -> void:
	_new_campaign_name.clear()
	_new_campaign_dialog.popup_centered(Vector2i(440, 210))
	_new_campaign_name.call_deferred("grab_focus")


func _confirm_new_campaign() -> void:
	var campaign_name: String = _new_campaign_name.text.strip_edges()
	if campaign_name.is_empty():
		_show_error("Inserisci un nome per la campagna.")
		return

	var manager: Node = _campaign_manager()
	if manager == null:
		_show_error("CampaignManager non disponibile.")
		return

	var campaign_id: String = String(
		manager.call("create_campaign", campaign_name)
	)
	if campaign_id.is_empty():
		_show_error("Impossibile creare la campagna.")
		return

	var error: Error = int(manager.call("open_campaign", campaign_id))
	if error != OK:
		_show_error(
			"Impossibile aprire la nuova campagna: %s"
			% error_string(error)
		)


func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _show_options_placeholder() -> void:
	_options_dialog.popup_centered(Vector2i(460, 190))


func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 180))
	dialog.close_requested.connect(dialog.queue_free)
