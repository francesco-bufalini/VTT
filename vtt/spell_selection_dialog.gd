extends ConfirmationDialog
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const Caption = preload("res://vtt/scrollable_caption.gd")
var _catalog: Array[Dictionary] = []
var _selected: Dictionary = {}
var _book: Dictionary = {}
var _wizard := false
var _single := false
var _max_selections := 0
var _change: Callable
var _limit := -1
var _cantrips := -1
var _search: LineEdit
var _level: OptionButton
var _sort: OptionButton
var _class_only: CheckBox
var _class_spell_ids: Dictionary = {}
var _rows: VBoxContainer
var _count: Label
var _details: Label
var _context: Dictionary = {}
var _display_limit := 120
var _checks: Dictionary = {}
var _book_checks: Dictionary = {}

func _ready() -> void:
	title = "Scegli incantesimi"
	ok_button_text = "Salva selezione"
	cancel_button_text = "Annulla"
	var layout := VBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	_count = Label.new()
	_count.size.x = 460
	_count.custom_minimum_size.x = 140
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_count)
	var info := Button.new()
	info.text = "ⓘ"
	info.tooltip_text = "Mostra i dettagli dell'origine e della lista"
	heading.add_child(info)
	_details = Label.new()
	_details.size.x = 460
	_details.custom_minimum_size.x = 140
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.hide()
	layout.add_child(_details)
	info.pressed.connect(func() -> void: _details.visible = not _details.visible)
	var filters := HBoxContainer.new()
	layout.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "Cerca per nome…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_value: String) -> void: _display_limit = 120; _rebuild())
	filters.add_child(_search)
	_level = OptionButton.new()
	_level.add_item("Tutti i livelli", 100)
	_level.add_item("Trucchetti", 0)
	for i: int in range(1, 10):
		_level.add_item("%d° livello" % i, i)
	_level.item_selected.connect(func(_index: int) -> void: _rebuild())
	filters.add_child(_level)
	var sorting := HFlowContainer.new()
	layout.add_child(sorting)
	_class_only = CheckBox.new()
	_class_only.text = "Incantesimi di classe"
	_class_only.toggled.connect(func(_on: bool) -> void: _display_limit = 120; _rebuild())
	sorting.add_child(_class_only)
	_sort = OptionButton.new()
	_sort.add_item("Nome A–Z", 0)
	_sort.add_item("Livello, poi nome", 1)
	_sort.add_item("Livello decrescente, poi nome", 2)
	_sort.item_selected.connect(func(_index: int) -> void: _rebuild())
	sorting.add_child(_sort)
	var guide := Label.new()
	guide.size.x = 460
	guide.custom_minimum_size.x = 140
	guide.text = "Spunta i disponibili. Passa sul nome per la descrizione; le modifiche si applicano con Salva."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(guide)
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	scroll.custom_minimum_size = Vector2(140, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	confirmed.connect(_save)
	canceled.connect(hide)
	close_requested.connect(hide)
	Caption.install(self)

func choose(options: Array[Dictionary], config: Dictionary, callback: Callable) -> void:
	_display_limit = 120
	_catalog = options.duplicate()
	_class_spell_ids.clear()
	for id: Variant in config.get("class_spell_ids", []):
		_class_spell_ids[String(id)] = true
	_class_only.visible = config.has("class_spell_ids")
	_class_only.set_pressed_no_signal(config.has("class_spell_ids") and bool(config.get("class_only_default", true)))
	_context = config.duplicate(true)
	_change = callback
	_wizard = bool(config.get("book_mode", false))
	_single = bool(config.get("single", false))
	_max_selections = int(config.get("max_selections", 1 if _single else 0))
	_limit = int(config.get("limit", -1))
	_cantrips = int(config.get("cantrips", -1))
	_selected.clear()
	_book.clear()
	for id: Variant in config.get("selected", []):
		_selected[String(id)] = true
	for id: Variant in config.get("book", []):
		_book[String(id)] = true
	title = String(config.get("title", "Scegli incantesimi"))
	_details.text = String(config.get("details", ""))
	_details.hide()
	_search.clear()
	_level.select(0)
	_rebuild()
	DialogLayout.popup(self, Vector2i(760, 620))
	_fit_dialog.call_deferred()

func _rebuild() -> void:
	_checks.clear()
	_book_checks.clear()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("level", 0))
		var right := int(b.get("level", 0))
		if _sort.get_selected_id() != 0 and left != right:
			return left < right if _sort.get_selected_id() == 1 else left > right
		var names := String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", "")))
		return names < 0 if names != 0 else String(a.get("id", "")) < String(b.get("id", ""))
	)
	var displayed := 0
	var matches := 0
	for spell: Dictionary in _catalog:
		var id: String = String(spell.get("id", ""))
		if _class_only.visible and _class_only.button_pressed and not _class_spell_ids.has(id):
			continue
		var level: int = int(spell.get("level", 0))
		if _level.get_selected_id() != 100 and level != _level.get_selected_id():
			continue
		if not _search.text.is_empty() and _search.text.to_lower() not in String(spell.get("name", "")).to_lower():
			continue
		matches += 1
		if displayed >= _display_limit:
			continue
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var selected := CheckBox.new()
		selected.text = "Preparato" if _wizard and level > 0 else "Disponibile"
		selected.button_pressed = _selected.has(id)
		_checks[id] = selected
		row.add_child(selected)
		selected.toggled.connect(func(on: bool) -> void:
			if _single:
				_selected.clear()
			if on:
				_selected[id] = true
				if _wizard and level > 0:
					_book[id] = true
			else:
				_selected.erase(id)
			if _single:
				for key: String in _checks:
					(_checks[key] as CheckBox).set_pressed_no_signal(_selected.has(key))
			if _wizard and _book_checks.has(id):
				(_book_checks[id] as CheckBox).set_pressed_no_signal(_book.has(id))
			_update_count()
		)
		var name_label := Label.new()
		name_label.size.x = 280
		name_label.text = String(spell.get("name", id)) + (" · trucchetto" if level == 0 else " · %d°" % level)
		name_label.set_meta("creature_gui_data", true)
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.tooltip_text = String(spell.get("description", ""))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if _wizard and level > 0:
			var book := CheckBox.new()
			book.text = "Nel libro"
			book.button_pressed = _book.has(id)
			_book_checks[id] = book
			book.toggled.connect(func(on: bool) -> void:
				if on:
					_book[id] = true
				else:
					_book.erase(id)
					_selected.erase(id)
				if _checks.has(id):
					(_checks[id] as CheckBox).set_pressed_no_signal(_selected.has(id))
				_update_count()
			)
			row.add_child(book)
		displayed += 1
	if matches > displayed:
		var more := Button.new()
		more.text = "Mostra altri incantesimi (%d rimanenti)" % (matches - displayed)
		more.pressed.connect(func() -> void: _display_limit += 120; _rebuild())
		_rows.add_child(more)
	var empty := Label.new()
	if displayed == 0:
		empty.text = "Nessun incantesimo corrisponde ai filtri."
		_rows.add_child(empty)
	else:
		empty.queue_free()
	_update_count()

func _update_count() -> void:
	var leveled := 0
	var cantrips := 0
	for spell: Dictionary in _catalog:
		if _selected.has(String(spell.get("id", ""))):
			if int(spell.get("level", 0)) == 0:
				cantrips += 1
			else:
				leveled += 1
	var warning: bool = (_limit >= 0 and leveled != _limit) or (_cantrips >= 0 and cantrips != _cantrips)
	_count.text = ("⚠ " if warning else "") + "Disponibili: %d / %s · Trucchetti: %d / %s" % [leveled,
		str(_limit) if _limit >= 0 else "—", cantrips, str(_cantrips) if _cantrips >= 0 else "—"]
	if _max_selections > 0:
		_count.text = "Scegli fino a %d incantesimo/i · %d selezionati" % [_max_selections, _selected.size()]
	get_ok_button().disabled = _max_selections > 0 and (_selected.is_empty() or _selected.size() > _max_selections)
	if _wizard:
		_count.text += " · Nel libro: %d" % _book.size()

func _save() -> void:
	hide()
	if _change.is_valid():
		_change.call({"selected": _selected.keys(), "book": _book.keys()})



func _fit_dialog() -> void:
	await get_tree().process_frame
	if not visible:
		return
	# Embedded windows use the parent viewport's coordinates, which can be
	# different from the root window's physical pixels under UI stretching.
	var area: Rect2 = get_parent().get_viewport().get_visible_rect()
	var title_height := maxi(get_theme_constant("title_height", "Window"), get_theme_font_size("title_font_size", "Window") + 12)
	add_theme_constant_override("title_height", title_height)
	var available := Vector2i(area.size * 0.92)
	available.y = mini(available.y, int(area.size.y) - title_height - 24)
	wrap_controls = false
	min_size = Vector2i.ZERO
	max_size = available
	size = Vector2i(760, 620).min(available)
	position = Vector2i(area.position) + (Vector2i(area.size) - size + Vector2i(0, title_height)) / 2


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()
