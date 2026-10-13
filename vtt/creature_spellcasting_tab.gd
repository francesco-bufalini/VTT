extends VBoxContainer

# Persistent spell selections and expendable resources for any creature.
# The existing 5etools-derived VTT catalog supplies spell descriptions;
# users choose the spells themselves rather than generating them from levels.
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const FormulaValue = preload("res://vtt/formula_value.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const CreatureLocale = preload("res://vtt/creature_gui_locale.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")

const CASTING_ABILITIES: Array[String] = ["", "str", "dex", "con", "int", "wis", "cha"]

const BOOK_VIEW_CLASS := 10
const BOOK_VIEW_BOOK := 11
const BOOK_EDIT := 12

var _on_change: Callable
var _on_status: Callable
var _on_cast_spell: Callable
var _on_bonus_request: Callable
var _cast_button: Button
var _cast_dialog: ConfirmationDialog
var _cast_slot_choice: OptionButton
var _pending_cast_spell: Dictionary = {}
var _manual_origin_spells: Array = []
var _granted_spell_boxes: VBoxContainer
var _grant_dialog: ConfirmationDialog
var _grant_origin: OptionButton
var _grant_spell: OptionButton
var _grant_tracker: OptionButton
var _grant_search: LineEdit
var _grant_spell_choices: Array[Dictionary] = []
var _record: Dictionary = {}
var _spell_summary: Label
var _spell_ability_choice: OptionButton
var _drop_concentration_button: Button
var _loading := false
var _gui_language := "it"
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
var _spent: Array = []
var _pact_total := 0
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
var _slot_formula_values: Dictionary = {}
var _pact_formula_value: FormulaValue
var _remaining_labels: Dictionary = {}
var _slot_use: Dictionary = {}
var _slot_recharge: Dictionary = {}
var _pact_total_spin: SpinBox
var _pact_level_spin: SpinBox
var _pact_remain: Label
var _pact_use: Button
var _pact_restore: Button
var _search_toggle: Button
var _search_row: HBoxContainer
var _catalog_title: Label
var _slot_grid: GridContainer
var _restore_all_button: Button
var _slots_eye: Button
var _pact_row: HBoxContainer
var _pact_eye: Button
var _slots_visible := true
var _pact_visible := true


func setup(
	on_change: Callable,
	on_status: Callable,
	on_cast_spell: Callable = Callable(),
	on_bonus_request: Callable = Callable()
) -> void:
	_on_change = on_change
	_on_status = on_status
	_on_cast_spell = on_cast_spell
	_on_bonus_request = on_bonus_request
	# setup() paints resource labels before load_record() is called.
	# Keep all three slot arrays in their canonical 0-9 shape from the start.
	_totals = _normal_slots(_totals)
	_spent = _normal_slots(_spent)
	add_theme_constant_override("separation", 7)
	_spell_summary = Label.new()
	_spell_summary.name = "SpellcastingStatistics"
	_spell_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spell_summary.text = "Caratteristica: — · Tiro per colpire: — · CD: —\nConcentrazione: nessuna"
	add_child(_spell_summary)
	var casting_controls := HBoxContainer.new()
	casting_controls.add_theme_constant_override("separation", 8)
	add_child(casting_controls)
	var ability_title := Label.new()
	ability_title.text = "Caratteristica degli incantesimi"
	casting_controls.add_child(ability_title)
	_spell_ability_choice = OptionButton.new()
	_spell_ability_choice.name = "SpellcastingAbilitySelector"
	_spell_ability_choice.custom_minimum_size.x = 145
	for option_text: String in ["Automatica", "FOR", "DES", "COS", "INT", "SAG", "CAR"]:
		_spell_ability_choice.add_item(option_text)
	_spell_ability_choice.item_selected.connect(_on_spellcasting_ability_selected)
	casting_controls.add_child(_spell_ability_choice)
	_drop_concentration_button = Button.new()
	_drop_concentration_button.name = "StopConcentrationButton"
	_drop_concentration_button.text = "Interrompi concentrazione"
	_drop_concentration_button.tooltip_text = "Termina la concentrazione su un incantesimo attivo."
	_drop_concentration_button.pressed.connect(_drop_concentration)
	casting_controls.add_child(_drop_concentration_button)
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
	_catalog_title.text = "Catalogo · doppio clic per lanciare"
	add_child(_catalog_title)
	_available = ItemList.new()
	_available.mouse_force_pass_scroll_events = false
	_available.custom_minimum_size = Vector2(0, 160)
	_available.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available.item_selected.connect(func(_index: int) -> void: _on_spell_list_selected("catalog"))
	_available.gui_input.connect(_on_spell_list_gui_input.bind("catalog"))
	_available.item_activated.connect(func(index: int) -> void: _on_spell_activated("catalog", index))
	add_child(_available)
	# Keep the library and chosen spells together; there is only one action
	# for adding/removing the current selection.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 7)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var known_col := VBoxContainer.new()
	known_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	known_col.size_flags_stretch_ratio = 1.0
	columns.add_child(known_col)
	var known_header := HBoxContainer.new()
	known_header.add_theme_constant_override("separation", 8)
	known_col.add_child(known_header)
	_known_title = Label.new()
	_known_title.text = "Incantesimi di classe"
	_known_title.tooltip_text = "Incantesimi delle classi fino al livello attuale"
	_known_title.clip_text = true
	_known_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_known_title.add_theme_font_size_override("font_size", 16)
	_known_title.add_theme_color_override("font_color", Color(0.96, 0.79, 0.51))
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
	_known_list.mouse_force_pass_scroll_events = false
	_known_list.custom_minimum_size = Vector2(0, 170)
	_known_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_known_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_known_list.item_selected.connect(_on_known_spell_selected)
	_known_list.gui_input.connect(_on_spell_list_gui_input.bind("known"))
	_known_list.item_activated.connect(func(index: int) -> void: _on_spell_activated("known", index))
	known_col.add_child(_known_list)
	# Keep the book's explanatory hint below, so both lists begin at the same height.
	known_col.move_child(_book_hint, _known_list.get_index() + 1)
	var prepared_col := VBoxContainer.new()
	prepared_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prepared_col.size_flags_stretch_ratio = 1.0
	columns.add_child(prepared_col)
	var prepared_header := HBoxContainer.new()
	prepared_header.add_theme_constant_override("separation", 8)
	prepared_col.add_child(prepared_header)
	var prepared_title := Label.new()
	prepared_title.text = "Incantesimi disponibili"
	prepared_title.clip_text = true
	prepared_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prepared_title.add_theme_font_size_override("font_size", 16)
	prepared_title.add_theme_color_override("font_color", Color(0.96, 0.79, 0.51))
	prepared_header.add_child(prepared_title)
	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(40, 30)
	prepared_header.add_child(header_spacer)
	_prepared_list = ItemList.new()
	_prepared_list.mouse_force_pass_scroll_events = false
	_prepared_list.custom_minimum_size = Vector2(0, 170)
	_prepared_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prepared_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prepared_list.item_selected.connect(func(_index: int) -> void: _on_spell_list_selected("prepared"))
	_prepared_list.gui_input.connect(_on_spell_list_gui_input.bind("prepared"))
	prepared_col.add_child(_prepared_list)
	_prepared_list.item_activated.connect(func(index: int) -> void: _on_spell_activated("prepared", index))

	# Feature and item-granted spells live in their own origin-labelled cards;
	# they are separate from prepared spells and never spend spell slots.
	var granted_heading := HBoxContainer.new()
	add_child(granted_heading)
	var granted_title := Label.new()
	granted_title.text = "Incantesimi concessi dalle origini"
	granted_title.add_theme_font_size_override("font_size", 16)
	granted_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	granted_heading.add_child(granted_title)
	var add_grant := Button.new()
	add_grant.text = "+ Concedi incantesimo"
	add_grant.tooltip_text = "Scegli l'origine, l'incantesimo e l'eventuale tracker da consumare."
	add_grant.pressed.connect(_open_grant_dialog)
	granted_heading.add_child(add_grant)
	_granted_spell_boxes = VBoxContainer.new()
	_granted_spell_boxes.add_theme_constant_override("separation", 5)
	add_child(_granted_spell_boxes)
	_grant_dialog = ConfirmationDialog.new()
	_grant_dialog.title = "Incantesimo concesso da un'origine"
	_grant_dialog.ok_button_text = "Aggiungi"
	_grant_dialog.confirmed.connect(_add_origin_spell)
	add_child(_grant_dialog)
	var grant_fields := VBoxContainer.new()
	grant_fields.add_theme_constant_override("separation", 5)
	_grant_dialog.add_child(grant_fields)
	for caption_text: String in ["Origine", "Cerca incantesimo", "Incantesimo", "Tracker consumato (anche di altra origine)"]:
		var label := Label.new()
		label.text = caption_text
		grant_fields.add_child(label)
		match caption_text:
			"Origine":
				_grant_origin = OptionButton.new()
				_grant_origin.custom_minimum_size.x = 400
				grant_fields.add_child(_grant_origin)
			"Cerca incantesimo":
				_grant_search = LineEdit.new()
				_grant_search.placeholder_text = "Nome incantesimo"
				_grant_search.text_changed.connect(_refresh_grant_spell_picker)
				grant_fields.add_child(_grant_search)
			"Incantesimo":
				_grant_spell = OptionButton.new()
				grant_fields.add_child(_grant_spell)
			_:
				_grant_tracker = OptionButton.new()
				grant_fields.add_child(_grant_tracker)

	# Search is the only optional panel and opens beneath the paired spell lists.
	var search_toggle_row := HBoxContainer.new()
	search_toggle_row.alignment = BoxContainer.ALIGNMENT_END
	add_child(search_toggle_row)
	_search_toggle = Button.new()
	_search_toggle.text = "🔍"
	_search_toggle.toggle_mode = true
	_search_toggle.tooltip_text = "Mostra ricerca incantesimi"
	_search_toggle.toggled.connect(_set_search_visible)
	search_toggle_row.add_child(_search_toggle)
	move_child(_search_row, search_toggle_row.get_index() + 1)
	move_child(_catalog_title, _search_row.get_index() + 1)
	move_child(_available, _catalog_title.get_index() + 1)

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
	_prepare.tooltip_text = "Aggiungi o rimuovi l’incantesimo selezionato dai disponibili"
	_prepare.pressed.connect(_toggle_selected_prepared)
	search_toggle_row.add_child(_prepare)
	_cast_button = Button.new()
	_cast_button.text = "✨ Lancia"
	_cast_button.custom_minimum_size = Vector2(100, 34)
	_cast_button.disabled = true
	_cast_button.tooltip_text = "Lancia l'incantesimo selezionato da una qualsiasi delle tre liste"
	_cast_button.pressed.connect(_request_cast_spell)
	search_toggle_row.add_child(_cast_button)

	_description = RichTextLabel.new()
	_description.mouse_force_pass_scroll_events = false
	_description.custom_minimum_size.y = 150
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description.scroll_active = true
	_description.selection_enabled = true
	_description.hide()
	actions.add_child(_description)

	var slot_title := HBoxContainer.new()
	add_child(slot_title)
	var heading := Label.new()
	heading.text = "Slot incantesimo"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 16)
	slot_title.add_child(heading)
	_restore_all_button = Button.new()
	_restore_all_button.text = "Ricarica"
	_restore_all_button.pressed.connect(_restore_all)
	slot_title.add_child(_restore_all_button)
	_slots_eye = Button.new()
	_slots_eye.custom_minimum_size = Vector2(36, 30)
	_slots_eye.pressed.connect(_toggle_slots_visibility)
	slot_title.add_child(_slots_eye)
	var slot_scroll := ScrollContainer.new()
	slot_scroll.mouse_force_pass_scroll_events = false
	slot_scroll.name = "SlotHorizontalScroll"
	slot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_scroll.custom_minimum_size.y = 425
	add_child(slot_scroll)
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 1
	_slot_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_slot_grid.add_theme_constant_override("v_separation", 5)
	slot_scroll.add_child(_slot_grid)
	var hint := Label.new()
	hint.text = "Liv.   −  +  Rimasti / max     (doppio clic sul massimo)"
	hint.add_theme_font_size_override("font_size", 12)
	_slot_grid.add_child(hint)
	for lvl: int in range(1, 10):
		# Match consumable trackers: −, +, then remaining / max (base and bonus).
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_slot_grid.add_child(row)
		var caption := Label.new()
		caption.text = "%d°" % lvl
		caption.custom_minimum_size.x = 28
		row.add_child(caption)
		var use := Button.new()
		use.text = "−"
		use.tooltip_text = "Consuma uno slot di livello %d" % lvl
		use.custom_minimum_size.x = 30
		use.pressed.connect(_change_slot.bind(lvl, 1))
		row.add_child(use)
		_slot_use[lvl] = use
		var remaining := Label.new()
		remaining.custom_minimum_size.x = 68
		remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(remaining)
		_remaining_labels[lvl] = remaining
		var max_label := Label.new()
		row.add_child(max_label)
		var total := SpinBox.new()
		total.min_value = 0
		total.max_value = 99
		total.rounded = true
		total.update_on_text_changed = true
		total.custom_minimum_size = Vector2(68, 36)
		total.tooltip_text = "Numero base di slot massimi"
		total.value_changed.connect(_on_slot_total_changed.bind(lvl))
		row.add_child(total)
		_slot_totals[lvl] = total
		var max_index: int = max_label.get_index()
		row.remove_child(max_label)
		var formula := FormulaValue.new()
		row.add_child(formula)
		row.move_child(formula, max_index)
		formula.setup(max_label, [total], ["Base"])
		formula.target_key = "slot:" + str(lvl)
		formula.bonus_requested.connect(_request_formula_bonus)
		_slot_formula_values[lvl] = formula
		var recharge := Button.new()
		recharge.text = "+"
		recharge.custom_minimum_size.x = 30
		recharge.tooltip_text = "Ricarica uno slot di livello %d" % lvl
		recharge.pressed.connect(_change_slot.bind(lvl, -1))
		row.add_child(recharge)
		row.move_child(recharge, use.get_index() + 1)
		_slot_recharge[lvl] = recharge

	var pact_header := HBoxContainer.new()
	add_child(pact_header)
	var pact_label := Label.new()
	pact_label.text = "Patto"
	pact_label.tooltip_text = "Slot di Magia del Patto"
	pact_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pact_header.add_child(pact_label)
	_pact_eye = Button.new()
	_pact_eye.custom_minimum_size = Vector2(36, 30)
	_pact_eye.pressed.connect(_toggle_pact_visibility)
	pact_header.add_child(_pact_eye)
	var pact_scroll := ScrollContainer.new()
	pact_scroll.mouse_force_pass_scroll_events = false
	pact_scroll.name = "PactHorizontalScroll"
	pact_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pact_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	pact_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pact_scroll.custom_minimum_size.y = 47
	add_child(pact_scroll)
	_pact_row = HBoxContainer.new()
	_pact_row.add_theme_constant_override("separation", 5)
	_pact_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pact_scroll.add_child(_pact_row)
	var level_group := HBoxContainer.new()
	_pact_row.add_child(level_group)
	var level_label := Label.new()
	level_label.text = "Liv."
	level_group.add_child(level_label)
	_pact_level_spin = SpinBox.new()
	_pact_level_spin.min_value = 1
	_pact_level_spin.max_value = 5
	_pact_level_spin.update_on_text_changed = true
	_pact_level_spin.custom_minimum_size.x = 54
	_pact_level_spin.value_changed.connect(_on_pact_values_changed)
	level_group.add_child(_pact_level_spin)
	var total_group := HBoxContainer.new()
	total_group.add_theme_constant_override("separation", 3)
	_pact_row.add_child(total_group)
	var pact_max_label := Label.new()
	total_group.add_child(pact_max_label)
	_pact_total_spin = SpinBox.new()
	_pact_total_spin.min_value = 0
	_pact_total_spin.max_value = 8
	_pact_total_spin.update_on_text_changed = true
	_pact_total_spin.custom_minimum_size = Vector2(54, 36)
	_pact_total_spin.value_changed.connect(_on_pact_values_changed)
	total_group.add_child(_pact_total_spin)
	var pact_index: int = pact_max_label.get_index()
	total_group.remove_child(pact_max_label)
	_pact_formula_value = FormulaValue.new()
	total_group.add_child(_pact_formula_value)
	total_group.move_child(_pact_formula_value, pact_index)
	_pact_formula_value.call("setup", pact_max_label,
		[_pact_total_spin], ["Base"])
	_pact_formula_value.target_key = "pact_slot"
	_pact_formula_value.bonus_requested.connect(_request_formula_bonus)
	_pact_remain = Label.new()
	_pact_remain.custom_minimum_size.x = 68
	_pact_row.add_child(_pact_remain)
	_pact_use = Button.new()
	_pact_use.text = "Usa"
	_pact_use.pressed.connect(_change_pact.bind(1))
	_pact_row.add_child(_pact_use)
	_pact_restore = Button.new()
	_pact_restore.text = "+"
	_pact_restore.tooltip_text = "Ricarica uno slot della Magia del Patto"
	_pact_restore.pressed.connect(_change_pact.bind(-1))
	_pact_row.add_child(_pact_restore)
	_pact_use.text = "−"
	_pact_row.move_child(_pact_use, level_group.get_index() + 1)
	_pact_row.move_child(_pact_restore, _pact_use.get_index() + 1)
	_pact_row.move_child(_pact_remain, _pact_restore.get_index() + 1)
	_pact_row.move_child(total_group, _pact_remain.get_index() + 1)

	_apply_resource_visibility()
	_update_resource_labels()
	_update_spell_controls()
	_set_search_visible(false)
	_build_cast_dialog()


func _build_cast_dialog() -> void:
	_cast_dialog = ConfirmationDialog.new()
	_cast_dialog.title = "Lancia incantesimo"
	_cast_dialog.ok_button_text = "Lancia"
	_cast_dialog.cancel_button_text = "Annulla"
	_cast_dialog.min_size = Vector2i(380, 170)
	add_child(_cast_dialog)
	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 10)
	_cast_dialog.add_child(slot_row)
	var caption: Label = Label.new()
	caption.text = "Slot:"
	slot_row.add_child(caption)
	_cast_slot_choice = OptionButton.new()
	_cast_slot_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cast_slot_choice.custom_minimum_size.x = 270
	slot_row.add_child(_cast_slot_choice)
	_cast_dialog.confirmed.connect(_confirm_cast_spell)


func _request_cast_spell() -> void:
	var spell: Dictionary = _selected_spell()
	if String(spell.get("id", "")).is_empty() or not _on_cast_spell.is_valid():
		return
	var base_level: int = int(spell.get("level", 0))
	if base_level <= 0:
		_dispatch_cast(spell, 0)
		return
	_pending_cast_spell = spell.duplicate(true)
	_cast_slot_choice.clear()
	_cast_slot_choice.add_item("Nessuno slot (non consumare)", 0)
	var default_index: int = 0
	for level: int in range(base_level, 10):
		var remaining: int = maxi(0, _effective_slot_total(level) - int(_spent[level]))
		if remaining <= 0:
			continue
		_cast_slot_choice.add_item("%d° livello · %d rimasti" % [level, remaining], level)
		if default_index == 0:
			default_index = _cast_slot_choice.item_count - 1
	if _pact_level >= base_level and _pact_spent < _effective_pact_total():
		_cast_slot_choice.add_item(
			"Patto · %d° livello · %d rimasti" % [
				_pact_level, _effective_pact_total() - _pact_spent
			],
			100 + _pact_level
		)
		if default_index == 0:
			default_index = _cast_slot_choice.item_count - 1
	_cast_slot_choice.select(default_index)
	_cast_dialog.dialog_text = "Lancia %s (livello %d). Scegli quale slot consumare." % [
		String(spell.get("name", "Incantesimo")), base_level
	]
	DialogLayout.popup(_cast_dialog, Vector2i(430, 190))


func _confirm_cast_spell() -> void:
	if _pending_cast_spell.is_empty():
		return
	var spell: Dictionary = _pending_cast_spell.duplicate(true)
	_pending_cast_spell.clear()
	_dispatch_cast(spell, _cast_slot_choice.get_selected_id())


func _dispatch_cast(spell: Dictionary, slot_choice: int, grant: Dictionary = {}) -> void:
	if not _on_cast_spell.is_valid():
		return
	var base_level: int = int(spell.get("level", 0))
	var level: int = base_level
	if slot_choice >= 100:
		level = slot_choice - 100
		if level != _pact_level or level < base_level or _pact_spent >= _effective_pact_total():
			return
	elif slot_choice > 0:
		level = slot_choice
		if level < base_level or level > 9 or _spent.size() <= level:
			return
		if _effective_slot_total(level) <= int(_spent[level]):
			return
	# The sheet's owner invokes the existing VTT system if the spell has an
	# effect and a linked caster. A spell with no VTT effect is still cast.
	if not bool(_on_cast_spell.call(spell, level, grant)):
		return
	if slot_choice >= 100:
		_change_pact(1)
	elif slot_choice > 0:
		_change_slot(slot_choice, 1)


func _set_search_visible(show: bool) -> void:
	_search_row.visible = show
	_catalog_title.visible = show
	_available.visible = show
	_search_toggle.set_pressed_no_signal(show)
	_search_toggle.tooltip_text = (
		"Nascondi ricerca incantesimi" if show else "Mostra ricerca incantesimi"
	)
	if not show:
		_available.deselect_all()
		_update_spell_controls()
	elif is_inside_tree():
		_search.grab_focus()


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_refresh_casting_summary()
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
	_catalog = SpellCatalog.all_spells_for_rules(
		String(_record.get("rules_version", "2014"))
	)
	_manual_origin_spells = _copy_spell_array(record.get("origin_spell_grants", []))
	_rebuild_class_spells()
	_totals = _normal_slots(record.get("spell_slots_total", []))
	_spent = _normal_slots(record.get("spell_slots_spent", []))
	for lvl: int in range(1, 10):
		_spent[lvl] = mini(int(_spent[lvl]), _effective_slot_total(lvl))
	_pact_total = maxi(0, int(record.get("pact_slots_total", 0)))
	_pact_spent = clampi(int(record.get("pact_slots_spent", 0)), 0, _effective_pact_total())
	_pact_level = clampi(int(record.get("pact_slot_level", 1)), 1, 5)
	_slots_visible = bool(record.get("spell_slots_visible", true))
	_pact_visible = bool(record.get("pact_slots_visible", true))
	_apply_resource_visibility()
	for lvl: int in range(1, 10):
		(_slot_totals[lvl] as SpinBox).value = int(_totals[lvl])
	_pact_total_spin.value = _pact_total
	_pact_level_spin.value = _pact_level
	_class_only.disabled = _class_keys().is_empty()
	_search.text = ""
	_refresh_saved_spell_lists()
	_refresh_granted_spell_boxes()
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



func _effective_slot_total(lvl: int) -> int:
	if lvl < 0 or lvl >= _totals.size():
		return 0
	return maxi(0, Bonuses.add(_record, "slot:" + str(lvl), int(_totals[lvl])))


func _effective_pact_total() -> int:
	return maxi(0, Bonuses.add(_record, "pact_slot", _pact_total))


func _request_formula_bonus(target: String) -> void:
	if _on_bonus_request.is_valid():
		_on_bonus_request.call(target)


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
			or Rules.class_hit_die(spell_class_key, String(cls.get("source", ""))) <= 0
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
		_catalog = SpellCatalog.all_spells_for_rules(
			String(_record.get("rules_version", "2014"))
		)
	var limits: Dictionary = _class_spell_level_limits()
	for entry: Dictionary in _catalog:
		if bool(entry.get("internal_grant", false)):
			continue
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
		_catalog = SpellCatalog.all_spells_for_rules(
			String(_record.get("rules_version", "2014"))
		)
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


func _on_spell_list_gui_input(event: InputEvent, origin: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.double_click or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var list: ItemList = _list_for_origin(origin)
	if list == null:
		return
	var index: int = list.get_item_at_position(click.position, true)
	if index >= 0 and list.is_selected(index):
		# ItemList does not emit item_selected for a repeated click. Defer
		# deselection until its built-in click processing has finished.
		call_deferred("_deselect_spell_item", origin, index)


func _on_spell_activated(origin: String, index: int) -> void:
	# Double-click always casts, regardless of the list it came from.
	# Re-select by index: a previous single click may have queued deselection.
	var list: ItemList = _list_for_origin(origin)
	if list == null or index < 0 or index >= list.item_count:
		return
	list.select(index)
	_on_spell_list_selected(origin)
	_request_cast_spell()

func _list_for_origin(origin: String) -> ItemList:
	match origin:
		"catalog":
			return _available
		"known":
			return _known_list
		"prepared":
			return _prepared_list
	return null


func _deselect_spell_item(origin: String, index: int) -> void:
	var list: ItemList = _list_for_origin(origin)
	if list == null or index < 0 or index >= list.item_count or not list.is_selected(index):
		return
	list.deselect(index)
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


func refresh_spell_state(record: Dictionary) -> void:
	# This changes the small header without rebuilding the expensive spell
	# catalog or discarding the current search and spell selection.
	_record = record.duplicate(true)
	_refresh_casting_summary()


func _on_spellcasting_ability_selected(index: int) -> void:
	if _loading or index < 0 or index >= CASTING_ABILITIES.size():
		return
	var ability: String = CASTING_ABILITIES[index]
	_record["spellcasting_ability"] = ability
	_refresh_casting_summary()
	if _on_change.is_valid():
		_on_change.call({"spellcasting_ability": ability})


func _drop_concentration() -> void:
	if _loading:
		return
	var conditions: Array = _record.get("conditions", []).duplicate()
	conditions.erase("concentrating")
	_record["conditions"] = conditions
	_record["concentrating_spell_id"] = ""
	_refresh_casting_summary()
	if _on_change.is_valid():
		_on_change.call({"conditions": conditions, "concentrating_spell_id": ""})


func _spellcasting_ability(record: Dictionary) -> String:
	var ability: String = String(record.get("spellcasting_ability", "")).to_lower().strip_edges()
	var stat: Dictionary = record.get("stat_block", {})
	if ability.is_empty():
		ability = String(stat.get("spellcasting_ability", "")).to_lower().strip_edges()
	if ability.is_empty():
		var spellcasting_value: Variant = stat.get("spellcasting", [])
		if spellcasting_value is Array and not (spellcasting_value as Array).is_empty():
			var first: Variant = (spellcasting_value as Array)[0]
			if first is Dictionary:
				ability = String((first as Dictionary).get("ability", "")).to_lower()
	if ability.is_empty():
		var name: String = String(record.get("class", "")).to_lower().strip_edges()
		if name.is_empty() and record.get("classes", []) is Array and not (record.get("classes", []) as Array).is_empty():
			var first_class: Variant = (record.get("classes", []) as Array)[0]
			if first_class is Dictionary:
				name = String((first_class as Dictionary).get("name", "")).to_lower()
		var class_abilities := {
			"wizard": "int", "mago": "int", "artificer": "int", "artefice": "int",
			"cleric": "wis", "chierico": "wis", "druid": "wis", "druido": "wis",
			"ranger": "wis", "bard": "cha", "bardo": "cha",
			"paladin": "cha", "paladino": "cha",
			"sorcerer": "cha", "stregone": "cha", "warlock": "cha"
		}
		ability = String(class_abilities.get(name, ""))
	if ability in ["strength", "forza"]: ability = "str"
	if ability in ["dexterity", "destrezza"]: ability = "dex"
	if ability in ["constitution", "costituzione"]: ability = "con"
	if ability in ["intelligence", "intelligenza"]: ability = "int"
	if ability in ["wisdom", "saggezza"]: ability = "wis"
	if ability in ["charisma", "carisma"]: ability = "cha"
	return ability if ability in ["str", "dex", "con", "int", "wis", "cha"] else ""


func _refresh_casting_summary() -> void:
	if _spell_summary == null:
		return
	if _spell_ability_choice != null:
		var manual_ability: String = String(_record.get("spellcasting_ability", "")).to_lower().strip_edges()
		var selection_index: int = CASTING_ABILITIES.find(manual_ability)
		_spell_ability_choice.select(maxi(0, selection_index))
	if _drop_concentration_button != null:
		_drop_concentration_button.disabled = (
			String(_record.get("concentrating_spell_id", "")).is_empty()
			and not ("concentrating" in _record.get("conditions", []))
		)
	var ability: String = _spellcasting_ability(_record)
	var italian_abbreviations := {"str": "FOR", "dex": "DES", "con": "COS",
		"int": "INT", "wis": "SAG", "cha": "CAR"}
	var stat_label: String = (
		ability.to_upper() if _gui_language == "en"
		else String(italian_abbreviations.get(ability, ""))
	)
	if ability.is_empty():
		stat_label = "non definita"
	var hit_label := "—"
	var dc_label := "—"
	var explanation := "Seleziona una classe da incantatore o imposta la caratteristica degli incantesimi."
	if not ability.is_empty():
		var prof: int = Bonuses.value(_record, "proficiency")
		var ability_mod: int = Bonuses.value(_record, "ability_mod:" + ability)
		var attack: int = prof + ability_mod + Bonuses.bonus(_record, "spell_attack")
		var dc: int = 8 + prof + ability_mod + Bonuses.bonus(_record, "spell_dc")
		hit_label = "%+d" % attack
		dc_label = str(dc)
		explanation = ("Modificatore %s %+d + competenza %+d; "
			+ "bonus tiro %+d, bonus CD %+d") % [
				ability.to_upper(), ability_mod, prof,
				Bonuses.bonus(_record, "spell_attack"),
				Bonuses.bonus(_record, "spell_dc")
			]
	var concentration_name := "nessuna"
	var concentration_id: String = String(_record.get("concentrating_spell_id", ""))
	if not concentration_id.is_empty():
		var definition: Dictionary = SpellCatalog.catalog_spell(concentration_id)
		concentration_name = String(definition.get("name", concentration_id))
	elif "concentrating" in _record.get("conditions", []):
		concentration_name = "attiva (incantesimo non specificato)"
	_spell_summary.text = "Caratteristica: %s  ·  Tiro per colpire: %s  ·  CD: %s\nConcentrazione: %s" % [
		stat_label, hit_label, dc_label, concentration_name
	]
	_spell_summary.tooltip_text = explanation


func update_character_context(record: Dictionary) -> void:
	_refresh_casting_summary()
	var current_class: Variant = record.get("classes", [])
	var current_primary: String = String(record.get("class", ""))
	# Every ordinary sheet edit reaches this method. Rebuilding both lists and
	# the full spell catalog is only necessary when their inputs change.
	if (current_class == _record.get("classes", [])
		and current_primary == String(_record.get("class", ""))
		and record.get("level", 1) == _record.get("level", 1)
		and String(record.get("rules_version", "2014")) == String(_record.get("rules_version", "2014"))):
		_record = record.duplicate(true)
		_refresh_casting_summary()
		_refresh_granted_spell_boxes()
		return
	# Own the snapshot so later in-place level/class edits are detectable.
	_record["classes"] = current_class.duplicate(true) if current_class is Array else current_class
	_record["class"] = current_primary
	_record["level"] = record.get("level", 1)
	_record["rules_version"] = String(record.get("rules_version", "2014"))
	_refresh_casting_summary()
	_catalog = SpellCatalog.all_spells_for_rules(
		String(_record.get("rules_version", "2014"))
	)
	_rebuild_class_spells()
	_refresh_saved_spell_lists()
	_refresh_granted_spell_boxes()
	_class_only.disabled = _class_keys().is_empty()
	_filter_spells()


func _selected_spell() -> Dictionary:
	var available_selected: PackedInt32Array = _available.get_selected_items()
	if not available_selected.is_empty() and available_selected[0] < _visible.size():
		return _visible[available_selected[0]]
	var known_selected: PackedInt32Array = _known_list.get_selected_items()
	if not known_selected.is_empty() and known_selected[0] < _displayed_known.size():
		return _spell_detail(_displayed_known[known_selected[0]])
	var prepared_selected: PackedInt32Array = _prepared_list.get_selected_items()
	if not prepared_selected.is_empty() and prepared_selected[0] < _prepared.size():
		return _spell_detail(_prepared[prepared_selected[0]])
	return {}


func _spell_detail(entry: Variant) -> Dictionary:
	var id: String = _entry_id(entry)
	var found: Dictionary = _spell_by_id(id)
	if not found.is_empty():
		return found
	# Class entries often carry their whole description; imported/homebrew
	# entries may use an alternative catalogue identifier.
	for candidate: Dictionary in _catalog:
		if String(candidate.get("id", "")) == id:
			return candidate
	if entry is Dictionary:
		var saved: Dictionary = entry as Dictionary
		for candidate: Dictionary in _catalog:
			if (
				String(candidate.get("name", "")).nocasecmp_to(String(saved.get("name", ""))) == 0
				and String(candidate.get("source", "")) == String(saved.get("source", ""))
			):
				return candidate
		return saved
	return {}


func _update_spell_controls() -> void:
	if _description == null:
		return
	var spell: Dictionary = _selected_spell()
	var id: String = String(spell.get("id", ""))
	_prepare.disabled = id.is_empty()
	_cast_button.disabled = id.is_empty() or not _on_cast_spell.is_valid()
	_prepare.text = (
		"Rimuovi dai disponibili"
		if _has_spell(_prepared, id)
		else "Aggiungi ai disponibili"
	)
	if id.is_empty():
		_description.clear()
		_description.hide()
		return
	var body: String = String(spell.get("description", "")).strip_edges()
	if body.is_empty():
		body = "Descrizione non disponibile nel catalogo."
	var higher_levels: String = String(spell.get("higher_levels", "")).strip_edges()
	if not higher_levels.is_empty():
		body += "\n\n" + higher_levels
	_description.show()
	# Localize only our metadata labels; 5etools spell text is unchanged.
	_description.text = "%s · %s %d · %s\n%s%s · %s%s\n%s%s\n\n%s" % [
		String(spell.get("name", id)), CreatureLocale.text_for("Livello", _gui_language),
		int(spell.get("level", 0)), String(spell.get("source", "")),
		CreatureLocale.text_for("Gittata: ", _gui_language), String(spell.get("range", "—")),
		CreatureLocale.text_for("Componenti: ", _gui_language), String(spell.get("components", "—")),
		CreatureLocale.text_for("Durata: ", _gui_language), String(spell.get("duration", "—")), body
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
	# Rebuilding ItemList otherwise clears the chosen row and its description.
	var known_id: String = _selected_list_id(_known_list, _displayed_known)
	var prepared_id: String = _selected_list_id(_prepared_list, _prepared)
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
	_restore_list_selection(_known_list, _displayed_known, known_id)
	_restore_list_selection(_prepared_list, _prepared, prepared_id)
	_update_book_menu()
	_update_spell_controls()


func _selected_list_id(list: ItemList, entries: Array) -> String:
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty() or selected[0] < 0 or selected[0] >= entries.size():
		return ""
	return _entry_id(entries[selected[0]])


func _restore_list_selection(list: ItemList, entries: Array, id: String) -> void:
	if id.is_empty():
		return
	for i: int in range(entries.size()):
		if _entry_id(entries[i]) == id:
			list.select(i)
			return


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



func _change_slot(lvl: int, spent_delta: int) -> void:
	_spent[lvl] = clampi(int(_spent[lvl]) + spent_delta, 0, _effective_slot_total(lvl))
	_update_resource_labels()
	_publish()


func _on_pact_values_changed(_value: float) -> void:
	if _loading:
		return
	_pact_total = maxi(0, int(_pact_total_spin.value))
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


func _toggle_slots_visibility() -> void:
	_slots_visible = not _slots_visible
	_apply_resource_visibility()
	_publish()


func _toggle_pact_visibility() -> void:
	_pact_visible = not _pact_visible
	_apply_resource_visibility()
	_publish()


func _apply_resource_visibility() -> void:
	_slot_grid.get_parent().visible = _slots_visible
	_restore_all_button.visible = _slots_visible
	_pact_row.get_parent().visible = _pact_visible
	_slots_eye.text = "👁" if _slots_visible else "👁̸"
	_slots_eye.tooltip_text = "Nascondi slot" if _slots_visible else "Mostra slot"
	_pact_eye.text = "👁" if _pact_visible else "👁̸"
	_pact_eye.tooltip_text = "Nascondi patto" if _pact_visible else "Mostra patto"


func _update_resource_labels() -> void:
	if _pact_remain == null:
		return
	for lvl: int in range(1, 10):
		var base: int = int(_totals[lvl]) if _totals.size() > lvl else 0
		var total: int = _effective_slot_total(lvl)
		var spent: int = clampi(int(_spent[lvl]), 0, total) if _spent.size() > lvl else 0
		(_remaining_labels[lvl] as Label).text = "%d /" % (total - spent)
		if _slot_formula_values.has(lvl):
			_slot_formula_values[lvl].set_formula(str(total),
				"Slot livello %d: base %d + bonus cumulabili %+d = %d" % [
					lvl, base, Bonuses.bonus(_record, "slot:" + str(lvl)), total
				] + ("\n" + Bonuses.description(_record, "slot:" + str(lvl))))
		(_slot_use[lvl] as Button).disabled = spent >= total
		(_slot_recharge[lvl] as Button).disabled = spent <= 0
	var pact_max: int = _effective_pact_total()
	_pact_remain.text = "%d /" % (pact_max - _pact_spent)
	if _pact_formula_value != null:
		_pact_formula_value.call("set_formula", str(pact_max),
			"Magia del Patto: base %d + bonus cumulabili %+d = %d" % [
				_pact_total, Bonuses.bonus(_record, "pact_slot"), pact_max
			] + ("\n" + Bonuses.description(_record, "pact_slot")))
	_pact_use.disabled = _pact_spent >= pact_max
	_pact_restore.disabled = _pact_spent <= 0


func _publish() -> void:
	if _loading or not _on_change.is_valid():
		return
	_on_change.call({
		"spells": _prepared.duplicate(true),
		"prepared_spells": _prepared.duplicate(true),
		"spellbook_spells": _spellbook.duplicate(true),
		"origin_spell_grants": _manual_origin_spells.duplicate(true),
		"spell_slots_total": _totals.duplicate(true),
		"spell_slots_spent": _spent.duplicate(true),
		"pact_slots_total": _pact_total,
		"pact_slots_spent": _pact_spent,
		"pact_slot_level": _pact_level,
		"spell_slots_visible": _slots_visible,
		"pact_slots_visible": _pact_visible
	})



# Editing is restricted to explicit user grants; class features are derived
# from the character each refresh and keep stable origin and tracker IDs.
func _grant_record() -> Dictionary:
	var data: Dictionary = _record.duplicate(true)
	data["origin_spell_grants"] = _manual_origin_spells.duplicate(true)
	return data


func _refresh_granted_spell_boxes() -> void:
	if _granted_spell_boxes == null:
		return
	for child: Node in _granted_spell_boxes.get_children():
		child.queue_free()
		_granted_spell_boxes.remove_child(child)
	var record: Dictionary = _grant_record()
	var groups: Dictionary = {}
	for grant: Dictionary in OriginSpells.all_grants(record):
		var origin_id: String = String(grant.get("origin_id", ""))
		if not groups.has(origin_id):
			groups[origin_id] = []
		groups[origin_id].append(grant)
	for origin_id: String in groups.keys():
		var panel := PanelContainer.new()
		_granted_spell_boxes.add_child(panel)
		var body := VBoxContainer.new()
		panel.add_child(body)
		var title := Label.new()
		var entries: Array = groups[origin_id]
		title.text = String((entries[0] as Dictionary).get("origin_name", origin_id))
		title.add_theme_font_size_override("font_size", 14)
		body.add_child(title)
		for raw: Variant in entries:
			var grant: Dictionary = raw
			var spell: Dictionary = SpellCatalog.catalog_spell(String(grant.get("spell_id", "")))
			if spell.is_empty():
				continue
			var row := HBoxContainer.new()
			body.add_child(row)
			var tracker: Dictionary = OriginSpells.tracker_for(record, grant)
			var remaining: int = OriginSpells.remaining(record, grant)
			var cost_label: String = "senza limite" if remaining < 0 else (
				"%d rimasti · %s" % [remaining, String(tracker.get("name", "tracker non disponibile"))])
			var cast := Button.new()
			cast.text = String(spell.get("name", "")) + " · " + cost_label
			cast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cast.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cast.disabled = remaining == 0 or not _on_cast_spell.is_valid()
			cast.tooltip_text = String(spell.get("description", ""))
			cast.pressed.connect(_cast_granted_spell.bind(grant.duplicate(true)))
			row.add_child(cast)
			if not bool(grant.get("automatic", false)):
				var remove := Button.new()
				remove.text = "×"
				remove.tooltip_text = "Rimuovi questa concessione, non il tracker né l'origine."
				remove.pressed.connect(_remove_origin_spell.bind(String(grant.get("id", ""))))
				row.add_child(remove)


func _cast_granted_spell(grant: Dictionary) -> void:
	var record: Dictionary = _grant_record()
	if OriginSpells.remaining(record, grant) == 0:
		return
	var spell: Dictionary = SpellCatalog.catalog_spell(String(grant.get("spell_id", "")))
	if spell.is_empty():
		return
	_dispatch_cast(spell, -1, grant)


func _open_grant_dialog() -> void:
	_grant_origin.clear()
	for origin: Dictionary in OriginChoices.available(_record):
		var sid: String = String(origin.get("id", ""))
		if sid.is_empty() or sid == OriginChoices.SPELL_PICKER_ID:
			continue
		_grant_origin.add_item(String(origin.get("name", sid)))
		_grant_origin.set_item_metadata(_grant_origin.item_count - 1, sid)
	_grant_tracker.clear()
	_grant_tracker.add_item("Nessun tracker (usi illimitati)")
	_grant_tracker.set_item_metadata(0, "")
	for tracker: Dictionary in Trackers.for_creature(_record):
		_grant_tracker.add_item(String(tracker.get("name", "")) + " · " + String(tracker.get("source_label", "")))
		_grant_tracker.set_item_metadata(_grant_tracker.item_count - 1, String(tracker.get("id", "")))
	_grant_search.clear()
	_refresh_grant_spell_picker("")
	_grant_dialog.get_ok_button().disabled = _grant_origin.item_count == 0
	_grant_dialog.popup_centered(Vector2i(540, 360))


func _refresh_grant_spell_picker(query: String) -> void:
	if _grant_spell == null:
		return
	_grant_spell.clear()
	_grant_spell_choices.clear()
	var needle: String = query.strip_edges().to_lower()
	for spell: Dictionary in _catalog:
		if not needle.is_empty() and needle not in String(spell.get("name", "")).to_lower():
			continue
		_grant_spell_choices.append(spell)
		_grant_spell.add_item("%s [%s]" % [String(spell.get("name", "")), String(spell.get("source", ""))])
		if _grant_spell_choices.size() >= 250:
			break


func _add_origin_spell() -> void:
	if _grant_origin.selected < 0 or _grant_spell.selected < 0 or _grant_spell.selected >= _grant_spell_choices.size():
		return
	var origin_id: String = String(_grant_origin.get_item_metadata(_grant_origin.selected))
	var spell_id: String = String(_grant_spell_choices[_grant_spell.selected].get("id", ""))
	if origin_id.is_empty() or spell_id.is_empty():
		return
	for row: Variant in _manual_origin_spells:
		if row is Dictionary and String(row.get("origin_id", "")) == origin_id and String(row.get("spell_id", "")) == spell_id:
			return
	_manual_origin_spells.append({
		"id": "origin_spell_%d" % Time.get_ticks_usec(),
		"origin_id": origin_id,
		"origin_name": _grant_origin.get_item_text(_grant_origin.selected),
		"spell_id": spell_id,
		"tracker_id": String(_grant_tracker.get_item_metadata(_grant_tracker.selected))
	})
	_publish()
	_refresh_granted_spell_boxes()


func _remove_origin_spell(id: String) -> void:
	for i: int in range(_manual_origin_spells.size() - 1, -1, -1):
		if String((_manual_origin_spells[i] as Dictionary).get("id", "")) == id:
			_manual_origin_spells.remove_at(i)
	_publish()
	_refresh_granted_spell_boxes()


func set_gui_language(language: String) -> void:
	if language not in ["it", "en"] or _gui_language == language:
		return
	_gui_language = language
	_refresh_casting_summary()
	_update_spell_controls()
