extends VBoxContainer
const Choices = preload("res://vtt/class_spell_selection.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
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
	var members: Array[Dictionary] = Choices.classes(record)
	var prepared: Array = record.get("prepared_spells", [])
	for member: Dictionary in members:
		_class_section(pair[0], record, member, prepared)
	var unassigned: Array[Dictionary] = []
	for item: Variant in prepared:
		if not item is Dictionary:
			continue
		var origins: Array = Choices.sources(item, record)
		var assigned_to_active_class := false
		for member: Dictionary in members:
			if member.id in origins:
				assigned_to_active_class = true
		if not assigned_to_active_class or "manual" in origins:
			unassigned.append(item)
	if not unassigned.is_empty():
		_heading(pair[0], "Altri incantesimi disponibili")
		_casting_statistics(pair[0], "manual", [String(_actions.default_ability.call())])
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
		var pending: Dictionary = choice.duplicate(true)
		pending["remaining"] = int(choice.get("count", 1)) - selected
		groups[sid].choices.append(pending)
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
		var suggested: Array[String] = []
		for grant: Dictionary in group.grants:
			suggested.append(String(grant.get("spellcasting_ability", "")))
		for choice: Dictionary in group.choices:
			suggested.append(String(choice.get("spellcasting_ability", "")))
		_casting_statistics(pair[0], "origin:" + sid, suggested)
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
			choose.text = "⚠ Scegli %d incantesimo/i" % int(choice.get("remaining", choice.get("count", 1)))
			choose.pressed.connect(_actions.choose_origin.bind(choice))
			pair[0].add_child(choose)
		if seen.is_empty():
			_label(pair[1], "Senza tracker · usa gli slot sopra quando previsto")
	_fit()
	_balance_lists.call_deferred()

func _pair() -> Array[VBoxContainer]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_table.add_child(row)
	_rows.append(row)
	var result: Array[VBoxContainer] = []
	for i: int in range(2):
		var panel := PanelContainer.new()
		panel.size_flags_vertical = Control.SIZE_FILL
		var style: StyleBoxFlat = get_theme_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
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

func _casting_statistics(parent: Node, section_id: String, suggested: Array[String]) -> void:
	var ability: String = String(_actions.section_ability.call(section_id, suggested))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	var picker := OptionButton.new()
	picker.name = "CastingAbility"
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = 70
	var english: bool = String(_actions.gui_language.call()) == "en"
	for key: String in ["str", "dex", "con", "int", "wis", "cha"]:
		picker.add_item(({"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"} if english else {"str": "FOR", "dex": "DES", "con": "COS", "int": "INT", "wis": "SAG", "cha": "CAR"})[key])
		picker.set_item_metadata(picker.item_count - 1, key)
		if key == ability:
			picker.select(picker.item_count - 1)
	picker.tooltip_text = "This section's spellcasting ability" if english else "Caratteristica da incantatore di questa sezione"
	picker.item_selected.connect(func(index: int) -> void:
		_actions.set_section_ability.call(section_id, String(picker.get_item_metadata(index)))
	)
	row.add_child(picker)
	var label: Label = _label(row, String(_actions.casting_stats.call(ability)))
	label.name = "CastingStatistics"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.91))

func _list(parent: Node, count: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 48.0
	scroll.set_meta("spell_list", true)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_force_pass_scroll_events = false
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
	_casting_statistics(section, String(member.id), [String(_actions.class_ability.call(String(member.name)))])
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
	if not grant.is_empty() and String(grant.get("payment_mode", "")) == "tracker":
		var cost: int = Grants.tracker_cost(grant)
		var english: bool = String(_actions.gui_language.call()) == "en"
		button.text += " · %d %s" % [cost, "uses" if english else "utilizzi"]
		button.tooltip_text += ("\n\nTracker cost: %d uses per cast" if english else "\n\nConsumo: %d utilizzi del tracker per lancio") % cost
	if grant.is_empty():
		button.pressed.connect(_actions.cast_class.bind(spell, member))
	else:
		button.pressed.connect(_actions.cast_origin.bind(grant))
	parent.add_child(button)

func _slots(parent: Node, record: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.name = "SlotGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	parent.add_child(grid)
	for index: int in range(3):
		var caption: Label = _label(grid, ["Liv.", "Classi", "Patto"][index])
		caption.custom_minimum_size.x = 24 if index == 0 else 104
		caption.size_flags_horizontal = Control.SIZE_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for level: int in range(1, 10):
		var title: Label = _label(grid, "%d°" % level)
		title.custom_minimum_size.x = 24
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		var totals: Array = record.get("spell_slots_total", [])
		var spent: Array = record.get("spell_slots_spent", [])
		var maximum: int = maxi(0, Bonuses.add(record, "slot:" + str(level), int(totals[level]) if totals.size() > level else 0))
		var used: int = int(spent[level]) if spent.size() > level else 0
		_counter(grid, maxi(0, maximum - used), maximum, _actions.slot.bind(level), level, record)
		var pact_max: int = maxi(0, Bonuses.add(record, "pact_slot", int(record.get("pact_slots_total", 0))))
		if level == int(record.get("pact_slot_level", 1)):
			_counter(grid, maxi(0, pact_max - int(record.get("pact_slots_spent", 0))), pact_max, _actions.pact, 0, record)
		else:
			_counter(grid, 0, 0, _actions.pact, 0, record)
	var restore := Button.new()
	restore.text = "Ripristina slot"
	restore.pressed.connect(_actions.restore)
	parent.add_child(restore)

func _counter(parent: Node, remaining: int, maximum: int, change: Callable, slot_level: int = -1, record: Dictionary = {}) -> void:
	var counter := HBoxContainer.new()
	counter.custom_minimum_size.x = 104
	counter.add_theme_constant_override("separation", 3)
	parent.add_child(counter)
	if maximum == 0 and slot_level == -1:
		var empty: Label = _label(counter, "0/0")
		empty.autowrap_mode = TextServer.AUTOWRAP_OFF
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	if maximum > 0:
		_compact_button(counter, "−", change.bind(1))
		_compact_button(counter, "+", change.bind(-1))
	var count: Label = _label(counter, str(remaining))
	count.custom_minimum_size.x = 18
	count.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var total: Label = _label(counter, "/%d" % maximum)
	total.custom_minimum_size.x = 24
	total.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	total.autowrap_mode = TextServer.AUTOWRAP_OFF
	if slot_level >= 0:
		var key: String = "pact_slot" if slot_level == 0 else "slot:" + str(slot_level)
		var base: int = int(record.get("pact_slots_total", 0)) if slot_level == 0 else (int(record.get("spell_slots_total", [])[slot_level]) if (record.get("spell_slots_total", []) as Array).size() > slot_level else 0)
		var bonus: int = Bonuses.bonus(record, key)
		var formula: String = "Base %d + bonus %+d = %d" % [base, bonus, maximum]
		var detail: String = Bonuses.description(record, key)
		total.tooltip_text = formula + ("\n" + detail if not detail.is_empty() else "") + "\nDoppio clic: modifica massimo. Clic destro: bonus e origini."
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = Color(0.55, 0.72, 0.81, 0.82)
		outline.set_border_width_all(1)
		outline.set_corner_radius_all(5)
		outline.set_content_margin_all(4)
		total.add_theme_stylebox_override("normal", outline)
		total.mouse_filter = Control.MOUSE_FILTER_STOP
		total.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		total.gui_input.connect(_slot_max_input.bind(slot_level))


func _slot_max_input(event: InputEvent, level: int) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		_actions.slot_max_bonus.call(level)
	elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click:
		_actions.slot_max_edit.call(level)


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
	_heading(parent, "Tracker · " + String(tracker.get("name", "Tracker")))
	var maximum: int = maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0))))
	var spent: int = int(record.get("resource_tracker_spent", {}).get(id, 0))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_counter(row, maxi(0, maximum - spent), maximum, _actions.tracker.bind(id, maximum))
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	if bool(tracker.get("disabled", false)) or not bool(enabled.get(String(tracker.get("origin_id", "")), true)):
		for button: Node in row.find_children("*", "Button", true, false):
			button.disabled = true
		_label(parent, "Tracker disattivato dall'origine")
	_label(parent, "Utilizzi disponibili; il costo per lancio è mostrato su ciascun potere")


func _definition(entry: Dictionary) -> Dictionary:
	var definition: Dictionary = Catalog.catalog_spell(String(entry.get("id", "")))
	return entry.duplicate(true) if definition.is_empty() else definition


func _balance_lists() -> void:
	# Measure the actual themed rows, not a guessed fixed pixel height.
	await get_tree().process_frame
	for row: HBoxContainer in _rows:
		var left := row.get_child(0).get_child(0) as VBoxContainer
		var right := row.get_child(1).get_child(0) as VBoxContainer
		var lists: Array[ScrollContainer] = []
		for node: Node in left.find_children("*", "ScrollContainer", true, false):
			if node.has_meta("spell_list"):
				var scroll := node as ScrollContainer
				scroll.custom_minimum_size.y = clampf(scroll.get_child(0).get_combined_minimum_size().y, 48.0, 180.0)
				lists.append(scroll)
		var extra := maxf(0.0, right.get_combined_minimum_size().y - left.get_combined_minimum_size().y)
		# Grow only lists with hidden content, until the neighbouring resources
		# no longer leave unused vertical space. Empty sections stay compact.
		for scroll: ScrollContainer in lists:
			var missing := maxf(0.0, scroll.get_child(0).get_combined_minimum_size().y - scroll.custom_minimum_size.y)
			var growth := minf(missing, extra)
			scroll.custom_minimum_size.y += growth
			extra -= growth
