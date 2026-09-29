extends Control

const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"

var _options_dialog: AcceptDialog
var _new_campaign_dialog: ConfirmationDialog
var _new_campaign_name: LineEdit


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.055, 0.06, 0.075, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 470)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.text = "VTT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	layout.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Virtual Tabletop"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.72, 0.75, 0.82, 1.0)
	layout.add_child(subtitle)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	layout.add_child(spacer)

	var active_button: Button = _menu_button("Campagne attive")
	active_button.pressed.connect(_open_active_campaigns)
	layout.add_child(active_button)

	var new_button: Button = _menu_button("Nuova campagna")
	new_button.pressed.connect(_request_new_campaign)
	layout.add_child(new_button)

	var options_button: Button = _menu_button("Opzioni")
	options_button.pressed.connect(_show_options_placeholder)
	layout.add_child(options_button)

	var hint: Label = Label.new()
	hint.text = "Audio, grafica e comandi verranno sviluppati successivamente."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.58, 0.61, 0.68, 1.0)
	layout.add_child(hint)

	_build_new_campaign_dialog()

	_options_dialog = AcceptDialog.new()
	_options_dialog.title = "Opzioni"
	_options_dialog.dialog_text = (
		"Sezione predisposta.\n"
		+ "Audio, grafica e comandi saranno aggiunti successivamente."
	)
	add_child(_options_dialog)


func _menu_button(label_text: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(330, 54)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _build_new_campaign_dialog() -> void:
	_new_campaign_dialog = ConfirmationDialog.new()
	_new_campaign_dialog.title = "Nuova campagna"
	_new_campaign_dialog.ok_button_text = "Crea campagna"
	_new_campaign_dialog.cancel_button_text = "Annulla"
	_new_campaign_dialog.min_size = Vector2i(440, 210)
	add_child(_new_campaign_dialog)

	var body: VBoxContainer = VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 18
	body.offset_top = 18
	body.offset_right = -18
	body.offset_bottom = -68
	body.add_theme_constant_override("separation", 10)
	_new_campaign_dialog.add_child(body)

	var label: Label = Label.new()
	label.text = "Inserisci il nome della campagna:"
	body.add_child(label)

	_new_campaign_name = LineEdit.new()
	_new_campaign_name.placeholder_text = "Nome campagna"
	_new_campaign_name.max_length = 80
	body.add_child(_new_campaign_name)

	_new_campaign_dialog.confirmed.connect(_confirm_new_campaign)


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

	var campaign_id: String = String(_campaign_manager().call("create_campaign", campaign_name))
	if campaign_id.is_empty():
		_show_error("Impossibile creare la campagna.")
		return

	var error: Error = int(_campaign_manager().call("open_campaign", campaign_id))
	if error != OK:
		_show_error("Impossibile aprire la nuova campagna: %s" % error_string(error))



func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _show_options_placeholder() -> void:
	_options_dialog.popup_centered(Vector2i(460, 190))


func _show_error(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 180))
	dialog.close_requested.connect(dialog.queue_free)
