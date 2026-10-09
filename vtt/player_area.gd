extends Node

const CharacterStore = preload("res://vtt/player_character_store.gd")
const PlayerReference = preload("res://vtt/player_reference_catalog.gd")
const Player5eToolsCatalog = preload("res://vtt/player_5etools_catalog.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")

const ITEM_DESCRIPTION_URLS := {
	"inventory_mundane": (
		"https://raw.githubusercontent.com/5etools-mirror-3/"
		+ "5etools-src/main/data/items-base.json"
	),
	"inventory_magic": (
		"https://raw.githubusercontent.com/5etools-mirror-3/"
		+ "5etools-src/main/data/items.json"
	),
}

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
var _attack_calculator: RichTextLabel
var _attack_list: ItemList
var _attack_definitions: Array[Dictionary] = []

var _spell_class_selector: OptionButton
var _spell_level_selector: OptionButton
var _catalog_search_fields: Dictionary = {}
var _catalog_available_lists: Dictionary = {}
var _catalog_available_rows: Dictionary = {}
var _catalog_owned_lists: Dictionary = {}
var _catalog_expanded: Dictionary = {}

var _spell_search_input: LineEdit
var _available_spells: ItemList
var _selected_spells: ItemList
var _prepared_spells: ItemList
var _slot_total_spins: Array[SpinBox] = []
var _slot_marker_rows: Array[HBoxContainer] = []
var _slot_spent_values: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0
]

var _name_dialog: ConfirmationDialog
var _name_input: LineEdit
var _name_dialog_mode: String = ""

var _link_dialog: ConfirmationDialog
var _link_info_label: Label
var _link_character_selector: OptionButton
var _link_token: CharacterBody3D

var _character_token_dialog: ConfirmationDialog
var _character_token_info_label: Label
var _character_token_selector: OptionButton

var _catalog_info_dialog: AcceptDialog
var _catalog_info_text: RichTextLabel
var _item_description_request: HTTPRequest
var _item_description_cache: Dictionary = {}
var _item_description_loaded: Dictionary = {}
var _pending_info_entry: Dictionary = {}
var _pending_info_character_key: String = ""
var _description_request_character_key: String = ""


func setup(root: Node3D) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return

	_store = CharacterStore.new()
	_store.call("setup", _campaign_manager())
	_build_ui()
	_build_name_dialog()
	_build_link_dialog()
	_build_character_token_dialog()
	_build_catalog_info_dialog()
	_build_item_description_request()
	_reload_characters()


func _unhandled_input(event: InputEvent) -> void:
	if (
		_panel == null
		or not _panel.visible
		or _player_modal_dialog_visible()
	):
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		hide_panel()
		get_viewport().set_input_as_handled()


func _player_modal_dialog_visible() -> bool:
	for dialog: Window in [
		_name_dialog,
		_link_dialog,
		_character_token_dialog,
		_catalog_info_dialog
	]:
		if dialog != null and is_instance_valid(dialog) and dialog.visible:
			return true
	return false


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


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
	_reload_characters()
	_collapse_all_catalog_sections(false)
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
	show_panel()
	_open_character_name_dialog("create")


func rename_current_character() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		_set_status("Seleziona prima un personaggio.")
		return
	_save_form()
	_open_character_name_dialog("rename")


func _open_character_name_dialog(mode: String) -> void:
	if _name_dialog == null or _name_input == null:
		return

	_name_dialog_mode = mode
	if mode == "rename":
		_name_dialog.title = "Rinomina personaggio"
		_name_dialog.ok_button_text = "Rinomina"
		_name_input.text = String(
			_characters[_current_index].get("name", "")
		)
	else:
		_name_dialog.title = "Aggiungi Personaggio"
		_name_dialog.ok_button_text = "Crea"
		_name_input.clear()

	_name_dialog.reset_size()
	_name_dialog.popup_centered_clamped(Vector2i(440, 190), 0.92)
	_name_input.call_deferred("grab_focus")
	if mode == "rename":
		_name_input.call_deferred("select_all")


func _confirm_character_name() -> void:
	var clean_name: String = _name_input.text.strip_edges()
	if clean_name.is_empty():
		_set_status("Inserisci un nome per il personaggio.")
		return

	if _name_dialog_mode == "create":
		var character: Dictionary = _store.call("create_character")
		character["name"] = clean_name
		_characters.append(character)
		_store.call("save_characters", _characters)
		_refresh_character_list(String(character.get("id", "")))
		_set_status("%s creato." % clean_name)
	elif (
		_name_dialog_mode == "rename"
		and _current_index >= 0
		and _current_index < _characters.size()
	):
		var character_id: String = String(
			_characters[_current_index].get("id", "")
		)
		_characters[_current_index]["name"] = clean_name
		_sync_linked_token_character_name(character_id, clean_name)
		_store.call("save_characters", _characters)
		_refresh_character_list(character_id)
		_set_status("Personaggio rinominato in %s." % clean_name)

	_name_dialog_mode = ""


func request_link_character_to_selected_token() -> void:
	show_panel()
	if _characters.is_empty():
		_set_status("Crea prima un personaggio da associare al token.")
		add_character()
		return

	var selected_tokens: Array[CharacterBody3D] = _selected_tokens()
	if selected_tokens.size() != 1:
		show_panel()
		_set_status(
			"Seleziona esattamente un token, poi scegli il personaggio da associare."
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
	_link_dialog.dialog_text = ""
	if _link_info_label != null:
		_link_info_label.text = (
			"Token selezionato: %s\n"
			+ "Scegli il personaggio da associare."
		) % token_name
	_link_dialog.reset_size()
	_link_dialog.popup_centered_clamped(Vector2i(520, 240), 0.92)


func request_link_selected_character_to_named_token() -> void:
	show_panel()
	if _current_index < 0 or _current_index >= _characters.size():
		_set_status("Seleziona prima un personaggio nell'Area Player.")
		return

	_save_form()
	_character_token_selector.clear()
	var current_character_id: String = String(
		_characters[_current_index].get("id", "")
	)
	var selected_index := 0
	var visible_token_count := 0

	for token: CharacterBody3D in _named_scene_tokens():
		var token_display_name: String = _display_token_name(token)
		if token_display_name.is_empty():
			continue
		_character_token_selector.add_item(token_display_name)
		var item_index: int = _character_token_selector.item_count - 1
		_character_token_selector.set_item_metadata(
			item_index,
			token.get_instance_id()
		)
		visible_token_count += 1

		if (
			token.has_meta("player_character_id")
			and String(token.get_meta("player_character_id"))
			== current_character_id
		):
			selected_index = item_index

	if visible_token_count == 0:
		_set_status(
			"Nello scenario non ci sono token con un nome. "
			+ "Assegna prima un nome al token."
		)
		return

	_character_token_selector.select(selected_index)
	var character_name: String = String(
		_characters[_current_index].get("name", "Personaggio")
	)
	_character_token_dialog.dialog_text = ""
	if _character_token_info_label != null:
		_character_token_info_label.text = (
			"Personaggio selezionato: %s\n"
			+ "Scegli un token con nome presente nello scenario."
		) % character_name
	_character_token_dialog.reset_size()
	_character_token_dialog.popup_centered_clamped(
		Vector2i(520, 250),
		0.92
	)


func character_count() -> int:
	return _characters.size()


func serialize_characters() -> Array[Dictionary]:
	return _characters.duplicate(true)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PlayerAreaPanel"
	# Open from the left toward the centre. The 54 px top inset keeps the
	# whole panel below the runtime toolbar at every viewport size.
	_panel.anchor_left = 0.02
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.62
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 4.0
	_panel.offset_top = 54.0
	_panel.offset_right = -4.0
	_panel.offset_bottom = -8.0
	_panel.clip_contents = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	ui_root.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	# Fully opaque: the game view and encounter HUD must not show through.
	panel_style.bg_color = Color(0.025, 0.028, 0.036, 1.0)
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
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

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
	split.split_offset = 190
	outer.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
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

	var add_button := Button.new()
	add_button.text = "+ Aggiungi"
	add_button.tooltip_text = "Crea un nuovo personaggio e assegnagli subito un nome"
	add_button.pressed.connect(add_character)
	left.add_child(add_button)

	var rename_button := Button.new()
	rename_button.text = "Rinomina"
	rename_button.pressed.connect(rename_current_character)
	left.add_child(rename_button)

	var selected_token_link_button := Button.new()
	selected_token_link_button.text = "Token selezionato → PG"
	selected_token_link_button.tooltip_text = (
		"Associa il token attualmente selezionato a un personaggio"
	)
	selected_token_link_button.pressed.connect(
		request_link_character_to_selected_token
	)
	left.add_child(selected_token_link_button)

	var character_token_link_button := Button.new()
	character_token_link_button.text = "PG → token…"
	character_token_link_button.tooltip_text = (
		"Associa il personaggio selezionato a un token con nome nello scenario"
	)
	character_token_link_button.pressed.connect(
		request_link_selected_character_to_named_token
	)
	left.add_child(character_token_link_button)

	var delete_button := Button.new()
	delete_button.text = "Elimina"
	delete_button.pressed.connect(_delete_current_character)
	left.add_child(delete_button)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_player_tab_changed)
	split.add_child(_tabs)

	_build_identity_tab()
	_build_combat_tab()
	_build_story_tab()
	_build_spells_tab()


func _on_player_tab_changed(_tab: int) -> void:
	_collapse_all_catalog_sections(true)


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
	abilities_grid.columns = 4
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

		var roll_ability := Button.new()
		roll_ability.text = "🎲"
		roll_ability.tooltip_text = (
			"Tira 1d20 usando il modificatore di %s"
			% String(ability.get("name", ability_id))
		)
		roll_ability.custom_minimum_size = Vector2(38, 28)
		roll_ability.pressed.connect(
			_roll_ability_check.bind(
				ability_id,
				String(ability.get("name", ability_id))
			)
		)
		abilities_grid.add_child(roll_ability)

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

	var initiative_roll := Button.new()
	initiative_roll.text = "🎲 Tira iniziativa"
	initiative_roll.tooltip_text = (
		"Lancia 1d20 e usa il modificatore Iniziativa della scheda"
	)
	initiative_roll.pressed.connect(_roll_initiative_from_sheet)
	body.add_child(initiative_roll)

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
		var roll_save := Button.new()
		roll_save.text = "🎲"
		roll_save.custom_minimum_size = Vector2(38, 28)
		roll_save.tooltip_text = (
			"Tira il tiro salvezza su %s"
			% String(ability.get("name", ability_id))
		)
		roll_save.pressed.connect(
			_roll_saving_throw.bind(
				ability_id,
				String(ability.get("name", ability_id))
			)
		)
		saves_grid.add_child(roll_save)

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

		var roll_skill := Button.new()
		roll_skill.text = "🎲"
		roll_skill.custom_minimum_size = Vector2(38, 28)
		roll_skill.tooltip_text = (
			"Tira 1d20 per %s"
			% String(skill.get("name", skill_id))
		)
		roll_skill.pressed.connect(
			_roll_skill_check.bind(
				skill_id,
				String(skill.get("name", skill_id))
			)
		)
		row.add_child(roll_skill)

	_section_title(body, "Attacchi")
	_attack_calculator = RichTextLabel.new()
	_attack_calculator.bbcode_enabled = true
	_attack_calculator.fit_content = true
	_attack_calculator.custom_minimum_size = Vector2(0, 150)
	_attack_calculator.scroll_active = false
	_attack_calculator.text = (
		"Aggiungi un'arma alla scheda per calcolare automaticamente "
		+ "tiro per colpire e danni."
	)
	body.add_child(_attack_calculator)

	_attack_list = ItemList.new()
	_attack_list.custom_minimum_size = Vector2(0, 155)
	_attack_list.select_mode = ItemList.SELECT_SINGLE
	_attack_list.item_activated.connect(
		func(_index: int) -> void:
			_activate_selected_attack()
	)
	body.add_child(_attack_list)

	var attack_actions := HBoxContainer.new()
	attack_actions.add_theme_constant_override("separation", 7)
	body.add_child(attack_actions)

	var roll_attack_button := Button.new()
	roll_attack_button.text = "🎲 Tiro per colpire"
	roll_attack_button.tooltip_text = (
		"Lancia 1d20 con il bonus per colpire dell'attacco selezionato"
	)
	roll_attack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_attack_button.pressed.connect(_roll_selected_attack_hit)
	attack_actions.add_child(roll_attack_button)

	var roll_damage_button := Button.new()
	roll_damage_button.text = "🎲 Danni"
	roll_damage_button.tooltip_text = (
		"Lancia i dadi danno dell'attacco selezionato con il suo modificatore"
	)
	roll_damage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_damage_button.pressed.connect(_roll_selected_attack_damage)
	attack_actions.add_child(roll_damage_button)

	var activate_attack_button := Button.new()
	activate_attack_button.text = "Attiva attacco"
	activate_attack_button.tooltip_text = (
		"Mostra la gittata e usa automaticamente come attaccante "
		+ "il token collegato alla scheda."
	)
	activate_attack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activate_attack_button.pressed.connect(_activate_selected_attack)
	attack_actions.add_child(activate_attack_button)

	_add_multiline_field(
		body,
		"Note attacchi / danni",
		"attacks",
		90
	)
	_add_multiline_field(body, "Munizioni / note", "ammunition", 60)

	_add_5etools_catalog_section(
		body,
		"Armi equipaggiate · catalogo 5e.tools",
		"weapons",
		"weapons_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Armature · catalogo 5e.tools",
		"armor",
		"armor_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Strumenti · catalogo 5e.tools",
		"tools",
		"tools_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Linguaggi · catalogo 5e.tools",
		"languages",
		"languages_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Talenti · catalogo 5e.tools",
		"feats",
		"feats_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Privilegi di classe · catalogo 5e.tools",
		"class_features",
		"class_features_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Tratti razziali / specie · catalogo 5e.tools",
		"species_traits",
		"species_traits_catalog"
	)
	_add_5etools_catalog_section(
		body,
		"Privilegi opzionali · catalogo 5e.tools",
		"optional_features",
		"optional_features_catalog"
	)


func _build_story_tab() -> void:
	var tab := _scroll_tab("Personaggio")
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
	_add_5etools_catalog_section(
		body,
		"Oggetti mondani · Items 5e.tools",
		"mundane_items",
		"inventory_mundane"
	)
	_add_5etools_catalog_section(
		body,
		"Oggetti magici · Items 5e.tools",
		"magic_items",
		"inventory_magic"
	)

	_section_title(body, "Note inventario")
	_add_multiline_field(
		body,
		"Equipaggiamento / quantità / contenitori",
		"equipment",
		100
	)
	_add_multiline_field(
		body,
		"Consumabili / cariche / note",
		"consumables",
		80
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

	var spell_attack_roll := Button.new()
	spell_attack_roll.text = "🎲 Tiro per colpire incantesimo"
	spell_attack_roll.tooltip_text = (
		"Lancia 1d20 con il bonus attacco incantesimi della scheda"
	)
	spell_attack_roll.pressed.connect(_roll_spell_attack_from_sheet)
	body.add_child(spell_attack_roll)

	_section_title(body, "Cerca nel catalogo 5e.tools")

	_spell_search_input = LineEdit.new()
	_spell_search_input.placeholder_text = "Cerca incantesimo per nome..."
	_spell_search_input.clear_button_enabled = true
	_spell_search_input.text_changed.connect(
		func(_query: String) -> void:
			_refresh_available_spells()
	)
	body.add_child(_spell_search_input)

	var filter_hint := Label.new()
	filter_hint.text = (
		"Scrivi un nome per cercare in tutto il catalogo, "
		+ "oppure usa classe e livello per filtrare."
	)
	filter_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filter_hint.add_theme_font_size_override("font_size", 12)
	filter_hint.modulate = Color(0.76, 0.79, 0.86, 1.0)
	body.add_child(filter_hint)

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

	var add_spell_actions := HBoxContainer.new()
	add_spell_actions.add_theme_constant_override("separation", 8)
	body.add_child(add_spell_actions)

	var add_spell_button := Button.new()
	add_spell_button.text = "Aggiungi ai conosciuti"
	add_spell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_spell_button.pressed.connect(_add_selected_spell)
	add_spell_actions.add_child(add_spell_button)

	var prepare_spell_button := Button.new()
	prepare_spell_button.text = "Aggiungi ai preparati"
	prepare_spell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prepare_spell_button.pressed.connect(_add_selected_prepared_spell)
	add_spell_actions.add_child(prepare_spell_button)

	_section_title(body, "Incantesimi conosciuti")
	_selected_spells = ItemList.new()
	_selected_spells.custom_minimum_size = Vector2(0, 150)
	_selected_spells.select_mode = ItemList.SELECT_SINGLE
	_selected_spells.item_activated.connect(
		func(_index: int) -> void:
			_activate_known_spell()
	)
	body.add_child(_selected_spells)

	var known_spell_actions := HBoxContainer.new()
	known_spell_actions.add_theme_constant_override("separation", 8)
	body.add_child(known_spell_actions)

	var activate_spell_button := Button.new()
	activate_spell_button.text = "Attiva incantesimo"
	activate_spell_button.tooltip_text = (
		"Usa automaticamente come caster il token collegato alla scheda"
	)
	activate_spell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activate_spell_button.pressed.connect(_activate_known_spell)
	known_spell_actions.add_child(activate_spell_button)

	var remove_spell_button := Button.new()
	remove_spell_button.text = "Rimuovi"
	remove_spell_button.pressed.connect(_remove_selected_spell)
	known_spell_actions.add_child(remove_spell_button)

	_section_title(body, "Incantesimi preparati")
	_prepared_spells = ItemList.new()
	_prepared_spells.custom_minimum_size = Vector2(0, 150)
	_prepared_spells.select_mode = ItemList.SELECT_SINGLE
	_prepared_spells.item_activated.connect(
		func(_index: int) -> void:
			_activate_prepared_spell()
	)
	body.add_child(_prepared_spells)

	var prepared_actions := HBoxContainer.new()
	prepared_actions.add_theme_constant_override("separation", 8)
	body.add_child(prepared_actions)

	var activate_prepared_button := Button.new()
	activate_prepared_button.text = "Attiva preparato"
	activate_prepared_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activate_prepared_button.pressed.connect(_activate_prepared_spell)
	prepared_actions.add_child(activate_prepared_button)

	var remove_prepared_button := Button.new()
	remove_prepared_button.text = "Rimuovi"
	remove_prepared_button.pressed.connect(_remove_selected_prepared_spell)
	prepared_actions.add_child(remove_prepared_button)

	var clear_prepared_button := Button.new()
	clear_prepared_button.text = "Svuota preparati"
	clear_prepared_button.pressed.connect(_clear_prepared_spells)
	prepared_actions.add_child(clear_prepared_button)

	_section_title(body, "Slot incantesimo")
	var slots_box := VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 5)
	body.add_child(slots_box)

	for level: int in range(1, 10):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		slots_box.add_child(row)

		var level_label := Label.new()
		level_label.text = "Lv %d" % level
		level_label.custom_minimum_size = Vector2(44, 0)
		row.add_child(level_label)

		var total_label := Label.new()
		total_label.text = "Totali"
		row.add_child(total_label)

		var total_spin := SpinBox.new()
		total_spin.min_value = 0
		total_spin.max_value = 20
		total_spin.custom_minimum_size = Vector2(72, 30)
		total_spin.value_changed.connect(
			_on_slot_total_changed.bind(level)
		)
		row.add_child(total_spin)
		_slot_total_spins.append(total_spin)

		var markers := HBoxContainer.new()
		markers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		markers.add_theme_constant_override("separation", 2)
		row.add_child(markers)
		_slot_marker_rows.append(markers)


func _on_slot_total_changed(_value: float, level: int) -> void:
	_refresh_slot_markers(level)
	if not _loading:
		_on_form_changed()


func _refresh_slot_markers(level: int) -> void:
	if level < 1 or level > 9:
		return
	var row_index := level - 1
	if (
		row_index >= _slot_marker_rows.size()
		or row_index >= _slot_total_spins.size()
	):
		return

	var markers: HBoxContainer = _slot_marker_rows[row_index]
	for child: Node in markers.get_children():
		markers.remove_child(child)
		child.queue_free()

	var total := maxi(0, int(_slot_total_spins[row_index].value))
	_slot_spent_values[level] = clampi(
		_slot_spent_values[level],
		0,
		total
	)
	for marker_index: int in range(total):
		var marker := Button.new()
		marker.flat = true
		marker.text = (
			"●"
			if marker_index < _slot_spent_values[level]
			else "○"
		)
		marker.tooltip_text = (
			"Slot usato"
			if marker_index < _slot_spent_values[level]
			else "Slot disponibile"
		)
		marker.custom_minimum_size = Vector2(27, 27)
		marker.pressed.connect(
			_on_slot_marker_pressed.bind(level, marker_index)
		)
		markers.add_child(marker)


func _refresh_all_slot_markers() -> void:
	for level: int in range(1, 10):
		_refresh_slot_markers(level)


func _on_slot_marker_pressed(level: int, marker_index: int) -> void:
	if level < 1 or level > 9:
		return
	var current := _slot_spent_values[level]
	if marker_index < current:
		_slot_spent_values[level] = marker_index
	else:
		_slot_spent_values[level] = marker_index + 1
	_refresh_slot_markers(level)
	_on_form_changed()


func _add_5etools_catalog_section(
	parent: Control,
	title_text: String,
	category: String,
	character_key: String
) -> void:
	_section_title(parent, title_text)

	var search := LineEdit.new()
	search.placeholder_text = "Cerca nel catalogo 5e.tools..."
	search.clear_button_enabled = true
	search.text_changed.connect(
		_on_catalog_search_changed.bind(character_key)
	)
	search.focus_entered.connect(
		_expand_catalog_section.bind(character_key)
	)
	search.gui_input.connect(
		_on_catalog_search_input.bind(character_key)
	)
	parent.add_child(search)
	_catalog_search_fields[character_key] = search

	var available_row := HBoxContainer.new()
	available_row.add_theme_constant_override("separation", 8)
	available_row.hide()
	parent.add_child(available_row)
	_catalog_available_rows[character_key] = available_row
	_catalog_expanded[character_key] = false

	var available := ItemList.new()
	available.custom_minimum_size = Vector2(0, 145)
	available.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	available.select_mode = ItemList.SELECT_SINGLE
	available.item_activated.connect(
		func(_index: int) -> void:
			_show_catalog_info_from_list(
				available,
				character_key
			)
	)
	available_row.add_child(available)
	_catalog_available_lists[character_key] = available
	available.set_meta("catalog_category", category)

	var available_actions := VBoxContainer.new()
	available_actions.custom_minimum_size = Vector2(124, 0)
	available_actions.add_theme_constant_override("separation", 6)
	available_row.add_child(available_actions)

	var info_button := Button.new()
	info_button.text = "ⓘ Info"
	info_button.tooltip_text = "Apri la scheda informativa della voce selezionata"
	info_button.pressed.connect(
		_show_catalog_info_from_list.bind(
			available,
			character_key
		)
	)
	available_actions.add_child(info_button)

	var add_button := Button.new()
	add_button.text = "Aggiungi"
	add_button.pressed.connect(
		_add_catalog_selection.bind(character_key)
	)
	available_actions.add_child(add_button)

	var close_catalog_button := Button.new()
	close_catalog_button.text = "Chiudi catalogo"
	close_catalog_button.tooltip_text = (
		"Nasconde il catalogo e torna a mostrare solo la scheda"
	)
	close_catalog_button.pressed.connect(
		_collapse_catalog_section.bind(character_key, true)
	)
	available_actions.add_child(close_catalog_button)

	var owned_label := Label.new()
	owned_label.text = "Nella scheda"
	owned_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(owned_label)

	var owned_row := HBoxContainer.new()
	owned_row.add_theme_constant_override("separation", 8)
	parent.add_child(owned_row)

	var owned := ItemList.new()
	owned.custom_minimum_size = Vector2(0, 115)
	owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned.select_mode = ItemList.SELECT_SINGLE
	owned.item_activated.connect(
		func(_index: int) -> void:
			_show_catalog_info_from_list(
				owned,
				character_key
			)
	)
	owned_row.add_child(owned)
	_catalog_owned_lists[character_key] = owned

	var owned_actions := VBoxContainer.new()
	owned_actions.custom_minimum_size = Vector2(124, 0)
	owned_actions.add_theme_constant_override("separation", 6)
	owned_row.add_child(owned_actions)

	var owned_info_button := Button.new()
	owned_info_button.text = "ⓘ Info"
	owned_info_button.pressed.connect(
		_show_catalog_info_from_list.bind(
			owned,
			character_key
		)
	)
	owned_actions.add_child(owned_info_button)

	var remove_button := Button.new()
	remove_button.text = "Rimuovi"
	remove_button.pressed.connect(
		_remove_catalog_selection.bind(character_key)
	)
	owned_actions.add_child(remove_button)


func _on_catalog_search_changed(
	_query: String,
	character_key: String
) -> void:
	if bool(_catalog_expanded.get(character_key, false)):
		_refresh_catalog_section(character_key)


func _on_catalog_search_input(
	event: InputEvent,
	character_key: String
) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_collapse_catalog_section(character_key, true)
		get_viewport().set_input_as_handled()


func _expand_catalog_section(character_key: String) -> void:
	_catalog_expanded[character_key] = true
	var row: Control = _catalog_available_rows.get(
		character_key
	) as Control
	if row != null:
		row.show()
	_refresh_catalog_section(character_key)


func _collapse_catalog_section(
	character_key: String,
	clear_search: bool = false
) -> void:
	_catalog_expanded[character_key] = false
	var row: Control = _catalog_available_rows.get(
		character_key
	) as Control
	if row != null:
		row.hide()

	var available: ItemList = _catalog_available_lists.get(
		character_key
	) as ItemList
	if available != null:
		available.clear()

	if clear_search:
		var search: LineEdit = _catalog_search_fields.get(
			character_key
		) as LineEdit
		if search != null:
			search.clear()
			search.release_focus()


func _collapse_all_catalog_sections(
	clear_search: bool = false
) -> void:
	for raw_key: Variant in _catalog_available_lists.keys():
		_collapse_catalog_section(
			String(raw_key),
			clear_search
		)


func _catalog_filters(character_key: String) -> Dictionary:
	var filters: Dictionary = {}
	if _current_index < 0 or _current_index >= _characters.size():
		return filters
	var character: Dictionary = _characters[_current_index]
	if character_key == "class_features_catalog":
		var player_class_name := String(
			character.get("class", "")
		).strip_edges()
		if not player_class_name.is_empty():
			filters["class_name"] = player_class_name
	elif character_key == "species_traits_catalog":
		var species_name := String(character.get("species", "")).strip_edges()
		if not species_name.is_empty():
			filters["species"] = species_name
	return filters


func _refresh_catalog_section(character_key: String) -> void:
	var available: ItemList = _catalog_available_lists.get(
		character_key
	) as ItemList
	var search: LineEdit = _catalog_search_fields.get(
		character_key
	) as LineEdit
	if available == null:
		return

	var is_expanded := bool(
		_catalog_expanded.get(character_key, false)
	)
	var row: Control = _catalog_available_rows.get(
		character_key
	) as Control

	if not is_expanded:
		available.clear()
		if row != null:
			row.hide()
		_refresh_catalog_owned(character_key)
		return

	if row != null:
		row.show()

	var category := String(
		available.get_meta("catalog_category", "")
	)
	var query := search.text if search != null else ""
	var entries: Array[Dictionary] = Player5eToolsCatalog.search(
		category,
		query,
		_catalog_filters(character_key),
		2000
	)

	available.clear()
	for entry: Dictionary in entries:
		available.add_item(
			Player5eToolsCatalog.display_label(entry)
		)
		available.set_item_metadata(
			available.item_count - 1,
			entry.duplicate(true)
		)

	_refresh_catalog_owned(character_key)


func _refresh_catalog_owned(character_key: String) -> void:
	var owned: ItemList = _catalog_owned_lists.get(
		character_key
	) as ItemList
	if owned == null:
		return
	owned.clear()
	if _current_index < 0 or _current_index >= _characters.size():
		return

	var values: Variant = _characters[_current_index].get(
		character_key,
		[]
	)
	if not values is Array:
		return

	for value: Variant in values:
		if not value is Dictionary:
			continue
		var entry: Dictionary = _resolve_catalog_entry(
			character_key,
			value as Dictionary
		)
		owned.add_item(Player5eToolsCatalog.display_label(entry))
		owned.set_item_metadata(
			owned.item_count - 1,
			entry.duplicate(true)
		)


func _catalog_category_for_key(character_key: String) -> String:
	match character_key:
		"weapons_catalog":
			return "weapons"
		"armor_catalog":
			return "armor"
		"tools_catalog":
			return "tools"
		"languages_catalog":
			return "languages"
		"feats_catalog":
			return "feats"
		"class_features_catalog":
			return "class_features"
		"species_traits_catalog":
			return "species_traits"
		"optional_features_catalog":
			return "optional_features"
		"inventory_mundane":
			return "mundane_items"
		"inventory_magic":
			return "magic_items"
	return ""


func _resolve_catalog_entry(
	character_key: String,
	saved_entry: Dictionary
) -> Dictionary:
	var entry_id := String(saved_entry.get("id", ""))
	var category := _catalog_category_for_key(character_key)
	if entry_id.is_empty() or category.is_empty():
		return saved_entry.duplicate(true)

	for candidate: Dictionary in Player5eToolsCatalog.entries(category):
		if String(candidate.get("id", "")) == entry_id:
			return candidate.duplicate(true)
	return saved_entry.duplicate(true)


func _refresh_all_catalog_sections() -> void:
	for raw_key: Variant in _catalog_available_lists.keys():
		_refresh_catalog_section(String(raw_key))


func _add_catalog_selection(character_key: String) -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return
	var available: ItemList = _catalog_available_lists.get(
		character_key
	) as ItemList
	if available == null:
		return
	var selected := available.get_selected_items()
	if selected.is_empty():
		return
	var metadata: Variant = available.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return

	var entry: Dictionary = (metadata as Dictionary).duplicate(true)
	var entry_id := String(entry.get("id", ""))
	var character: Dictionary = _characters[_current_index]
	var raw_values: Variant = character.get(character_key, [])
	var values: Array = (
		(raw_values as Array).duplicate(true)
		if raw_values is Array
		else []
	)
	for existing: Variant in values:
		if (
			existing is Dictionary
			and String((existing as Dictionary).get("id", ""))
			== entry_id
		):
			return
	values.append(entry)
	character[character_key] = values
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_catalog_owned(character_key)
	_refresh_attack_calculator()


func _remove_catalog_selection(character_key: String) -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return
	var owned: ItemList = _catalog_owned_lists.get(
		character_key
	) as ItemList
	if owned == null:
		return
	var selected := owned.get_selected_items()
	if selected.is_empty():
		return
	var selected_metadata: Variant = owned.get_item_metadata(selected[0])
	var entry_id := (
		String((selected_metadata as Dictionary).get("id", ""))
		if selected_metadata is Dictionary
		else String(selected_metadata)
	)

	var character: Dictionary = _characters[_current_index]
	var raw_values: Variant = character.get(character_key, [])
	if not raw_values is Array:
		return
	var values: Array = (raw_values as Array).duplicate(true)
	for index: int in range(values.size() - 1, -1, -1):
		var value: Variant = values[index]
		if (
			value is Dictionary
			and String((value as Dictionary).get("id", ""))
			== entry_id
		):
			values.remove_at(index)
			break
	character[character_key] = values
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_catalog_owned(character_key)
	_refresh_attack_calculator()


func _build_name_dialog() -> void:
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.name = "PlayerCharacterNameDialog"
	_name_dialog.title = "Aggiungi Personaggio"
	_name_dialog.ok_button_text = "Crea"
	_name_dialog.cancel_button_text = "Annulla"
	_name_dialog.min_size = Vector2i(440, 190)
	_name_dialog.add_theme_constant_override("buttons_min_width", 100)
	_name_dialog.add_theme_constant_override("buttons_min_height", 34)
	ui_root.add_child(_name_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(400, 78)
	body.add_theme_constant_override("separation", 8)
	_name_dialog.add_child(body)

	var label := Label.new()
	label.text = "Nome del personaggio"
	body.add_child(label)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Es. Sariel, Tharivol, Brakka…"
	_name_input.max_length = 100
	_name_input.text_submitted.connect(
		func(_value: String) -> void:
			if not _name_input.text.strip_edges().is_empty():
				_name_dialog.get_ok_button().emit_signal("pressed")
	)
	body.add_child(_name_input)
	_name_dialog.confirmed.connect(_confirm_character_name)


func _build_link_dialog() -> void:
	_link_dialog = ConfirmationDialog.new()
	_link_dialog.title = "Token selezionato → personaggio"
	_link_dialog.ok_button_text = "Collega"
	_link_dialog.cancel_button_text = "Annulla"
	_link_dialog.dialog_text = ""
	_link_dialog.min_size = Vector2i(520, 270)
	_link_dialog.add_theme_constant_override("buttons_min_width", 100)
	_link_dialog.add_theme_constant_override("buttons_min_height", 34)
	ui_root.add_child(_link_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(480, 145)
	body.add_theme_constant_override("separation", 10)
	_link_dialog.add_child(body)

	_link_info_label = Label.new()
	_link_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_link_info_label.custom_minimum_size = Vector2(0, 52)
	body.add_child(_link_info_label)

	var label := Label.new()
	label.text = "Personaggio"
	body.add_child(label)

	_link_character_selector = OptionButton.new()
	body.add_child(_link_character_selector)
	_link_dialog.confirmed.connect(_confirm_link_character)


func _build_character_token_dialog() -> void:
	_character_token_dialog = ConfirmationDialog.new()
	_character_token_dialog.name = "CharacterToTokenDialog"
	_character_token_dialog.title = "Personaggio → token"
	_character_token_dialog.ok_button_text = "Collega"
	_character_token_dialog.cancel_button_text = "Annulla"
	_character_token_dialog.dialog_text = ""
	_character_token_dialog.min_size = Vector2i(520, 280)
	_character_token_dialog.add_theme_constant_override("buttons_min_width", 100)
	_character_token_dialog.add_theme_constant_override("buttons_min_height", 34)
	ui_root.add_child(_character_token_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(480, 145)
	body.add_theme_constant_override("separation", 10)
	_character_token_dialog.add_child(body)

	_character_token_info_label = Label.new()
	_character_token_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_character_token_info_label.custom_minimum_size = Vector2(0, 52)
	body.add_child(_character_token_info_label)

	var label := Label.new()
	label.text = "Token nello scenario"
	body.add_child(label)

	_character_token_selector = OptionButton.new()
	body.add_child(_character_token_selector)
	_character_token_dialog.confirmed.connect(
		_confirm_character_token_link
	)


func _build_catalog_info_dialog() -> void:
	_catalog_info_dialog = AcceptDialog.new()
	_catalog_info_dialog.name = "CatalogInfoDialog"
	_catalog_info_dialog.title = "Informazioni 5e.tools"
	_catalog_info_dialog.ok_button_text = "Chiudi"
	_catalog_info_dialog.min_size = Vector2i(560, 520)
	_catalog_info_dialog.add_theme_constant_override("buttons_min_width", 100)
	_catalog_info_dialog.add_theme_constant_override("buttons_min_height", 34)
	ui_root.add_child(_catalog_info_dialog)

	_catalog_info_text = RichTextLabel.new()
	_catalog_info_text.custom_minimum_size = Vector2(520, 410)
	_catalog_info_text.bbcode_enabled = false
	_catalog_info_text.fit_content = false
	_catalog_info_text.scroll_active = true
	_catalog_info_text.selection_enabled = true
	_catalog_info_dialog.add_child(_catalog_info_text)


func _build_item_description_request() -> void:
	_item_description_request = HTTPRequest.new()
	_item_description_request.name = "PlayerItemDescriptionRequest"
	_item_description_request.timeout = 15.0
	ui_root.add_child(_item_description_request)
	_item_description_request.request_completed.connect(
		_on_item_description_request_completed
	)


func _show_catalog_info_from_list(
	list_control: ItemList,
	character_key: String = ""
) -> void:
	if list_control == null:
		return
	var selected := list_control.get_selected_items()
	if selected.is_empty():
		_set_status("Seleziona prima una voce del catalogo.")
		return

	var metadata: Variant = list_control.get_item_metadata(selected[0])
	var entry: Dictionary = {}
	if metadata is Dictionary:
		entry = (metadata as Dictionary).duplicate(true)
	else:
		var wanted_id := String(metadata)
		var category := String(
			list_control.get_meta("catalog_category", "")
		)
		for candidate: Dictionary in Player5eToolsCatalog.entries(category):
			if String(candidate.get("id", "")) == wanted_id:
				entry = candidate
				break

	if entry.is_empty():
		_set_status("Informazioni non disponibili per questa voce.")
		return

	var description: String = _cached_item_description(
		character_key,
		entry
	)
	var needs_description := (
		character_key in ITEM_DESCRIPTION_URLS
		and description.is_empty()
	)
	_show_catalog_info_entry(entry, description, needs_description)
	if needs_description:
		_request_item_description(entry, character_key)


func _show_catalog_info_entry(
	entry: Dictionary,
	description: String = "",
	loading_description: bool = false,
	description_error: String = ""
) -> void:
	_catalog_info_dialog.title = String(
		entry.get("name", "Informazioni 5e.tools")
	)
	var text: String = Player5eToolsCatalog.info_text(
		entry,
		description
	)
	if loading_description:
		text += "\n\nDescrizione:\nCaricamento descrizione…"
	elif not description_error.is_empty():
		text += "\n\nDescrizione:\n" + description_error
	_catalog_info_text.text = text
	_catalog_info_dialog.reset_size()
	_catalog_info_dialog.popup_centered_clamped(
		Vector2i(620, 560),
		0.92
	)


func _cached_item_description(
	character_key: String,
	entry: Dictionary
) -> String:
	var category_cache: Variant = _item_description_cache.get(
		character_key,
		{}
	)
	if not category_cache is Dictionary:
		return ""
	return String(
		(category_cache as Dictionary).get(
			_item_description_key(entry),
			""
		)
	).strip_edges()


func _request_item_description(
	entry: Dictionary,
	character_key: String
) -> void:
	if character_key not in ITEM_DESCRIPTION_URLS:
		return
	_pending_info_entry = entry.duplicate(true)
	_pending_info_character_key = character_key

	if bool(_item_description_loaded.get(character_key, false)):
		var cached := _cached_item_description(character_key, entry)
		if cached.is_empty():
			_show_catalog_info_entry(
				entry,
				"",
				false,
				"Descrizione completa non disponibile per questa voce."
			)
		else:
			_show_catalog_info_entry(entry, cached)
		return

	if _item_description_request == null:
		return
	if _description_request_character_key == character_key:
		return
	if not _description_request_character_key.is_empty():
		_item_description_request.cancel_request()

	_description_request_character_key = character_key
	var error: Error = _item_description_request.request(
		String(ITEM_DESCRIPTION_URLS[character_key])
	)
	if error != OK:
		_description_request_character_key = ""
		_show_catalog_info_entry(
			entry,
			"",
			false,
			"Impossibile caricare la descrizione dalla sorgente 5e.tools."
		)


func _on_item_description_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var requested_key := _description_request_character_key
	_description_request_character_key = ""
	if requested_key.is_empty():
		return

	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code < 200
		or response_code >= 300
	):
		if _pending_info_character_key == requested_key:
			_show_catalog_info_entry(
				_pending_info_entry,
				"",
				false,
				"Descrizione non disponibile: controlla la connessione."
			)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		if _pending_info_character_key == requested_key:
			_show_catalog_info_entry(
				_pending_info_entry,
				"",
				false,
				"Descrizione non disponibile: dati 5e.tools non validi."
			)
		return

	_item_description_cache[requested_key] = (
		_build_item_description_lookup(
			parsed as Dictionary,
			requested_key
		)
	)
	_item_description_loaded[requested_key] = true

	if _pending_info_character_key != requested_key:
		return
	var description := _cached_item_description(
		requested_key,
		_pending_info_entry
	)
	if description.is_empty():
		_show_catalog_info_entry(
			_pending_info_entry,
			"",
			false,
			"Descrizione completa non disponibile per questa voce."
		)
	else:
		_show_catalog_info_entry(_pending_info_entry, description)


func _build_item_description_lookup(
	payload: Dictionary,
	character_key: String
) -> Dictionary:
	var lookup: Dictionary = {}
	var source_key := (
		"baseitem"
		if character_key == "inventory_mundane"
		else "item"
	)
	var raw_items: Variant = payload.get(source_key, [])
	if raw_items is Array:
		for raw_value: Variant in raw_items:
			if not raw_value is Dictionary:
				continue
			var raw_item := raw_value as Dictionary
			var description := (
				Player5eToolsCatalog.description_text_from_raw_item(
					raw_item
				)
			)
			if description.is_empty():
				continue
			lookup[_item_description_key(raw_item)] = description

	# 5e.tools represents some magic-item variants through an itemGroup.
	# Map the shared group text to each concrete item reference as fallback.
	if character_key == "inventory_magic":
		var raw_groups: Variant = payload.get("itemGroup", [])
		if raw_groups is Array:
			for group_value: Variant in raw_groups:
				if not group_value is Dictionary:
					continue
				var group := group_value as Dictionary
				var group_description := (
					Player5eToolsCatalog.description_text_from_raw_item(group)
				)
				if group_description.is_empty():
					continue
				var references: Variant = group.get("items", [])
				if not references is Array:
					continue
				for reference_value: Variant in references:
					var parts := String(reference_value).split("|")
					if parts.is_empty():
						continue
					var referenced := {
						"name": String(parts[0]),
						"source": String(parts[1]) if parts.size() > 1 else ""
					}
					var lookup_key := _item_description_key(referenced)
					if not lookup.has(lookup_key):
						lookup[lookup_key] = group_description
	return lookup


func _item_description_key(entry: Dictionary) -> String:
	return "%s|%s" % [
		String(entry.get("name", "")).strip_edges().to_lower(),
		String(entry.get("source", "")).strip_edges().to_lower()
	]


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
			if key == "class":
				_refresh_catalog_section("class_features_catalog")
			elif key == "species":
				_refresh_catalog_section("species_traits_catalog")
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
	_sync_all_character_health_bars()


func _refresh_character_list(select_id: String = "") -> void:
	_character_list.clear()
	for character: Dictionary in _characters:
		var entry_name: String = String(
			character.get("name", "Personaggio")
		).strip_edges()
		if entry_name.is_empty():
			entry_name = "Personaggio senza nome"

		var linked_token: String = String(
			character.get("linked_token_name", "")
		).strip_edges()
		if not linked_token.is_empty():
			entry_name += "  [↔ %s]" % linked_token

		_character_list.add_item(entry_name)
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
	_collapse_all_catalog_sections(true)
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
		_slot_spent_values[index + 1] = (
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
	_refresh_prepared_spells()
	_refresh_available_spells()
	_refresh_all_slot_markers()
	_refresh_all_catalog_sections()
	_sync_character_health_to_token(character)


func _save_form() -> void:
	if _loading or _current_index < 0 or _current_index >= _characters.size():
		return

	var character: Dictionary = _characters[_current_index].duplicate(true)
	var previous_character_name: String = String(character.get("name", ""))

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
		spent_slots.append(
			clampi(
				_slot_spent_values[index + 1],
				0,
				int(_slot_total_spins[index].value)
			)
		)
	character["spell_slots_total"] = total_slots
	character["spell_slots_spent"] = spent_slots

	_characters[_current_index] = character
	var current_character_name: String = String(character.get("name", ""))
	if current_character_name != previous_character_name:
		_sync_linked_token_character_name(
			String(character.get("id", "")),
			current_character_name
		)
	_store.call("save_characters", _characters)
	_refresh_character_list_label(_current_index)
	_refresh_derived_values()
	_sync_character_health_to_token(character)


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
	_refresh_attack_calculator()


func _refresh_attack_calculator() -> void:
	if _attack_calculator == null:
		return
	if _current_index < 0 or _current_index >= _characters.size():
		_attack_calculator.text = "Nessun personaggio selezionato."
		_attack_definitions.clear()
		if _attack_list != null:
			_attack_list.clear()
		return

	var character: Dictionary = _characters[_current_index]
	var level := clampi(int(character.get("level", 1)), 1, 20)
	var proficiency := PlayerReference.proficiency_bonus(level)
	var strength_mod := _ability_modifier_from_form("str")
	var dexterity_mod := _ability_modifier_from_form("dex")

	var lines: PackedStringArray = []
	lines.append(
		"[b]Bonus competenza:[/b] %s"
		% _signed(proficiency)
	)

	var raw_weapons: Variant = character.get("weapons_catalog", [])
	var weapons: Array[Dictionary] = []
	if raw_weapons is Array:
		for raw_weapon: Variant in raw_weapons:
			if raw_weapon is Dictionary:
				weapons.append(
					_resolve_catalog_entry(
						"weapons_catalog",
						raw_weapon as Dictionary
					)
				)

	if weapons.is_empty():
		lines.append("")
		lines.append(
			"[i]Nessuna arma equipaggiata nella scheda.[/i]"
		)
	else:
		lines.append("")
		lines.append("[b]Armi equipaggiate[/b]")
		for weapon: Dictionary in weapons:
			var ability_id := _weapon_attack_ability(
				weapon,
				strength_mod,
				dexterity_mod
			)
			var ability_mod := (
				dexterity_mod
				if ability_id == "dex"
				else strength_mod
			)
			var attack_bonus := proficiency + ability_mod
			var damage_die := String(
				weapon.get("damage", "")
			).strip_edges()
			if damage_die.is_empty():
				damage_die = "—"
			var damage_text := _damage_expression(
				damage_die,
				ability_mod
			)
			var damage_type := _attack_damage_type(
				String(weapon.get("damage_type", ""))
			)
			if not damage_type.is_empty():
				damage_text += " " + damage_type

			lines.append(
				"• [b]%s[/b] — Colpire %s | Danni %s (%s)"
				% [
					String(weapon.get("name", "Arma")),
					_signed(attack_bonus),
					damage_text,
					"DES" if ability_id == "dex" else "FOR",
				]
			)

	var feature_names := _class_feature_names(character)
	var has_attack_feature := false

	if "sneak attack" in feature_names:
		var eligible_weapon_names: PackedStringArray = []
		for weapon: Dictionary in weapons:
			if _weapon_allows_sneak_attack(weapon):
				eligible_weapon_names.append(
					String(weapon.get("name", "Arma"))
				)
		if not eligible_weapon_names.is_empty():
			if not has_attack_feature:
				lines.append("")
				lines.append("[b]Privilegi offensivi[/b]")
				has_attack_feature = true
			var sneak_dice := ceili(float(level) / 2.0)
			lines.append(
				(
					"• [b]Attacco Furtivo[/b] — +%dd6 una volta per "
					+ "turno con arma idonea (%s)"
				)
				% [
					sneak_dice,
					", ".join(eligible_weapon_names),
				]
			)
		else:
			if not has_attack_feature:
				lines.append("")
				lines.append("[b]Privilegi offensivi[/b]")
				has_attack_feature = true
			lines.append(
				"• [b]Attacco Furtivo[/b] — privilegio presente, "
				+ "ma nessuna arma Finesse/a distanza equipaggiata."
			)

	var has_martial_arts := (
		"martial arts" in feature_names
		or "bonus unarmed strike" in feature_names
		or "flurry of blows" in feature_names
		or "ki-fueled attack" in feature_names
	)
	if has_martial_arts:
		if not has_attack_feature:
			lines.append("")
			lines.append("[b]Privilegi offensivi[/b]")
			has_attack_feature = true

		var martial_mod := maxi(strength_mod, dexterity_mod)
		var martial_ability := (
			"DES" if dexterity_mod >= strength_mod else "FOR"
		)
		var martial_die := _monk_martial_arts_die(
			level,
			String(character.get("rules_version", "2024"))
		)
		var martial_hit := proficiency + martial_mod
		var martial_damage := _damage_expression(
			martial_die,
			martial_mod
		)

		lines.append(
			(
				"• [b]Colpo senz'armi[/b] — Colpire %s | Danni %s "
				+ "contundenti (%s)"
			)
			% [
				_signed(martial_hit),
				martial_damage,
				martial_ability,
			]
		)

		if "bonus unarmed strike" in feature_names:
			lines.append(
				"• [b]Bonus Unarmed Strike[/b] — 1 colpo senz'armi "
				+ "aggiuntivo con gli stessi valori."
			)

		if "flurry of blows" in feature_names:
			var flurry_attacks := 2
			if (
				String(character.get("rules_version", "2024")) == "2024"
				and level >= 10
				and "heightened focus" in feature_names
			):
				flurry_attacks = 3
			lines.append(
				(
					"• [b]Raffica di Colpi[/b] — %d colpi; ciascuno "
					+ "Colpire %s | Danni %s."
				)
				% [
					flurry_attacks,
					_signed(martial_hit),
					martial_damage,
				]
			)

		if "ki-fueled attack" in feature_names:
			lines.append(
				"• [b]Ki-Fueled Attack[/b] — 1 attacco bonus "
				+ "idoneo dopo l'uso di Ki."
			)

	_attack_calculator.text = "\n".join(lines)
	_refresh_attack_actions()


func _refresh_attack_actions() -> void:
	_attack_definitions.clear()
	if _attack_list != null:
		_attack_list.clear()
	if _current_index < 0 or _current_index >= _characters.size():
		return

	var character: Dictionary = _characters[_current_index]
	_attack_definitions = _build_attack_definitions(character)
	if _attack_list == null:
		return

	for attack: Dictionary in _attack_definitions:
		var attack_name := String(attack.get("name", "Attacco"))
		var range_feet := int(round(float(attack.get("range_feet", 5.0))))
		var damage_expression := String(
			attack.get("damage_expression", "0")
		)
		var damage_type := String(attack.get("damage_type", "")).strip_edges()
		var label := "%s · Colpire %s · %d ft · Danni %s" % [
			attack_name,
			_signed(int(attack.get("attack_bonus", 0))),
			range_feet,
			damage_expression,
		]
		if not damage_type.is_empty():
			label += " " + damage_type
		_attack_list.add_item(label)
		_attack_list.set_item_metadata(
			_attack_list.item_count - 1,
			attack.duplicate(true)
		)


func _build_attack_definitions(
	character: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var level := clampi(int(character.get("level", 1)), 1, 20)
	var proficiency := PlayerReference.proficiency_bonus(level)
	var strength_mod := _ability_modifier_from_form("str")
	var dexterity_mod := _ability_modifier_from_form("dex")

	var raw_weapons: Variant = character.get("weapons_catalog", [])
	if raw_weapons is Array:
		for raw_weapon: Variant in raw_weapons:
			if not raw_weapon is Dictionary:
				continue
			var weapon := _resolve_catalog_entry(
				"weapons_catalog",
				raw_weapon as Dictionary
			)
			var ability_id := _weapon_attack_ability(
				weapon,
				strength_mod,
				dexterity_mod
			)
			var ability_mod := (
				dexterity_mod
				if ability_id == "dex"
				else strength_mod
			)
			var damage_die := String(
				weapon.get("damage", "")
			).strip_edges()
			if damage_die.is_empty():
				continue

			var modes: Array[Dictionary] = _weapon_attack_modes(weapon)
			for mode: Dictionary in modes:
				var suffix := String(mode.get("suffix", ""))
				var attack_name := String(
					weapon.get("name", "Arma")
				)
				if not suffix.is_empty():
					attack_name += " " + suffix

				result.append({
					"id": "%s:%s" % [
						String(weapon.get("id", attack_name)),
						String(mode.get("id", "base")),
					],
					"name": attack_name,
					"kind": "weapon",
					"source_id": String(weapon.get("id", "")),
					"range_feet": float(mode.get("range_feet", 5.0)),
					"attack_bonus": proficiency + ability_mod,
					"ability": ability_id,
					"damage_expression": _damage_expression(
						damage_die,
						ability_mod
					),
					"damage_type": _attack_damage_type(
						String(weapon.get("damage_type", ""))
					),
					"sneak_eligible": _weapon_allows_sneak_attack(weapon),
				})

	var feature_names := _class_feature_names(character)

	if "sneak attack" in feature_names:
		var sneak_dice := ceili(float(level) / 2.0)
		var existing_attacks := result.duplicate(true)
		for raw_attack: Variant in existing_attacks:
			if not raw_attack is Dictionary:
				continue
			var base_attack: Dictionary = raw_attack as Dictionary
			if not bool(base_attack.get("sneak_eligible", false)):
				continue
			var sneak_attack := base_attack.duplicate(true)
			sneak_attack["id"] = (
				String(base_attack.get("id", "attack"))
				+ ":sneak"
			)
			sneak_attack["name"] = (
				String(base_attack.get("name", "Attacco"))
				+ " + Attacco Furtivo"
			)
			sneak_attack["kind"] = "sneak_attack"
			sneak_attack["damage_expression"] = (
				String(base_attack.get("damage_expression", "0"))
				+ " + %dd6" % sneak_dice
			)
			result.append(sneak_attack)

	var has_martial_arts := (
		"martial arts" in feature_names
		or "bonus unarmed strike" in feature_names
		or "flurry of blows" in feature_names
		or "ki-fueled attack" in feature_names
	)
	if has_martial_arts:
		var martial_mod := maxi(strength_mod, dexterity_mod)
		var martial_ability := (
			"dex" if dexterity_mod >= strength_mod else "str"
		)
		var martial_die := _monk_martial_arts_die(
			level,
			String(character.get("rules_version", "2024"))
		)
		var base_unarmed := {
			"id": "martial_arts:unarmed",
			"name": "Colpo senz'armi",
			"kind": "unarmed",
			"range_feet": 5.0,
			"attack_bonus": proficiency + martial_mod,
			"ability": martial_ability,
			"damage_expression": _damage_expression(
				martial_die,
				martial_mod
			),
			"damage_type": "contundenti",
			"sneak_eligible": false,
		}
		result.append(base_unarmed)

		if "bonus unarmed strike" in feature_names:
			var bonus_unarmed := base_unarmed.duplicate(true)
			bonus_unarmed["id"] = "martial_arts:bonus_unarmed"
			bonus_unarmed["name"] = "Bonus Unarmed Strike"
			result.append(bonus_unarmed)

		if "flurry of blows" in feature_names:
			var flurry_attacks := 2
			if (
				String(character.get("rules_version", "2024")) == "2024"
				and level >= 10
				and "heightened focus" in feature_names
			):
				flurry_attacks = 3
			var flurry := base_unarmed.duplicate(true)
			flurry["id"] = "martial_arts:flurry"
			flurry["name"] = "Raffica di Colpi"
			flurry["kind"] = "flurry"
			flurry["damage_expression"] = _multiply_die_expression(
				martial_die,
				martial_mod,
				flurry_attacks
			)
			result.append(flurry)

		if "ki-fueled attack" in feature_names:
			var ki_attack := base_unarmed.duplicate(true)
			ki_attack["id"] = "martial_arts:ki_fueled"
			ki_attack["name"] = "Ki-Fueled Attack"
			ki_attack["kind"] = "ki_attack"
			result.append(ki_attack)

	return result


func _weapon_attack_modes(
	weapon: Dictionary
) -> Array[Dictionary]:
	var modes: Array[Dictionary] = []
	var type_code := String(weapon.get("type", "")).split("|")[0]
	var normal_range := _weapon_normal_range_feet(weapon)

	if type_code == "R":
		modes.append({
			"id": "ranged",
			"suffix": "",
			"range_feet": normal_range if normal_range > 0.0 else 5.0,
		})
		return modes

	var melee_range := (
		10.0
		if Player5eToolsCatalog.has_property(weapon, "R")
		else 5.0
	)
	modes.append({
		"id": "melee",
		"suffix": "(mischia)" if normal_range > 0.0 else "",
		"range_feet": melee_range,
	})

	if (
		Player5eToolsCatalog.has_property(weapon, "T")
		and normal_range > 0.0
	):
		modes.append({
			"id": "thrown",
			"suffix": "(lancio)",
			"range_feet": normal_range,
		})
	return modes


func _weapon_normal_range_feet(weapon: Dictionary) -> float:
	var range_text := String(weapon.get("range", "")).strip_edges()
	if range_text.is_empty():
		return 0.0
	var first_part := range_text.split("/")[0].strip_edges()
	if not first_part.is_valid_float():
		return 0.0
	return maxf(0.0, float(first_part))


func _multiply_die_expression(
	die_text: String,
	modifier: int,
	count: int
) -> String:
	var safe_count := maxi(1, count)
	var normalized := die_text.strip_edges().to_lower()
	var d_index := normalized.find("d")
	var dice_expression := normalized
	if d_index > 0:
		var dice_count := int(normalized.substr(0, d_index))
		var sides := normalized.substr(d_index + 1)
		dice_expression = "%dd%s" % [
			maxi(1, dice_count) * safe_count,
			sides,
		]
	return _damage_expression(
		dice_expression,
		modifier * safe_count
	)


func _dice_roller() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null
	var value: Variant = board_root.get("dice_roller_chat")
	if value is Node and is_instance_valid(value):
		return value as Node
	return board_root.get_node_or_null("DiceRollerChat")


func _character_roll_label(action_name: String) -> String:
	var character_name := "Personaggio"
	if _current_index >= 0 and _current_index < _characters.size():
		character_name = String(
			_characters[_current_index].get("name", "Personaggio")
		).strip_edges()
		if character_name.is_empty():
			character_name = "Personaggio"
	return "%s · %s" % [character_name, action_name]


func _roll_sheet_d20(action_name: String, modifier: int) -> void:
	var roller := _dice_roller()
	if roller == null or not roller.has_method("roll_from_sheet"):
		_set_status("Dice roller non disponibile.")
		return
	roller.call(
		"roll_from_sheet",
		_character_roll_label(action_name),
		"d20",
		1,
		modifier,
		"",
		_current_character_token()
	)
	_set_status(
		"%s: 1d20 %s inviato al dice roller."
		% [action_name, _signed(modifier)]
	)


func _roll_ability_check(
	ability_id: String,
	ability_name: String
) -> void:
	_roll_sheet_d20(
		"Prova di %s" % ability_name,
		_ability_modifier_from_form(ability_id)
	)


func _saving_throw_bonus_from_form(ability_id: String) -> int:
	var bonus := _ability_modifier_from_form(ability_id)
	var level := 1
	if _current_index >= 0 and _current_index < _characters.size():
		level = clampi(
			int(_characters[_current_index].get("level", 1)),
			1,
			20
		)
	var check: CheckButton = _save_checks.get(ability_id) as CheckButton
	if check != null and check.button_pressed:
		bonus += PlayerReference.proficiency_bonus(level)
	return bonus


func _roll_saving_throw(
	ability_id: String,
	ability_name: String
) -> void:
	_roll_sheet_d20(
		"Tiro salvezza · %s" % ability_name,
		_saving_throw_bonus_from_form(ability_id)
	)


func _skill_bonus_from_form(skill_id: String) -> int:
	var ability_id := ""
	for skill: Dictionary in PlayerReference.SKILLS:
		if String(skill.get("id", "")) == skill_id:
			ability_id = String(skill.get("ability", ""))
			break
	if ability_id.is_empty():
		return 0

	var bonus := _ability_modifier_from_form(ability_id)
	var level := 1
	if _current_index >= 0 and _current_index < _characters.size():
		level = clampi(
			int(_characters[_current_index].get("level", 1)),
			1,
			20
		)
	var proficiency := PlayerReference.proficiency_bonus(level)
	var proficient: CheckButton = _skill_checks.get(skill_id) as CheckButton
	var expertise: CheckButton = (
		_skill_expertise_checks.get(skill_id) as CheckButton
	)
	if expertise != null and expertise.button_pressed:
		bonus += proficiency * 2
	elif proficient != null and proficient.button_pressed:
		bonus += proficiency
	return bonus


func _roll_skill_check(skill_id: String, skill_name: String) -> void:
	_roll_sheet_d20(
		"Abilità · %s" % skill_name,
		_skill_bonus_from_form(skill_id)
	)


func _roll_initiative_from_sheet() -> void:
	var spin: SpinBox = _int_fields.get("initiative") as SpinBox
	var modifier := int(spin.value) if spin != null else 0
	_roll_sheet_d20("Iniziativa", modifier)


func _roll_spell_attack_from_sheet() -> void:
	var spin: SpinBox = _int_fields.get("spell_attack_bonus") as SpinBox
	var modifier := int(spin.value) if spin != null else 0
	_roll_sheet_d20("Tiro per colpire incantesimo", modifier)


func _selected_attack_definition() -> Dictionary:
	if _attack_list == null:
		return {}
	var selected := _attack_list.get_selected_items()
	if selected.is_empty():
		_set_status("Seleziona prima un attacco.")
		return {}
	var metadata: Variant = _attack_list.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return {}
	return (metadata as Dictionary).duplicate(true)


func _roll_selected_attack_hit() -> void:
	var attack := _selected_attack_definition()
	if attack.is_empty():
		return
	var attack_name := String(attack.get("name", "Attacco"))
	_roll_sheet_d20(
		"Tiro per colpire · %s" % attack_name,
		int(attack.get("attack_bonus", 0))
	)


func _roll_selected_attack_damage() -> void:
	var attack := _selected_attack_definition()
	if attack.is_empty():
		return
	var expression := String(
		attack.get("damage_expression", "")
	).strip_edges()
	if expression.is_empty() or expression == "—":
		_set_status("L'attacco selezionato non ha dadi danno.")
		return

	var roller := _dice_roller()
	if roller == null or not roller.has_method("roll_expression_from_sheet"):
		_set_status("Dice roller non disponibile.")
		return

	var attack_name := String(attack.get("name", "Attacco"))
	var damage_type := String(
		attack.get("damage_type", "")
	).strip_edges()
	var label := "Danni · %s" % attack_name
	if not damage_type.is_empty():
		label += " · " + damage_type
	roller.call(
		"roll_expression_from_sheet",
		_character_roll_label(label),
		expression,
		_current_character_token()
	)
	_set_status(
		"%s: %s inviato al dice roller."
		% [attack_name, expression]
	)


func _activate_selected_attack() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		_set_status("Seleziona prima un personaggio.")
		return
	if _attack_list == null:
		return

	var selected := _attack_list.get_selected_items()
	if selected.is_empty():
		_set_status("Seleziona un attacco.")
		return
	var metadata: Variant = _attack_list.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return
	var attack: Dictionary = (metadata as Dictionary).duplicate(true)

	_save_form()
	var character: Dictionary = _characters[_current_index]
	var character_id := String(character.get("id", ""))
	var attacker: CharacterBody3D = _linked_token_for_character(character_id)
	if attacker == null:
		_set_status(
			"Questo personaggio non ha un token collegato nello scenario."
		)
		return

	var attack_system_value: Variant = board_root.get("attack_system")
	if not attack_system_value is Node:
		_set_status("Sistema attacchi non disponibile.")
		return
	var runtime_attack_system := attack_system_value as Node
	if (
		not is_instance_valid(runtime_attack_system)
		or not runtime_attack_system.has_method("start_attack")
	):
		_set_status("Sistema attacchi non disponibile.")
		return

	hide_panel()
	var started := bool(
		runtime_attack_system.call(
			"start_attack",
			attacker,
			attack
		)
	)
	if not started:
		show_panel()
		_set_status("Impossibile attivare l'attacco selezionato.")


func apply_attack_damage_to_token(
	target: CharacterBody3D,
	damage: int
) -> Dictionary:
	if (
		target == null
		or not is_instance_valid(target)
		or damage < 0
	):
		return {"applied": false}

	var character_id := ""
	if target.has_meta("player_character_id"):
		character_id = String(
			target.get_meta("player_character_id")
		)
	var character_index := _character_index_by_id(character_id)

	if character_index >= 0:
		var character: Dictionary = _characters[character_index]
		var remaining_damage := damage
		var temporary_hp := maxi(
			0,
			int(character.get("temporary_hp", 0))
		)
		if temporary_hp > 0 and remaining_damage > 0:
			var absorbed := mini(temporary_hp, remaining_damage)
			temporary_hp -= absorbed
			remaining_damage -= absorbed

		var max_hp := maxi(0, int(character.get("max_hp", 0)))
		var current_hp := clampi(
			int(character.get("current_hp", max_hp)),
			0,
			max_hp
		)
		current_hp = maxi(0, current_hp - remaining_damage)

		character["temporary_hp"] = temporary_hp
		character["current_hp"] = current_hp
		_characters[character_index] = character
		_store.call("save_characters", _characters)
		_sync_character_health_to_token(character)

		if character_index == _current_index:
			_loading = true
			var hp_spin: SpinBox = _int_fields.get(
				"current_hp"
			) as SpinBox
			if hp_spin != null:
				hp_spin.value = current_hp
			var temp_spin: SpinBox = _int_fields.get(
				"temporary_hp"
			) as SpinBox
			if temp_spin != null:
				temp_spin.value = temporary_hp
			_loading = false

		return {
			"applied": true,
			"current_hp": current_hp,
			"max_hp": max_hp,
			"temporary_hp": temporary_hp,
		}

	if target.has_method("get_player_hit_points"):
		var hp_value: Variant = target.call("get_player_hit_points")
		if hp_value is Dictionary:
			var hp_data: Dictionary = hp_value as Dictionary
			var max_hp := maxi(0, int(hp_data.get("max", 0)))
			if max_hp > 0:
				var current_hp := clampi(
					int(hp_data.get("current", max_hp)) - damage,
					0,
					max_hp
				)
				if target.has_method("set_player_hit_points"):
					target.call(
						"set_player_hit_points",
						current_hp,
						max_hp
					)
				return {
					"applied": true,
					"current_hp": current_hp,
					"max_hp": max_hp,
					"temporary_hp": 0,
				}

	return {"applied": false}


func _ability_modifier_from_form(ability_id: String) -> int:
	var spin: SpinBox = _ability_spins.get(ability_id) as SpinBox
	if spin == null:
		return 0
	return PlayerReference.ability_modifier(int(spin.value))


func _weapon_attack_ability(
	weapon: Dictionary,
	strength_mod: int,
	dexterity_mod: int
) -> String:
	var type_code := String(weapon.get("type", "")).split("|")[0]
	if type_code == "R":
		return "dex"
	if Player5eToolsCatalog.has_property(weapon, "F"):
		return "dex" if dexterity_mod >= strength_mod else "str"
	return "str"


func _weapon_allows_sneak_attack(weapon: Dictionary) -> bool:
	var type_code := String(weapon.get("type", "")).split("|")[0]
	return (
		type_code == "R"
		or Player5eToolsCatalog.has_property(weapon, "F")
	)


func _class_feature_names(character: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var value: Variant = character.get("class_features_catalog", [])
	if not value is Array:
		return result
	for raw_feature: Variant in value:
		if not raw_feature is Dictionary:
			continue
		var feature_name := String(
			(raw_feature as Dictionary).get("name", "")
		).strip_edges().to_lower()
		if not feature_name.is_empty() and feature_name not in result:
			result.append(feature_name)
	return result


func _monk_martial_arts_die(
	level: int,
	rules_version: String
) -> String:
	if rules_version == "2014":
		if level < 5:
			return "1d4"
		if level < 11:
			return "1d6"
		if level < 17:
			return "1d8"
		return "1d10"

	if level < 5:
		return "1d6"
	if level < 11:
		return "1d8"
	if level < 17:
		return "1d10"
	return "1d12"


func _damage_expression(die_text: String, modifier: int) -> String:
	if modifier > 0:
		return "%s + %d" % [die_text, modifier]
	if modifier < 0:
		return "%s - %d" % [die_text, absi(modifier)]
	return die_text


func _attack_damage_type(code: String) -> String:
	match code.strip_edges().to_upper():
		"B":
			return "contundenti"
		"P":
			return "perforanti"
		"S":
			return "taglienti"
	return ""


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
	if _prepared_spells != null:
		_prepared_spells.clear()
	for owned_value: Variant in _catalog_owned_lists.values():
		if owned_value is ItemList:
			(owned_value as ItemList).clear()
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
			if token.has_method("clear_player_hit_points"):
				token.call("clear_player_hit_points")
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

	_link_character_to_token(character_index, _link_token)
	_link_token = null


func _confirm_character_token_link() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return
	if _character_token_selector.selected < 0:
		return

	var instance_id: int = int(
		_character_token_selector.get_item_metadata(
			_character_token_selector.selected
		)
	)
	var token_value: Object = instance_from_id(instance_id)
	if not token_value is CharacterBody3D:
		_set_status("Il token scelto non è più disponibile.")
		return

	_link_character_to_token(
		_current_index,
		token_value as CharacterBody3D
	)


func _link_character_to_token(
	character_index: int,
	token: CharacterBody3D
) -> void:
	if (
		character_index < 0
		or character_index >= _characters.size()
		or token == null
		or not is_instance_valid(token)
	):
		return
	if token.has_meta("master_creature_id"):
		_set_status(
			"Questo token è già collegato a una creatura dell'Area Master."
		)
		return

	_save_form()
	var character_id: String = String(
		_characters[character_index].get("id", "")
	)

	# One character ↔ one token. Detach this character from any old token.
	for scene_token: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			scene_token.has_meta("player_character_id")
			and String(scene_token.get_meta("player_character_id"))
			== character_id
		):
			if scene_token.has_method("clear_player_hit_points"):
				scene_token.call("clear_player_hit_points")
			scene_token.remove_meta("player_character_id")
			scene_token.remove_meta("player_character_name")

	# If the target token belonged to another character, clear that sheet.
	var previous_character_id := ""
	if token.has_meta("player_character_id"):
		previous_character_id = String(
			token.get_meta("player_character_id")
		)
	if (
		not previous_character_id.is_empty()
		and previous_character_id != character_id
	):
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
	token.set_meta("player_character_id", character_id)
	token.set_meta("player_character_name", character_name)

	var sync_id := ""
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null and is_instance_valid(sync):
		if sync.has_method("get_sync_id_for_node"):
			sync_id = String(
				sync.call("get_sync_id_for_node", token)
			)

	character["linked_token_sync_id"] = sync_id
	character["linked_token_name"] = _token_name(token)
	_characters[character_index] = character
	_store.call("save_characters", _characters)
	_sync_character_health_to_token(character)

	_current_index = character_index
	_loading = true
	_refresh_character_list(character_id)
	_loading = false
	_set_status(
		"%s collegato a %s."
		% [character_name, _token_name(token)]
	)


func _sync_linked_token_character_name(
	character_id: String,
	character_name: String
) -> void:
	if character_id.is_empty():
		return
	for token: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			token.has_meta("player_character_id")
			and String(token.get_meta("player_character_id"))
			== character_id
		):
			token.set_meta("player_character_name", character_name)


func _named_scene_tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if board_root == null or not is_instance_valid(board_root):
		return result

	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and board_root.is_ancestor_of(node)
			and not _display_token_name(node as CharacterBody3D).is_empty()
		):
			result.append(node as CharacterBody3D)

	result.sort_custom(
		func(a: CharacterBody3D, b: CharacterBody3D) -> bool:
			return _display_token_name(a).naturalnocasecmp_to(
				_display_token_name(b)
			) < 0
	)
	return result


func _display_token_name(token: CharacterBody3D) -> String:
	if token != null and is_instance_valid(token):
		if token.has_method("get_display_name"):
			return String(token.call("get_display_name")).strip_edges()
	return ""


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
	var display_name: String = _display_token_name(token)
	if not display_name.is_empty():
		return display_name
	return "Token senza nome"


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
	if _available_spells == null:
		return
	_available_spells.clear()

	var query := ""
	if _spell_search_input != null:
		query = _spell_search_input.text.strip_edges().to_lower()

	var spells: Array[Dictionary] = []
	if not query.is_empty():
		for spell: Dictionary in SpellCatalog.all_spells():
			var spell_name: String = String(
				spell.get("name", "")
			).to_lower()
			if query in spell_name:
				spells.append(spell)
				if spells.size() >= 100:
					break
	else:
		if _spell_class_selector == null or _spell_class_selector.selected <= 0:
			return

		var class_metadata: Variant = _spell_class_selector.get_item_metadata(
			_spell_class_selector.selected
		)
		if not class_metadata is Dictionary:
			return
		var selected_class_name: String = String(
			(class_metadata as Dictionary).get("name", "")
		)
		if selected_class_name.is_empty():
			return

		var level := 0
		if (
			_spell_level_selector != null
			and _spell_level_selector.selected >= 0
		):
			level = int(
				_spell_level_selector.get_item_metadata(
					_spell_level_selector.selected
				)
			)
		spells = SpellCatalog.spells_for_class_and_level(
			selected_class_name,
			level
		)

	for spell: Dictionary in spells:
		var spell_name: String = String(
			spell.get("name", "Incantesimo")
		)
		var source: String = String(spell.get("source", ""))
		var level: int = int(spell.get("level", 0))
		var level_text := (
			"Trucchetto" if level == 0 else "Lv %d" % level
		)
		_available_spells.add_item(
			"%s · %s%s" % [
				level_text,
				spell_name,
				(" · " + source) if not source.is_empty() else ""
			]
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
	_refresh_spell_list(_selected_spells, "spells")


func _refresh_prepared_spells() -> void:
	_refresh_spell_list(_prepared_spells, "prepared_spells")


func _refresh_spell_list(
	list_control: ItemList,
	character_key: String
) -> void:
	if list_control == null:
		return
	list_control.clear()
	if _current_index < 0 or _current_index >= _characters.size():
		return

	var spells_value: Variant = _characters[_current_index].get(
		character_key,
		[]
	)
	if not spells_value is Array:
		return

	for spell_value: Variant in spells_value:
		if not spell_value is Dictionary:
			continue
		var spell: Dictionary = spell_value as Dictionary
		var level: int = int(spell.get("level", 0))
		var level_text := (
			"Trucchetto" if level == 0 else "Lv %d" % level
		)
		list_control.add_item(
			"%s · %s" % [
				level_text,
				String(spell.get("name", "Incantesimo"))
			]
		)
		list_control.set_item_metadata(
			list_control.item_count - 1,
			String(spell.get("id", ""))
		)


func _add_selected_spell() -> void:
	_add_selected_spell_to("spells")


func _add_selected_prepared_spell() -> void:
	_add_selected_spell_to("prepared_spells")


func _add_selected_spell_to(character_key: String) -> void:
	if _current_index < 0 or _available_spells == null:
		return
	var selected: PackedInt32Array = _available_spells.get_selected_items()
	if selected.is_empty():
		return

	var metadata: Variant = _available_spells.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return
	var new_spell: Dictionary = (metadata as Dictionary).duplicate(true)
	var new_id := String(new_spell.get("id", ""))
	if new_id.is_empty():
		return

	var character: Dictionary = _characters[_current_index]
	var raw_value: Variant = character.get(character_key, [])
	var spells: Array = (
		(raw_value as Array).duplicate(true)
		if raw_value is Array
		else []
	)
	for existing_value: Variant in spells:
		if (
			existing_value is Dictionary
			and String((existing_value as Dictionary).get("id", ""))
			== new_id
		):
			return

	spells.append(new_spell)
	character[character_key] = spells
	_characters[_current_index] = character
	_store.call("save_characters", _characters)

	if character_key == "prepared_spells":
		_refresh_prepared_spells()
	else:
		_refresh_selected_spells()


func _activate_known_spell() -> void:
	_activate_spell_from_sheet(_selected_spells, "spells")


func _activate_prepared_spell() -> void:
	_activate_spell_from_sheet(_prepared_spells, "prepared_spells")


func _activate_spell_from_sheet(
	list_control: ItemList,
	character_key: String
) -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		_set_status("Seleziona prima un personaggio.")
		return
	if list_control == null:
		return

	var selected := list_control.get_selected_items()
	if selected.is_empty():
		_set_status("Seleziona un incantesimo.")
		return

	_save_form()
	var character: Dictionary = _characters[_current_index]
	var character_id := String(character.get("id", ""))
	var caster: CharacterBody3D = _linked_token_for_character(character_id)
	if caster == null:
		_set_status(
			"Questo personaggio non ha un token collegato nello scenario."
		)
		return

	var spell_id := String(list_control.get_item_metadata(selected[0]))
	var spell_data: Dictionary = {}
	var raw_spells: Variant = character.get(character_key, [])
	if raw_spells is Array:
		for item: Variant in raw_spells:
			if (
				item is Dictionary
				and String((item as Dictionary).get("id", "")) == spell_id
			):
				spell_data = (item as Dictionary).duplicate(true)
				break
	if spell_data.is_empty():
		_set_status("Incantesimo non trovato nella scheda.")
		return

	var spell_level := int(spell_data.get("level", 0))
	if spell_level > 0:
		if spell_level > 9:
			_set_status("Livello incantesimo non valido per gli slot.")
			return
		var total_slots := int(_slot_total_spins[spell_level - 1].value)
		var spent_slots := _slot_spent_values[spell_level]
		if total_slots <= spent_slots:
			_set_status(
				"Nessuno slot di livello %d disponibile." % spell_level
			)
			return

	var spell_system_value: Variant = board_root.get("spell_system")
	if not spell_system_value is Node:
		_set_status("Sistema incantesimi non disponibile.")
		return
	var runtime_spell_system: Node = spell_system_value as Node
	if (
		not is_instance_valid(runtime_spell_system)
		or not runtime_spell_system.has_method(
			"activate_spell_from_caster"
		)
	):
		_set_status("Sistema incantesimi non disponibile.")
		return

	# The sheet closes before targeting so it cannot intercept clicks.
	hide_panel()
	var activated := bool(
		runtime_spell_system.call(
			"activate_spell_from_caster",
			spell_id,
			caster,
			String(spell_data.get("name", "")),
			String(spell_data.get("source", ""))
		)
	)
	if not activated:
		show_panel()
		_set_status(
			"L'incantesimo è nella scheda, ma il suo effetto VTT "
			+ "non è disponibile nel catalogo runtime corrente."
		)
		return

	if spell_level > 0:
		_consume_spell_slot(spell_level)


func _consume_spell_slot(level: int) -> void:
	if (
		level < 1
		or level > 9
		or _current_index < 0
		or _current_index >= _characters.size()
	):
		return
	var total := int(_slot_total_spins[level - 1].value)
	if _slot_spent_values[level] >= total:
		return

	_slot_spent_values[level] += 1
	var character: Dictionary = _characters[_current_index]
	var raw_slots: Variant = character.get("spell_slots_spent", [])
	var spent_slots: Array = (
		(raw_slots as Array).duplicate(true)
		if raw_slots is Array
		else []
	)
	while spent_slots.size() < 10:
		spent_slots.append(0)
	spent_slots[level] = _slot_spent_values[level]
	character["spell_slots_spent"] = spent_slots
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	_refresh_slot_markers(level)


func _current_character_token() -> CharacterBody3D:
	if _current_index < 0 or _current_index >= _characters.size():
		return null
	return _linked_token_for_character(
		String(_characters[_current_index].get("id", ""))
	)


func _linked_token_for_character(
	character_id: String
) -> CharacterBody3D:
	if character_id.is_empty():
		return null
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and board_root.is_ancestor_of(node)
			and node.has_meta("player_character_id")
			and String(node.get_meta("player_character_id"))
			== character_id
		):
			return node as CharacterBody3D
	return null


func _remove_selected_spell() -> void:
	_remove_spell_from_sheet(_selected_spells, "spells")


func _remove_selected_prepared_spell() -> void:
	_remove_spell_from_sheet(_prepared_spells, "prepared_spells")


func _remove_spell_from_sheet(
	list_control: ItemList,
	character_key: String
) -> void:
	if _current_index < 0 or list_control == null:
		return
	var selected := list_control.get_selected_items()
	if selected.is_empty():
		return
	var spell_id := String(list_control.get_item_metadata(selected[0]))

	var character: Dictionary = _characters[_current_index]
	var raw_spells: Variant = character.get(character_key, [])
	if not raw_spells is Array:
		return
	var spells: Array = (raw_spells as Array).duplicate(true)
	for index: int in range(spells.size() - 1, -1, -1):
		var item: Variant = spells[index]
		if (
			item is Dictionary
			and String((item as Dictionary).get("id", "")) == spell_id
		):
			spells.remove_at(index)
			break

	character[character_key] = spells
	_characters[_current_index] = character
	_store.call("save_characters", _characters)
	if character_key == "prepared_spells":
		_refresh_prepared_spells()
	else:
		_refresh_selected_spells()


func _clear_prepared_spells() -> void:
	if _current_index < 0 or _current_index >= _characters.size():
		return
	_characters[_current_index]["prepared_spells"] = []
	_store.call("save_characters", _characters)
	_refresh_prepared_spells()


func _sync_character_health_to_token(character: Dictionary) -> void:
	var character_id := String(character.get("id", ""))
	var token: CharacterBody3D = _linked_token_for_character(character_id)
	if token == null:
		return
	if token.has_method("set_player_hit_points"):
		token.call(
			"set_player_hit_points",
			int(character.get("current_hp", 0)),
			int(character.get("max_hp", 0))
		)


func _sync_all_character_health_bars() -> void:
	for character: Dictionary in _characters:
		_sync_character_health_to_token(character)


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for character: Dictionary in _characters:
		var token_id := String(
			character.get("linked_token_sync_id", "")
		).strip_edges()
		if token_id.is_empty():
			continue
		var max_hp := maxi(0, int(character.get("max_hp", 0)))
		if max_hp <= 0:
			continue
		var current_hp := clampi(
			int(character.get("current_hp", 0)),
			0,
			max_hp
		)
		entries.append({
			"token_id": token_id,
			"percent": clampf(
				float(current_hp) / float(max_hp) * 100.0,
				0.0,
				100.0
			)
		})
	return entries


func _clear_character_health_from_token(character_id: String) -> void:
	var token: CharacterBody3D = _linked_token_for_character(character_id)
	if token != null and token.has_method("clear_player_hit_points"):
		token.call("clear_player_hit_points")



func _campaign_manager() -> Node:
	return get_node_or_null("/root/CampaignManager")


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _signed(value: int) -> String:
	return "+%d" % value if value >= 0 else str(value)
