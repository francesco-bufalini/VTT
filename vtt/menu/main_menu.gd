extends Control

const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"
const MenuStyle = preload("res://vtt/menu/menu_style.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const MENU_BACKGROUND_DIRECTORY := (
	"res://assets/menu/background/slideshow"
)
const MENU_BACKGROUND_FALLBACK := (
	"res://assets/menu/background/menu_background.webp"
)
const SLIDE_DURATION_SECONDS := 60.0
const FADE_DURATION_SECONDS := 2.5

var _options_dialog: AcceptDialog
var _new_campaign_dialog: ConfirmationDialog
var _new_campaign_name: LineEdit
var _soundtrack_toggle: CheckButton
var _soundtrack_volume: HSlider
var _soundtrack_volume_label: Label
var _mute_button: Button
var _controls_anchor: MarginContainer
var _title_margin: MarginContainer
var _title_label: Label
var _controls_scroll: ScrollContainer
var _title_eyebrow: Label

var _background_layers: Array[TextureRect] = []
var _background_paths: Array[String] = []
var _background_index := 0
var _active_layer := 0
var _slide_elapsed := 0.0
var _slide_tween: Tween
var _background_root: Control
var _background_rng := RandomNumberGenerator.new()


func _ready() -> void:
	preload("res://vtt/scrollable_caption.gd").install(self)
	if OS.has_feature("mobile") or OS.has_feature("vtt_mobile"):
		get_tree().call_deferred("change_scene_to_file", "res://vtt/mobile/creatures_mobile.tscn")
		return
	_build_ui()
	_refresh_responsive_layout()


func _process(delta: float) -> void:
	if _background_paths.size() <= 1:
		return

	_slide_elapsed += delta
	if _slide_elapsed >= SLIDE_DURATION_SECONDS:
		_slide_elapsed = 0.0
		_show_next_background()


func _build_ui() -> void:
	_build_image_background()
	_build_vignette()
	_build_title()
	_build_bottom_controls()
	_build_new_campaign_dialog()
	_build_options_dialog()


func _build_image_background() -> void:
	_background_root = Control.new()
	_background_root.name = "FantasyBackground"
	_background_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_root.clip_contents = true
	_background_root.z_index = -100
	add_child(_background_root)
	move_child(_background_root, 0)

	_background_paths = _discover_backgrounds()

	if _background_paths.is_empty() and ResourceLoader.exists(MENU_BACKGROUND_FALLBACK):
		_background_paths.append(MENU_BACKGROUND_FALLBACK)

	if _background_paths.is_empty():
		push_error("MainMenu: nessuna texture di sfondo disponibile.")
		return

	for layer_index in range(2):
		var layer := TextureRect.new()
		layer.name = "BackgroundLayer%d" % layer_index
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		layer.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_background_root.add_child(layer)
		_background_layers.append(layer)

	_background_rng.randomize()
	_background_index = _background_rng.randi_range(
		0,
		_background_paths.size() - 1
	)
	_background_layers[0].modulate.a = 1.0
	_background_layers[0].texture = load(
		_background_paths[_background_index]
	)


func _discover_backgrounds() -> Array[String]:
	var paths: Array[String] = []
	# Imported images use remapped filenames inside exported PCK files.
	for file_name: String in ResourceLoader.list_directory(MENU_BACKGROUND_DIRECTORY):
		var extension := file_name.get_extension().to_lower()
		if extension not in ["jpg", "jpeg", "png", "webp"]:
			continue
		paths.append(MENU_BACKGROUND_DIRECTORY + "/" + file_name)

	paths.sort()
	return paths


func _pick_random_background_index() -> int:
	if _background_paths.size() <= 1:
		return 0

	var next_index := _background_index
	while next_index == _background_index:
		next_index = _background_rng.randi_range(
			0,
			_background_paths.size() - 1
		)
	return next_index


func _show_next_background() -> void:
	if _background_paths.size() <= 1 or _background_layers.size() < 2:
		return

	var incoming_layer_index := 1 - _active_layer
	var outgoing := _background_layers[_active_layer]
	var incoming := _background_layers[incoming_layer_index]

	_background_index = _pick_random_background_index()
	incoming.texture = load(_background_paths[_background_index])
	incoming.modulate.a = 0.0
	incoming.position = Vector2.ZERO
	incoming.scale = Vector2.ONE
	outgoing.position = Vector2.ZERO
	outgoing.scale = Vector2.ONE

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.set_trans(Tween.TRANS_SINE)
	_slide_tween.set_ease(Tween.EASE_IN_OUT)
	_slide_tween.tween_property(
		incoming,
		"modulate:a",
		1.0,
		FADE_DURATION_SECONDS
	)
	_slide_tween.tween_property(
		outgoing,
		"modulate:a",
		0.0,
		FADE_DURATION_SECONDS
	)
	_active_layer = incoming_layer_index

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
	_title_margin = MarginContainer.new()
	_title_margin.name = "TitleArea"
	_title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_margin)

	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	_title_margin.add_child(copy)

	var eyebrow := Label.new()
	_title_eyebrow = eyebrow
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eyebrow.text = "VIRTUAL TABLETOP  /  CHRONICLES & ADVENTURES"
	eyebrow.add_theme_font_override("font", MenuStyle.menu_font())
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", MenuStyle.GOLD_BRIGHT)
	copy.add_child(eyebrow)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.name = "GameTitle"
	_title_label.text = "Kruphix's Chessboard"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuStyle.apply_title_style(_title_label, 60)
	copy.add_child(_title_label)

	var subtitle := Label.new()
	subtitle.text = "Le tue storie. Il tuo tavolo."
	subtitle.add_theme_font_override("font", MenuStyle.menu_font())
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", MenuStyle.MUTED)
	copy.add_child(subtitle)




func _build_bottom_controls() -> void:
	_controls_anchor = MarginContainer.new()
	_controls_anchor.name = "BottomControls"
	_controls_anchor.anchor_left = 0.0
	_controls_anchor.anchor_right = 0.0
	_controls_anchor.anchor_top = 1.0
	_controls_anchor.anchor_bottom = 1.0
	add_child(_controls_anchor)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.menu_panel_style())
	_controls_anchor.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_controls_scroll = ScrollContainer.new()
	_controls_scroll.name = "MenuActionsScroll"
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_scroll.follow_focus = true
	panel.add_child(_controls_scroll)
	_controls_scroll.add_child(margin)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 7)
	margin.add_child(layout)

	var heading := Label.new()
	heading.text = "IL TAVOLO"
	heading.add_theme_font_override("font", MenuStyle.medieval_title_font())
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", MenuStyle.GOLD_BRIGHT)
	layout.add_child(heading)

	var subtitle := Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = "Scegli come iniziare la tua avventura"
	subtitle.add_theme_font_override("font", MenuStyle.menu_font())
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", MenuStyle.MUTED)
	layout.add_child(subtitle)

	var separator := HSeparator.new()
	separator.modulate = MenuStyle.GOLD
	layout.add_child(separator)

	var active_button: Button = MenuStyle.menu_button("Campagne attive", Vector2(0, 48))
	active_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_button.pressed.connect(_open_active_campaigns)
	layout.add_child(active_button)

	var new_button: Button = MenuStyle.menu_button("Nuova campagna", Vector2(0, 48))
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(_request_new_campaign)
	layout.add_child(new_button)

	var options_button: Button = MenuStyle.menu_button("Opzioni", Vector2(0, 48))
	options_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_button.pressed.connect(_show_options_placeholder)
	layout.add_child(options_button)

	_mute_button = MenuStyle.menu_button("Muta musica", Vector2(0, 48))
	_mute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mute_button.pressed.connect(_toggle_soundtrack_muted)
	layout.add_child(_mute_button)
	_refresh_mute_button()

	var exit_button: Button = MenuStyle.menu_button("Esci", Vector2(0, 48))
	exit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	layout.add_child(exit_button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _controls_anchor != null:
		_refresh_responsive_layout()


func _refresh_responsive_layout() -> void:
	if _title_margin == null or _controls_anchor == null:
		return
	var compact: bool = size.x < 1000.0 or size.y < 680.0
	_title_margin.anchor_left = 0.0
	_title_margin.anchor_right = 0.0
	_title_margin.anchor_top = 0.0
	_title_margin.anchor_bottom = 0.0
	_title_margin.offset_left = 24.0 if compact else 40.0
	_title_margin.offset_top = 16.0 if compact else 28.0
	_title_margin.offset_right = minf(size.x - 18.0, 960.0)
	_title_margin.offset_bottom = 135.0 if compact else 176.0
	_title_label.add_theme_font_size_override("font_size", 30 if size.x < 600.0 else (43 if compact else 60))
	_title_eyebrow.visible = size.y >= 480.0

	_controls_anchor.offset_left = 20.0 if compact else 36.0
	_controls_anchor.offset_right = minf(size.x - 20.0, 372.0 if compact else 408.0)
	_controls_anchor.offset_top = -maxf(48.0, minf(420.0, size.y - (150.0 if size.x < 600.0 else 142.0)))
	_controls_anchor.offset_bottom = -16.0 if compact else -28.0




func _build_new_campaign_dialog() -> void:
	_new_campaign_dialog = ConfirmationDialog.new()
	_new_campaign_dialog.title = "Nuova campagna"
	_new_campaign_dialog.ok_button_text = "Crea campagna"
	_new_campaign_dialog.cancel_button_text = "Annulla"
	_new_campaign_dialog.min_size = Vector2i(500, 220)
	_new_campaign_dialog.add_theme_constant_override("buttons_min_width", 100)
	_new_campaign_dialog.add_theme_constant_override("buttons_min_height", 34)
	add_child(_new_campaign_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(445, 95)
	body.add_theme_constant_override("separation", 10)
	_new_campaign_dialog.add_child(body)

	var label := Label.new()
	label.text = "Inserisci il nome della campagna:"
	body.add_child(label)

	_new_campaign_name = LineEdit.new()
	_new_campaign_name.placeholder_text = "Nome campagna"
	_new_campaign_name.max_length = 80
	body.add_child(_new_campaign_name)

	var hint := Label.new()
	hint.text = (
		"La campagna raccoglie uno o più scenari. "
		+ "Dopo la creazione potrai aggiungere gli scenari e scegliere "
		+ "il preset di ciascuno."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.72, 0.75, 0.82, 1.0)
	body.add_child(hint)

	_new_campaign_dialog.confirmed.connect(_confirm_new_campaign)


func _build_options_dialog() -> void:
	_options_dialog = AcceptDialog.new()
	_options_dialog.title = "Impostazioni menu"
	_options_dialog.ok_button_text = "Chiudi"
	_options_dialog.min_size = Vector2i(520, 300)
	_options_dialog.add_theme_constant_override("buttons_min_width", 100)
	_options_dialog.add_theme_constant_override("buttons_min_height", 34)
	add_child(_options_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(470, 205)
	body.add_theme_constant_override("separation", 14)
	_options_dialog.add_child(body)

	var audio_title := Label.new()
	audio_title.text = "Audio del menu"
	audio_title.add_theme_font_size_override("font_size", 21)
	body.add_child(audio_title)
	var settings_help := Label.new()
	settings_help.text = "Le modifiche vengono salvate subito su questo dispositivo."
	settings_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(settings_help)

	_soundtrack_toggle = CheckButton.new()
	_soundtrack_toggle.text = "Riproduci la colonna sonora nel menu"
	_soundtrack_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(_soundtrack_toggle)

	_soundtrack_toggle.toggled.connect(_on_soundtrack_toggled)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	body.add_child(volume_row)

	var volume_title := Label.new()
	volume_title.text = "Volume"
	volume_title.custom_minimum_size = Vector2(80, 0)
	volume_row.add_child(volume_title)

	_soundtrack_volume = HSlider.new()
	_soundtrack_volume.min_value = 0.0
	_soundtrack_volume.max_value = 100.0
	_soundtrack_volume.step = 1.0
	_soundtrack_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_soundtrack_volume.tooltip_text = "Volume della colonna sonora"
	volume_row.add_child(_soundtrack_volume)

	_soundtrack_volume_label = Label.new()
	_soundtrack_volume_label.custom_minimum_size = Vector2(48, 0)
	_soundtrack_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_soundtrack_volume_label)

	_soundtrack_volume.value_changed.connect(_on_soundtrack_volume_changed)

	var info := Label.new()
	info.text = (
		"La colonna sonora viene riprodotta nel Menu, in Campagne attive "
		+ "e in Scenari della campagna. Entrando in uno scenario viene "
		+ "fermata automaticamente."
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate = Color(0.72, 0.75, 0.82, 1.0)
	body.add_child(info)

	_refresh_audio_settings_ui()


func _open_active_campaigns() -> void:
	get_tree().change_scene_to_file(ACTIVE_CAMPAIGNS_SCENE_PATH)


func _request_new_campaign() -> void:
	_new_campaign_name.clear()
	DialogLayout.popup(_new_campaign_dialog, Vector2i(500, 220), 0.92)
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

	var campaign_group_id: String = String(
		manager.call("create_campaign_group", campaign_name)
	)
	if campaign_group_id.is_empty():
		_show_error("Impossibile creare la campagna.")
		return

	var error: Error = int(
		manager.call("open_campaign_group", campaign_group_id)
	)
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
	_refresh_audio_settings_ui()
	DialogLayout.popup(_options_dialog, Vector2i(520, 300), 0.92)


func _menu_audio_manager() -> Node:
	return get_node_or_null("/root/MenuAudioManager")


func _refresh_audio_settings_ui() -> void:
	var manager := _menu_audio_manager()
	if manager == null or _soundtrack_toggle == null or _soundtrack_volume == null:
		return

	var enabled: bool = bool(manager.get("soundtrack_enabled"))
	var volume: float = float(manager.call("get_soundtrack_volume"))
	var available: bool = bool(manager.call("is_soundtrack_available"))

	_soundtrack_toggle.set_pressed_no_signal(enabled)
	# The settings remain editable even if the audio asset is temporarily
	# unavailable. The chosen values are persisted and take effect as soon
	# as the soundtrack is available.
	_soundtrack_toggle.disabled = false
	_soundtrack_volume.value = volume * 100.0
	_soundtrack_volume.editable = true
	_soundtrack_volume.mouse_filter = Control.MOUSE_FILTER_STOP
	_soundtrack_volume.modulate.a = 1.0
	_soundtrack_volume_label.text = "%d%%" % roundi(volume * 100.0)

	if not available:
		_soundtrack_toggle.tooltip_text = (
			"La soundtrack non è ancora disponibile. "
			+ "Le impostazioni verranno applicate automaticamente "
			+ "quando il file viene aggiunto."
		)
		_soundtrack_volume.tooltip_text = (
			"Impostazione salvata: la soundtrack verrà riprodotta "
			+ "con questo volume quando il file sarà disponibile."
		)
	else:
		_soundtrack_toggle.tooltip_text = ""
		_soundtrack_volume.tooltip_text = "Volume della colonna sonora"

	_refresh_mute_button()


func _refresh_mute_button() -> void:
	if _mute_button == null:
		return

	var manager := _menu_audio_manager()
	if manager == null:
		_mute_button.disabled = true
		_mute_button.text = "Muta musica"
		return

	_mute_button.disabled = false
	var enabled: bool = bool(manager.get("soundtrack_enabled"))
	_mute_button.text = "Muta musica" if enabled else "Riattiva musica"


func _toggle_soundtrack_muted() -> void:
	var manager := _menu_audio_manager()
	if manager == null:
		return

	var enabled: bool = bool(manager.get("soundtrack_enabled"))
	manager.call("set_soundtrack_enabled", not enabled)
	_refresh_audio_settings_ui()


func _on_soundtrack_toggled(enabled: bool) -> void:
	var manager := _menu_audio_manager()
	if manager != null:
		manager.call("set_soundtrack_enabled", enabled)
	_refresh_mute_button()


func _on_soundtrack_volume_changed(value: float) -> void:
	_soundtrack_volume_label.text = "%d%%" % roundi(value)
	var manager := _menu_audio_manager()
	if manager != null:
		manager.call("set_soundtrack_volume", value / 100.0)


func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = message
	add_child(dialog)
	DialogLayout.popup(dialog, Vector2i(480, 180), 0.92)
	dialog.close_requested.connect(dialog.queue_free)
