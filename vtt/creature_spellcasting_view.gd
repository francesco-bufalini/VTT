extends VBoxContainer
const Choices = preload("res://vtt/class_spell_selection.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Abilities = preload("res://vtt/activated_ability_catalog.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
var _actions: Dictionary
var _table: VBoxContainer
var _rows: Array[BoxContainer] = []
var _left_width := 430.0
var _right_width := 310.0
var _touch_layout := false

func setup(actions: Dictionary) -> void:
	_actions = actions
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 12)
	add_child(_table)
	resized.connect(_fit)

func configure_touch_layout() -> void:
	_touch_layout = true
	refresh()

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
			unassigned.append({"spell": _definition(item), "member": {}, "grant": {}})
	if not unassigned.is_empty():
		_heading(pair[0], "Altri incantesimi disponibili")
		_casting_statistics(pair[0], "manual", [String(_actions.default_ability.call())])
		_leveled_spell_list(pair[0], unassigned)
	if members.is_empty() and unassigned.is_empty():
		_label(pair[0], "Nessuna classe con incantesimi. Le concessioni dei privilegi sono qui sotto.")
	_slots(pair[1], record)

	# Slot-paid grants keep their casting origin. Every other spell/ability
	# shares a box with the other powers spending its tracker, across origins.
	var slot_origins: Dictionary = {}
	var tracker_groups: Dictionary = {}
	for grant: Dictionary in Grants.all_grants(record):
		if String(grant.get("payment_mode", "")) == "slot":
			var sid: String = String(grant.get("origin_id", ""))
			if not slot_origins.has(sid):
				slot_origins[sid] = {"grants": [], "choices": [], "name": grant.get("origin_name", sid)}
			slot_origins[sid]["grants"].append(grant)
		else:
			_add_tracker_power(tracker_groups, record, grant)
	for choice: Dictionary in Structured.for_creature(record).get("choices", []):
		var selected := 0
		for saved: Variant in record.get("origin_spell_grants", []):
			if saved is Dictionary and String(saved.get("source_choice_id", "")) == String(choice.get("id", "")):
				selected += 1
		if selected >= int(choice.get("count", 1)):
			continue
		var sid: String = String(choice.get("origin_id", ""))
		if not slot_origins.has(sid):
			slot_origins[sid] = {"grants": [], "choices": [], "name": choice.get("origin_name", sid)}
		var pending: Dictionary = choice.duplicate(true)
		pending["remaining"] = int(choice.get("count", 1)) - selected
		slot_origins[sid]["choices"].append(pending)
	var origin_ids: Array = slot_origins.keys()
	origin_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(slot_origins[a]["name"]).naturalnocasecmp_to(String(slot_origins[b]["name"])) < 0)
	for sid: String in origin_ids:
		var group: Dictionary = slot_origins[sid]
		pair = _pair()
		var heading := HBoxContainer.new()
		pair[0].add_child(heading)
		var title := _label(heading, "Origine · " + String(group["name"]))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var edit := Button.new()
		edit.text = "✎"
		edit.tooltip_text = "Scegli o modifica gli incantesimi di questa origine"
		edit.pressed.connect(_actions.edit_origin.bind(sid))
		heading.add_child(edit)
		var suggested: Array[String] = []
		var spells: Array[Dictionary] = []
		var abilities: Array[Dictionary] = []
		for grant: Dictionary in group["grants"]:
			suggested.append(String(grant.get("spellcasting_ability", "")))
			var spell: Dictionary = Catalog.catalog_spell(String(grant.get("spell_id", "")))
			if Abilities.is_ability(spell):
				abilities.append({"spell": spell, "grant": grant})
			else:
				spells.append({"spell": spell, "member": {}, "grant": grant})
		for choice: Dictionary in group["choices"]:
			suggested.append(String(choice.get("spellcasting_ability", "")))
		_casting_statistics(pair[0], "origin:" + sid, suggested)
		if not spells.is_empty():
			_leveled_spell_list(pair[0], spells)
		for entry: Dictionary in abilities:
			_spell_button(pair[0], entry["spell"], {}, entry["grant"])
		for choice: Dictionary in group["choices"]:
			var choose := Button.new()
			choose.text = "⚠ Scegli %d incantesimo/i" % int(choice.get("remaining", choice.get("count", 1)))
			choose.pressed.connect(_actions.choose_origin.bind(choice))
			pair[0].add_child(choose)
		_label(pair[1], "Usa gli slot di classe o del Patto")

	# Class abilities use the very same tracker grouping as granted spells.
	var features: Array[Dictionary] = preload("res://vtt/class_feature_activation.gd").entries(record)
	for feature: Dictionary in features:
		_add_tracker_feature(tracker_groups, record, feature)
	var tracker_keys: Array = tracker_groups.keys()
	tracker_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		if String(a) == "free": return false
		if String(b) == "free": return true
		return String(tracker_groups[a]["name"]).naturalnocasecmp_to(String(tracker_groups[b]["name"])) < 0)
	for key: String in tracker_keys:
		var group: Dictionary = tracker_groups[key]
		pair = _pair()
		_heading(pair[0], String(group["name"]))
		var suggested_origins: Dictionary = {}
		var spell_entries: Array[Dictionary] = []
		var abilities: Array[Dictionary] = []
		for entry: Dictionary in group["powers"]:
			var spell: Dictionary = entry["spell"]
			var grant: Dictionary = entry["grant"]
			if Abilities.is_ability(spell):
				abilities.append(entry)
			else:
				spell_entries.append({"spell": spell, "member": {}, "grant": grant})
				var sid: String = String(grant.get("origin_id", ""))
				if not suggested_origins.has(sid):
					suggested_origins[sid] = {"name": String(grant.get("origin_name", sid)), "abilities": []}
				suggested_origins[sid]["abilities"].append(String(grant.get("spellcasting_ability", "")))
		for sid: String in suggested_origins:
			var suggested: Array[String] = []
			suggested.assign(suggested_origins[sid]["abilities"])
			_label(pair[0], "Lancio · " + String(suggested_origins[sid]["name"]))
			_casting_statistics(pair[0], "origin:" + sid, suggested)
		if not spell_entries.is_empty():
			_leveled_spell_list(pair[0], spell_entries)
		if not abilities.is_empty() or not (group["features"] as Array).is_empty():
			_heading(pair[0], "Capacità")
			abilities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a["spell"].get("name", "")).naturalnocasecmp_to(String(b["spell"].get("name", ""))) < 0)
			for entry: Dictionary in abilities:
				_spell_button(pair[0], entry["spell"], {}, entry["grant"])
			for feature: Dictionary in group["features"]:
				_feature_button(pair[0], feature)
		var tracker: Dictionary = group["tracker"]
		if not tracker.is_empty():
			_tracker(pair[1], record, tracker)
		elif key == "free":
			_label(pair[1], "Nessuna risorsa consumata")
		else:
			_label(pair[1], "⚠ Tracker non disponibile")
	_fit()
	_balance_lists.call_deferred()

func _add_tracker_power(groups: Dictionary, record: Dictionary, grant: Dictionary) -> void:
	var mode: String = String(grant.get("payment_mode", "free"))
	var id: String = String(grant.get("tracker_id", "")) if mode == "tracker" else ""
	var key: String = ("tracker:" + id) if not id.is_empty() else ("missing" if mode == "tracker" else "free")
	var tracker: Dictionary = Grants.tracker_for(record, grant) if not id.is_empty() else {}
	if not groups.has(key):
		groups[key] = {"name": String(tracker.get("name", id)) if not id.is_empty() else ("Tracker non disponibile" if mode == "tracker" else "Senza consumo"),
			"tracker": tracker, "powers": [], "features": []}
	var spell: Dictionary = Catalog.catalog_spell(String(grant.get("spell_id", "")))
	if not spell.is_empty():
		groups[key]["powers"].append({"spell": spell, "grant": grant})

func _add_tracker_feature(groups: Dictionary, record: Dictionary, feature: Dictionary) -> void:
	const Activation = preload("res://vtt/class_feature_activation.gd")
	var resource: String = String(feature.get("resource_name", ""))
	var tracker: Dictionary = Activation.tracker_named(record, resource, String(feature.get("class_name", "")))
	var cost: int = int(feature.get("cost", 0))
	var id: String = String(tracker.get("id", feature.get("tracker_id", ""))) if cost > 0 and not resource.is_empty() else ""
	var key: String = ("tracker:" + id) if not id.is_empty() else ("missing" if cost > 0 and not resource.is_empty() else "free")
	if not groups.has(key):
		groups[key] = {"name": String(tracker.get("name", resource)) if not id.is_empty() else ("Tracker non disponibile" if key == "missing" else "Senza consumo"),
			"tracker": tracker, "powers": [], "features": []}
	groups[key]["features"].append(feature)

func _feature_button(parent: Node, feature: Dictionary) -> void:
	var button := Button.new()
	button.text = ("Termina · " if bool(feature.get("active", false)) else "Usa · ") + String(feature.get("name", ""))
	button.tooltip_text = String(feature.get("detail", ""))
	button.custom_minimum_size.y = 40
	button.pressed.connect(_actions.class_feature.bind(String(feature.get("id", ""))))
	parent.add_child(button)
	if int(feature.get("cost", 0)) > 0 and not String(feature.get("resource_name", "")).is_empty():
		var price: Label = _label(parent, "Costo: %d" % int(feature["cost"]))
		price.add_theme_font_size_override("font_size", 12)

func _pair() -> Array[VBoxContainer]:
	var row: BoxContainer
	if _touch_layout:
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_table.add_child(row)
	_rows.append(row)
	var result: Array[VBoxContainer] = []
	for i: int in range(2):
		var panel := PanelContainer.new()
		panel.size_flags_vertical = Control.SIZE_FILL
		var style := preload("res://vtt/creature_sheet_style.gd").section_style()
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		result.append(box)
	return result

func _fit() -> void:
	if _touch_layout:
		for row: BoxContainer in _rows:
			for panel: Control in row.get_children():
				panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if panel.custom_minimum_size.x != 0:
					panel.custom_minimum_size.x = 0
		return
	if size.x > 0:
		_left_width = clampf((size.x - 12.0) * 0.58, 270.0, 680.0)
		_right_width = clampf(size.x - 12.0 - _left_width, 240.0, 420.0)
	for row: BoxContainer in _rows:
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
	preload("res://vtt/creature_sheet_style.gd").heading(label, "spell_cast")

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
	scroll.custom_minimum_size.y = 68.0
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
	var spells: Array[Dictionary] = []
	for id: String in selected:
		spells.append({"spell": Catalog.catalog_spell(id), "member": member, "grant": {}})
	if spells.is_empty():
		_label(section, "Nessun incantesimo selezionato")
	else:
		_leveled_spell_list(section, spells)
	if bool(member.book):
		_label(section, "📖 Libro: %d incantesimi conosciuti" % (record.get("spellbook_spells", []) as Array).size())

func _leveled_spell_list(parent: Node, entries: Array[Dictionary]) -> VBoxContainer:
	var list: VBoxContainer = _list(parent, entries.size())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Dictionary = a["spell"]
		var sb: Dictionary = b["spell"]
		var level_a: int = int(sa.get("level", 0))
		var level_b: int = int(sb.get("level", 0))
		if level_a != level_b: return level_a < level_b
		return String(sa.get("name", "")).naturalnocasecmp_to(String(sb.get("name", ""))) < 0)
	var previous := -1
	for entry: Dictionary in entries:
		var spell: Dictionary = entry["spell"]
		if spell.is_empty():
			continue
		var level: int = int(spell.get("level", 0))
		if level != previous:
			var heading: Label = _label(list, "Trucchetti" if level == 0 else "Livello %d" % level)
			heading.name = "SpellLevelHeader"
			heading.add_theme_font_size_override("font_size", 14)
			heading.add_theme_color_override("font_color", Color(0.84, 0.71, 0.49))
			previous = level
		_spell_button(list, spell, entry["member"], entry["grant"])
	return list

func _spell_button(parent: Node, spell: Dictionary, member: Dictionary, grant: Dictionary) -> void:
	if spell.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "PowerRow"
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var button := Button.new()
	button.set_meta("creature_gui_data", true)
	button.text = String(spell.get("name", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = String(spell.get("description", ""))
	row.add_child(button)
	if not grant.is_empty() and String(grant.get("payment_mode", "")) == "tracker":
		var cost: int = Grants.tracker_cost(grant)
		var english: bool = String(_actions.gui_language.call()) == "en"
		var cost_label := _label(row, ("Cost: %d" if english else "Costo: %d") % cost)
		cost_label.name = "PowerCost"
		cost_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost_label.add_theme_font_size_override("font_size", 13)
		cost_label.add_theme_color_override("font_color", Color(0.79, 0.86, 0.91))
		cost_label.tooltip_text = ("Tracker cost per cast: %d" if english else "Utilizzi del tracker consumati per lancio: %d") % cost
	if Abilities.is_ability(spell) and String(spell.get("activation_mode", "")) == "contextual":
		# Maneuvers occur in attack/reaction contexts. Browsing a maneuver
		# must never consume a Superiority Die or invent a map effect.
		button.pressed.connect(_inspect_ability.bind(spell))
	elif grant.is_empty():
		button.pressed.connect(_actions.cast_class.bind(spell, member))
	else:
		button.pressed.connect(_actions.cast_origin.bind(grant))


func _inspect_ability(ability: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Capacità · " + String(ability.get("name", ""))
	dialog.dialog_text = String(ability.get("description", "Descrizione non disponibile."))
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	DialogLayout.popup(dialog, Vector2i(620, 420), 0.92)

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
		var created: Array = record.get("created_spell_slots", [])
		maximum += int(created[level]) if created.size() > level else 0
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
	counter.name = "ResourceCounter"
	counter.custom_minimum_size.x = 138 if _touch_layout else 126
	counter.add_theme_constant_override("separation", 3)
	parent.add_child(counter)
	# Fixed action cell: the numbers do not move when both buttons disappear.
	var actions := HBoxContainer.new()
	actions.name = "ResourceActions"
	actions.custom_minimum_size.x = 73 if _touch_layout else 67
	actions.add_theme_constant_override("separation", 3)
	counter.add_child(actions)
	if maximum > 0:
		_compact_button(actions, "−", change.bind(1))
		_compact_button(actions, "+", change.bind(-1))
	var count: Label = _label(counter, str(remaining))
	count.custom_minimum_size.x = 24
	count.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var total: Label = _label(counter, "/%d" % maximum)
	total.custom_minimum_size.x = 30
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
	button.set_meta("touch_compact_action", true)
	button.custom_minimum_size = Vector2(32 if _touch_layout else 30, 32 if _touch_layout else 26)
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
	var maximum: int = maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0))))
	var spent: int = int(record.get("resource_tracker_spent", {}).get(id, 0))
	var row := HBoxContainer.new()
	row.name = "TrackerRow"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	# Counters come first and the resource name shares the same line.
	_counter(row, maxi(0, maximum - spent), maximum, _actions.tracker.bind(id, maximum))
	var name: Label = _label(row, String(tracker.get("name", "Risorsa")))
	name.name = "TrackerName"
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 15)
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	if bool(tracker.get("disabled", false)) or not bool(enabled.get(String(tracker.get("origin_id", "")), true)):
		for button: Node in row.find_children("*", "Button", true, false):
			button.disabled = true
		name.tooltip_text = "Tracker disattivato dall'origine"

func _definition(entry: Dictionary) -> Dictionary:
	var definition: Dictionary = Catalog.catalog_spell(String(entry.get("id", "")))
	return entry.duplicate(true) if definition.is_empty() else definition


func _balance_lists() -> void:
	# Measure the actual themed rows, not a guessed fixed pixel height.
	await get_tree().process_frame
	for row: BoxContainer in _rows:
		var left := row.get_child(0).get_child(0) as VBoxContainer
		var right := row.get_child(1).get_child(0) as VBoxContainer
		var lists: Array[ScrollContainer] = []
		for node: Node in left.find_children("*", "ScrollContainer", true, false):
			if node.has_meta("spell_list"):
				var scroll := node as ScrollContainer
				var content: VBoxContainer = scroll.get_child(0) as VBoxContainer
				var first_height := 0.0
				if content != null and content.get_child_count() > 0 and content.get_child(0) is Control:
					first_height = (content.get_child(0) as Control).get_combined_minimum_size().y
				# A section must show its casting ability and at least one full
				# spell/button, even if the neighbouring tracker column is tiny.
				var minimum_visible: float = maxf(68.0, first_height + 8.0)
				scroll.custom_minimum_size.y = maxf(minimum_visible,
					minf(content.get_combined_minimum_size().y, 180.0))
				lists.append(scroll)
		var extra := maxf(0.0, right.get_combined_minimum_size().y - left.get_combined_minimum_size().y)
		# Grow only lists with hidden content, until the neighbouring resources
		# no longer leave unused vertical space. Empty sections stay compact.
		for scroll: ScrollContainer in lists:
			var missing := maxf(0.0, scroll.get_child(0).get_combined_minimum_size().y - scroll.custom_minimum_size.y)
			var growth := minf(missing, extra)
			scroll.custom_minimum_size.y += growth
			extra -= growth
