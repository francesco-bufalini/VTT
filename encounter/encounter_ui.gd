extends VBoxContainer

var controller: Node
var _status: Label
var _round: Label
var _details: Label
var _feedback: Label
var _advance: Button
var _damage: SpinBox
var _target: OptionButton
var _seals: Array[ProgressBar] = []
var _seal_labels: Array[Label] = []
var _buttons: Array[Button] = []
var _rendering: bool = false

func setup(progress: Node) -> void:
	controller = progress
	# Runtime toolbar occupies the top strip; keep the encounter HUD below it.
	position = Vector2(14, 54)
	custom_minimum_size.x = 244
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_label(self, "Il filo del destino", 21)
	_round = _label(self, "", 12)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.035,0.045,0.048,0.93), Color(0.3,0.32,0.30)))
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	_status = _label(content, "", 13)
	content.add_child(HSeparator.new())
	for seal_name in ["Fronte", "Polso sinistro", "Polso destro"]:
		_seal_labels.append(_label(content, seal_name, 12))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 9)
		bar.max_value = controller.seals.break_damage
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _style(Color(0.12,0.14,0.15),Color.TRANSPARENT,0))
		bar.add_theme_stylebox_override("fill", _style(Color(0.50,0.66,0.68),Color.TRANSPARENT,0))
		content.add_child(bar)
		_seals.append(bar)
	var row := HBoxContainer.new()
	content.add_child(row)
	_target = OptionButton.new()
	for target_name in ["Kaos", "Sigillo fronte", "Sigillo sinistro", "Sigillo destro"]:
		_target.add_item(target_name)
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_target)
	_damage = SpinBox.new()
	_damage.max_value = 1000000
	_damage.custom_minimum_size.x = 66
	row.add_child(_damage)
	_button(content, "Applica danno", _apply_damage)
	_advance = _button(content, "Avanza", controller.advance_encounter)
	var save_row := HBoxContainer.new()
	content.add_child(save_row)
	_button(save_row, "Salva", func(): _feedback.text = "Incontro salvato" if controller.save_to_file() == OK else "Salvataggio non riuscito")
	_button(save_row, "Carica", func(): _feedback.text = "Incontro caricato" if controller.load_from_file() else "Salvataggio assente o non valido")
	_button(content, "Esporta vista 3D", _export_view)
	_feedback = _label(content, "", 12)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.x = 220
	var debug := VBoxContainer.new()
	add_child(debug)
	debug.visible = OS.is_debug_build() and controller.config.debug_panel_enabled
	_details = _label(debug, "", 12)
	_button(debug, "Reset", controller.reset_encounter)
	controller.state_changed.connect(refresh)
	refresh()

func _apply_damage() -> void:
	var amount := _damage.value
	_damage.value = 0
	var was_petrified: bool = controller.giant_petrified
	if _target.selected == 0:
		controller.register_kaos_damage(amount)
	else:
		controller.register_seal_damage(_target.selected-1, amount)
	if not was_petrified and controller.giant_petrified:
		_feedback.text = "Il gigante e' pietrificato. Kaos Grande entra nello scontro."

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _style(color: Color, border: Color, margin: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 12
	result.set_color("font_color", "Label", Color(0.88,0.90,0.88))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal",type,_style(Color(0.10,0.13,0.14),Color(0.28,0.33,0.33),7))
		result.set_stylebox("hover",type,_style(Color(0.18,0.23,0.24),Color(0.69,0.59,0.38),7))
		result.set_stylebox("pressed",type,_style(Color(0.08,0.16,0.17),Color(0.65,0.69,0.6),7))
		result.set_stylebox("disabled",type,_style(Color(0.08,0.09,0.10),Color(0.17,0.18,0.19),7))
	return result

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
	return button

func refresh() -> void:
	if not is_instance_valid(_status):
		return
	_round.text = "ROUND %02d" % controller.round_number
	_target.set_item_text(0,"Kaos Grande - fase 2" if controller.giant_petrified else "Kaos gigante")
	_status.text = "Kaos: %d m da Klothis\nProssimo avanzamento: %d m" % [controller.get_remaining_meters(),controller.get_next_movement_meters()]
	if controller.kaos_slowed:
		_status.text += "\nKaos rallentato"
	if controller.encounter_finished:
		_status.text = "Incontro terminato\n"+controller.end_reason
	elif controller.giant_petrified:
		_status.text = "Fase 2: Kaos Grande"
	elif controller.kaos_step == 0:
		_status.text = "Kaos si arrampica" if controller.is_advancing else "Kaos sulla sfera"
	elif controller.is_advancing:
		_status.text += "\nAvanzamento in corso"
	for index in range(3):
		_seals[index].value = controller.seals.break_damage - controller.seals.damage[index]
		var entry_name: String = ["Fronte", "Polso sinistro", "Polso destro"][index]
		_seal_labels[index].text = entry_name + (": infranto" if _seals[index].value == 0 else ": %.0f / %.0f danni" % [controller.seals.damage[index], controller.seals.break_damage])
		_seals[index].tooltip_text = "Danni: %.0f / %.0f" % [controller.seals.damage[index],controller.seals.break_damage]
	_details.text = "Step %d | danni %.0f / %.0f\nMinacciate %d | collassate %d\nSeed %s" % [controller.kaos_step,controller.damage_since_last_advance,controller.config.slow_damage_threshold,controller.hazards.threatened_cells.size(),controller.hazards.collapsed_cells.size(),str(controller.encounter_seed)]
	for button in _buttons:
		button.disabled = controller.is_advancing or _rendering
	_advance.disabled = controller.is_advancing or controller.encounter_finished or _rendering
	_advance.text = "Prossimo turno" if controller.kaos_step == 0 or controller.giant_petrified else "Avanza"

func _export_view(output_path: String = "", reveal_folder: bool = true) -> void:
	if _rendering:
		return
	_rendering = true
	refresh()
	var board: Node3D = controller.get_parent()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560,1440)
	viewport.world_3d = board.get_world_3d()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.global_transform = board.camera.global_transform
	camera.fov = board.camera.fov
	camera.near = board.camera.near
	camera.far = board.camera.far
	camera.current = true
	for frame in range(8):
		await RenderingServer.frame_post_draw
	var directory := "user://renders"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory + "/kaos_%d.png" % Time.get_unix_time_from_system() if output_path.is_empty() else output_path
	var error := viewport.get_texture().get_image().save_png(path)
	viewport.queue_free()
	_rendering = false
	refresh()
	_feedback.text = "Render salvato in user://renders" if error == OK else "Esportazione non riuscita"
	if error == OK and reveal_folder:
		OS.shell_open(ProjectSettings.globalize_path(directory))
