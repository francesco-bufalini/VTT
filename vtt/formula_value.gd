extends HBoxContainer

signal bonus_requested(target: String)
var target_key := ""

# A compact number and formula hint. All editing uses the existing SpinBoxes
# and their original save callbacks, with no additional persisted state.
var value_label: Label
var _readout: HBoxContainer
var _editor: HBoxContainer
var _fields: Array[SpinBox] = []


func setup(label: Label, inputs: Array, captions: Array) -> void:
	add_theme_constant_override("separation", 3)
	value_label = label
	_readout = HBoxContainer.new()
	_readout.add_theme_constant_override("separation", 3)
	_readout.mouse_filter = Control.MOUSE_FILTER_STOP
	_readout.gui_input.connect(_on_readout_input)
	add_child(_readout)
	_readout.add_child(value_label)
	value_label.add_theme_font_size_override("font_size", 17)
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	# A thin outline, with no fill, denotes a computed value.
	# The detailed formula remains in the hover tooltip.
	var outline := StyleBoxFlat.new()
	outline.draw_center = false
	outline.border_color = Color(0.55, 0.72, 0.81, 0.82)
	outline.set_border_width_all(1)
	outline.set_corner_radius_all(5)
	outline.set_content_margin_all(4)
	value_label.add_theme_stylebox_override("normal", outline)
	_editor = HBoxContainer.new()
	_editor.add_theme_constant_override("separation", 5)
	add_child(_editor)
	for index: int in range(inputs.size()):
		var spin: SpinBox = inputs[index] as SpinBox
		if spin == null:
			continue
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 2)
		_editor.add_child(group)
		var heading := Label.new()
		heading.text = String(captions[index]) if index < captions.size() else "Valore"
		heading.add_theme_font_size_override("font_size", 11)
		group.add_child(heading)
		spin.reparent(group)
		spin.custom_minimum_size.x = minf(72.0, maxf(55.0, spin.custom_minimum_size.x))
		spin.get_line_edit().focus_exited.connect(_close_if_outside.call_deferred)
		# Let SpinBox commit the typed number before hiding its LineEdit.
		spin.get_line_edit().text_submitted.connect(func(_text: String) -> void: call_deferred("close_editor"))
		_fields.append(spin)
	_editor.hide()


func set_formula(result: String, explanation: String) -> void:
	value_label.text = result
	_readout.tooltip_text = explanation + ("\nDoppio clic per modificare i valori consentiti." if not _fields.is_empty() else "")
	_readout.tooltip_text += "\nClic destro per gestire i bonus e le loro origini."
	value_label.tooltip_text = _readout.tooltip_text


func _on_readout_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		bonus_requested.emit(target_key)
		accept_event()
	elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click:
		if _fields.is_empty():
			bonus_requested.emit(target_key)
		else:
			open_editor()
		accept_event()


func open_editor() -> void:
	if _fields.is_empty():
		return
	_readout.hide()
	_editor.show()
	_fields[0].get_line_edit().grab_focus()
	_fields[0].get_line_edit().select_all()


func close_editor() -> void:
	if _editor == null:
		return
	_editor.hide()
	_readout.show()


func _close_if_outside() -> void:
	if not _editor.visible or not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _editor.is_ancestor_of(focused):
		close_editor()
