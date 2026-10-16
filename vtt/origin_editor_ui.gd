extends RefCounted
const OriginButton = preload("res://vtt/bounded_tooltip_button.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")
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
	open.pressed.connect(func() -> void: DialogLayout.popup(dialog, Vector2i(640, 400)))
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
	open.pressed.connect(func() -> void: DialogLayout.popup(dialog, Vector2i(560, 230)))

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



# Shared origin card used by bonus, proficiency, feat, tracker and defense
# editors. The caller decides visibility, counts, grants, warnings and
# whether an origin can be toggled; only its presentation lives here.
# Identical scroll spacing, sizing and wheel handoff in every origin column.
static func origin_list(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 245
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_force_pass_scroll_events = false
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ScrollBoundaryGuard.install(scroll)
	parent.add_child(scroll)
	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 5)
	scroll.add_child(cards)
	return cards


static func clear_origin_cards(parent: Control) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func origin_card(owner: Control, parent: Control, config: Dictionary) -> Button:
	var sid: String = String(config.get("id", ""))
	var selected: bool = bool(config.get("selected", false))
	var active: bool = bool(config.get("active", true))
	var panel := PanelContainer.new()
	panel.name = "OriginCard"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var line := HBoxContainer.new()
	line.name = "OriginCardActions"
	line.add_theme_constant_override("separation", 4)
	panel.add_child(line)

	var select := OriginButton.new()
	select.name = "OriginSelect"
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.toggle_mode = true
	select.button_pressed = selected
	select.clip_text = true
	select.text = String(config.get("text", config.get("name", sid)))
	select.tooltip_text = String(config.get("tooltip", ""))
	var on_select: Callable = config.get("on_select", Callable())
	if on_select.is_valid():
		select.pressed.connect(on_select)
	line.add_child(select)
	if bool(config.get("link", true)):
		origin_link(owner, line, sid, String(config.get("name", sid)))
	# The overview has more room; origin cards must fit narrow editor columns.
	# Long names are clipped on the button and readable in the full tooltip.
	select.custom_minimum_size.x = 105

	# Domain editors can add completion and editing actions without having to
	# recreate a card. They appear before the origin activation control.
	var actions: Array = config.get("actions", [])
	for entry: Variant in actions:
		if not entry is Dictionary:
			continue
		var action: Dictionary = entry
		var callback: Callable = action.get("callback", Callable())
		if not callback.is_valid():
			continue
		var extra := Button.new()
		extra.flat = true
		extra.text = String(action.get("text", "⚠"))
		extra.custom_minimum_size.x = 32
		extra.tooltip_text = String(action.get("tooltip", ""))
		if bool(action.get("warning", false)):
			extra.add_theme_color_override("font_color", Color(1.0, 0.80, 0.33))
		extra.pressed.connect(callback)
		line.add_child(extra)

	var on_toggle: Callable = config.get("on_toggle", Callable())
	if not sid.is_empty() and on_toggle.is_valid():
		var toggle := CheckButton.new()
		toggle.name = "OriginActive"
		toggle.text = "⏻"
		toggle.button_pressed = active
		toggle.disabled = bool(config.get("toggle_disabled", false))
		toggle.tooltip_text = String(config.get("toggle_tooltip",
			"Attiva o disattiva questa origine senza eliminare i benefici."))
		toggle.toggled.connect(on_toggle)
		line.add_child(toggle)

	select.set_meta("origin_active", active)
	origin_card_state(panel, selected, active)
	return select


# Keep caption headings and disabled-grant markers consistent. Editors still
# decide which grants are selected, automatic or domain-specific.
static func grants_tooltip(
	selected: PackedStringArray, automatic: PackedStringArray,
	extra: PackedStringArray, extra_title: String
) -> String:
	var sections := PackedStringArray()
	if not selected.is_empty():
		sections.append("Scelte già effettuate:\n" + "\n".join(selected))
	if not automatic.is_empty():
		sections.append("Concessioni automatiche:\n" + "\n".join(automatic))
	if not extra.is_empty() and not extra_title.is_empty():
		sections.append(extra_title + ":\n" + "\n".join(extra))
	return "\n\n" + "\n\n".join(sections) if not sections.is_empty() else ""


static func origin_card_state(panel: Control, selected: bool, active: bool) -> void:
	# A selected, disabled origin is still legible and visually selected.
	# Keep the same compact layout and selection border in every editor.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
	style.border_color = Color(0.40, 0.72, 0.91) if selected else Color(0.36, 0.31, 0.27, 0.75)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	panel.modulate.a = 1.0 if selected or active else 0.58


static func highlight(card: Control, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
	style.border_color = Color(0.40, 0.72, 0.91) if selected else Color(0.36, 0.31, 0.27, 0.75)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(7)
	card.add_theme_stylebox_override("panel", style)
