extends RefCounted
# Stateless presentation helpers for origin editors.

static func popup_form(owner: Control, form: Control, caption: String, submit: Button = null) -> AcceptDialog:
	var parent: Node = form.get_parent()
	var index: int = form.get_index()
	parent.remove_child(form)
	var dialog := AcceptDialog.new()
	dialog.title = caption
	dialog.ok_button_text = "Chiudi"
	owner.add_child(dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	dialog.add_child(scroll)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	var open := Button.new()
	open.text = caption
	parent.add_child(open)
	parent.move_child(open, index)
	open.pressed.connect(func() -> void: dialog.popup_centered(Vector2i(640, 400)))
	if submit != null:
		submit.pressed.connect(dialog.hide)
	return dialog

static func edit_fields(owner: Control, parent: Control, fields: Array[Control], title: String, apply: Callable = Callable()) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	for field: Control in fields:
		field.reparent(box)
	if not apply.is_valid():
		popup_form(owner, box, "Modifica · " + title)
		return
	parent.remove_child(box)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Modifica · " + title
	dialog.ok_button_text = "Salva"
	dialog.cancel_button_text = "Annulla"
	owner.add_child(dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	dialog.add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	dialog.confirmed.connect(apply)
	var open := Button.new()
	open.text = "Modifica"
	parent.add_child(open)
	var initial: Array[Dictionary] = []
	for field: Control in fields:
		_capture_fields(field, initial)
	dialog.canceled.connect(func() -> void:
		for item: Dictionary in initial:
			var control: Control = item["control"]
			if control is SpinBox:
				control.set_value_no_signal(float(item["value"]))
			elif control is OptionButton:
				control.select(int(item["value"]))
			elif control is LineEdit:
				control.text = String(item["value"])
	)
	open.pressed.connect(func() -> void: dialog.popup_centered(Vector2i(560, 230)))

static func origin_link(owner: Control, row: Control, sid: String, title: String) -> void:
	if sid.is_empty():
		return
	var select: Control = row.get_child(0) as Control if row.get_child_count() > 0 else null
	if select != null:
		if select is Label:
			select.mouse_filter = Control.MOUSE_FILTER_PASS
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.custom_minimum_size.x = 180
		var base_tooltip: String = select.tooltip_text
		select.mouse_entered.connect(func() -> void:
			var preview: Callable = _callback(owner, "origin_preview")
			if preview.is_valid():
				select.tooltip_text = base_tooltip + "\n\n" + String(preview.call(sid))
		)
	var link := Button.new()
	link.name = "OriginTraitLink"
	link.text = "↗"
	link.custom_minimum_size = Vector2(32, 32)
	link.tooltip_text = "Vai al tratto · " + title
	link.set_meta("origin_id", sid)
	row.add_child(link)
	link.pressed.connect(func() -> void:
		var navigate: Callable = _callback(owner, "origin_navigate")
		if navigate.is_valid():
			navigate.call(sid, title)
	)


static func _callback(owner: Node, key: String) -> Callable:
	var node: Node = owner
	while node != null:
		if node.has_meta(key):
			return node.get_meta(key) as Callable
		node = node.get_parent()
	return Callable()


static func _capture_fields(node: Control, values: Array[Dictionary]) -> void:
	if node is SpinBox:
		values.append({"control": node, "value": node.value})
		return
	if node is OptionButton:
		values.append({"control": node, "value": node.selected})
	elif node is LineEdit:
		values.append({"control": node, "value": node.text})
	for child: Node in node.get_children():
		if child is Control:
			_capture_fields(child, values)


static func highlight(card: Control, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
	style.border_color = Color(0.40, 0.72, 0.91) if selected else Color(0.36, 0.31, 0.27, 0.75)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(7)
	card.add_theme_stylebox_override("panel", style)
