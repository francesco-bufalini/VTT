extends VBoxContainer

# Persistent spell selections and expendable resources for any creature.
# The existing 5etools-derived VTT catalog supplies spell descriptions;
# users choose the spells themselves rather than generating them from levels.
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const ManualBonus = preload("res://vtt/manual_bonus_style.gd")

const BOOK_VIEW_CLASS := 10
const BOOK_VIEW_BOOK := 11
const BOOK_EDIT := 12

var _on_change: Callable
var _on_status: Callable
var _record: Dictionary = {}
var _loading := false
var _catalog: Array[Dictionary] = []
var _visible: Array[Dictionary] = []
var _known: Array = []
var _prepared: Array = []
# The class list is generated automatically; the spellbook is user-selected.
var _spellbook: Array = []
var _displayed_known: Array = []
var _show_spellbook := false
var _editing_spellbook := false
var _totals: Array = []
# Slot bonuses are tracked separately so automatic recalculation never erases them.
var _slot_bonuses: Array = []
var _spent: Array = []
var _pact_total := 0
var _pact_bonus := 0
var _pact_spent := 0
var _pact_level := 1

var _search: LineEdit
var _class_only: CheckBox
var _level_filter: OptionButton
var _available: ItemList
var _known_list: ItemList
var _prepared_list: ItemList
var _known_title: Label
var _book_menu: MenuButton
var _book_hint: Label
var _description: RichTextLabel
var _prepare: Button
var _slot_totals: Dictionary = {}
var _slot_bonus_controls: Dictionary = {}
var _remaining_labels: Dictionary = {}
var _slot_use: Dictionary = {}
var _slot_recharge: Dictionary = {}
var _pact_total_spin: SpinBox
var _pact_bonus_spin: SpinBox
var _pact_level_spin: SpinBox
var _pact_remain: Label
var _pact_use: Button
var _pact_restore: Button
var _spell_options: MenuButton
var _search_row: HBoxContainer
var _catalog_title: Label


func setup(on_change: Callable, on_status: Callable) -> void:
	_on_change = on_change
	_on_status = on_status
	add_theme_constant_override("separation", 7)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	add_child(title_row)
	var title := Label.new()
	title.text = "Grimorio e preparazione"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.79, 0.51))
	title_row.add_child(title)
	_spell_options = MenuButton.new()
	_spell_options.text = "Opzioni ▾"
	title_row.add_child(_spell_options)
	var menu: PopupMenu = _spell_options.get_popup()
	menu.add_check_item("Mostra ricerca incantesimi", 1)
	menu.add_item("Ricalcola slot dalle classi", 2)
	menu.add_item("Ricarica automaticamente", 3)
	menu.id_pressed.connect(_on_options_selected)
	_search_row = HBoxContainer.new()
	add_child(_search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Cerca incantesimo per nome, descrizione o fonte"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_v: String) -> void: _filter_spells())
	_search_row.add_child(_search)
	_class_only = CheckBox.new()
	_class_only.text = "Mie classi"
	_class_only.tooltip_text = "Limita la ricerca agli incantesimi delle mie classi"
	_class_only.button_pressed = false
	_class_only.toggled.connect(func(_v: bool) -> void: _filter_spells())
	_search_row.add_child(_class_only)
	_level_filter = OptionButton.new()
	_level_filter.fit_to_longest_item = false
	_level_filter.clip_text = true
	_level_filter.custom_minimum_size.x = 105
	_level_filter.add_item("Tutti i livelli")
	_level_filter.add_item("Trucchetti")
	for lvl: int in range(1, 10):
		_level_filter.add_item("Livello %d" % lvl)
	_level_filter.item_selected.connect(func(_index: int) -> void: _filter_spells())
	_search_row.add_child(_level_filter)

	_catalog_title = Label.new()
	_catalog_title.text = "Catalogo · doppio clic per aggiungere / rimuovere"
	add_child(_catalog_title)
	_available = ItemList.new()
	_available.custom_minimum_size = Vector2(0, 160)
	_available.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available.item_selected.connect(func(_index: int) -> void: _on_spell_list_selected("catalog"))
	_available.item_activated.connect(func(_index: int) -> void: _toggle_selected_prepared())
	add_child(_available)
	# Keep the library and chosen spells together; there is only one action
	# for adding/removing the current selection.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 7)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var known_col := VBoxContainer.new()
	known_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(known_col)
	var known_header := HBoxContainer.new()
	known_header.add_theme_constant_override("separation", 8)
	known_col.add_child(known_header)
	_known_title = Label.new()
	_known_title.text = "Incantesimi di classe"
	_known_title.tooltip_text = "Incantesimi delle classi fino al livello attuale"
	_known_title.clip_text = true
	_known_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	known_header.add_child(_known_title)
	_book_menu = MenuButton.new()
	_book_menu.text = "📖 ▾"
	_book_menu.tooltip_text = "Libro degli incantesimi: vista e selezione delle magie trascritte"
	_book_menu.custom_minimum_size = Vector2(40, 30)
	known_header.add_child(_book_menu)
	var book_popup: PopupMenu = _book_menu.get_popup()
	book_popup.add_radio_check_item("Mostra incantesimi di classe", BOOK_VIEW_CLASS)
	book_popup.add_radio_check_item("Mostra incantesimi del libro", BOOK_VIEW_BOOK)
	book_popup.add_separator()
	book_popup.add_check_item("Seleziona incantesimi nel libro", BOOK_EDIT)
	book_popup.id_pressed.connect(_on_book_menu_selected)
	_book_hint = Label.new()
	_book_hint.text = "Modalità libro: clicca una magia per inserirla o rimuoverla."
	_book_hint.add_theme_font_size_override("font_size", 12)
	_book_hint.add_theme_color_override("font_color", Color(0.95, 0.78, 0.51, 1.0))
	_book_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_book_hint.hide()
	known_col.add_child(_book_hint)
	_known_list = ItemList.new()
	_known_list.custom_minimum_size = Vector2(0, 150)
	_known_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_known_list.item_selected.connect(_on_known_spell_selected)
	_known_list.item_activated.connect(
		func(_index: int) -> void:
			if not _editing_spellbook:
				_toggle_selected_prepared()
	)
	known_col.add_child(_known_list)
	var prepared_col := VBoxContainer.new()
	prepared_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(prepared_col)
	var prepared_title := Label.new()
	prepared_title.text = "Incantesimi disponibili"
	prepared_title.add_theme_font_size_override("font_size", 16)
	prepared_title.add_theme_color_override("font_color", Color(0.96, 0.79, 0.51))
	prepared_col.add_child(prepared_title)
	_prepared_list = ItemList.new()
	_prepared_list.custom_minimum_size = Vector2(0, 150)
	_prepared_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prepared_list.item_selected.connect(func(_index: int) -> void: _on_spell_list_selected("prepared"))
	prepared_col.add_child(_prepared_list)
	_prepared_list.item_activated.connect(func(_index: int) -> void: _toggle_selected_prepared())

	# The action is a single compact row. Descriptions are a separate row
	# underneath the persistent selection hint, never next to a tall button.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	add_child(actions)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	actions.add_child(action_row)
	var selection_hint := Label.new()
	selection_hint.text = "Seleziona un incantesimo per consultare la descrizione."
	selection_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_row.add_child(selection_hint)
	_prepare = Button.new()
	_prepare.text = "Aggiungi ai disponibili"
	_prepare.custom_minimum_size = Vector2(170, 34)
	_prepare.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prepare.tooltip_text = "Doppio clic su una magia oppure premi questo pulsante"
	_prepare.pressed.connect(_toggle_selected_prepared)
	action_row.add_child(_prepare)

	_description = RichTextLabel.new()
	_description.custom_minimum_size.y = 150
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description.scroll_active = true
	_description.selection_enabled = true
	_description.hide()
	actions.add_child(_description)

	var slot_title := HBoxContainer.new()
	add_child(slot_title)
	var heading := Label.new()
	heading.text = "Slot · disponibili / max"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 16)
	slot_title.add_child(heading)
	var rest_all := Button.new()
	rest_all.text = "Ricarica"
	rest_all.pressed.connect(_restore_all)
	slot_title.add_child(rest_all)
	var slot_grid := GridContainer.new()
	slot_grid.columns = 6
	slot_grid.add_theme_constant_override("h_separation", 6)
	slot_grid.add_theme_constant_override("v_separation", 5)
	add_child(slot_grid)
	for label_text: String in ["Liv.", "Max", "Di cui bonus", "Rimasti / max", "Usa", "Ricarica"]:
		var header := Label.new()
		header.text = label_text
		slot_grid.add_child(header)
	for lvl: int in range(1, 10):
		var caption := Label.new()
		caption.text = "%d°" % lvl
		slot_grid.add_child(caption)
		var total := SpinBox.new()
		total.min_value = 0
		total.max_value = 99
		total.rounded = true
		total.update_on_text_changed = true
		total.custom_minimum_size.x = 62
		total.value_changed.connect(_on_slot_total_changed.bind(lvl))
		slot_grid.add_child(total)
		_slot_totals[lvl] = total
		var bonus := SpinBox.new()
		bonus.min_value = -99
		bonus.max_value = 99
		bonus.step = 1
		bonus.rounded = true
		bonus.custom_minimum_size.x = 62
		bonus.tooltip_text = "Bonus manuale agli slot massimi: aggiunto al massimo base"
		ManualBonus.decorate(bonus)
		bonus.value_changed.connect(_on_slot_bonus_changed.bind(lvl))
		slot_grid.add_child(bonus)
		_slot_bonus_controls[lvl] = bonus
		var remaining := Label.new()
		remaining.custom_minimum_size.x = 58
		slot_grid.add_child(remaining)
		_remaining_labels[lvl] = remaining
		var use := Button.new()
		use.text = "−"
		use.tooltip_text = "Consuma uno slot di livello %d" % lvl
		use.pressed.connect(_change_slot.bind(lvl, 1))
		slot_grid.add_child(use)
		_slot_use[lvl] = use
		var recharge := Button.new()
		recharge.text = "+"
		recharge.tooltip_text = "Ricarica uno slot di livello %d" % lvl
		recharge.pressed.connect(_change_slot.bind(lvl, -1))
		slot_grid.add_child(recharge)
		_slot_recharge[lvl] = recharge

	var pact_row := HBoxContainer.new()
	pact_row.add_theme_constant_override("separation", 5)
	add_child(pact_row)
	var pact_label := Label.new()
	pact_label.text = "Patto"
	pact_label.tooltip_text = "Slot di Magia del Patto"
	pact_row.add_child(pact_label)
	var level_label := Label.new()
	level_label.text = "Liv."
	pact_row.add_child(level_label)
	_pact_level_spin = SpinBox.new()
	_pact_level_spin.min_value = 1
	_pact_level_spin.max_value = 5
	_pact_level_spin.update_on_text_changed = true
	_pact_level_spin.custom_minimum_size.x = 54
	_pact_level_spin.value_changed.connect(_on_pact_values_changed)
	pact_row.add_child(_pact_level_spin)
	var total_label := Label.new()
	total_label.text = "Base"
	pact_row.add_child(total_label)
	_pact_total_spin = SpinBox.new()
	_pact_total_spin.min_value = 0
	_pact_total_spin.max_value = 8
	_pact_total_spin.update_on_text_changed = true
	_pact_total_spin.custom_minimum_size.x = 54
	_pact_total_spin.value_changed.connect(_on_pact_values_changed)
	pact_row.add_child(_pact_total_spin)
	var bonus_label := Label.new()
	bonus_label.text = "Di cui bonus"
	pact_row.add_child(bonus_label)
	_pact_bonus_spin = SpinBox.new()
	_pact_bonus_spin.min_value = -8
	_pact_bonus_spin.max_value = 20
	_pact_bonus_spin.step = 1
	_pact_bonus_spin.custom_minimum_size.x = 54
	_pact_bonus_spin.tooltip_text = "Bonus manuale agli slot massimi della Magia del Patto"
	ManualBonus.decorate(_pact_bonus_spin)
	_pact_bonus_spin.value_changed.connect(_on_pact_values_changed)
	pact_row.add_child(_pact_bonus_spin)
	_pact_remain = Label.new()
	_pact_remain.custom_minimum_size.x = 64
	pact_row.add_child(_pact_remain)
	_pact_use = Button.new()
	_pact_use.text = "Usa"
	_pact_use.pressed.connect(_change_pact.bind(1))
	pact_row.add_child(_pact_use)
	_pact_restore = Button.new()
	_pact_restore.text = "+"
	_pact_restore.tooltip_text = "Ricarica uno slot della Magia del Patto"
	_pact_restore.pressed.connect(_change_pact.bind(-1))
	pact_row.add_child(_pact_restore)
	_update_resource_labels()
	_update_spell_controls()
	_set_search_visible(false)


func _set_search_visible(show: bool) -> void:
	_search_row.visible = show
	_catalog_title.visible = show
	_available.visible = show
	_spell_options.get_popup().set_item_checked(
		_spell_options.get_popup().get_item_index(1), show
	)
	if show:
		_search.grab_focus()


func _on_options_selected(item_id: int) -> void:
	match item_id:
		1:
			_set_search_visible(not _search_row.visible)
		2:
			_calculate_slot_totals(false)
		3:
			_calculate_slot_totals(true)


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	# Older records separate known and prepared. Preserve BOTH collections
	# in the new single available-spell selection on first load.
	_known.clear()
	_spellbook = _copy_spell_array(record.get("spellbook_spells", []))
	# Editing and view modes are UI-only and reset when changing creature.
	_show_spellbook = false
	_editing_spellbook = false
	_prepared = _copy_spell_array(record.get("prepared_spells", []))
	for legacy: Variant in _copy_spell_array(record.get("spells", [])):
		if not _has_spell(_prepared, _entry_id(legacy)):
			_prepared.append(legacy)
	if _catalog.is_empty():
		_catalog = SpellCatalog.all_spells()
	_rebuild_class_spells()
	_totals = _normal_slots(record.get("spell_slots_total", []))
	_slot_bonuses = _normal_slot_bonuses(record.get("spell_slots_bonus", []))
	_spent = _normal_slots(record.get("spell_slots_spent", []))
	for lvl: int in range(1, 10):
		_spent[lvl] = mini(int(_spent[lvl]), _effective_slot_total(lvl))
	_pact_total = maxi(0, int(record.get("pact_slots_total", 0)))
	_pact_bonus = clampi(int(record.get("pact_slots_bonus", 0)), -8, 20)
	_pact_spent = clampi(int(record.get("pact_slots_spent", 0)), 0, _effective_pact_total())
	_pact_level = clampi(int(record.get("pact_slot_level", 1)), 1, 5)
	for lvl: int in range(1, 10):
		(_slot_totals[lvl] as SpinBox).value = int(_totals[lvl])
		(_slot_bonus_controls[lvl] as SpinBox).value = int(_slot_bonuses[lvl])
	_pact_total_spin.value = _pact_total
	_pact_bonus_spin.value = _pact_bonus
	_pact_level_spin.value = _pact_level
	_class_only.disabled = _class_keys().is_empty()
	_search.text = ""
	_refresh_saved_spell_lists()
	_update_resource_labels()
	_loading = false
	_filter_spells()


static func _copy_spell_array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


static func _normal_slots(value: Variant) -> Array:
	var result: Array = []
	for index: int in range(10):
		var number := 0
		if value is Array and (value as Array).size() > index:
			number = maxi(0, int((value as Array)[index]))
		result.append(number)
	return result


static func _normal_slot_bonuses(value: Variant) -> Array:
	var result: Array = []
	for index: int in range(10):
		var number: int = 0
		if value is Array and (value as Array).size() > index:
			number = clampi(int((value as Array)[index]), -99, 99)
		result.append(number)
	return result


func _effective_slot_total(lvl: int) -> int:
	return maxi(0, int(_totals[lvl]) + int(_slot_bonuses[lvl]))


func _effective_pact_total() -> int:
	return maxi(0, _pact_total + _pact_bonus)


static func _entry_id(item: Variant) -> String:
	if item is Dictionary:
		return String((item as Dictionary).get("id", (item as Dictionary).get("name", "")))
	return String(item)


func _has_spell(items: Array, id: String) -> bool:
	for entry: Variant in items:
		if _entry_id(entry) == id:
			return true
	return false


func _spell_by_id(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var found: Dictionary = SpellCatalog.catalog_spell(id)
	return found


func _spell_label(item: Variant) -> String:
	if item is Dictionary:
		var name: String = String((item as Dictionary).get("name", ""))
		if not name.is_empty():
			return name
	var found: Dictionary = _spell_by_id(_entry_id(item))
	return String(found.get("name", _entry_id(item)))


func _class_keys() -> Dictionary:
	var keys: Dictionary = {}
	var classes_value: Variant = _record.get("classes", [])
	if classes_value is Array:
		for raw: Variant in classes_value as Array:
			if raw is Dictionary:
				var name: String = String((raw as Dictionary).get("name", "")).strip_edges()
				if not name.is_empty() and name.to_lower() != "mostro":
					keys[SpellCatalog.canonical_class_name(name).to_lower()] = true
	var primary: String = String(_record.get("class", "")).strip_edges()
	if not primary.is_empty() and primary.to_lower() != "mostro":
		keys[SpellCatalog.canonical_class_name(primary).to_lower()] = true
	return keys


# Resolve each class independently: multiclass spell levels are limited
# by that class's own progression, not by the overall character level.
func _class_spell_level_limits() -> Dictionary:
	var limits: Dictionary = {}
	for cls: Dictionary in Rules.level_classes(_record):
		var spell_class_key: String = SpellCatalog.canonical_class_name(
			String(cls.get("name", ""))
		).to_lower()
		if (
			spell_class_key.is_empty()
			or spell_class_key == "mostro"
			or spell_class_key not in Rules.HIT_DICE
		):
			continue
		var single: Dictionary = {
			"classes": [cls], "rules_version": _record.get("rules_version", "2014")
		}
		var progression: Dictionary = Rules.spell_slot_progression(single)
		var highest: int = 0
		var slots_value: Variant = progression.get("slots", [])
		if slots_value is Array:
			for lvl: int in range(1, mini(10, (slots_value as Array).size())):
				if int((slots_value as Array)[lvl]) > 0:
					highest = lvl
		if spell_class_key == "warlock" and int(progression.get("pact_total", 0)) > 0:
			highest = maxi(highest, int(progression.get("pact_level", 1)))
		if highest > 0:
			limits[spell_class_key] = maxi(int(limits.get(spell_class_key, 0)), highest)
	return limits


func _rebuild_class_spells() -> void:
	_known.clear()
	if _catalog.is_empty():
		_catalog = SpellCatalog.all_spells()
	var limits: Dictionary = _class_spell_level_limits()
	for entry: Dictionary in _catalog:
		var level: int = int(entry.get("level", 0))
		var classes_value: Variant = entry.get("classes", [])
		if not classes_value is Array:
			continue
		for cls: Variant in classes_value as Array:
			var spell_class_key: String = SpellCatalog.canonical_class_name(
				String(cls)
			).to_lower()
			if limits.has(spell_class_key) and level <= int(limits[spell_class_key]):
				_known.append(entry)
				break


func _filter_spells() -> void:
	if _search == null:
		return
	if _catalog.is_empty():
		_catalog = SpellCatalog.all_spells()
	_visible.clear()
	_available.clear()
	var needle: String = _search.text.strip_edges().to_lower()
	var class_keys: Dictionary = _class_keys()
	var level_limits: Dictionary = _class_spell_level_limits()
	var limit_level: int = _level_filter.selected - 1
	var filter_class: bool = _class_only.button_pressed and not class_keys.is_empty()
	for entry: Dictionary in _catalog:
		var level: int = int(entry.get("level", 0))
		if limit_level >= 0 and level != limit_level:
			continue
		if filter_class:
			var classes_value: Variant = entry.get("classes", [])
			var matches := false
			if classes_value is Array:
				for class_value: Variant in classes_value as Array:
					var spell_class_key: String = SpellCatalog.canonical_class_name(
						String(class_value)
					).to_lower()
					if class_keys.has(spell_class_key) and level_limits.has(spell_class_key) and level <= int(level_limits[spell_class_key]):
						matches = true
						break
			if not matches:
				continue
		if not needle.is_empty():
			var searchable: String = (
				String(entry.get("name", "")) + " "
				+ String(entry.get("source", "")) + " "
				+ String(entry.get("description", ""))
			).to_lower()
			if needle not in searchable:
				continue
		_visible.append(entry)
		_available.add_item("%s · livello %d [%s]" % [
			String(entry.get("name", "")), level, String(entry.get("source", ""))
		])
		if _visible.size() >= 300:
			break
	_update_spell_controls()


func _on_spell_list_selected(origin: String) -> void:
	# Only one source drives Prepara/Dimentica. Otherwise a stale search
	# selection wins over a newly clicked known or prepared entry.
	if origin != "catalog":
		_available.deselect_all()
	if origin != "known":
		_known_list.deselect_all()
	if origin != "prepared":
		_prepared_list.deselect_all()
	_update_spell_controls()


func update_character_context(record: Dictionary) -> void:
	var current_class: Variant = record.get("classes", [])
	var current_primary: String = String(record.get("class", ""))
	_record["classes"] = current_class
	_record["class"] = current_primary
	_record["level"] = record.get("level", 1)
	_record["rules_version"] = String(record.get("rules_version", "2014"))
	_rebuild_class_spells()
	_refresh_saved_spell_lists()
	_class_only.disabled = _class_keys().is_empty()
	_filter_spells()


func _selected_spell() -> Dictionary:
	var available_selected: PackedInt32Array = _available.get_selected_items()
	if not available_selected.is_empty() and available_selected[0] < _visible.size():
		return _visible[available_selected[0]]
	var known_selected: PackedInt32Array = _known_list.get_selected_items()
	if not known_selected.is_empty() and known_selected[0] < _displayed_known.size():
		return _spell_by_id(_entry_id(_displayed_known[known_selected[0]]))
	var prepared_selected: PackedInt32Array = _prepared_list.get_selected_items()
	if not prepared_selected.is_empty() and prepared_selected[0] < _prepared.size():
		return _spell_by_id(_entry_id(_prepared[prepared_selected[0]]))
	return {}


func _update_spell_controls() -> void:
	if _description == null:
		return
	var spell: Dictionary = _selected_spell()
	var id: String = String(spell.get("id", ""))
	_prepare.disabled = id.is_empty()
	_prepare.text = (
		"Rimuovi dai disponibili"
		if _has_spell(_prepared, id)
		else "Aggiungi ai disponibili"
	)
	if id.is_empty():
		_description.clear()
		_description.hide()
		return
	_description.show()
	_description.text = "%s · livello %d · %s\nGittata: %s · Componenti: %s\nDurata: %s\n%s" % [
		String(spell.get("name", id)), int(spell.get("level", 0)),
		String(spell.get("source", "")), String(spell.get("range", "—")),
		String(spell.get("components", "—")),
		String(spell.get("duration", "—")), String(spell.get("description", ""))
	]


func _toggle_selected_prepared() -> void:
	var spell: Dictionary = _selected_spell()
	var id: String = String(spell.get("id", ""))
	if id.is_empty():
		return
	if _has_spell(_prepared, id):
		for i: int in range(_prepared.size() - 1, -1, -1):
			if _entry_id(_prepared[i]) == id:
				_prepared.remove_at(i)
	else:
		_prepared.append({
			"id": id, "name": String(spell.get("name", "")),
			"source": String(spell.get("source", "")),
			"level": int(spell.get("level", 0))
		})
	_publish()
	_refresh_saved_spell_lists()


func _refresh_saved_spell_lists() -> void:
	_known_list.clear()
	_prepared_list.clear()
	_displayed_known = _spellbook.duplicate(true) if _show_spellbook else _known.duplicate(true)
	for item: Variant in _displayed_known:
		var prefix := ""
		if _editing_spellbook:
			prefix = "☑  " if _has_spell(_spellbook, _entry_id(item)) else "☐  "
		elif not _show_spellbook and _has_spell(_spellbook, _entry_id(item)):
			prefix = "📖  "
		_known_list.add_item(prefix + _spell_label(item))
	for item: Variant in _prepared:
		_prepared_list.add_item(_spell_label(item))
	_update_book_menu()
	_update_spell_controls()


func _on_book_menu_selected(item_id: int) -> void:
	match item_id:
		BOOK_VIEW_CLASS:
			_show_spellbook = false
			_editing_spellbook = false
		BOOK_VIEW_BOOK:
			_show_spellbook = true
			_editing_spellbook = false
		BOOK_EDIT:
			_editing_spellbook = not _editing_spellbook
			if _editing_spellbook:
				# Show all class spells so the user can check or uncheck them.
				_show_spellbook = false
	_refresh_saved_spell_lists()


func _update_book_menu() -> void:
	if _book_menu == null:
		return
	_known_title.text = (
		"Incantesimi del libro (%d)" % _spellbook.size()
		if _show_spellbook
		else "Incantesimi di classe"
	)
	_book_hint.visible = _editing_spellbook
	var popup: PopupMenu = _book_menu.get_popup()
	popup.set_item_checked(popup.get_item_index(BOOK_VIEW_CLASS), not _show_spellbook)
	popup.set_item_checked(popup.get_item_index(BOOK_VIEW_BOOK), _show_spellbook)
	popup.set_item_checked(popup.get_item_index(BOOK_EDIT), _editing_spellbook)
	_book_menu.tooltip_text = (
		"Libro: %d incantesimi · Apri per cambiare vista o modificare" % _spellbook.size()
	)


func _on_known_spell_selected(index: int) -> void:
	_on_spell_list_selected("known")
	if not _editing_spellbook or index < 0 or index >= _displayed_known.size():
		return
	var spell: Variant = _displayed_known[index]
	var id: String = _entry_id(spell)
	if id.is_empty():
		return
	if _has_spell(_spellbook, id):
		for i: int in range(_spellbook.size() - 1, -1, -1):
			if _entry_id(_spellbook[i]) == id:
				_spellbook.remove_at(i)
	else:
		var detail: Dictionary = _spell_by_id(id)
		if detail.is_empty() and spell is Dictionary:
			detail = spell as Dictionary
		_spellbook.append({
			"id": id,
			"name": String(detail.get("name", _spell_label(spell))),
			"source": String(detail.get("source", "")),
			"level": int(detail.get("level", 0))
		})
	_publish()
	_refresh_saved_spell_lists()



func _on_slot_total_changed(value: float, lvl: int) -> void:
	if _loading:
		return
	_totals[lvl] = maxi(0, int(value))
	_spent[lvl] = mini(int(_spent[lvl]), _effective_slot_total(lvl))
	_update_resource_labels()
	_publish()


func _on_slot_bonus_changed(value: float, lvl: int) -> void:
	if _loading:
		return
	_slot_bonuses[lvl] = clampi(int(value), -99, 99)
	_spent[lvl] = mini(int(_spent[lvl]), _effective_slot_total(lvl))
	_update_resource_labels()
	_publish()


func _change_slot(lvl: int, spent_delta: int) -> void:
	_spent[lvl] = clampi(int(_spent[lvl]) + spent_delta, 0, _effective_slot_total(lvl))
	_update_resource_labels()
	_publish()


func _on_pact_values_changed(_value: float) -> void:
	if _loading:
		return
	_pact_total = maxi(0, int(_pact_total_spin.value))
	_pact_bonus = clampi(int(_pact_bonus_spin.value), -8, 20)
	_pact_level = clampi(int(_pact_level_spin.value), 1, 5)
	_pact_spent = mini(_pact_spent, _effective_pact_total())
	_update_resource_labels()
	_publish()


func _change_pact(spent_delta: int) -> void:
	_pact_spent = clampi(_pact_spent + spent_delta, 0, _effective_pact_total())
	_update_resource_labels()
	_publish()


func _restore_all() -> void:
	for lvl: int in range(1, 10):
		_spent[lvl] = 0
	_pact_spent = 0
	_update_resource_labels()
	_publish()


func _calculate_slot_totals(recharge: bool = false) -> void:
	if _class_keys().is_empty():
		if _on_status.is_valid():
			_on_status.call("I mostri senza livelli di classe gestiscono gli slot manualmente.")
		return
	var result: Dictionary = Rules.spell_slot_progression(_record)
	var totals: Variant = result.get("slots", [])
	if not totals is Array:
		return
	_loading = true
	_totals = _normal_slots(totals)
	for lvl: int in range(1, 10):
		_spent[lvl] = 0 if recharge else mini(int(_spent[lvl]), _effective_slot_total(lvl))
		(_slot_totals[lvl] as SpinBox).value = int(_totals[lvl])
	_pact_total = int(result.get("pact_total", 0))
	_pact_level = int(result.get("pact_level", 1))
	_pact_spent = 0 if recharge else mini(_pact_spent, _effective_pact_total())
	_pact_total_spin.value = _pact_total
	_pact_level_spin.value = _pact_level
	_loading = false
	_update_resource_labels()
	_publish()
	var warnings: String = String(result.get("warnings", ""))
	if not warnings.is_empty() and _on_status.is_valid():
		_on_status.call(warnings)


func _update_resource_labels() -> void:
	if _pact_remain == null:
		return
	for lvl: int in range(1, 10):
		var total: int = _effective_slot_total(lvl) if _totals.size() > lvl and _slot_bonuses.size() > lvl else 0
		var spent: int = clampi(int(_spent[lvl]), 0, total) if _spent.size() > lvl else 0
		(_remaining_labels[lvl] as Label).text = "%d / %d" % [total - spent, total]
		(_slot_use[lvl] as Button).disabled = spent >= total
		(_slot_recharge[lvl] as Button).disabled = spent <= 0
	var pact_max: int = _effective_pact_total()
	_pact_remain.text = "%d / %d" % [pact_max - _pact_spent, pact_max]
	_pact_use.disabled = _pact_spent >= pact_max
	_pact_restore.disabled = _pact_spent <= 0


func _publish() -> void:
	if _loading or not _on_change.is_valid():
		return
	_on_change.call({
		"spells": _prepared.duplicate(true),
		"prepared_spells": _prepared.duplicate(true),
		"spellbook_spells": _spellbook.duplicate(true),
		"spell_slots_total": _totals.duplicate(true),
		"spell_slots_bonus": _slot_bonuses.duplicate(true),
		"spell_slots_spent": _spent.duplicate(true),
		"pact_slots_total": _pact_total,
		"pact_slots_bonus": _pact_bonus,
		"pact_slots_spent": _pact_spent,
		"pact_slot_level": _pact_level
	})
