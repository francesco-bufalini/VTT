extends Node

const CharacterStore = preload("res://vtt/player_character_store.gd")
const PlayerReference = preload("res://vtt/player_reference_catalog.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")

var board_root: Node3D
var ui_root: CanvasLayer
var _store: RefCounted
var _characters: Array[Dictionary] = []
var _current_index: int = -1
var _loading: bool = false

var _panel: PanelContainer
var _character_list: ItemList
var _status_label: Label
var _tabs: TabContainer
var _linked_token_label: Label

var _text_fields: Dictionary = {}
var _int_fields: Dictionary = {}
var _bool_fields: Dictionary = {}
var _option_fields: Dictionary = {}
var _ability_spins: Dictionary = {}
var _ability_mod_labels: Dictionary = {}
var _save_checks: Dictionary = {}
var _save_value_labels: Dictionary = {}
var _skill_checks: Dictionary = {}
var _skill_expertise_checks: Dictionary = {}
var _skill_value_labels: Dictionary = {}
var _proficiency_label: Label
var _passive_perception_label: Label

var _spell_class_selector: OptionButton
var _spell_level_selector: OptionButton
var _available_spells: ItemList
var _selected_spells: ItemList
var _slot_total_spins: Array[SpinBox] = []
var _slot_spent_spins: Array[SpinBox] = []

var _link_dialog: ConfirmationDialog
var _link_character_selector: OptionButton
var _link_token: CharacterBody3D


func setup(root: Node3D) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return

	_store = CharacterStore.new()
	_store.call("setup", _campaign_manager())
	_build_ui()
	_build_link_dialog()
	_reload_characters()


func toggle_panel() -> void:
	if _panel == null:
		return
	if _panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	if _panel == null:
		return
	_panel.show()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")
	else:
		board_root.set("_ui_owns_mouse", true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_panel() -> void:
	if _panel == null:
		return
	_save_form()
	_panel.hide()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")


func add_character() -> void:
	if _store == null:
		return
	var character: Dictionary = _store.call("create_character")
	_characters.append(character)
	_store.call("save_characters", _characters)
	_refresh_character_list(String(character.get("id", "")))
	show_panel()
	_set_status("Nuovo personaggio creato.")


func request_link_character_to_selected_token() -> void:
	if _characters.is_empty():
		add_character()

	var selected_tokens: Array[CharacterBody3D] = _selected_tokens()
	if selected_tokens.size() != 1:
		show_panel()
		_set_status(
			"Seleziona esattamente un token, poi usa «Collega personaggio a token»."
		)
		return

	_link_token = selected_tokens[0]
	_link_character_selector.clear()
	for character: Dictionary in _characters:
		var label: String = String(character.get("name", "Personaggio"))
		var linked_name: String = String(
			character.get("linked_token_name", "")
		).strip_edges()
		if not linked_name.is_empty():
			label += "  →  " + linked_name
		_link_character_selector.add_item(label)
		var item_index: int = _link_character_selector.item_count - 1
		_link_character_selector.set_item_metadata(
			item_index,
			String(character.get("id", ""))
		)

	if _current_index >= 0 and _current_index < _characters.size():
		var current_id: String = String(
			_characters[_current_index].get("id", "")
		)
		for index: int in range(_link_character_selector.item_count):
			if String(
				_link_character_selector.get_item_metadata(index)
			) == current_id:
				_link_character_selector.select(index)
				break

	var token_name := _token_name(_link_token)
	_link_dialog.dialog_text = (
		"Token selezionato: %s\nScegli il personaggio da associare."
		% token_name
	)
	_link_dialog.reset_size()
	_link_dialog.popup_centered_clamped(Vector2i(520, 240), 0.92)


func character_count() -> int:
	return _characters.size()


func serialize_characters() -> Array[Dictionary]:
	return _characters.duplicate(true)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PlayerAreaPanel"
	_panel.anchor_left = 0.045
	_panel.anchor_top = 0.045
	_panel.anchor_right = 0.955
	_panel.anchor_bottom = 0.955
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	ui_root.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.028, 0.036, 0.97)
	panel_style.border_color = Color(0.56, 0.43, 0.24, 0.84)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", panel_style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)

	var title := Label.new()
	title.text = "Area Player"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var add_button := Button.new()
	add_button.text = "Aggiungi Personaggio"
	add_button.pressed.connect(add_character)
	header.add_child(add_button)

	var link_button := Button.new()
	link_button.text = "Collega a token"
	link_button.pressed.connect(request_link_character_to_selected_token)
	header.add_child(link_button)

	var close_button := Button.new()
	close_button.text = "Chiudi"
	close_button.pressed.connect(hide_panel)
	header.add_child(close_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.modulate = Color(0.82, 0.78, 0.70, 1.0)
	outer.add_child(_status_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 230
	outer.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)

	var list_title := Label.new()
	list_title.text = "Personaggi"
	list_title.add_theme_font_size_override("font_size", 17)
	left.add_child(list_title)

	_character_list = ItemList.new()
	_character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_list.select_mode = ItemList.SELECT_SINGLE
	_character_list.item_selected.connect(_on_character_selected)
	left.add_child(_character_list)

	var delete_button := Button.new()
	delete_button.text = "Elimina personaggio"
	delete_button.pressed.connect(_delete_current_character)
	left.add_child(delete_button)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)

	_build_identity_tab()
	_build_combat_tab()
	_build_story_tab()
	_build_spells_tab()


func _build_identity_tab() -> void:
	var tab := _scroll_tab("Scheda")
	var body: VBoxContainer = tab.get_meta("body") as VBoxContainer

	_section_title(body, "Identità")
	var identity_grid := GridContainer.new()
	identity_grid.columns = 4
	identity_grid.add_theme_constant_override("h_separation", 10)
	identity_grid.add_theme_constant_override("v_separation", 7)
	body.add_child(identity_grid)

	_add_text_field(identity_grid, "Nome personaggio", "name")
	_add_text_field(identity_grid, "Nome giocatore", "player_name")
	_add_option_field(
		identity_grid,
		"Regole",
		"rules_version",
		[
			{"label": "2024", "value": "2024"},
			{"label": "2014", "value": "2014"}
		]
	)
	_add_int_field(identity_grid, "Livello", "level", 1, 20)

	_add_reference_option(
		identity_grid,
		"Classe",
		"class",
		PlayerReference.CLASSES
	)
	_add_reference_option(
		identity_grid,
		"Specie / Razza",
		"species",
		PlayerReference.SPECIES
	)
	_add_reference_option(
		identity_grid,
		"Background",
		"background",
		PlayerReference.BACKGROUNDS
	)
	_add_text_field(identity_grid, "Allineamento", "alignment")
	_add_text_field(identity_grid, "Sesso", "sex")

	_linked_token_label = Label.new()
	_linked_token_label.text = "Token collegato: nessuno"
	_linked_token_label.modulate = Color(0.78, 0.80, 0.86, 1.0)
	body.add_child(_linked_token_label)

	_section_title(body, "Caratteristiche")
	var abilities_grid := GridContainer.new()
	abilities_grid.columns = 3
	abilities_grid.add_theme_constant_override("h_separation", 12)
	abilities_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(abilities_grid)

	for ability: Dictionary in PlayerReference.ABILITIES:
		var ability_id: String = String(ability.get("id", ""))
		var label := Label.new()
		label.text = String(ability.get("name", ability_id))
		abilities_grid.add_child(label)

		var score := SpinBox.new()
		score.min_value = 1
		score.max_value = 30
		score.step = 1
		score.custom_minimum_size = Vector2(100, 32)
		score.value_changed.connect(
			func(_value: float) -> void:
				_on_form_changed()
		)
		abilities_grid.add_child(score)
		_ability_spins[ability_id] = score

		var modifier := Label.new()
		modifier.text = "+0"
		modifier.custom_minimum_size = Vector2(54, 0)
		abilities_grid.add_child(modifier)
		_ability_mod_labels[ability_id] = modifier

	_section_title(body, "Difese e risorse")
	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override("h_separation", 10)
	stats_grid.add_theme_constant_override("v_separation", 7)
	body.add_child(stats_grid)
	_add_int_field(stats_grid, "CA", "armor_class", 0, 40)
	_add_int_field(stats_grid, "CA temporanea", "temporary_ac", 0, 40)
	_add_int_field(stats_grid, "Iniziativa", "initiative", -20, 30)
	_add_int_field(stats_grid, "Velocità (ft)", "speed", 0, 300)
	_add_int_field(stats_grid, "PF massimi", "max_hp", 0, 9999)
	_add_int_field(stats_grid, "PF attuali", "current_hp", -999, 9999)
	_add_int_field(stats_grid, "PF temporanei", "temporary_hp", 0, 9999)
	_add_int_field(stats_grid, "Scurovisione (ft)", "darkvision", 0, 1000)
	_add_int_field(stats_grid, "Affaticamento", "exhaustion", 0, 6)
	_add_text_field(stats_grid, "Dadi vita", "hit_dice")
	_add_int_field(
		stats_grid,
		"TS morte · successi",
		"death_save_successes",
		0,
		3
	)
	_add_int_field(
		stats_grid,
		"TS morte · fallimenti",
		"death_save_failures",
		0,
		3
	)

	_bool_fields["inspiration"] = _add_check(body, "Ispirazione")
	_proficiency_label = Label.new()
	_proficiency_label.text = "Bonus di competenza: +2"
	body.add_child(_proficiency_label)
	_passive_perception_label = Label.new()
	_passive_perception_label.text = "Percezione passiva: 10"
	body.add_child(_passive_perception_label)


func _build_combat_tab() -> void:
	var tab := _scroll_tab("Combattimento")
	var body: VBoxContainer = tab.get_meta("body") as VBoxContainer

	_section_title(body, "Tiri salvezza")
	var saves_grid := GridContainer.new()
	saves_grid.columns = 3
	body.add_child(saves_grid)
	for ability: Dictionary in PlayerReference.ABILITIES:
		var ability_id: String = String(ability.get("id", ""))
		var check := CheckButton.new()
		check.text = String(ability.get("name", ability_id))
		check.toggled.connect(
			func(_pressed: bool) -> void:
				_on_form_changed()
		)
		saves_grid.add_child(check)
		_save_checks[ability_id] = check

		var value_label := Label.new()
		value_label.text = "+0"
		saves_grid.add_child(value_label)
		_save_value_labels[ability_id] = value_label
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(10, 0)
		saves_grid.add_child(spacer)

	_section_title(body, "Abilità")
	var skills_grid := GridContainer.new()
	skills_grid.columns = 2
	skills_grid.add_theme_constant_override("h_separation", 16)
	skills_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(skills_grid)

	for skill: Dictionary in PlayerReference.SKILLS:
		var skill_id: String = String(skill.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		skills_grid.add_child(row)

		var proficient := CheckButton.new()
		proficient.tooltip_text = "Competenza"
		proficient.toggled.connect(
			func(_pressed: bool) -> void:
				_on_form_changed()
		)
		row.add_child(proficient)
		_skill_checks[skill_id] = proficient

		var expertise := CheckButton.new()
		expertise.text = "M"
		expertise.tooltip_text = "Maestria"
		expertise.toggled.connect(
			func(_pressed: bool) -> void:
				_on_form_changed()
		)
		row.add_child(expertise)
		_skill_expertise_checks[skill_id] = expertise

		var label := Label.new()
		label.text = String(skill.get("name", skill_id))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var value_label := Label.new()
		value_label.text = "+0"
		value_label.custom_minimum_size = Vector2(40, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_skill_value_labels[skill_id] = value_label

	_section_title(body, "Attacchi & Incantesimi")
	_add_multiline_field(body, "Attacchi / armi / danni", "attacks", 120)
	_add_multiline_field(body, "Munizioni", "ammunition", 70)

	_section_title(body, "Competenze")
	_add_multiline_field(body, "Armature", "armor_proficiencies", 65)
	_add_multiline_field(body, "Armi", "weapon_proficiencies", 65)
	_add_multiline_field(body, "Strumenti", "tool_proficiencies", 65)
	_add_multiline_field(body, "Linguaggi", "languages", 65)

	_section_title(body, "Privilegi")
	_add_multiline_field(body, "Talenti", "feats", 90)
	_add_multiline_field(body, "Privilegi di classe", "class_features", 140)
	_add_multiline_field(
		body,
		"Tratti razziali / specie e background",
		"racial_background_traits",
		120
	)
	_add_multiline_field(
		body,
		"Privilegi e tratti limitati",
		"limited_features",
		100
	)


func _build_story_tab() -> void:
	var tab := _scroll_tab("Personaggio & Inventario")
	var body: VBoxContainer = tab.get_meta("body") as VBoxContainer

	_section_title(body, "Aspetto del personaggio")
	var appearance_grid := GridContainer.new()
	appearance_grid.columns = 4
	appearance_grid.add_theme_constant_override("h_separation", 10)
	appearance_grid.add_theme_constant_override("v_separation", 7)
	body.add_child(appearance_grid)
	_add_text_field(appearance_grid, "Età", "age")
	_add_text_field(appearance_grid, "Altezza", "height")
	_add_text_field(appearance_grid, "Peso", "weight")
	_add_text_field(appearance_grid, "Occhi", "eyes")
	_add_text_field(appearance_grid, "Carnagione", "skin")
	_add_text_field(appearance_grid, "Capelli", "hair")
	_add_text_field(appearance_grid, "Fazione", "faction")
	_add_text_field(appearance_grid, "Simbolo", "symbol")
	_add_multiline_field(body, "Aspetto", "appearance", 110)

	_section_title(body, "Personalità")
	_add_multiline_field(body, "Tratti caratteriali", "personality_traits", 90)
	_add_multiline_field(body, "Ideali", "ideals", 80)
	_add_multiline_field(body, "Legami", "bonds", 80)
	_add_multiline_field(body, "Difetti", "flaws", 80)
	_add_multiline_field(body, "Nemici", "enemies", 80)
	_add_multiline_field(
		body,
		"Tratti & privilegi aggiuntivi",
		"additional_traits",
		110
	)

	_section_title(body, "Inventario")
	_add_multiline_field(body, "Equipaggiamento", "equipment", 150)
	_add_multiline_field(body, "Consumabili", "consumables", 100)
	_add_multiline_field(
		body,
		"Oggetti magici armonizzati",
		"magic_items",
		100
	)


func _build_spells_tab() -> void:
	var tab := _scroll_tab("Incantesimi")
	var body: VBoxContainer = tab.get_meta("body") as VBoxContainer

	_section_title(body, "Incantatore")
	var caster_grid := GridContainer.new()
	caster_grid.columns = 4
	caster_grid.add_theme_constant_override("h_separation", 10)
	caster_grid.add_theme_constant_override("v_separation", 7)
	body.add_child(caster_grid)

	_spell_class_selector = _add_reference_option(
		caster_grid,
		"Classe da incantatore",
		"spellcasting_class",
		PlayerReference.CLASSES
	)
	_add_ability_option(
		caster_grid,
		"Caratteristica",
		"spellcasting_ability"
	)
	_add_int_field(caster_grid, "CD TS incantesimi", "spell_save_dc", 0, 40)
	_add_int_field(
		caster_grid,
		"Bonus attacco incantesimi",
		"spell_attack_bonus",
		-20,
		30
	)

	_section_title(body, "Aggiungi dal catalogo 5e.tools")
	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 8)
	body.add_child(picker_row)

	_spell_level_selector = OptionButton.new()
	for level: int in range(10):
		_spell_level_selector.add_item(
			"Trucchetti" if level == 0 else "Livello %d" % level
		)
		_spell_level_selector.set_item_metadata(level, level)
	_spell_level_selector.item_selected.connect(
		func(_index: int) -> void:
			_refresh_available_spells()
	)
	picker_row.add_child(_spell_level_selector)

	var refresh_button := Button.new()
	refresh_button.text = "Aggiorna elenco"
	refresh_button.pressed.connect(_refresh_available_spells)
	picker_row.add_child(refresh_button)

	_available_spells = ItemList.new()
	_available_spells.custom_minimum_size = Vector2(0, 180)
	_available_spells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_available_spells)

	var add_spell_button := Button.new()
	add_spell_button.text = "Aggiungi incantesimo selezionato"
	add_spell_button.pressed.connect(_add_selected_spell)
	body.add_child(add_spell_button)

	_section_title(body, "Incantesimi del personaggio")
	_selected_spells = ItemList.new()
	_selected_spells.custom_minimum_size = Vector2(0, 160)
	body.add_child(_selected_spells)

	var remove_spell_button := Button.new()
	remove_spell_button.text = "Rimuovi incantesimo selezionato"
	remove_spell_button.pressed.connect(_remove_selected_spell)
	body.add_child(remove_spell_button)

	_section_title(body, "Slot")
	var slots_grid := GridContainer.new()
	slots_grid.columns = 5
	slots_grid.add_theme_constant_override("h_separation", 8)
	slots_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(slots_grid)

	for level: int in range(1, 10):
		var level_label := Label.new()
		level_label.text = "Lv %d" % level
		slots_grid.add_child(level_label)

		var total_label := Label.new()
		total_label.text = "Totali"
		slots_grid.add_child(total_label)

		var total_spin := SpinBox.new()
		total_spin.min_value = 0
		total_spin.max_value = 20
		total_spin.value_changed.connect(
			func(_value: float) -> void:
				_on_form_changed()
		)
		slots_grid.add_child(total_spin)
		_slot_total_spins.append(total_spin)

		var spent_label := Label.new()
		spent_label.text = "Spesi"
		slots_grid.add_child(spent_label)

		var spent_spin := SpinBox.new()
		spent_spin.min_value = 0
		spent_spin.max_value = 20
		spent_spin.value_changed.connect(
			func(_value: float) -> void:
				_on_form_changed()
		)
		slots_grid.add_child(spent_spin)
		_slot_spent_spins.append(spent_spin)


func _build_link_dialog() -> void:
	_link_dialog = ConfirmationDialog.new()
	_link_dialog.title = "Collega personaggio a token"
	_link_dialog.ok_button_text = "Collega"
	_link_dialog.cancel_button_text = "Annulla"
	_link_dialog.min_size = Vector2i(520, 240)
	ui_root.add_child(_link_dialog)

	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 18
	body.offset_top = 80
	body.offset_right = -18
	body.offset_bottom = -70
	body.add_theme_constant_override("separation", 8)
	_link_dialog.add_child(body)

	var label := Label.new()
	label.text = "Personaggio"
	body.add_child(label)

	_link_character_selector = OptionButton.new()
	body.add_child(_link_character_selector)
	_link_dialog.confirmed.connect(_confirm_link_character)


func _scroll_tab(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	margin.add_child(body)
	scroll.set_meta("body", body)
	return scroll


func _section_title(parent: Control, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)


func _add_text_field(
	parent: Control,
	label_text: String,
	key: String
) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(150, 32)
	field.text_changed.connect(
		func(_value: String) -> void:
			_on_form_changed()
	)
	parent.add_child(field)
	_text_fields[key] = field
	return field


func _add_multiline_field(
	parent: Control,
	label_text: String,
	key: String,
	height: float
) -> TextEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := TextEdit.new()
	field.custom_minimum_size = Vector2(0, height)
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.text_changed.connect(_on_form_changed)
	parent.add_child(field)
	_text_fields[key] = field
	return field


func _add_int_field(
	parent: Control,
	label_text: String,
	key: String,
	min_value: int,
	max_value: int
) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := SpinBox.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = 1
	field.custom_minimum_size = Vector2(110, 32)
	field.value_changed.connect(
		func(_value: float) -> void:
			_on_form_changed()
	)
	parent.add_child(field)
	_int_fields[key] = field
	return field


func _add_check(parent: Control, label_text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = label_text
	check.toggled.connect(
		func(_value: bool) -> void:
			_on_form_changed()
	)
	parent.add_child(check)
	return check


func _add_option_field(
	parent: Control,
	label_text: String,
	key: String,
	options: Array
) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := OptionButton.new()
	field.custom_minimum_size = Vector2(150, 32)
	for option_value: Variant in options:
		if not option_value is Dictionary:
			continue
		var option: Dictionary = option_value as Dictionary
		field.add_item(String(option.get("label", "")))
		field.set_item_metadata(
			field.item_count - 1,
			option.get("value", "")
		)
	field.item_selected.connect(
		func(_index: int) -> void:
			_on_form_changed()
	)
	parent.add_child(field)
	_option_fields[key] = field
	return field


func _add_reference_option(
	parent: Control,
	label_text: String,
	key: String,
	options: Array[Dictionary]
) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := OptionButton.new()
	field.custom_minimum_size = Vector2(170, 32)
	field.add_item("—")
	field.set_item_metadata(0, {})

	for option: Dictionary in options:
		var display: String = PlayerReference.display_name(option)
		var source: String = String(option.get("source", ""))
		var item_label: String = (
			"%s · %s" % [display, source]
			if not source.is_empty()
			else display
		)
		field.add_item(item_label)
		field.set_item_metadata(
			field.item_count - 1,
			option.duplicate(true)
		)

	field.item_selected.connect(
		func(_index: int) -> void:
			_on_form_changed()
			if field == _spell_class_selector:
				_refresh_available_spells()
	)
	parent.add_child(field)
	_option_fields[key] = field
	return field


func _add_ability_option(
	parent: Control,
	label_text: String,
	key: String
) -> OptionButton:
	var options: Array = [{"label": "—", "value": ""}]
	for ability: Dictionary in PlayerReference.ABILITIES:
		options.append({
			"label": String(ability.get("name", "")),
			"value": String(ability.get("id", ""))
		})
	return _add_option_field(parent, label_text, key, options)


func _reload_characters() -> void:
	_characters.clear()
	var raw_value: Variant = _store.call("list_characters")
	if raw_value is Array:
		for item: Variant in raw_value:
			if item is Dictionary:
				_characters.append(
					_store.call(
						"normalize_character",
						item as Dictionary
					)
				)
	_refresh_character_list()


func _refresh_character_list(select_id: String = "") -> void:
	_character_list.clear()
	for character: Dictionary in _characters:
		var name: String = String(
			character.get("name", "Personaggio")
		).strip_edges()
		if name.is_empty():
			name = "Personaggio senza nome"

		var linked_token: String = String(
			character.get("linked_token_name", "")
		).strip_edges()
		if not linked_token.is_empty():
			name += "  [↔ %s]" % linked_token

		_character_list.add_item(name)
		_character_list.set_item_metadata(
			_character_list.item_count - 1,
			String(character.get("id", ""))
		)

	if _characters.is_empty():
		_current_index = -1
		_clear_form()
		return

	var target_index := 0
	if not select_id.is_empty():
		for index: int in range(_character_list.item_count):
			if String(_character_list.get_item_metadata(index)) == select_id:
				target_index = index
				break
	elif _current_index >= 0:
		target_index = mini(_current_index, _characters.size() - 1)

	_character_list.select(target_index)
	_on_character_selected(target_index)


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	if not _loading:
		_save_form()
	_current_index = index
	_load_form(_characters[index])


func _load_form(character: Dictionary) -> void:
	_loading = true

	for key: Variant in _text_fields.keys():
		var control: Control = _text_fields[key] as Control
		if control is LineEdit:
			(control as LineEdit).text = String(character.get(key, ""))
		elif control is TextEdit:
			(control as TextEdit).text = String(character.get(key, ""))

	for key: Variant in _int_fields.keys():
		var spin: SpinBox = _int_fields[key] as SpinBox
		if spin != null:
			spin.value = float(character.get(key, 0))

	for key: Variant in _bool_fields.keys():
		var check: CheckButton = _bool_fields[key] as CheckButton
		if check != null:
			check.set_pressed_no_signal(bool(character.get(key, false)))

	for key: Variant in _option_fields.keys():
		var option: OptionButton = _option_fields[key] as OptionButton
		if option == null:
			continue
		_select_option_value(option, String(character.get(key, "")))

	var abilities_value: Variant = character.get("abilities", {})
	var abilities: Dictionary = (
		abilities_value as Dictionary
		if abilities_value is Dictionary
		else {}
	)
	for ability_id: Variant in _ability_spins.keys():
		var ability_spin: SpinBox = _ability_spins[ability_id] as SpinBox
		if ability_spin != null:
			ability_spin.value = int(abilities.get(ability_id, 10))

	var save_proficiencies: Array = character.get(
		"saving_throw_proficiencies",
		[]
	)
	for ability_id: Variant in _save_checks.keys():
		var save_check: CheckButton = _save_checks[ability_id] as CheckButton
		save_check.set_pressed_no_signal(
			String(ability_id) in save_proficiencies
		)

	var skill_proficiencies: Array = character.get(
		"skill_proficiencies",
		[]
	)
	var skill_expertise: Array = character.get(
		"skill_expertise",
		[]
	)
	for skill_id: Variant in _skill_checks.keys():
		var skill_check: CheckButton = _skill_checks[skill_id] as CheckButton
		var expertise_check: CheckButton = (
			_skill_expertise_checks[skill_id] as CheckButton
		)
		skill_check.set_pressed_no_signal(
			String(skill_id) in skill_proficiencies
		)
		expertise_check.set_pressed_no_signal(
			String(skill_id) in skill_expertise
		)

	var total_slots: Array = character.get("spell_slots_total", [])
	var spent_slots: Array = character.get("spell_slots_spent", [])
	for index: int in range(9):
		_slot_total_spins[index].value = (
			int(total_slots[index + 1])
			if total_slots.size() > index + 1
			else 0
		)
		_slot_spent_spins[index].value = (
			int(spent_slots[index + 1])
			if spent_slots.size() > index + 1
			else 0
		)

	var linked_token_name: String = String(
		character.get("linked_token_name", "")
	).strip_edges()
	_linked_token_label.text = (
		"Token collegato: " + linked_token_name
		if not linked_token_name.is_empty()
		else "Token collegato: nessuno"
	)

	_loading = false
	_refresh_derived_values()
	_refresh_selected_spells()
	_refresh_available_spells()


func _save_form() -> void:
	if _loading or _current_index < 0 or _current_index >= _characters.size():
		return

	var character: Dictionary = _characters[_current_index].duplicate(true)

	for key: Variant in _text_fields.keys():
		var control: Control = _text_fields[key] as Control
		if control is LineEdit:
			character[key] = (control as LineEdit).text
		elif control is TextEdit:
			character[key] = (control as TextEdit).text

	for key: Variant in _int_fields.keys():
		var spin: SpinBox = _int_fields[key] as SpinBox
		if spin != null:
			character[key] = int(spin.value)

	for key: Variant in _bool_fields.keys():
		var check: CheckButton = _bool_fields[key] as CheckButton
		if check != null:
			character[key] = check.button_pressed

	for key: Variant in _option_fields.keys():
		var option: OptionButton = _option_fields[key] as OptionButton
		if option == null or option.selected < 0:
			continue
		var metadata: Variant = option.get_item_metadata(option.selected)
		if metadata is Dictionary:
			var data: Dictionary = metadata as Dictionary
			character[key] = String(data.get("name", ""))
			if key == "class":
				character["class_source"] = String(data.get("source", ""))
			elif key == "species":
				character["species_source"] = String(data.get("source", ""))
			elif key == "background":
				character["background_source"] = String(data.get("source", ""))
		else:
			character[key] = String(metadata)

	var abilities: Dictionary = {}
	for ability_id: Variant in _ability_spins.keys():
		var spin: SpinBox = _ability_spins[ability_id] as SpinBox
		abilities[String(ability_id)] = int(spin.value)
	character["abilities"] = abilities

	var save_proficiencies: Array[String] = []
	for ability_id: Variant in _save_checks.keys():
		var save_check: CheckButton = _save_checks[ability_id] as CheckButton
		if save_check.button_pressed:
			save_proficiencies.append(String(ability_id))
	character["saving_throw_proficiencies"] = save_proficiencies

	var skill_proficiencies: Array[String] = []
	var skill_expertise: Array[String] = []
	for skill_id: Variant in _skill_checks.keys():
		var check: CheckButton = _skill_checks[skill_id] as CheckButton
		var expertise_check: CheckButton = (
			_skill_expertise_checks[skill_id] as CheckButton
		)
		if expertise_check.button_pressed and not check.button_pressed:
			check.set_pressed_no_signal(true)
		if check.button_pressed:
			skill_proficiencies.append(String(skill_id))
		if expertise_check.button_pressed:
			skill_expertise.append(String(skill_id))
	character["skill_proficiencies"] = skill_proficiencies
	character["skill_expertise"] = skill_expertise

	var total_slots: Array = [0]
	var spent_slots: Array = [0]
	for index: int in range(9):
		total_slots.append(int(_slot_total_spins[index].value))
		spent_slots.append(int(_slot_spent_spins[index].value))
	character["spell_slots_total"] = total_slots
	character["spell_slots_spent"] = spent_slots

	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_character_list_label(_current_index)
	_refresh_derived_values()


func _on_form_changed() -> void:
	if _loading:
		return
	_save_form()
	_refresh_available_spells()


func _refresh_derived_values() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return

	var level: int = int(_characters[_current_index].get("level", 1))
	var proficiency_bonus: int = PlayerReference.proficiency_bonus(level)
	_proficiency_label.text = "Bonus di competenza: %s" % _signed(
		proficiency_bonus
	)

	for ability_id: Variant in _ability_spins.keys():
		var score: int = int((_ability_spins[ability_id] as SpinBox).value)
		var modifier: int = PlayerReference.ability_modifier(score)
		(_ability_mod_labels[ability_id] as Label).text = _signed(modifier)

		var save_bonus: int = modifier
		if (_save_checks[ability_id] as CheckButton).button_pressed:
			save_bonus += proficiency_bonus
		(_save_value_labels[ability_id] as Label).text = _signed(save_bonus)

	for skill: Dictionary in PlayerReference.SKILLS:
		var skill_id: String = String(skill.get("id", ""))
		var ability_id: String = String(skill.get("ability", ""))
		var ability_spin: SpinBox = _ability_spins.get(ability_id) as SpinBox
		if ability_spin == null:
			continue
		var value: int = PlayerReference.ability_modifier(
			int(ability_spin.value)
		)
		var proficient: bool = (
			_skill_checks[skill_id] as CheckButton
		).button_pressed
		var expertise: bool = (
			_skill_expertise_checks[skill_id] as CheckButton
		).button_pressed
		if expertise:
			value += proficiency_bonus * 2
		elif proficient:
			value += proficiency_bonus
		(_skill_value_labels[skill_id] as Label).text = _signed(value)

	var perception_value: int = PlayerReference.ability_modifier(
		int((_ability_spins["wis"] as SpinBox).value)
	)
	if (_skill_expertise_checks["perception"] as CheckButton).button_pressed:
		perception_value += proficiency_bonus * 2
	elif (_skill_checks["perception"] as CheckButton).button_pressed:
		perception_value += proficiency_bonus
	_passive_perception_label.text = (
		"Percezione passiva: %d" % (10 + perception_value)
	)


func _refresh_character_list_label(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	if index >= _character_list.item_count:
		return
	var character: Dictionary = _characters[index]
	var label: String = String(character.get("name", "Personaggio")).strip_edges()
	if label.is_empty():
		label = "Personaggio senza nome"
	var linked_name: String = String(
		character.get("linked_token_name", "")
	).strip_edges()
	if not linked_name.is_empty():
		label += "  [↔ %s]" % linked_name
	_character_list.set_item_text(index, label)


func _clear_form() -> void:
	_loading = true
	for control_value: Variant in _text_fields.values():
		if control_value is LineEdit:
			(control_value as LineEdit).clear()
		elif control_value is TextEdit:
			(control_value as TextEdit).clear()
	if _linked_token_label != null:
		_linked_token_label.text = "Token collegato: nessuno"
	if _selected_spells != null:
		_selected_spells.clear()
	_loading = false


func _delete_current_character() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return
	var character_id: String = String(
		_characters[_current_index].get("id", "")
	)
	for token: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			token.has_meta("player_character_id")
			and String(token.get_meta("player_character_id")) == character_id
		):
			token.remove_meta("player_character_id")
			token.remove_meta("player_character_name")

	_characters.remove_at(_current_index)
	_current_index = -1
	_store.call("save_characters", _characters)
	_refresh_character_list()
	_set_status("Personaggio eliminato.")


func _confirm_link_character() -> void:
	if _link_token == null or not is_instance_valid(_link_token):
		_set_status("Il token selezionato non è più disponibile.")
		return
	if _link_character_selector.selected < 0:
		return

	var character_id: String = String(
		_link_character_selector.get_item_metadata(
			_link_character_selector.selected
		)
	)
	var character_index: int = _character_index_by_id(character_id)
	if character_index < 0:
		return

	# One character ↔ one token. Clear previous links on both sides first.
	for token: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			token.has_meta("player_character_id")
			and String(token.get_meta("player_character_id")) == character_id
		):
			token.remove_meta("player_character_id")
			token.remove_meta("player_character_name")

	var previous_character_id: String = ""
	if _link_token.has_meta("player_character_id"):
		previous_character_id = String(
			_link_token.get_meta("player_character_id")
		)
	if not previous_character_id.is_empty():
		var previous_index: int = _character_index_by_id(
			previous_character_id
		)
		if previous_index >= 0:
			_characters[previous_index]["linked_token_sync_id"] = ""
			_characters[previous_index]["linked_token_name"] = ""

	var character: Dictionary = _characters[character_index]
	var character_name: String = String(
		character.get("name", "Personaggio")
	)
	_link_token.set_meta("player_character_id", character_id)
	_link_token.set_meta("player_character_name", character_name)

	var sync_id := ""
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null and is_instance_valid(sync):
		if sync.has_method("get_sync_id_for_node"):
			sync_id = String(
				sync.call("get_sync_id_for_node", _link_token)
			)

	character["linked_token_sync_id"] = sync_id
	character["linked_token_name"] = _token_name(_link_token)
	_characters[character_index] = character
	_store.call("save_characters", _characters)

	_current_index = character_index
	_refresh_character_list(character_id)
	_set_status(
		"%s collegato a %s."
		% [character_name, _token_name(_link_token)]
	)
	_link_token = null


func _selected_tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if board_root.has_method("get_selected_tokens_for_player_area"):
		var value: Variant = board_root.call(
			"get_selected_tokens_for_player_area"
		)
		if value is Array:
			for item: Variant in value:
				if item is CharacterBody3D:
					result.append(item as CharacterBody3D)
	return result


func _token_name(token: CharacterBody3D) -> String:
	if token.has_method("get_display_name"):
		var display_name: String = String(
			token.call("get_display_name")
		).strip_edges()
		if not display_name.is_empty():
			return display_name
	return String(token.name)


func _character_index_by_id(character_id: String) -> int:
	for index: int in range(_characters.size()):
		if String(_characters[index].get("id", "")) == character_id:
			return index
	return -1


func _select_option_value(option: OptionButton, value: String) -> void:
	for index: int in range(option.item_count):
		var metadata: Variant = option.get_item_metadata(index)
		var candidate := ""
		if metadata is Dictionary:
			candidate = String((metadata as Dictionary).get("name", ""))
		else:
			candidate = String(metadata)
		if candidate == value:
			option.select(index)
			return
	option.select(0)


func _refresh_available_spells() -> void:
	if _available_spells == null or _spell_class_selector == null:
		return
	_available_spells.clear()
	if _spell_class_selector.selected <= 0:
		return

	var class_metadata: Variant = _spell_class_selector.get_item_metadata(
		_spell_class_selector.selected
	)
	if not class_metadata is Dictionary:
		return
	var class_name: String = String(
		(class_metadata as Dictionary).get("name", "")
	)
	if class_name.is_empty():
		return

	var level := 0
	if _spell_level_selector != null and _spell_level_selector.selected >= 0:
		level = int(
			_spell_level_selector.get_item_metadata(
				_spell_level_selector.selected
			)
		)

	var spells: Array[Dictionary] = SpellCatalog.spells_for_class_and_level(
		class_name,
		level
	)
	for spell: Dictionary in spells:
		var spell_name: String = String(spell.get("name", "Incantesimo"))
		var source: String = String(spell.get("source", ""))
		_available_spells.add_item(
			"%s  ·  %s" % [spell_name, source]
			if not source.is_empty()
			else spell_name
		)
		_available_spells.set_item_metadata(
			_available_spells.item_count - 1,
			{
				"id": String(spell.get("id", "")),
				"name": spell_name,
				"level": level,
				"source": source
			}
		)


func _refresh_selected_spells() -> void:
	if _selected_spells == null:
		return
	_selected_spells.clear()
	if _current_index < 0 or _current_index >= _characters.size():
		return
	var spells_value: Variant = _characters[_current_index].get("spells", [])
	if not spells_value is Array:
		return
	var spells: Array = spells_value as Array
	for spell_value: Variant in spells:
		if not spell_value is Dictionary:
			continue
		var spell: Dictionary = spell_value as Dictionary
		var level: int = int(spell.get("level", 0))
		var level_text: String = (
			"Trucchetto" if level == 0 else "Lv %d" % level
		)
		_selected_spells.add_item(
			"%s · %s" % [
				level_text,
				String(spell.get("name", "Incantesimo"))
			]
		)
		_selected_spells.set_item_metadata(
			_selected_spells.item_count - 1,
			String(spell.get("id", ""))
		)


func _add_selected_spell() -> void:
	if _current_index < 0 or _available_spells == null:
		return
	var selected: PackedInt32Array = _available_spells.get_selected_items()
	if selected.is_empty():
		return

	var metadata: Variant = _available_spells.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return
	var new_spell: Dictionary = (metadata as Dictionary).duplicate(true)
	var new_id: String = String(new_spell.get("id", ""))
	if new_id.is_empty():
		return

	var character: Dictionary = _characters[_current_index]
	var spells_value: Variant = character.get("spells", [])
	var spells: Array = (
		(spells_value as Array).duplicate(true)
		if spells_value is Array
		else []
	)
	for existing_value: Variant in spells:
		if (
			existing_value is Dictionary
			and String((existing_value as Dictionary).get("id", "")) == new_id
		):
			return
	spells.append(new_spell)
	character["spells"] = spells
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_selected_spells()


func _remove_selected_spell() -> void:
	if _current_index < 0 or _selected_spells == null:
		return
	var selected: PackedInt32Array = _selected_spells.get_selected_items()
	if selected.is_empty():
		return
	var spell_id: String = String(
		_selected_spells.get_item_metadata(selected[0])
	)

	var character: Dictionary = _characters[_current_index]
	var spells_value: Variant = character.get("spells", [])
	if not spells_value is Array:
		return
	var spells: Array = (spells_value as Array).duplicate(true)
	for index: int in range(spells.size() - 1, -1, -1):
		var item: Variant = spells[index]
		if (
			item is Dictionary
			and String((item as Dictionary).get("id", "")) == spell_id
		):
			spells.remove_at(index)
			break
	character["spells"] = spells
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_selected_spells()


func _campaign_manager() -> Node:
	return get_node_or_null("/root/CampaignManager")


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _signed(value: int) -> String:
	return "+%d" % value if value >= 0 else str(value)
