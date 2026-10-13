extends VBoxContainer
const Choices = preload("res://vtt/class_spell_selection.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
var _actions: Dictionary
var _table: VBoxContainer
var _rows: Array[HBoxContainer] = []
var _left_width := 430.0
var _right_width := 310.0

func setup(actions: Dictionary) -> void:
	_actions = actions
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 12)
	add_child(_table)
	resized.connect(_fit)

func refresh() -> void:
	for child: Node in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	_rows.clear()
	var record: Dictionary = _actions.record.call()
	var pair: Array[VBoxContainer] = _pair()
	var class_header := HBoxContainer.new()
	pair[0].add_child(class_header)
	_heading(class_header, "Incantesimi disponibili")
	var manual := Button.new()
	manual.text = "⋯"
	manual.tooltip_text = "Scegli altri incantesimi disponibili o assegna le selezioni precedenti"
	manual.pressed.connect(_actions.manual)
	class_header.add_child(manual)
	var slot_header := HBoxContainer.new()
	pair[1].add_child(slot_header)
	_heading(slot_header, "Slot · Classi / Patto")
	var settings := Button.new()
	settings.text = "⚙"
	settings.tooltip_text = "Modifica i massimi base e i bonus degli slot"
	settings.pressed.connect(_actions.resource_settings)
	slot_header.add_child(settings)
	var members: Array[Dictionary] = Choices.classes(record)
	var prepared: Array = record.get("prepared_spells", [])
	for member: Dictionary in members:
		_class_section(pair[0], record, member, prepared)
	var unassigned: Array[Dictionary] = []
	for item: Variant in prepared:
		if item is Dictionary and (Choices.sources(item, record).is_empty() or "manual" in Choices.sources(item, record)):
			unassigned.append(item)
	if not unassigned.is_empty():
		_heading(pair[0], "Altri incantesimi disponibili")
		var manual_list: VBoxContainer = _list(pair[0], unassigned.size())
		for spell: Dictionary in unassigned:
			_spell_button(manual_list, _definition(spell), {}, {})
	if members.is_empty() and unassigned.is_empty():
		_label(pair[0], "Nessuna classe con incantesimi. Le concessioni dei privilegi sono qui sotto.")
	_slots(pair[1], record)
	var groups: Dictionary = {}
	for grant: Dictionary in Grants.all_grants(record):
		var sid: String = String(grant.get("origin_id", ""))
		if not groups.has(sid):
			groups[sid] = {"grants": [], "choices": [], "name": grant.get("origin_name", sid)}
		groups[sid].grants.append(grant)
	for choice: Dictionary in Structured.for_creature(record).get("choices", []):
		var selected := 0
		for saved: Variant in record.get("origin_spell_grants", []):
			if saved is Dictionary and String(saved.get("source_choice_id", "")) == String(choice.get("id", "")):
				selected += 1
		if selected >= int(choice.get("count", 1)):
			continue
		var sid: String = String(choice.get("origin_id", ""))
		if not groups.has(sid):
			groups[sid] = {"grants": [], "choices": [], "name": choice.get("origin_name", sid)}
		groups[sid].choices.append(choice)
	for sid: String in groups:
		var group: Dictionary = groups[sid]
		pair = _pair()
		var heading := HBoxContainer.new()
		pair[0].add_child(heading)
		var title := _label(heading, "Origine · " + String(group.name))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var edit := Button.new()
		edit.text = "✎"
		edit.tooltip_text = "Scegli o modifica gli incantesimi di questa origine"
		edit.pressed.connect(_actions.edit_origin.bind(sid))
		heading.add_child(edit)
		var list: VBoxContainer = _list(pair[0], group.grants.size())
		var seen: Dictionary = {}
		for grant: Dictionary in group.grants:
			var spell: Dictionary = Catalog.catalog_spell(String(grant.get("spell_id", "")))
			_spell_button(list, spell, {}, grant)
			var id: String = String(grant.get("tracker_id", ""))
			if String(grant.get("payment_mode", "")) == "tracker" and not id.is_empty() and not seen.has(id):
				seen[id] = true
				_tracker(pair[1], record, Grants.tracker_for(record, grant))
		for choice: Dictionary in group.choices:
			var tracker_id: String = String(choice.get("tracker_id", ""))
			if not tracker_id.is_empty() and not seen.has(tracker_id):
				for tracker: Dictionary in Trackers.for_creature(record):
					if String(tracker.get("id", "")) == tracker_id:
						seen[tracker_id] = true
						_tracker(pair[1], record, tracker)
						break
			var choose := Button.new()
			choose.text = "⚠ Scegli %d incantesimo/i" % int(choice.get("count", 1))
			choose.pressed.connect(_actions.choose_origin.bind(choice))
			pair[0].add_child(choose)
		if seen.is_empty():
			_label(pair[1], "Senza tracker · usa gli slot sopra quando previsto")
	_fit()

func _pair() -> Array[VBoxContainer]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_table.add_child(row)
	_rows.append(row)
	var result: Array[VBoxContainer] = []
	for i: int in range(2):
		var panel := PanelContainer.new()
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.13, 0.9)
		style.border_color = Color(0.43, 0.36, 0.28)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		result.append(box)
	return result

func _fit() -> void:
	if size.x > 0:
		_left_width = clampf((size.x - 12.0) * 0.58, 270.0, 680.0)
		_right_width = clampf(size.x - 12.0 - _left_width, 240.0, 420.0)
	for row: HBoxContainer in _rows:
		row.get_child(0).custom_minimum_size.x = _left_width
		row.get_child(1).custom_minimum_size.x = _right_width

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _heading(parent: Node, text: String) -> void:
	var label: Label = _label(parent, text)
	label.add_theme_font_size_override("font_size", 17)

func _list(parent: Node, count: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = clampf(float(count) * 35.0, 48.0, 180.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = true
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _class_section(parent: Node, record: Dictionary, member: Dictionary, prepared: Array) -> void:
	var section := VBoxContainer.new()
	section.name = "Class_" + String(member.name)
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	var selected: Array[String] = Choices.selected(record, prepared, member.id)
	var leveled := 0
	var cantrips := 0
	for id: String in selected:
		if int(Catalog.catalog_spell(id).get("level", 0)) == 0:
			cantrips += 1
		else:
			leveled += 1
	var status: Label = _label(header, "%s · %s %d/%s · Trucchetti %d/%d" % [member.name,
		member.mode, leveled, str(member.limit) if int(member.limit) >= 0 else "—", cantrips, member.cantrips])
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if (int(member.limit) >= 0 and leveled != int(member.limit)) or cantrips != int(member.cantrips):
		var warning := _label(header, "⚠")
		warning.autowrap_mode = TextServer.AUTOWRAP_OFF
		warning.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		warning.custom_minimum_size.x = 24
		warning.tooltip_text = "Selezione incompleta o superiore agli incantesimi concessi dalla classe."
		warning.mouse_filter = Control.MOUSE_FILTER_PASS
	var choose := Button.new()
	choose.text = "Scegli"
	choose.pressed.connect(_actions.edit_class.bind(member))
	header.add_child(choose)
	var list: VBoxContainer = _list(section, selected.size())
	if selected.is_empty():
		_label(list, "Nessun incantesimo selezionato")
	for id: String in selected:
		_spell_button(list, Catalog.catalog_spell(id), member, {})
	if bool(member.book):
		_label(section, "📖 Libro: %d incantesimi conosciuti" % (record.get("spellbook_spells", []) as Array).size())

func _spell_button(parent: Node, spell: Dictionary, member: Dictionary, grant: Dictionary) -> void:
	if spell.is_empty():
		return
	var button := Button.new()
	button.set_meta("creature_gui_data", true)
	button.text = String(spell.get("name", "")) + (" · 0°" if int(spell.get("level", 0)) == 0 else " · %d°" % int(spell.get("level", 0)))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = String(spell.get("description", ""))
	if grant.is_empty():
		button.pressed.connect(_actions.cast_class.bind(spell, member))
	else:
		button.pressed.connect(_actions.cast_origin.bind(grant))
	parent.add_child(button)

func _slots(parent: Node, record: Dictionary) -> void:
	var headings := HBoxContainer.new()
	parent.add_child(headings)
	headings.add_theme_constant_override("separation", 5)
	for index: int in range(3):
		var caption: Label = _label(headings, ["Liv.", "Classi", "Patto"][index])
		caption.custom_minimum_size.x = 24 if index == 0 else 104
		caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for level: int in range(10):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		parent.add_child(row)
		var title: Label = _label(row, "%d°" % level)
		title.custom_minimum_size.x = 24
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		if level == 0:
			_label(row, "Trucchetti · senza slot")
			continue
		var totals: Array = record.get("spell_slots_total", [])
		var spent: Array = record.get("spell_slots_spent", [])
		var maximum: int = maxi(0, Bonuses.add(record, "slot:" + str(level), int(totals[level]) if totals.size() > level else 0))
		var used: int = int(spent[level]) if spent.size() > level else 0
		_counter(row, maxi(0, maximum - used), maximum, _actions.slot.bind(level))
		var pact_max: int = maxi(0, Bonuses.add(record, "pact_slot", int(record.get("pact_slots_total", 0))))
		if level == int(record.get("pact_slot_level", 1)):
			_counter(row, maxi(0, pact_max - int(record.get("pact_slots_spent", 0))), pact_max, _actions.pact)
		else:
			var empty: Label = _label(row, "0/0")
			empty.custom_minimum_size.x = 104
			empty.autowrap_mode = TextServer.AUTOWRAP_OFF
			empty.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var restore := Button.new()
	restore.text = "Ripristina slot"
	restore.pressed.connect(_actions.restore)
	parent.add_child(restore)

func _counter(parent: Node, remaining: int, maximum: int, change: Callable) -> void:
	var counter := HBoxContainer.new()
	counter.custom_minimum_size.x = 104
	counter.add_theme_constant_override("separation", 3)
	parent.add_child(counter)
	_compact_button(counter, "−", change.bind(1))
	var count: Label = _label(counter, "%d/%d" % [remaining, maximum])
	count.custom_minimum_size.x = 38
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compact_button(counter, "+", change.bind(-1))

func _compact_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = button.get_theme_stylebox(state).duplicate()
		style.content_margin_left = 4
		style.content_margin_right = 4
		button.add_theme_stylebox_override(state, style)
	button.tooltip_text = "Consuma un utilizzo" if text == "−" else "Recupera un utilizzo"
	button.pressed.connect(action)
	parent.add_child(button)


func _tracker(parent: Node, record: Dictionary, tracker: Dictionary) -> void:
	if tracker.is_empty():
		_label(parent, "⚠ Tracker non disponibile")
		return
	var id: String = String(tracker.get("id", ""))
	_heading(parent, String(tracker.get("name", "Tracker")))
	var maximum: int = maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0))))
	var spent: int = int(record.get("resource_tracker_spent", {}).get(id, 0))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_counter(row, maxi(0, maximum - spent), maximum, _actions.tracker.bind(id, maximum))
	_label(parent, "Consumo: 1 utilizzo per lancio")


func _definition(entry: Dictionary) -> Dictionary:
	var definition: Dictionary = Catalog.catalog_spell(String(entry.get("id", "")))
	return entry.duplicate(true) if definition.is_empty() else definition
