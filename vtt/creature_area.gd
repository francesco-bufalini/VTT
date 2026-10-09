extends Node

# Reusable creature sheet for players and GMs. No role-specific permissions.
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const Archive = preload("res://vtt/creature_archive.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const DiceRoller = preload("res://vtt/dice_roller_chat.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const Bestiary = preload("res://vtt/bestiary_5etools_client.gd")
const PlayerReference = preload("res://vtt/player_reference_catalog.gd")
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")

var board_root: Node3D
var _archive
var _client: Node
var _records: Array[Dictionary] = []
var _selected_id := ""
var _selected_kind := ""
var _catalog: Array[Dictionary] = []
var _filtered_catalog: Array[Dictionary] = []
var _loading := false

var _panel: PanelContainer
var _status: Label
var _creature_list: VBoxContainer
var _creature_list_scroll: ScrollContainer
var _creature_row_buttons: Array[Button] = []
var _creature_eye_buttons: Array[Button] = []
var _creature_presence_elapsed := 0.0
var _creature_context_menu: PopupMenu
var _automatic_dialog: ConfirmationDialog
var _automatic_hp: CheckBox
var _automatic_proficiency: CheckBox
var _automatic_spells: CheckBox
var _automatic_preview: RichTextLabel
var _automatic_target_id := ""
var _delete_dialog: ConfirmationDialog
var _delete_target: Dictionary = {}
var _catalog_list: ItemList
var _catalog_filter: LineEdit
var _name: LineEdit
var _hp: SpinBox
var _max_hp: SpinBox
var _temp_hp: SpinBox
var _hp_delta_dialog: ConfirmationDialog
var _hp_delta_sign := -1
var _hp_delta_amount: SpinBox
var _hp_amount_row: HBoxContainer
var _hp_use_dice: CheckBox
var _hp_dice_formula: LineEdit
var _hp_quick_dice_row: HBoxContainer
var _hp_formula_status: Label
var _size_choice: OptionButton
var _reach: SpinBox
var _front: OptionButton
var _party: LineEdit
var _tabs: TabContainer
var _ac: SpinBox
var _ability_spins: Dictionary = {}
var _species: OptionButton
var _class_name: OptionButton
var _rules_edition: OptionButton
var _multiclass_rows: VBoxContainer
var _multiclass_controls: Array[Dictionary] = []
var _level: SpinBox
var _feats: TextEdit
var _default_miniature: LineEdit
var _default_miniature_id := ""
var _miniature_dialog: ConfirmationDialog
var _miniature_hint: Label
var _miniature_filter: LineEdit
var _miniature_list: ItemList
var _miniature_choices: Array[Dictionary] = []
var _visible_miniatures: Array[Dictionary] = []
var _pending_miniature_record: Dictionary = {}
var _pending_new_creature := false
var _picker_current := false
var _chosen_miniature_id := ""
var _current_miniature: Label
var _reference: RichTextLabel
var _condition_rows: VBoxContainer
var _effect_dialog: AcceptDialog
var _effect_text: RichTextLabel
var _owner_target: LineEdit
var _options_menu: MenuButton
var _transfer_dialog: ConfirmationDialog
var _feat_dialog: ConfirmationDialog
var _feat_filter: LineEdit
var _feat_list: ItemList
var _feat_details: RichTextLabel
var _visible_feats: Array[Dictionary] = []
var _suggested_miniature_ids: Array[String] = []
var _import_dialog: AcceptDialog
var _import_text: TextEdit
var _auto_reference_requests: Dictionary = {}


func setup(root: Node3D) -> void:
	board_root = root
	_archive = Archive.new()
	_archive.setup(get_node_or_null("/root/CampaignManager"))
	_client = Bestiary.new()
	_client.name = "CreatureBestiary"
	add_child(_client)
	_client.call("setup")
	_client.catalog_ready.connect(_on_catalog_ready)
	_client.creature_ready.connect(_on_monster_received)
	_client.catalog_failed.connect(func(message: String) -> void: _set_status(message))
	_client.creature_failed.connect(_on_creature_request_failed)
	_build_ui()
	_build_miniature_dialog()
	_build_transfer_dialog()
	_build_transfer_request_dialog()
	_build_feat_dialog()
	_reload()
	if DisplayServer.get_name() != "headless":
		_client.call("load_catalog")
	_on_catalog_ready(ContentCatalog.home_entries("monsters"))
	call_deferred("refresh_owned_sheets")


# Token context menu and the archive open the very same persistent sheet.
# Non-owned / unlinked tokens retain their standalone visual editor.
func open_for_token(token: CharacterBody3D) -> bool:
	if token == null or not is_instance_valid(token):
		return false
	var wanted_id := String(token.get_meta("creature_id", ""))
	if wanted_id.is_empty() or String(token.get_meta("creature_owner_id", "")) != Owner.local_id():
		return false
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != wanted_id:
			continue
		_selected_id = wanted_id
		_selected_kind = String(record.get("kind", ""))
		show_panel()
		return true
	return false


func sync_linked_token_editor(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	var wanted_id := String(token.get_meta("creature_id", ""))
	if wanted_id.is_empty() or String(token.get_meta("creature_owner_id", "")) != Owner.local_id():
		return
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != wanted_id:
			continue
		if token.has_method("get_conditions"):
			record["conditions"] = token.call("get_conditions")
		if token.has_method("get_display_name"):
			record["name"] = token.call("get_display_name")
		if token.has_method("get_token_pack_id"):
			var live_id := String(token.call("get_token_pack_id"))
			if not live_id.is_empty():
				record["current_miniature_id"] = live_id
		if token.has_method("get_size_name"):
			record["size_name"] = token.call("get_size_name")
		if token.has_method("get_footprint_cells"):
			record["footprint"] = token.call("get_footprint_cells")
		if token.has_method("get_reach_feet"):
			record["reach_feet"] = token.call("get_reach_feet")
		if token.has_method("get_visual_front_quarter_turns"):
			record["visual_front_quarter_turns"] = token.call("get_visual_front_quarter_turns")
		if token.has_method("get_party_id"):
			record["party_id"] = token.call("get_party_id")
		if _archive.save(record) == OK:
			_replace_current_record(record)
			if _panel.visible and _selected_id == wanted_id:
				_load_form(record)
		return


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func get_owned_creature_names(excluded_id: String = "") -> Array[String]:
	var names: Array[String] = []
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) == excluded_id:
			continue
		var record_name: String = String(record.get("name", "")).strip_edges()
		if not record_name.is_empty():
			names.append(record_name)
	return names


func find_linked_token_for_creature(creature_id: String) -> CharacterBody3D:
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != creature_id:
			continue
		var linked: CharacterBody3D = _find_linked_token(record) as CharacterBody3D
		if linked != null:
			return linked
		# A restored map may assign a new board sync ID while preserving the
		# creature ID on the token: do not create a duplicate in that case.
		for node: Node in get_tree().get_nodes_in_group("dnd_token"):
			if (
				node is CharacterBody3D
				and board_root.is_ancestor_of(node)
				and String(node.get_meta("creature_id", "")) == creature_id
				and String(node.get_meta("creature_owner_id", "")) == Owner.local_id()
			):
				return node as CharacterBody3D
	return null


func link_spawned_token(token: CharacterBody3D, creature_id: String) -> void:
	if token == null or not is_instance_valid(token):
		return
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != creature_id:
			continue
		# The generator reserves unique names against both live tokens and
		# owned sheets. Keep the persistent sheet consistent with that name.
		var placed_name: String = String(token.call("get_display_name")).strip_edges()
		if not placed_name.is_empty() and placed_name != String(record.get("name", "")):
			record["name"] = placed_name
			if _archive.save(record) != OK:
				_set_status("Impossibile aggiornare il nome della creatura.")
				return
		_selected_id = creature_id
		_selected_kind = String(record.get("kind", ""))
		_reload()
		_link_selected_token()
		return


func _request_spawn_selected_creature() -> void:
	_save()
	var record: Dictionary = _current()
	if record.is_empty():
		return
	if not board_root.has_method("begin_creature_token_placement"):
		_set_status("Piazzamento token non disponibile.")
		return
	if bool(board_root.call("begin_creature_token_placement", record)):
		hide_panel()


func toggle_panel() -> void:
	if _panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	for area_name: String in ["Compendio"]:
		var area := board_root.get_node_or_null(area_name)
		if area != null and area.has_method("hide_panel"):
			var panel: Control = area.get("_panel") as Control
			if panel != null and panel.visible:
				area.call("hide_panel")
	_reload()
	_panel.show()
	# Transparent UI themes must not leak tactical portraits through the sheet.
	var tactical_overlay: Control = board_root.get_node_or_null(
		"UI/TopDownElevationOverlay"
	) as Control
	if tactical_overlay != null:
		tactical_overlay.hide()
	# Immediately suppress tactical condition badges before they can draw
	# on top of the newly opened panel (including the very first frame).
	var flanking: Node = board_root.get_node_or_null("FlankingSystem")
	if flanking != null and flanking.has_method("refresh_now"):
		flanking.call("refresh_now")
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")


func hide_panel() -> void:
	_save()
	_panel.hide()
	var tactical_overlay: Control = board_root.get_node_or_null(
		"UI/TopDownElevationOverlay"
	) as Control
	if tactical_overlay != null and board_root.has_method("is_2d_view_enabled"):
		tactical_overlay.call(
			"set_2d_active", bool(board_root.call("is_2d_view_enabled"))
		)
	var flanking: Node = board_root.get_node_or_null("FlankingSystem")
	if flanking != null and flanking.has_method("refresh_now"):
		flanking.call("refresh_now")
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not (
			_import_dialog.visible
			or _miniature_dialog.visible
			or _feat_dialog.visible
			or _transfer_dialog.visible
			or _delete_dialog.visible
		):
			hide_panel()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CreatureSheet"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 26
	_panel.offset_top = 52
	_panel.offset_right = -26
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure UI sheets outrank any remaining tactical screen-space badges.
	_panel.z_index = 30
	_panel.hide()
	(board_root.get_node("UI") as CanvasLayer).add_child(_panel)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_options_menu = MenuButton.new()
	_options_menu.text = "Opzioni ▾"
	var popup := _options_menu.get_popup()
	popup.add_item("Copia il mio ID", 1)
	popup.add_item("Cartella homebrew", 2)
	popup.add_item("Ricarica homebrew", 3)
	popup.add_separator()
	popup.add_item("Associa a token selezionato", 4)
	popup.add_item("Cedi controllo…", 5)
	popup.add_item("Ricevi creatura…", 6)
	popup.add_separator()
	popup.add_item("Elimina creatura selezionata…", 7)
	popup.id_pressed.connect(_on_options_selected)
	header.add_child(_options_menu)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(hide_panel)
	header.add_child(close)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.clip_text = true
	outer.add_child(_status)

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 300
	outer.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	columns.add_child(left)
	_creature_list_scroll = ScrollContainer.new()
	_creature_list_scroll.custom_minimum_size.y = 40
	_creature_list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creature_list_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_creature_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_creature_list_scroll)
	_creature_list = VBoxContainer.new()
	_creature_list.name = "CreatureRows"
	_creature_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creature_list.add_theme_constant_override("separation", 2)
	_creature_list.tooltip_text = "Le mie creature · clic destro per le azioni"
	_creature_list_scroll.add_child(_creature_list)
	_creature_context_menu = PopupMenu.new()
	_creature_context_menu.add_item("Genera token / riposiziona", 1)
	_creature_context_menu.add_item("Calcola automaticamente…", 2)
	_creature_context_menu.add_separator()
	_creature_context_menu.add_item("Elimina creatura…", 3)
	_creature_context_menu.id_pressed.connect(_on_creature_context_action)
	_creature_list.add_child(_creature_context_menu)
	var spawn_selected := Button.new()
	spawn_selected.text = "Genera token / riposiziona"
	spawn_selected.tooltip_text = (
		"Se la creatura ha già un token, spostalo senza duplicarlo. "
		+ "Altrimenti genera un token e collegalo alla scheda."
	)
	spawn_selected.pressed.connect(_request_spawn_selected_creature)
	left.add_child(spawn_selected)

	var add_general := Button.new()
	add_general.text = "+ Aggiungi personaggio"
	add_general.pressed.connect(begin_add_creature)
	left.add_child(add_general)
	_catalog_filter = LineEdit.new()
	_catalog_filter.placeholder_text = "Bestiario · cerca per nome o fonte"
	_catalog_filter.text_changed.connect(_filter_catalog)
	left.add_child(_catalog_filter)
	_catalog_list = ItemList.new()
	_catalog_list.custom_minimum_size.y = 75
	_catalog_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_list.item_activated.connect(_request_monster)
	left.add_child(_catalog_list)
	var add_monster := Button.new()
	add_monster.text = "+ Creatura del bestiario"
	add_monster.pressed.connect(_request_selected_monster)
	left.add_child(add_monster)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.add_child(_tabs)
	var form := _add_sheet_tab(_tabs, "Statistiche")
	var appearance_tab := _add_sheet_tab(_tabs, "Aspetto")
	var traits_tab := _add_sheet_tab(_tabs, "Tratti e talenti")
	var conditions_tab := _add_sheet_tab(_tabs, "Stati")
	_tabs.current_tab = 0

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	form.add_child(name_row)
	_add_label(name_row, "Nome")
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_v: String) -> void: _save())
	name_row.add_child(_name)
	_add_label(name_row, "CA")
	_ac = _spin(name_row, 0, 99)
	_ac.custom_minimum_size.x = 64

	var health_panel := PanelContainer.new()
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = Color(0.12, 0.17, 0.22, 0.92)
	health_style.border_color = Color(0.35, 0.54, 0.6, 0.5)
	health_style.set_border_width_all(1)
	health_style.set_corner_radius_all(7)
	health_style.set_content_margin_all(7)
	health_panel.add_theme_stylebox_override("panel", health_style)
	health_panel.tooltip_text = "PF attuali, massimi e temporanei. I danni consumano prima i PF temporanei."
	form.add_child(health_panel)
	var health := HBoxContainer.new()
	health.add_theme_constant_override("separation", 4)
	health_panel.add_child(health)
	_add_label(health, "❤️")
	var damage := Button.new()
	damage.text = "−"
	damage.tooltip_text = "Sottrai PF: inserisci un valore o tira un dado"
	damage.custom_minimum_size.x = 30
	damage.pressed.connect(_open_hp_delta.bind(-1))
	_hp = _spin(health, -999, 99999)
	_hp.custom_minimum_size = Vector2(68, 30)
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_label(health, "/")
	_max_hp = _spin(health, 0, 99999)
	_max_hp.custom_minimum_size = Vector2(68, 30)
	_max_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var heal := Button.new()
	heal.text = "+"
	heal.tooltip_text = "Aggiungi PF: inserisci un valore o tira un dado"
	heal.custom_minimum_size.x = 30
	heal.pressed.connect(_open_hp_delta.bind(1))
	# Adjacent − and + form a single compact health-action group.
	health.add_child(damage)
	health.add_child(heal)
	var restore_hp := Button.new()
	restore_hp.text = "↺"
	restore_hp.tooltip_text = "Ripristina i PF al valore massimo"
	restore_hp.custom_minimum_size.x = 30
	restore_hp.pressed.connect(_restore_full_hp)
	health.add_child(restore_hp)
	var temp_health := HBoxContainer.new()
	temp_health.add_theme_constant_override("separation", 6)
	form.add_child(temp_health)
	_add_label(temp_health, "🛡 PF temporanei")
	_temp_hp = _spin(temp_health, 0, 99999)
	_temp_hp.custom_minimum_size.x = 85
	_temp_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var abilities_row := GridContainer.new()
	abilities_row.columns = 6
	form.add_child(abilities_row)
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var cell := VBoxContainer.new()
		abilities_row.add_child(cell)
		_add_label(cell, ability.to_upper())
		var spin := _spin(cell, 1, 30)
		_ability_spins[ability] = spin

	var classes_row := GridContainer.new()
	classes_row.columns = 4
	form.add_child(classes_row)
	_add_label(classes_row, "Razza / Specie")
	_species = _reference_option(classes_row, Player5eTools.entries("races"))
	_add_label(classes_row, "Regole")
	_rules_edition = OptionButton.new()
	_rules_edition.add_item("2014")
	_rules_edition.add_item("2024")
	_rules_edition.item_selected.connect(_on_rules_edition_changed)
	classes_row.add_child(_rules_edition)
	_add_label(classes_row, "Classe base")
	_class_name = _reference_option(
		classes_row, Player5eTools.class_choices(), false
	)
	_add_label(classes_row, "Livello classe base")
	_level = SpinBox.new()
	_level.min_value = 1
	_level.max_value = 20
	_level.step = 1
	_level.update_on_text_changed = true
	_level.rounded = true
	_level.custom_minimum_size = Vector2(82, 30)
	_level.value_changed.connect(_on_level_changed)
	classes_row.add_child(_level)

	var multiclass_header := HBoxContainer.new()
	form.add_child(multiclass_header)
	_add_label(multiclass_header, "Classi aggiuntive (multiclasse)")
	var add_class := Button.new()
	add_class.text = "+ Classe"
	add_class.pressed.connect(_add_multiclass_row)
	multiclass_header.add_child(add_class)
	_multiclass_rows = VBoxContainer.new()
	form.add_child(_multiclass_rows)

	var feats_header := HBoxContainer.new()
	traits_tab.add_child(feats_header)
	_add_label(feats_header, "Talenti e scelte manuali")
	var search_feat := Button.new()
	search_feat.text = "Cerca talenti…"
	search_feat.pressed.connect(_open_feat_dialog)
	feats_header.add_child(search_feat)
	_feats = TextEdit.new()
	_feats.custom_minimum_size = Vector2(0, 56)
	_feats.text_changed.connect(_save)
	traits_tab.add_child(_feats)

	var miniature_row := HBoxContainer.new()
	appearance_tab.add_child(miniature_row)
	_add_label(miniature_row, "Miniatura base")
	_default_miniature = LineEdit.new()
	_default_miniature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_default_miniature.placeholder_text = "Scegli una miniatura dal catalogo"
	_default_miniature.editable = false
	miniature_row.add_child(_default_miniature)
	var choose_miniature := Button.new()
	choose_miniature.text = "Cerca e scegli…"
	choose_miniature.pressed.connect(func() -> void: _choose_miniature(_current(), false))
	miniature_row.add_child(choose_miniature)
	_current_miniature = Label.new()
	_current_miniature.text = "Aspetto attuale: nessun token"
	appearance_tab.add_child(_current_miniature)
	var appearance_actions := HBoxContainer.new()
	appearance_actions.add_theme_constant_override("separation", 8)
	appearance_tab.add_child(appearance_actions)
	var edit_appearance := Button.new()
	edit_appearance.text = "Scegli aspetto attuale…"
	edit_appearance.tooltip_text = "Cerca la miniatura attuale; funziona anche senza token in scena."
	edit_appearance.pressed.connect(_edit_linked_token_appearance)
	appearance_actions.add_child(edit_appearance)
	var reset_appearance := Button.new()
	reset_appearance.text = "↺ Aspetto di base"
	reset_appearance.tooltip_text = "Reimposta l'aspetto attuale alla miniatura di base."
	reset_appearance.pressed.connect(_restore_default_appearance)
	appearance_actions.add_child(reset_appearance)

	var geometry := GridContainer.new()
	geometry.columns = 2
	geometry.add_theme_constant_override("h_separation", 14)
	geometry.add_theme_constant_override("v_separation", 10)
	appearance_tab.add_child(geometry)
	_add_label(geometry, "Taglia")
	_size_choice = OptionButton.new()
	for size_name: String in ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]:
		_size_choice.add_item(size_name)
	_size_choice.item_selected.connect(func(_i: int) -> void: _save())
	geometry.add_child(_size_choice)
	_add_label(geometry, "Gittata (ft)")
	_reach = _spin(geometry, 5, 1000)
	_reach.step = 5.0
	_add_label(geometry, "Fronte della miniatura")
	_front = OptionButton.new()
	for direction: String in ["−Z · 0°", "+X · 90°", "+Z · 180°", "−X · 270°"]:
		_front.add_item(direction)
	_front.item_selected.connect(func(_i: int) -> void: _save())
	geometry.add_child(_front)
	_add_label(geometry, "Party")
	_party = LineEdit.new()
	_party.placeholder_text = "Default"
	_party.text_changed.connect(func(_text: String) -> void: _save())
	geometry.add_child(_party)
	var hint := Label.new()
	hint.text = "Questi parametri sono salvati sulla creatura e usati al prossimo piazzamento."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.7
	appearance_tab.add_child(hint)


	_condition_rows = VBoxContainer.new()
	conditions_tab.add_child(_condition_rows)

	_reference = RichTextLabel.new()
	_reference.bbcode_enabled = false
	_reference.selection_enabled = true
	_reference.scroll_active = true
	_reference.custom_minimum_size.y = 250
	_reference.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	traits_tab.add_child(_reference)
	_effect_dialog = AcceptDialog.new()
	_effect_dialog.title = "5etools · Effect details"
	_effect_dialog.min_size = Vector2i(560, 420)
	add_child(_effect_dialog)
	_effect_text = RichTextLabel.new()
	_effect_text.custom_minimum_size = Vector2(530, 320)
	_effect_text.selection_enabled = true
	_effect_text.scroll_active = true
	_effect_dialog.get_vbox().add_child(_effect_text)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina creatura"
	_delete_dialog.confirmed.connect(_delete_selected_creature)
	add_child(_delete_dialog)
	_build_automatic_dialog()
	_build_hp_delta_dialog()



func _add_sheet_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 12)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	return content


func _on_options_selected(id: int) -> void:
	match id:
		1:
			DisplayServer.clipboard_set(Owner.local_id())
			_set_status("ID controllore copiato.")
		2:
			OS.shell_open(ProjectSettings.globalize_path(ContentCatalog.HOME_DIR))
		3:
			_reload_homebrew()
		4:
			_link_selected_token()
		5:
			if _current().is_empty():
				_set_status("Seleziona una creatura da cedere.")
				return
			_owner_target.clear()
			_transfer_dialog.popup_centered_clamped(Vector2i(520, 175), 0.9)
		6:
			_show_import()
		7:
			_confirm_delete()


func _on_creature_row_gui_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	_select_creature_row(index)
	_creature_context_menu.position = Vector2i(
		get_viewport().get_mouse_position()
	)
	_creature_context_menu.popup()
	get_viewport().set_input_as_handled()


func _select_creature_row(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	if (
		_selected_id != String(_records[index].get("id", ""))
		or _selected_kind != String(_records[index].get("kind", ""))
	):
		_save()
	_on_selected(index)


func _focus_creature_token(creature_id: String) -> void:
	var token: CharacterBody3D = find_linked_token_for_creature(creature_id)
	if token == null or not is_instance_valid(token):
		_refresh_creature_eye_buttons()
		return
	# The sheet covers the board; close it so the centered token is visible.
	hide_panel()
	if board_root.has_method("focus_camera_on_token"):
		board_root.call("focus_camera_on_token", token)


func _refresh_creature_eye_buttons() -> void:
	# Scan the live tokens once instead of rereading the archive for each
	# character on every UI refresh. Include restored tokens whose sync ID
	# changed, but ignore remote-owned and queued-for-deletion instances.
	var present: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is CharacterBody3D or not board_root.is_ancestor_of(node):
			continue
		if node.is_queued_for_deletion():
			continue
		if String(node.get_meta("creature_owner_id", "")) != Owner.local_id():
			continue
		var creature_id: String = String(node.get_meta("creature_id", ""))
		if not creature_id.is_empty():
			present[creature_id] = true
	for i: int in range(mini(_records.size(), _creature_eye_buttons.size())):
		_creature_eye_buttons[i].visible = present.has(
			String(_records[i].get("id", ""))
		)


func _process(delta: float) -> void:
	if _panel == null or not _panel.visible:
		return
	_creature_presence_elapsed += delta
	if _creature_presence_elapsed >= 0.4:
		_creature_presence_elapsed = 0.0
		_refresh_creature_eye_buttons()


func _on_creature_context_action(action: int) -> void:
	match action:
		1:
			_request_spawn_selected_creature()
		2:
			_open_automatic_calculation()
		3:
			_confirm_delete()


func _build_automatic_dialog() -> void:
	_automatic_dialog = ConfirmationDialog.new()
	_automatic_dialog.title = "Calcola automaticamente"
	_automatic_dialog.dialog_text = ""
	_automatic_dialog.min_size = Vector2i(560, 360)
	(board_root.get_node("UI") as CanvasLayer).add_child(_automatic_dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_automatic_dialog.get_vbox().add_child(content)
	var intro := Label.new()
	intro.text = "Scegli i valori da ricalcolare. Gli altri campi restano invariati."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.y = 24
	content.add_child(intro)
	_automatic_hp = CheckBox.new()
	_automatic_hp.text = "PF massimi: media dei dadi vita + Costituzione"
	_automatic_hp.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_hp)
	_automatic_proficiency = CheckBox.new()
	_automatic_proficiency.text = "Bonus di competenza: somma livelli di classe"
	_automatic_proficiency.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_proficiency)
	_automatic_spells = CheckBox.new()
	_automatic_spells.text = "Limiti degli incantesimi conosciuti/preparabili"
	_automatic_spells.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_spells)
	var explanation := Label.new()
	explanation.text = "Gli incantesimi effettivamente scelti non vengono cambiati. I PF attuali sono conservati (limitati al nuovo massimo)."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	_automatic_preview = RichTextLabel.new()
	_automatic_preview.custom_minimum_size = Vector2(0, 135)
	_automatic_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_automatic_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_automatic_preview.scroll_active = true
	content.add_child(_automatic_preview)
	_automatic_dialog.confirmed.connect(_apply_automatic_calculation)


func _open_automatic_calculation() -> void:
	_save()
	var record: Dictionary = _current()
	if record.is_empty():
		return
	_automatic_target_id = String(record.get("id", ""))
	var character: bool = String(record.get("kind", "")) == "character"
	var hp_result: Dictionary = (
		Rules.automatic_hit_points(record)
		if character else Rules.automatic_monster_hit_points(record)
	)
	_automatic_hp.disabled = not bool(hp_result.get("available", false))
	_automatic_proficiency.disabled = not character
	_automatic_spells.disabled = not character
	_automatic_hp.set_pressed_no_signal(false)
	_automatic_proficiency.set_pressed_no_signal(false)
	_automatic_spells.set_pressed_no_signal(false)
	_refresh_automatic_preview()
	_automatic_dialog.popup_centered_clamped(Vector2i(610, 430), 0.85)


func _refresh_automatic_preview() -> void:
	if _automatic_preview == null:
		return
	var record: Dictionary = _current()
	var lines := PackedStringArray()
	var is_character: bool = String(record.get("kind", "")) == "character"
	var hp: Dictionary = (
		Rules.automatic_hit_points(record)
		if is_character else Rules.automatic_monster_hit_points(record)
	)
	if _automatic_hp.button_pressed and bool(hp.get("available", false)):
		lines.append("PF massimi → %d (%s)" % [
			int(hp.get("value", 0)), String(hp.get("detail", ""))
		])
	elif not bool(hp.get("available", false)):
		lines.append("PF non calcolabili: " + String(hp.get("reason", "")))
	if is_character:
		if _automatic_proficiency.button_pressed:
			lines.append("Competenza → +%d" % Rules.proficiency_bonus(record))
		if _automatic_spells.button_pressed:
			var limits: Dictionary = Rules.spellcasting_limits(record)
			lines.append(String(limits.get("detail", "Nessuna classe magica.")))
	if lines.is_empty():
		lines.append("Seleziona almeno un valore per vedere l'anteprima.")
	_automatic_preview.text = "\n".join(lines)
	_automatic_dialog.get_ok_button().disabled = (
		not _automatic_hp.button_pressed
		and not _automatic_proficiency.button_pressed
		and not _automatic_spells.button_pressed
	)


func _apply_automatic_calculation() -> void:
	var record: Dictionary = _current()
	if record.is_empty() or String(record.get("id", "")) != _automatic_target_id:
		return
	if _automatic_hp.button_pressed:
		var hp: Dictionary = (
			Rules.automatic_hit_points(record)
			if String(record.get("kind", "")) == "character"
			else Rules.automatic_monster_hit_points(record)
		)
		if bool(hp.get("available", false)):
			var maximum: int = int(hp.get("value", 1))
			record["max_hp"] = maximum
			record["current_hp"] = mini(int(record.get("current_hp", maximum)), maximum)
	if _automatic_proficiency.button_pressed:
		record["proficiency_bonus"] = Rules.proficiency_bonus(record)
	if _automatic_spells.button_pressed:
		record["spellcasting_calculation"] = Rules.spellcasting_limits(record)
	if _archive.save(record) != OK:
		_set_status("Calcolo riuscito ma salvataggio non completato.")
		return
	_replace_current_record(record)
	_load_form(record)
	_sync_token_health(record)
	_set_status("Calcoli selezionati applicati alla creatura.")


func _build_transfer_request_dialog() -> void:
	_transfer_dialog = ConfirmationDialog.new()
	_transfer_dialog.title = "Cedi il controllo della creatura"
	_transfer_dialog.dialog_text = ""
	(board_root.get_node("UI") as CanvasLayer).add_child(_transfer_dialog)
	var hint := Label.new()
	hint.text = "ID controllore del destinatario"
	_transfer_dialog.get_vbox().add_child(hint)
	_owner_target = LineEdit.new()
	_owner_target.placeholder_text = "Incolla l'ID controllore"
	_owner_target.custom_minimum_size.x = 430
	_transfer_dialog.get_vbox().add_child(_owner_target)
	_transfer_dialog.confirmed.connect(_transfer)


func _build_feat_dialog() -> void:
	_feat_dialog = ConfirmationDialog.new()
	_feat_dialog.title = "Talenti · 5e.tools e homebrew"
	_feat_dialog.dialog_text = ""
	_feat_dialog.min_size = Vector2i(590, 400)
	(board_root.get_node("UI") as CanvasLayer).add_child(_feat_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_feat_dialog.get_vbox().add_child(body)
	var hint := Label.new()
	hint.text = "Cerca un talento e leggi i suoi effetti prima di aggiungerlo."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	_feat_filter = LineEdit.new()
	_feat_filter.placeholder_text = "Cerca talenti per nome o fonte..."
	_feat_filter.clear_button_enabled = true
	_feat_filter.text_changed.connect(_search_feats)
	body.add_child(_feat_filter)
	_feat_list = ItemList.new()
	_feat_list.custom_minimum_size = Vector2(0, 130)
	_feat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feat_list.item_selected.connect(_show_feat_details)
	_feat_list.item_activated.connect(_show_feat_details)
	body.add_child(_feat_list)
	_feat_details = RichTextLabel.new()
	_feat_details.selection_enabled = true
	_feat_details.custom_minimum_size.y = 125
	body.add_child(_feat_details)
	_feat_dialog.confirmed.connect(_confirm_feat)


func _open_feat_dialog() -> void:
	if _current().is_empty():
		_set_status("Seleziona prima una creatura.")
		return
	_feat_filter.text = ""
	_search_feats("")
	_feat_dialog.popup_centered_clamped(Vector2i(680, 465), 0.88)
	_feat_filter.grab_focus()


func _search_feats(query: String) -> void:
	if _feat_list == null:
		return
	_feat_list.clear()
	_visible_feats = Player5eTools.search("feats", query, {}, 400)
	for entry: Dictionary in _visible_feats:
		_feat_list.add_item(Player5eTools.display_label(entry))
	_feat_details.text = "Seleziona un talento per leggerne gli effetti."
	_feat_dialog.get_ok_button().disabled = true


func _show_feat_details(index: int) -> void:
	if index < 0 or index >= _visible_feats.size():
		return
	var entry: Dictionary = _visible_feats[index]
	_feat_details.text = Player5eTools.info_text(entry, ContentCatalog.description(entry))
	_feat_dialog.get_ok_button().disabled = false


func _confirm_feat() -> void:
	var chosen: PackedInt32Array = _feat_list.get_selected_items()
	if chosen.is_empty() or chosen[0] >= _visible_feats.size():
		return
	var entry: Dictionary = _visible_feats[chosen[0]]
	var source := String(entry.get("source", ""))
	var label := String(entry.get("name", "Talento"))
	if not source.is_empty():
		label += " [" + source + "]"
	for existing: String in _feats.text.split("\n", false):
		if existing.strip_edges().nocasecmp_to(label) == 0:
			_set_status("Talento già presente nella scheda.")
			return
	_feats.text += ("\n" if not _feats.text.strip_edges().is_empty() else "") + label
	_save()
	var record: Dictionary = _current()
	if not record.is_empty():
		var saved: Array = record.get("feats_catalog", []).duplicate(true)
		var ref_id := String(entry.get("id", ""))
		var duplicate_entry := false
		for previous: Variant in saved:
			if previous is Dictionary and String(previous.get("id", "")) == ref_id:
				duplicate_entry = true
				break
		if not duplicate_entry:
			saved.append({
				"id": ref_id,
				"name": String(entry.get("name", "")),
				"source": source,
				"origin": String(entry.get("origin", "5etools"))
			})
			record["feats_catalog"] = saved
			if _archive.save(record) == OK:
				_replace_current_record(record)
	_set_status("Talento aggiunto: " + label)


# Reverse lookup of the explicit, curated miniature-to-bestiary associations.
# Never infer a connection from an approximate name match.
static func _associated_miniature_ids(bestiary_name: String, source: String) -> Array[String]:
	var exact: Array[String] = []
	var alternate_edition: Array[String] = []
	var file := FileAccess.open("res://vtt/data/miniature_bestiary.json", FileAccess.READ)
	if file == null:
		return exact
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return exact
	var entries: Variant = (parsed as Dictionary).get("entries", {})
	if not entries is Dictionary:
		return exact
	for id_value: Variant in (entries as Dictionary).keys():
		var data: Dictionary = (entries as Dictionary)[id_value]
		var editions: Variant = data.get("editions", {})
		if not editions is Dictionary:
			continue
		var name_match := false
		var precise_match := false
		for edition: Variant in (editions as Dictionary).values():
			if not edition is Dictionary:
				continue
			var reference: Dictionary = edition as Dictionary
			if String(reference.get("name", "")).nocasecmp_to(bestiary_name) != 0:
				continue
			name_match = true
			if String(reference.get("source", "")).nocasecmp_to(source) == 0:
				precise_match = true
		var miniature_id := String(id_value)
		if precise_match:
			exact.append(miniature_id)
		elif name_match:
			alternate_edition.append(miniature_id)
	exact.sort()
	alternate_edition.sort()
	# Exact book matches take precedence, with references from other
	# editions shown as alternatives at the start of the same list.
	exact.append_array(alternate_edition)
	return exact

func _build_transfer_dialog() -> void:
	_import_dialog = AcceptDialog.new()
	_import_dialog.title = "Ricevi il controllo di una creatura"
	_import_dialog.ok_button_text = "Importa"
	_import_dialog.confirmed.connect(_import)
	add_child(_import_dialog)
	_import_text = TextEdit.new()
	_import_text.custom_minimum_size = Vector2(620, 220)
	_import_text.placeholder_text = "Incolla qui il codice JSON ricevuto dal precedente controllore."
	_import_dialog.get_vbox().add_child(_import_text)


func _add_label(parent: Node, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


func _spin(parent: Node, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.update_on_text_changed = true
	spin.custom_minimum_size = Vector2(84, 30)
	spin.value_changed.connect(func(_v: float) -> void: _save())
	parent.add_child(spin)
	return spin


func _reference_option(
	parent: Node, choices: Array[Dictionary], show_source: bool = true
) -> OptionButton:
	var select := OptionButton.new()
	_set_reference_choices(select, choices, show_source)
	select.item_selected.connect(func(_i: int) -> void: _save())
	parent.add_child(select)
	return select


func _set_reference_choices(
	option: OptionButton, choices: Array[Dictionary], show_source: bool = true
) -> void:
	option.clear()
	option.add_item("—")
	option.set_item_metadata(0, {})
	for item: Dictionary in choices:
		var label := PlayerReference.display_name(item)
		if show_source:
			label += " · " + String(item.get("source", ""))
		option.add_item(label)
		option.set_item_metadata(option.item_count - 1, item.duplicate(true))


func _selected_rules_version() -> String:
	return "2024" if _rules_edition.selected == 1 else "2014"


func _refresh_class_choices() -> void:
	var primary := _reference_entry(_class_name)
	var choices := Player5eTools.class_choices(_selected_rules_version())
	_set_reference_choices(_class_name, choices, false)
	_select_reference(_class_name, String(primary.get("name", "")), String(primary.get("source", "")), String(primary.get("id", "")))
	for definition: Dictionary in _multiclass_controls:
		var option: OptionButton = definition["selector"]
		var old := _reference_entry(option)
		_set_reference_choices(option, choices, false)
		_select_reference(option, String(old.get("name", "")), String(old.get("source", "")), String(old.get("id", "")))


func _on_rules_edition_changed(_index: int) -> void:
	if _loading:
		return
	_loading = true
	_refresh_class_choices()
	_loading = false
	_save()


func _add_multiclass_row(
	class_value: String = "", class_level: int = 1,
	source: String = "",
	reference_id: String = ""
) -> void:
	var row := HBoxContainer.new()
	_multiclass_rows.add_child(row)
	var selector := _reference_option(row, Player5eTools.class_choices(_selected_rules_version()), false)
	_select_reference(selector, class_value, source, reference_id)
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = 20
	level.step = 1
	level.update_on_text_changed = true
	level.value = clampi(class_level, 1, 20)
	level.custom_minimum_size = Vector2(82, 30)
	level.value_changed.connect(func(_v: float) -> void: _save())
	row.add_child(level)
	var remove := Button.new()
	remove.text = "×"
	row.add_child(remove)
	var definition := {"row": row, "selector": selector, "level": level}
	_multiclass_controls.append(definition)
	remove.pressed.connect(
		func() -> void:
			_multiclass_controls.erase(definition)
			_multiclass_rows.remove_child(row)
			row.queue_free()
			_save()
	)
	_save()


func _clear_multiclass() -> void:
	for definition: Dictionary in _multiclass_controls:
		var row: HBoxContainer = definition["row"]
		_multiclass_rows.remove_child(row)
		row.queue_free()
	_multiclass_controls.clear()


func _select_reference(option: OptionButton, name: String, source: String = "", stable_id: String = "") -> void:
	option.select(0)
	if name.is_empty() and stable_id.is_empty():
		return
	var fallback := -1
	for i: int in range(1, option.item_count):
		var row: Dictionary = option.get_item_metadata(i)
		if not stable_id.is_empty() and String(row.get("id", "")) == stable_id:
			option.select(i)
			return
		if String(row.get("name", "")).nocasecmp_to(name) == 0:
			if source.is_empty() or String(row.get("source", "")) == source:
				option.select(i)
				return
			if fallback < 0:
				fallback = i
	if fallback >= 0:
		option.select(fallback)


func _reference_entry(option: OptionButton) -> Dictionary:
	var value: Variant = option.get_item_metadata(option.selected)
	return value as Dictionary if value is Dictionary else {}


func _reload() -> void:
	_records = _archive.list_owned()
	for child: Node in _creature_list.get_children():
		if child == _creature_context_menu:
			continue
		_creature_list.remove_child(child)
		child.queue_free()
	_creature_row_buttons.clear()
	_creature_eye_buttons.clear()

	var selected_index := -1
	for i: int in range(_records.size()):
		var item: Dictionary = _records[i]
		var kind: String = String(item.get("kind", ""))
		var icon: String = "◇" if kind == "monster" else "♙"
		var creature_id: String = String(item.get("id", ""))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 35
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 3)
		_creature_list.add_child(row)
		var select_button := Button.new()
		select_button.text = "%s %s" % [icon, String(item.get("name", ""))]
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.clip_text = true
		select_button.toggle_mode = true
		select_button.custom_minimum_size.y = 34
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.pressed.connect(_select_creature_row.bind(i))
		select_button.gui_input.connect(_on_creature_row_gui_input.bind(i))
		row.add_child(select_button)
		_creature_row_buttons.append(select_button)
		var eye := Button.new()
		eye.name = "FocusToken"
		eye.text = "👁"
		eye.tooltip_text = "Centra la visuale sul token di questa creatura"
		eye.custom_minimum_size = Vector2(35, 34)
		eye.size_flags_horizontal = Control.SIZE_SHRINK_END
		eye.pressed.connect(_focus_creature_token.bind(creature_id))
		eye.gui_input.connect(_on_creature_row_gui_input.bind(i))
		row.add_child(eye)
		_creature_eye_buttons.append(eye)
		if (
			creature_id == _selected_id
			and kind == _selected_kind
		):
			selected_index = i

	# A short list takes only its actual height; larger archives scroll.
	var visible_rows: int = mini(maxi(_records.size(), 1), 7)
	_creature_list_scroll.custom_minimum_size.y = float(
		visible_rows * 37 + 6
	)
	_refresh_creature_eye_buttons()
	if selected_index < 0 and not _records.is_empty():
		selected_index = 0
	if _options_menu != null:
		var options_popup := _options_menu.get_popup()
		options_popup.set_item_disabled(
			options_popup.get_item_index(7), selected_index < 0
		)
	if selected_index >= 0:
		_on_selected(selected_index)
	else:
		_selected_id = ""
		_selected_kind = ""
		_loading = true
		_reference.text = "Crea un personaggio o cerca una creatura nel bestiario."
		_loading = false


func _current() -> Dictionary:
	for item: Dictionary in _records:
		if (
			String(item.get("id", "")) == _selected_id
			and String(item.get("kind", "")) == _selected_kind
		):
			return item.duplicate(true)
	return {}


func _on_selected(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	var record := _records[index]
	_selected_id = String(record.get("id", ""))
	_selected_kind = String(record.get("kind", ""))
	for i: int in range(_creature_row_buttons.size()):
		_creature_row_buttons[i].set_pressed_no_signal(i == index)
	_load_form(record)


func _load_form(record: Dictionary) -> void:
	_loading = true
	_name.text = String(record.get("name", ""))
	_hp.value = int(record.get("current_hp", 1))
	_max_hp.value = int(record.get("max_hp", 1))
	_temp_hp.value = int(record.get("temporary_hp", 0))
	_ac.value = int(record.get("armor_class", 10))
	var abilities_value: Variant = record.get("abilities", {})
	var abilities: Dictionary = (
		abilities_value as Dictionary if abilities_value is Dictionary else {}
	)
	for ability: String in _ability_spins.keys():
		(_ability_spins[ability] as SpinBox).value = int(abilities.get(ability, 10))
	_select_reference(_species, String(record.get("species", "")), String(record.get("species_source", "")), String(record.get("species_id", "")))
	var class_source := String(record.get("class_source", ""))
	var edition := String(record.get("rules_version", "2014"))
	if class_source in ["XPHB", "EFA"]:
		edition = "2024"
	elif class_source in ["PHB", "TCE"]:
		edition = "2014"
	_rules_edition.select(1 if edition == "2024" else 0)
	_refresh_class_choices()
	_select_reference(_class_name, String(record.get("class", "")), class_source, String(record.get("class_id", "")))
	_clear_multiclass()
	var classes_value: Variant = record.get("classes", [])
	if classes_value is Array:
		for i: int in range(1, (classes_value as Array).size()):
			var class_value: Variant = (classes_value as Array)[i]
			if class_value is Dictionary:
				_add_multiclass_row(
					String(class_value.get("name", "")),
					int(class_value.get("level", 1)),
					String(class_value.get("source", "")),
					String(class_value.get("id", ""))
				)
	# Existing sheets store the primary class at classes[0]; older sheets
	# with no class rows retain the legacy total-level fallback.
	var primary_level: int = int(record.get("level", 1))
	if classes_value is Array and not (classes_value as Array).is_empty():
		var first_class: Variant = (classes_value as Array)[0]
		if first_class is Dictionary:
			primary_level = int((first_class as Dictionary).get("level", primary_level))
	_level.value = clampi(primary_level, 1, 20)
	_feats.text = String(record.get("feats", ""))
	_default_miniature_id = String(record.get("default_miniature_id", ""))
	_default_miniature.text = _miniature_display_name(_default_miniature_id)
	_select_sheet_size(String(record.get("size_name", "Medium")))
	_reach.value = float(record.get("reach_feet", 5.0))
	_front.select(clampi(int(record.get("visual_front_quarter_turns", 0)), 0, 3))
	_party.text = String(record.get("party_id", ""))
	_default_miniature.tooltip_text = (
		"ID catalogo: " + _default_miniature_id
		if not _default_miniature_id.is_empty()
		else "Scegli una miniatura con il pulsante Cerca…"
	)
	var is_character := String(record.get("kind", "")) == "character"
	_species.disabled = not is_character
	_class_name.disabled = not is_character
	_rules_edition.disabled = not is_character
	_level.editable = is_character
	_refresh_conditions(record)
	_refresh_reference(record)
	_refresh_current_miniature(record)
	_loading = false


func _on_level_changed(_value: float) -> void:
	_save()


func _replace_current_record(record: Dictionary) -> void:
	for i: int in range(_records.size()):
		if (
			String(_records[i].get("id", "")) == _selected_id
			and String(_records[i].get("kind", "")) == _selected_kind
		):
			_records[i] = record
			break


func _save() -> void:
	if _loading:
		return
	var record := _current()
	if record.is_empty():
		return
	record["name"] = _name.text.strip_edges()
	record["current_hp"] = int(_hp.value)
	record["max_hp"] = int(_max_hp.value)
	record["temporary_hp"] = int(_temp_hp.value)
	record["size_name"] = _size_choice.get_item_text(_size_choice.selected)
	record["footprint"] = _selected_size_footprint()
	record["reach_feet"] = float(_reach.value)
	record["visual_front_quarter_turns"] = _front.selected
	record["party_id"] = _party.text.strip_edges()
	record["armor_class"] = int(_ac.value)
	var abilities: Dictionary = {}
	for ability: String in _ability_spins.keys():
		abilities[ability] = int((_ability_spins[ability] as SpinBox).value)
	record["abilities"] = abilities
	record["default_miniature_id"] = _default_miniature_id
	record["feats"] = _feats.text
	if String(record.get("kind", "")) == "character":
		var species := _reference_entry(_species)
		var class_ref := _reference_entry(_class_name)
		record["species_id"] = String(species.get("id", ""))
		record["class_id"] = String(class_ref.get("id", ""))
		record["species"] = String(species.get("name", ""))
		record["species_source"] = String(species.get("source", ""))
		record["class"] = String(class_ref.get("name", ""))
		record["class_source"] = String(class_ref.get("source", ""))
		record["rules_version"] = _selected_rules_version()
		var primary_level: int = clampi(int(_level.value), 1, 20)
		var classes: Array[Dictionary] = []
		var extras_level := 0
		for definition: Dictionary in _multiclass_controls:
			var secondary_option: OptionButton = definition["selector"]
			var extra_ref := _reference_entry(secondary_option)
			var extra_name := String(extra_ref.get("name", ""))
			if extra_name.is_empty():
				continue
			var extra_level := int((definition["level"] as SpinBox).value)
			extras_level += extra_level
			classes.append({
				"name": extra_name,
				"source": String(extra_ref.get("source", "")),
				"id": String(extra_ref.get("id", "")),
				"level": extra_level
			})
		# Level is derived from the class levels, NEVER used as an input
		# for calculating the base class. D&D 5e caps their sum at 20.
		if primary_level + extras_level > 20:
			_set_status("La somma dei livelli delle classi (base compresa) non può superare 20.")
			return
		record["level"] = primary_level + extras_level
		if not String(record["class"]).is_empty():
			classes.push_front({
				"name": record["class"],
				"source": record["class_source"],
				"id": record["class_id"],
				"level": primary_level
			})
		record["classes"] = classes
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio non riuscito: %s" % error_string(error))
		return
	_replace_current_record(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	# A visible sheet follows current level and race/class immediately.
	_refresh_reference(record)


func _select_sheet_size(size_name: String) -> void:
	for i: int in range(_size_choice.item_count):
		if _size_choice.get_item_text(i) == size_name:
			_size_choice.select(i)
			return
	_size_choice.select(2)


func _selected_size_footprint() -> float:
	var sizes: Array[float] = [0.5, 1.0, 1.0, 2.0, 3.0, 4.0]
	return sizes[clampi(_size_choice.selected, 0, sizes.size() - 1)]


func _build_hp_delta_dialog() -> void:
	_hp_delta_dialog = ConfirmationDialog.new()
	_hp_delta_dialog.title = "Modifica PF"
	_hp_delta_dialog.dialog_text = ""
	_hp_delta_dialog.min_size = Vector2i(390, 235)
	(board_root.get_node("UI") as CanvasLayer).add_child(_hp_delta_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_hp_delta_dialog.get_vbox().add_child(body)
	var explanation := Label.new()
	explanation.text = "Scegli una quantità o tira un dado con il roller."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(explanation)
	_hp_amount_row = HBoxContainer.new()
	body.add_child(_hp_amount_row)
	_add_label(_hp_amount_row, "Quantità")
	_hp_delta_amount = SpinBox.new()
	_hp_delta_amount.min_value = 1
	_hp_delta_amount.max_value = 99999
	_hp_delta_amount.value = 1
	_hp_delta_amount.rounded = true
	_hp_delta_amount.update_on_text_changed = true
	_hp_delta_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_amount_row.add_child(_hp_delta_amount)
	_hp_use_dice = CheckBox.new()
	_hp_use_dice.text = "Usa una formula di dadi"
	_hp_use_dice.toggled.connect(func(_value: bool) -> void: _refresh_hp_delta_mode())
	body.add_child(_hp_use_dice)
	_hp_dice_formula = LineEdit.new()
	_hp_dice_formula.placeholder_text = "Esempio: 2d6+3"
	_hp_dice_formula.text = "1d8"
	_hp_dice_formula.text_changed.connect(func(_value: String) -> void: _refresh_hp_delta_mode())
	body.add_child(_hp_dice_formula)
	_hp_quick_dice_row = HBoxContainer.new()
	_hp_quick_dice_row.add_theme_constant_override("separation", 5)
	body.add_child(_hp_quick_dice_row)
	for die: String in ["d4", "d6", "d8", "d10", "d12", "d20"]:
		var quick_die := Button.new()
		quick_die.text = die
		quick_die.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick_die.pressed.connect(_set_hp_dice_formula.bind("1" + die))
		_hp_quick_dice_row.add_child(quick_die)
	_hp_formula_status = Label.new()
	_hp_formula_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hp_formula_status)
	_hp_delta_dialog.confirmed.connect(_confirm_hp_delta)
	_refresh_hp_delta_mode()


func _open_hp_delta(sign: int) -> void:
	if _current().is_empty():
		return
	_hp_delta_sign = -1 if sign < 0 else 1
	_hp_delta_dialog.title = (
		"Sottrai punti ferita" if sign < 0 else "Aggiungi punti ferita"
	)
	_hp_delta_amount.value = 1
	_hp_use_dice.set_pressed_no_signal(false)
	_refresh_hp_delta_mode()
	_hp_delta_dialog.popup_centered_clamped(Vector2i(500, 295), 0.9)


func _set_hp_dice_formula(expression: String) -> void:
	_hp_dice_formula.text = expression
	_refresh_hp_delta_mode()


func _refresh_hp_delta_mode() -> void:
	if _hp_delta_dialog == null:
		return
	var rolling: bool = _hp_use_dice.button_pressed
	_hp_amount_row.visible = not rolling
	_hp_dice_formula.visible = rolling
	_hp_quick_dice_row.visible = rolling
	_hp_formula_status.visible = rolling
	_hp_delta_dialog.get_ok_button().text = (
		"Tira e applica" if rolling else "Applica"
	)
	if rolling:
		var roller: Node = board_root.get_node_or_null("DiceRollerChat")
		var parsed: Dictionary = DiceRoller.parse_dice_expression(
			_hp_dice_formula.text
		)
		var valid: bool = (
			roller != null and roller.has_method("roll_expression_from_sheet")
			and not parsed.is_empty()
		)
		_hp_formula_status.text = (
			"Il risultato sarà registrato nel roller della chat."
			if valid else "Inserisci una formula valida (es. 2d6+3)."
		)
		_hp_delta_dialog.get_ok_button().disabled = not valid
	else:
		_hp_delta_dialog.get_ok_button().disabled = false


func _confirm_hp_delta() -> void:
	var amount: int = maxi(0, int(_hp_delta_amount.value))
	if _hp_use_dice.button_pressed:
		var roller: Node = board_root.get_node_or_null("DiceRollerChat")
		if roller == null or not roller.has_method("roll_expression_from_sheet"):
			_set_status("Il roller della chat non è disponibile.")
			return
		var actor: CharacterBody3D = find_linked_token_for_creature(_selected_id)
		var rolled: Variant = roller.call(
			"roll_expression_from_sheet",
			("Danni" if _hp_delta_sign < 0 else "Cura")
			+ " · " + String(_current().get("name", "Creatura")),
			_hp_dice_formula.text,
			actor
		)
		if not (rolled is int or rolled is float) or int(rolled) < 0:
			_set_status("Formula di dadi non valida; nessun PF modificato.")
			return
		amount = maxi(0, int(rolled))
	if amount > 0:
		_change_hit_points(_hp_delta_sign * amount)
		_set_status("%s %d PF." % [
			"Sottratti" if _hp_delta_sign < 0 else "Aggiunti", amount
		])


func _change_hit_points(delta: int) -> void:
	if _current().is_empty():
		return
	var hp := int(_hp.value)
	var temp := int(_temp_hp.value)
	if delta < 0:
		var absorbed := mini(temp, -delta)
		temp -= absorbed
		hp = maxi(0, hp - (-delta - absorbed))
	else:
		hp = mini(int(_max_hp.value), hp + delta)
	_loading = true
	_temp_hp.value = temp
	_hp.value = hp
	_loading = false
	_save()


func _apply_sheet_properties(record: Dictionary) -> void:
	var token := find_linked_token_for_creature(String(record.get("id", "")))
	if token != null and board_root.has_method("apply_creature_sheet_properties"):
		board_root.call("apply_creature_sheet_properties", token, record)


func _apply_current_appearance(record: Dictionary) -> void:
	var token := find_linked_token_for_creature(String(record.get("id", "")))
	if token != null and board_root.has_method("apply_creature_sheet_appearance"):
		var applied: bool = bool(board_root.call(
			"apply_creature_sheet_appearance", token, record
		))
		if not applied:
			_set_status("Aspetto salvato. Se la miniatura è remota, sarà applicata quando sarà disponibile.")


func _restore_default_appearance() -> void:
	var record := _current()
	if record.is_empty():
		return
	var original_id := String(record.get("default_miniature_id", ""))
	if original_id.is_empty():
		_set_status("Questa creatura non ha ancora una miniatura di base.")
		return
	_set_current_miniature(original_id)


func _set_current_miniature(miniature_id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty() or miniature_id.is_empty():
		return
	record["current_miniature_id"] = miniature_id
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare l'aspetto attuale.")
		return
	_replace_current_record(record)
	_refresh_current_miniature(record)
	_apply_current_appearance(record)


func _restore_full_hp() -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var maximum: int = maxi(0, int(record.get("max_hp", 0)))
	if maximum == int(record.get("current_hp", 0)):
		return
	_hp.value = maximum
	_save()
	_set_status("Punti ferita ripristinati al massimo.")

func _refresh_reference(record: Dictionary) -> void:
	if String(record.get("kind", "")) == "monster":
		var stat: Dictionary = record.get("stat_block", {})
		var lines: PackedStringArray = [
			String(stat.get("name", record.get("name", ""))),
			"Fonte: %s" % String(stat.get("source", "5e.tools")),
			"GS: %s" % str(stat.get("cr", "—"))
		]
		for section: String in [
			"trait", "spellcasting", "action", "bonus", "reaction",
			"legendary", "mythic", "lairActions"
		]:
			var entries: Variant = stat.get(section, [])
			if not entries is Array:
				continue
			lines.append("")
			lines.append(section.to_upper())
			for raw: Variant in entries as Array:
				if raw is Dictionary:
					var item: Dictionary = raw as Dictionary
					lines.append("• " + String(item.get("name", section)))
					lines.append(_text_entries(item.get("entries", [])))
				elif raw is String:
					lines.append(String(raw))
		_reference.text = "\n".join(lines)
		return

	var primary_class_name := String(record.get("class", ""))
	var species := String(record.get("species", ""))
	var character_level: int = clampi(int(record.get("level", 1)), 1, 20)
	var parts: PackedStringArray = [
		"%s · %s" % [
			String(record.get("name", "")), species
		], "", "PRIVILEGI DI CLASSE (5e.tools)"
	]

	var calculation_value: Variant = record.get("spellcasting_calculation", {})
	if calculation_value is Dictionary:
		var spell_summary: String = String(
			(calculation_value as Dictionary).get("detail", "")
		).strip_edges()
		if not spell_summary.is_empty():
			parts.append("")
			parts.append("LIMITI DEGLI INCANTESIMI (ULTIMO CALCOLO)")
			parts.append(spell_summary)
			parts.append("")
	var class_rows: Array = record.get("classes", [])
	if class_rows.is_empty() and not primary_class_name.is_empty():
		class_rows = [{"name": primary_class_name, "level": character_level}]
	for class_value: Variant in class_rows:
		if not class_value is Dictionary:
			continue
		var class_data: Dictionary = class_value as Dictionary
		var this_name := String(class_data.get("name", ""))
		var this_level: int = clampi(
			int(class_data.get("level", character_level)), 1, 20
		)
		parts.append("")
		parts.append("%s (livello %d)" % [this_name, this_level])
		for feature: Dictionary in Player5eTools.entries("class_features"):
			if String(feature.get("class_name", "")).nocasecmp_to(this_name) != 0:
				continue
			var level := int(feature.get("level", 0))
			var selected_source := String(class_data.get("source", record.get("class_source", "")))
			if not selected_source.is_empty() and String(feature.get("class_source", "")) != selected_source:
				continue
			if level > this_level:
				continue
			parts.append("Lv %d · %s" % [level, Player5eTools.display_label(feature)])
			var description := ContentCatalog.description(feature)
			if not description.is_empty():
				parts.append(description)
	parts.append("")
	parts.append("TRATTI DELLA SPECIE (5e.tools)")
	for feature: Dictionary in Player5eTools.entries("races"):
		if String(feature.get("id", "")) == String(record.get("species_id", "")) or (String(feature.get("name", "")) == species and String(feature.get("source", "")) == String(record.get("species_source", ""))):
			parts.append(ContentCatalog.description(feature))
	_reference.text = "\n".join(parts)


func _text_entries(value: Variant) -> String:
	var parts: PackedStringArray = []
	if value is String:
		return String(value)
	if value is Array:
		for raw: Variant in value as Array:
			if raw is String:
				parts.append(String(raw))
			elif raw is Dictionary:
				var entry: Dictionary = raw as Dictionary
				if entry.has("name"):
					parts.append(String(entry.get("name", "")))
				parts.append(_text_entries(entry.get("entries", [])))
	return ContentCatalog.description({"entries": value})


func _filter_catalog(query: String) -> void:
	_catalog_list.clear()
	_filtered_catalog.clear()
	var text_query := query.strip_edges().to_lower()
	if text_query.is_empty():
		return
	for entry: Dictionary in _catalog:
		var label := "%s %s" % [
			String(entry.get("name", "")), String(entry.get("source", ""))
		]
		# Split search words so e.g. "red dragon" also matches
		# reordered catalogue labels and edition/source metadata.
		var searchable: String = label.to_lower()
		var matches := true
		for word: String in text_query.split(" ", false):
			if word not in searchable:
				matches = false
				break
		if not matches:
			continue
		_filtered_catalog.append(entry)
		_catalog_list.add_item(label)
		if _filtered_catalog.size() >= 80:
			break


# Bundled 5e.tools miniature references are a searchable fallback even
# before the remote search index is downloaded (or while offline).
static func _bundled_bestiary_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(
		"res://vtt/data/miniature_bestiary.json", FileAccess.READ
	)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return result
	var entries_value: Variant = (parsed as Dictionary).get("entries", {})
	if not entries_value is Dictionary:
		return result
	var seen: Dictionary = {}
	for raw: Variant in (entries_value as Dictionary).values():
		if not raw is Dictionary:
			continue
		var editions: Variant = (raw as Dictionary).get("editions", {})
		if not editions is Dictionary:
			continue
		for edition: Variant in (editions as Dictionary).values():
			if not edition is Dictionary:
				continue
			var ref: Dictionary = edition as Dictionary
			var name: String = String(ref.get("name", "")).strip_edges()
			var source: String = String(ref.get("source", "")).strip_edges()
			if name.is_empty() or source.is_empty():
				continue
			var key: String = (name + "|" + source).to_lower()
			if seen.has(key):
				continue
			seen[key] = true
			result.append({
				"name": name, "source": source,
				"page": int(ref.get("page", 0))
			})
	return result


func _on_catalog_ready(entries: Array[Dictionary]) -> void:
	var combined: Array[Dictionary] = entries.duplicate(true)
	var names_by_source: Dictionary = {}
	for entry: Dictionary in combined:
		names_by_source[(
			String(entry.get("name", "")) + "|"
			+ String(entry.get("source", ""))
		).to_lower()] = true
	for bundled: Dictionary in _bundled_bestiary_entries():
		var key: String = (
			String(bundled.get("name", "")) + "|"
			+ String(bundled.get("source", ""))
		).to_lower()
		if not names_by_source.has(key):
			names_by_source[key] = true
			combined.append(bundled)
	_catalog = ContentCatalog.merge("monsters", combined)
	_filter_catalog(_catalog_filter.text)
	_set_status("%d voci del bestiario ricercabili" % _catalog.size())


func _request_selected_monster() -> void:
	var chosen := _catalog_list.get_selected_items()
	if not chosen.is_empty():
		_request_monster(chosen[0])


func _request_monster(index: int) -> void:
	if index < 0 or index >= _filtered_catalog.size():
		return
	var entry := _filtered_catalog[index]
	if entry.get("origin") == "homebrew":
		_on_monster_received("homebrew", entry)
		return
	_client.call(
		"request_creature",
		String(entry.get("name", "")), String(entry.get("source", "")),
		"new_creature_%d" % Time.get_ticks_usec()
	)
	_set_status("Caricamento creatura da 5e.tools…")


func _on_monster_received(request_key: String, stat: Dictionary) -> void:
	if _auto_reference_requests.has(request_key):
		var record_id := String(_auto_reference_requests[request_key])
		_auto_reference_requests.erase(request_key)
		_complete_auto_reference(record_id, stat)
		return
	var record: Dictionary = _archive.create_monster(stat)
	record["kind"] = "monster"
	_choose_miniature(record, true)
	_set_status("Seleziona la miniatura predefinita per completare l’importazione.")


func refresh_owned_sheets() -> void:
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if node is Node3D and board_root.is_ancestor_of(node):
			if String(node.get_meta("creature_owner_id", "")) == Owner.local_id():
				ensure_sheet_for_token(node as Node3D)


# Called only for tokens created locally, or for tokens whose public owner ID
# now equals this installation after a remote ownership transfer. Never claim
# unowned tokens just because they are visible in a received scene.
func ensure_sheet_for_token(token: Node3D, locally_created: bool = false) -> void:
	if token == null or not is_instance_valid(token) or not board_root.is_ancestor_of(token):
		return
	var local_owner := Owner.local_id()
	var current_owner := String(token.get_meta("creature_owner_id", "")).strip_edges()
	if current_owner != local_owner and (not locally_created or not current_owner.is_empty()):
		return
	var token_id := ""
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null and sync.has_method("get_sync_id_for_node"):
		token_id = String(sync.call("get_sync_id_for_node", token))
	if token_id.is_empty():
		return
	var sheet_id := String(token.get_meta("creature_id", "")).strip_edges()
	var record: Dictionary = {}
	for owned: Dictionary in _archive.list_owned():
		if not sheet_id.is_empty() and String(owned.get("id", "")) == sheet_id:
			record = owned.duplicate(true)
			break
		if sheet_id.is_empty() and String(owned.get("linked_token_sync_id", "")) == token_id:
			record = owned.duplicate(true)
			break
	if not record.is_empty() and String(record.get("linked_token_sync_id", "")) == token_id:
		# A just-created token can be picked up by the sheet refresh before
		# the creation dialog applies its selected conditions. On the explicit
		# creation path persist those final conditions instead of letting the
		# early return later restore stale empty conditions from the sheet.
		if locally_created and token.has_method("get_conditions"):
			var initial_conditions: Array = token.call("get_conditions")
			if record.get("conditions", []) != initial_conditions:
				record["conditions"] = initial_conditions.duplicate()
				if _archive.save(record) == OK:
					_replace_current_record(record)
		# Keep all other existing sheet data, including player edits and HP.
		_set_token_sheet_metadata(token, record)
		return

	var newly_created: bool = record.is_empty()
	var display_name := String(token.call("get_display_name")) if token.has_method("get_display_name") else String(token.name)
	var pack_id := String(token.call("get_token_pack_id")) if token.has_method("get_token_pack_id") else ""
	var identity := String(token.call("get_miniature_identity")) if token.has_method("get_miniature_identity") else pack_id
	var reference: Dictionary = {}
	if TokenPackManager != null:
		reference = TokenPackManager.get_bestiary_reference(identity, "2014")
		if reference.is_empty():
			reference = TokenPackManager.get_bestiary_reference(identity, "2024")
	var is_character := String(token.get_meta("player_character_id", "")).strip_edges() != ""
	if record.is_empty():
		if is_character:
			record = _archive.create_character()
		else:
			var stat: Dictionary = {
				"name": String(reference.get("name", display_name)),
				"source": String(reference.get("source", "")),
			}
			if not reference.is_empty():
				# A lightweight official reference is always available even
				# while the full stat block is downloading.
				stat["bestiary_reference"] = reference.duplicate(true)
				stat["reference_pending"] = true
			record = _archive.create_monster(stat)
		if not sheet_id.is_empty():
			record["id"] = sheet_id
		record["name"] = display_name
	if pack_id.is_empty():
		pack_id = identity
	# Preserve conditions set during token creation before syncing the new
	# persistent sheet back to the token.
	if newly_created and token.has_method("get_conditions"):
		record["conditions"] = token.call("get_conditions")
	if newly_created:
		record["current_miniature_id"] = pack_id
		if token.has_method("get_size_name"):
			record["size_name"] = token.call("get_size_name")
		if token.has_method("get_footprint_cells"):
			record["footprint"] = token.call("get_footprint_cells")
		if token.has_method("get_reach_feet"):
			record["reach_feet"] = token.call("get_reach_feet")
		if token.has_method("get_visual_front_quarter_turns"):
			record["visual_front_quarter_turns"] = token.call("get_visual_front_quarter_turns")
		if token.has_method("get_party_id"):
			record["party_id"] = token.call("get_party_id")
	record["default_miniature_id"] = pack_id
	record["owner_id"] = local_owner
	record["linked_token_sync_id"] = token_id
	record["linked_token_name"] = display_name
	if _archive.save(record) != OK:
		push_warning("CreatureArea: impossibile creare la scheda per %s" % display_name)
		return
	_set_token_sheet_metadata(token, record)
	_sync_token_health(record)
	_reload()
	var saved_stat: Dictionary = record.get("stat_block", {})
	if bool(saved_stat.get("reference_pending", false)) and DisplayServer.get_name() != "headless":
		var key := "auto:%s" % String(record.get("id", ""))
		_auto_reference_requests[key] = String(record.get("id", ""))
		_client.call("request_creature", String(reference.get("name", "")), String(reference.get("source", "")), key)


func _set_token_sheet_metadata(token: Node3D, record: Dictionary) -> void:
	var id := String(record.get("id", ""))
	token.set_meta("creature_id", id)
	token.set_meta("creature_owner_id", Owner.local_id())
	token.set_meta("default_miniature_id", String(record.get("default_miniature_id", "")))
	if String(record.get("kind", "")) == "character":
		for key: String in ["master_creature_id", "master_creature_name", "master_creature_side"]:
			if token.has_meta(key):
				token.remove_meta(key)
		token.set_meta("player_character_id", id)
		token.set_meta("player_character_name", String(record.get("name", "")))
	else:
		for key: String in ["player_character_id", "player_character_name"]:
			if token.has_meta(key):
				token.remove_meta(key)
		token.set_meta("master_creature_id", id)
		token.set_meta("master_creature_name", String(record.get("name", "")))
		token.set_meta("master_creature_side", String(record.get("side", "ally")))


func _complete_auto_reference(id: String, stat: Dictionary) -> void:
	for owned: Dictionary in _archive.list_owned():
		if String(owned.get("id", "")) != id or String(owned.get("kind", "")) != "monster":
			continue
		var previous: Dictionary = owned.get("stat_block", {})
		if not bool(previous.get("reference_pending", false)):
			return
		owned["stat_block"] = stat.duplicate(true)
		owned["source"] = String(stat.get("source", ""))
		var completed: Dictionary = _archive.create_monster(stat)
		# Change only provisional defaults: explicit user edits take precedence.
		if int(owned.get("max_hp", 1)) == 1:
			owned["max_hp"] = completed.get("max_hp", 1)
			if int(owned.get("current_hp", 1)) == 1:
				owned["current_hp"] = completed.get("current_hp", 1)
		if int(owned.get("armor_class", 10)) == 10:
			owned["armor_class"] = completed.get("armor_class", 10)
		if _archive.save(owned) == OK:
			_reload()
			_sync_token_health(owned)
		return


func _on_creature_request_failed(request_key: String, message: String) -> void:
	if _auto_reference_requests.has(request_key):
		_auto_reference_requests.erase(request_key)
		push_warning("CreatureArea: scheda conservata senza stat block completo: %s" % message)
	else:
		_set_status(message)



# All creation paths (character, bestiary and GUI) share this mandatory picker.
func begin_add_creature() -> void:
	# Importing a bestiary monster already has its own search below the list.
	# The primary Add action creates a character directly.
	show_panel()
	_create_character()


func _build_miniature_dialog() -> void:
	_miniature_dialog = ConfirmationDialog.new()
	_miniature_dialog.title = "Miniatura predefinita"
	_miniature_dialog.dialog_text = ""
	_miniature_dialog.min_size = Vector2i(540, 340)
	(board_root.get_node("UI") as CanvasLayer).add_child(_miniature_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_miniature_dialog.get_vbox().add_child(body)
	_miniature_hint = Label.new()
	_miniature_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_miniature_hint.custom_minimum_size.y = 24
	body.add_child(_miniature_hint)
	_miniature_filter = LineEdit.new()
	_miniature_filter.placeholder_text = "Cerca miniatura per nome o ID..."
	_miniature_filter.clear_button_enabled = true
	_miniature_filter.text_changed.connect(_filter_miniatures)
	body.add_child(_miniature_filter)
	_miniature_list = ItemList.new()
	_miniature_list.custom_minimum_size = Vector2(0, 215)
	_miniature_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_miniature_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_miniature_list.item_selected.connect(_on_miniature_selected)
	_miniature_list.item_activated.connect(_on_miniature_selected)
	body.add_child(_miniature_list)
	_miniature_dialog.confirmed.connect(_confirm_miniature)


func _choose_miniature(record: Dictionary, is_new: bool, choose_current: bool = false) -> void:
	_picker_current = choose_current
	if record.is_empty():
		_set_status("Seleziona una creatura.")
		return
	_pending_miniature_record = record.duplicate(true)
	_pending_new_creature = is_new
	_miniature_dialog.title = (
		"Scegli aspetto attuale" if _picker_current else "Miniatura di base"
	)
	_miniature_choices.clear()
	_suggested_miniature_ids.clear()
	var raw: Variant = board_root.call("list_available_miniatures")
	if raw is Array:
		for candidate: Variant in raw:

			if candidate is Dictionary and not String(candidate.get("id", "")).is_empty():
				_miniature_choices.append((candidate as Dictionary).duplicate(true))
	# A ternary with [] returns an untyped Array in GDScript. Keep the
	# result typed on both paths, including creation of a new character.
	var associated_ids: Array[String] = []
	if String(record.get("kind", "")) == "monster":
		associated_ids = _associated_miniature_ids(
			String(record.get("name", record.get("base_name", ""))),
			String(record.get("source", ""))
		)
	for associated_id: String in associated_ids:
		for profile: Dictionary in _miniature_choices:
			if String(profile.get("id", "")) == associated_id:
				_suggested_miniature_ids.append(associated_id)
				break
	_miniature_choices.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := String(a.get("id", ""))
			var b_id := String(b.get("id", ""))
			var a_pos := _suggested_miniature_ids.find(a_id)
			var b_pos := _suggested_miniature_ids.find(b_id)
			if a_pos >= 0 or b_pos >= 0:
				if a_pos < 0:
					return false
				if b_pos < 0:
					return true
				return a_pos < b_pos
			return String(a.get("name", a_id)).naturalnocasecmp_to(
				String(b.get("name", b_id))
			) < 0
	)
	_miniature_hint.text = (
		"★ Le miniature associate alla voce del bestiario sono mostrate per prime."
		if not _suggested_miniature_ids.is_empty()
		else "Cerca nel catalogo e seleziona una miniatura."
	)
	_miniature_filter.text = ""
	# New characters must make an explicit selection. Do not silently
	# accept the first available miniature or a guessed species match.
	_chosen_miniature_id = (
		"" if is_new
		else String(record.get(
			"current_miniature_id" if _picker_current else "default_miniature_id", ""
		))
	)
	_filter_miniatures("")
	_miniature_dialog.popup_centered_clamped(Vector2i(620, 440), 0.85)


func _filter_miniatures(query: String) -> void:
	_miniature_list.clear()
	_visible_miniatures.clear()
	var needle := query.strip_edges().to_lower()
	var selected_index := -1
	for profile: Dictionary in _miniature_choices:
		var name := String(profile.get("name", profile.get("id", "Miniatura")))
		var id := String(profile.get("id", ""))
		if not needle.is_empty() and needle not in (name + " " + id).to_lower():
			continue
		var index := _visible_miniatures.size()
		_visible_miniatures.append(profile)
		_miniature_list.add_item("%s%s · %s" % [
			"★ " if id in _suggested_miniature_ids else "", name, id
		])
		if id == _chosen_miniature_id:
			selected_index = index
	if selected_index >= 0:
		_miniature_list.select(selected_index)
	else:
		_chosen_miniature_id = ""
	_miniature_dialog.get_ok_button().disabled = _chosen_miniature_id.is_empty()


func _on_miniature_selected(index: int) -> void:
	if index >= 0 and index < _visible_miniatures.size():
		_chosen_miniature_id = String(_visible_miniatures[index].get("id", ""))
		_miniature_dialog.get_ok_button().disabled = _chosen_miniature_id.is_empty()


func _confirm_miniature() -> void:
	if _chosen_miniature_id.is_empty() or _pending_miniature_record.is_empty():
		return
	var record: Dictionary = _pending_miniature_record.duplicate(true)
	if _picker_current:
		record["current_miniature_id"] = _chosen_miniature_id
	else:
		record["default_miniature_id"] = _chosen_miniature_id
		if _pending_new_creature or String(record.get("current_miniature_id", "")).is_empty():
			record["current_miniature_id"] = _chosen_miniature_id
		if _pending_new_creature:
			# The selected physical miniature supplies the initial size, but
			# changing an existing creature's base never overrides its size.
			for profile: Dictionary in _miniature_choices:
				if String(profile.get("id", "")) != _chosen_miniature_id:
					continue
				var size_name := String(profile.get("size_name", "Medium"))
				var footprint := maxf(0.5, float(profile.get("footprint", 1.0)))
				record["size_name"] = size_name
				record["footprint"] = footprint
				record["reach_feet"] = maxf(5.0, footprint * 5.0)
				break
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare la miniatura della creatura.")
		return
	_selected_id = String(record.get("id", ""))
	_selected_kind = String(record.get("kind", ""))
	var changed_current := _picker_current
	_pending_miniature_record.clear()
	_pending_new_creature = false
	_picker_current = false
	_reload()
	if changed_current:
		_apply_current_appearance(record)
	_set_status("Aspetto attuale aggiornato." if changed_current else
		"Miniatura di base selezionata: %s" % _chosen_miniature_id)

func _create_character() -> void:
	var record: Dictionary = _archive.create_character()
	record["kind"] = "character"
	_choose_miniature(record, true)


func _confirm_delete() -> void:
	var record := _current()
	if record.is_empty():
		return
	_delete_target = record.duplicate(true)
	_delete_dialog.dialog_text = "Eliminare definitivamente '%s' dal tuo archivio?\nVerranno eliminati anche i suoi token presenti nella scena." % String(record.get("name", "Creatura"))
	_delete_dialog.popup_centered()


func _delete_selected_creature() -> void:
	if _delete_target.is_empty():
		return
	var record := _delete_target.duplicate(true)
	_delete_target.clear()
	var error: Error = _archive.delete(record)
	if error != OK:
		_set_status("Eliminazione non riuscita: %s" % error_string(error))
		return
	_remove_deleted_creature_tokens(record)
	if _selected_id == String(record.get("id", "")) and _selected_kind == String(record.get("kind", "")):
		_selected_id = ""
		_selected_kind = ""
	_reload()
	_set_status("Creatura e relativi token eliminati.")


func _remove_deleted_creature_tokens(record: Dictionary) -> void:
	var creature_id: String = String(record.get("id", ""))
	var local_owner: String = Owner.local_id()
	var deleted: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is CharacterBody3D or not board_root.is_ancestor_of(node):
			continue
		if (
			String(node.get_meta("creature_id", "")) == creature_id
			and String(node.get_meta("creature_owner_id", "")) == local_owner
		):
			deleted.append(node as CharacterBody3D)
	if deleted.is_empty():
		return
	# Let the board clear selection, first-person camera and undo state,
	# and publish the deletion in the next synchronized board snapshot.
	if board_root.has_method("remove_owned_creature_tokens"):
		board_root.call("remove_owned_creature_tokens", deleted)
	else:
		for token: CharacterBody3D in deleted:
			token.queue_free()


func _link_selected_token() -> void:
	var selected_value: Variant = board_root.call(
		"get_selected_tokens_for_creatures"
	)
	if not selected_value is Array or (selected_value as Array).size() != 1:
		_set_status("Seleziona un solo token nella scena.")
		return
	var record := _current()
	if record.is_empty():
		return
	var token: Node3D = (selected_value as Array)[0] as Node3D
	if token == null:
		return
	if token.has_meta("creature_owner_id") and String(token.get_meta("creature_owner_id")) != Owner.local_id():
		_set_status("Il token è associato a una creatura di un altro controllore.")
		return
	var creature_id := String(record.get("id", ""))
	for other: Node in get_tree().get_nodes_in_group("dnd_token"):
		if other != token and other.has_meta("creature_id"):
			if String(other.get_meta("creature_id", "")) == creature_id:
				for field: String in [
					"creature_id", "creature_owner_id", "default_miniature_id",
					"player_character_id", "player_character_name",
					"master_creature_id", "master_creature_name",
					"master_creature_side"
				]:
					if other.has_meta(field):
						other.remove_meta(field)
	for field: String in [
		"player_character_id", "player_character_name",
		"master_creature_id", "master_creature_name",
		"master_creature_side"
	]:
		if token.has_meta(field):
			token.remove_meta(field)
	token.set_meta("creature_id", creature_id)
	token.set_meta("creature_owner_id", Owner.local_id())
	token.set_meta("default_miniature_id", String(record.get("default_miniature_id", "")))
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null:
		record["linked_token_sync_id"] = String(
			sync.call("get_sync_id_for_node", token)
		)
	record["linked_token_name"] = String(token.call("get_display_name"))
	if String(record.get("kind", "")) == "character":
		token.set_meta("player_character_id", creature_id)
		token.set_meta("player_character_name", String(record.get("name", "")))
	else:
		token.set_meta("master_creature_id", creature_id)
		token.set_meta("master_creature_name", String(record.get("name", "")))
		token.set_meta("master_creature_side", String(record.get("side", "ally")))
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_sync_token_health(record)
		_refresh_current_miniature(record)
		_set_status("Creatura associata alla miniatura senza modificarne l'aspetto.")


func _species_default_miniature(species: String) -> String:
	if species.is_empty():
		return ""
	# Never guess token pack IDs. Pick an actually published pack only
	# when its label unambiguously matches the 5e.tools species.
	var packs := get_node_or_null("/root/TokenPackManager")
	if packs == null:
		return ""
	for entry: Dictionary in packs.call("get_entries"):
		if String(entry.get("name", "")).nocasecmp_to(species) == 0:
			return String(entry.get("id", ""))
	return ""


func _edit_linked_token_appearance() -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	_choose_miniature(record, false, true)


func _miniature_display_name(miniature_id: String) -> String:
	if miniature_id.is_empty():
		return "Nessuna miniatura selezionata"
	if board_root.has_method("list_available_miniatures"):
		var profiles: Variant = board_root.call("list_available_miniatures")
		if profiles is Array:
			for raw: Variant in profiles:
				if raw is Dictionary and String(raw.get("id", "")) == miniature_id:
					return String(raw.get("name", miniature_id))
	return miniature_id


func _refresh_current_miniature(record: Dictionary) -> void:
	var current_id := String(record.get("current_miniature_id", ""))
	if current_id.is_empty():
		current_id = String(record.get("default_miniature_id", ""))
	var token := find_linked_token_for_creature(String(record.get("id", "")))
	_current_miniature.text = (
		"Aspetto attuale: %s%s" % [
			_miniature_display_name(current_id),
			" · token in scena" if token != null else " · salvato per il prossimo token"
		]
	)


func _find_linked_token(record: Dictionary) -> Node3D:
	var token_id := String(record.get("linked_token_sync_id", ""))
	if token_id.is_empty():
		return null
	var sync: Node = board_root.get("board_sync") as Node
	if sync == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is Node3D or not board_root.is_ancestor_of(node):
			continue
		if String(sync.call("get_sync_id_for_node", node)) == token_id and String(node.get_meta("creature_id", "")) == String(record.get("id", "")) and String(node.get_meta("creature_owner_id", "")) == Owner.local_id():
			return node as Node3D
	return null


# Combat damage must use the same persistent sheet as the token's health bar.
# The legacy PlayerArea is no longer instantiated.
func apply_attack_damage_to_token(target: Node3D, damage: int) -> Dictionary:
	if target == null or not is_instance_valid(target) or damage < 0:
		return {"applied": false}
	if String(target.get_meta("creature_owner_id", "")) != Owner.local_id():
		return {"applied": false}
	var creature_id := String(target.get_meta("creature_id", ""))
	for owned: Dictionary in _archive.list_owned():
		if String(owned.get("id", "")) != creature_id:
			continue
		var hp_max := maxi(0, int(owned.get("max_hp", 0)))
		if hp_max <= 0:
			return {"applied": false}
		var hp_now := clampi(int(owned.get("current_hp", hp_max)), 0, hp_max)
		var temp_hp := maxi(0, int(owned.get("temporary_hp", 0)))
		var absorbed := mini(temp_hp, damage)
		temp_hp -= absorbed
		hp_now = maxi(0, hp_now - (damage - absorbed))
		owned["current_hp"] = hp_now
		owned["temporary_hp"] = temp_hp
		if _archive.save(owned) != OK:
			return {"applied": false}
		_replace_current_record(owned)
		_sync_token_health(owned)
		if String(owned.get("id", "")) == _selected_id and is_panel_open():
			_load_form(owned)
		return {
			"applied": true,
			"current_hp": hp_now,
			"max_hp": hp_max,
			"temporary_hp": temp_hp
		}
	return {"applied": false}


func _sync_token_health(record: Dictionary) -> void:
	var token := _find_linked_token(record)
	if token == null:
		return
	var method := (
		"set_player_hit_points"
		if String(record.get("kind", "")) == "character"
		else "set_master_hit_points"
	)
	token.set_meta("rules_version", String(record.get("rules_version", "2014")))
	if token.has_method("set_display_name"):
		token.call("set_display_name", String(record.get("name", "")))
	if token.has_method("set_conditions"):
		token.call("set_conditions", record.get("conditions", []))
	if token.has_method(method):
		token.call(
			method, int(record.get("current_hp", 1)),
			int(record.get("max_hp", 1))
		)


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in _records:
		var id := String(record.get("linked_token_sync_id", ""))
		var maximum := int(record.get("max_hp", 0))
		if id.is_empty() or maximum <= 0 or _find_linked_token(record) == null:
			continue
		rows.append({
			"token_id": id,
			"percent": clampf(
				float(record.get("current_hp", 0)) / float(maximum) * 100.0,
				0.0, 100.0
			)
		})
	return rows


func _transfer() -> void:
	var record := _current()
	if record.is_empty():
		return
	var package: Dictionary = _archive.relinquish(
		record, _owner_target.text
	)
	if package.is_empty():
		_set_status("ID non valido o cessione non salvata.")
		return
	var linked_token := _find_linked_token(record)
	if linked_token != null:
		linked_token.set_meta("creature_owner_id", String(package.get("recipient", "")))
		var sync: Node = board_root.get("board_sync") as Node
		if sync != null and sync.has_method("sync_local_change_now"):
			sync.call_deferred("sync_local_change_now")
	# Optional recovery copy of the full private sheet; never required to
	# accept ownership of the miniature in a synchronized scene.
	DisplayServer.clipboard_set(JSON.stringify(package))
	_selected_id = ""
	_selected_kind = ""
	_reload()
	_set_status(
		"Controllo trasferito automaticamente al destinatario tramite la mappa. "
		+ "Il codice privato copiato è facoltativo per recuperare i dettagli "
		+ "completi della scheda."
	)


func _show_import() -> void:
	_import_text.clear()
	_import_dialog.popup_centered_clamped(Vector2i(720, 340), 0.9)


func _import() -> void:
	var parsed: Variant = JSON.parse_string(_import_text.text)
	if not parsed is Dictionary:
		_set_status("Codice di trasferimento non valido.")
		return
	var error: Error = _archive.import_transfer(parsed as Dictionary)
	if error != OK:
		_set_status(
			"Importazione non riuscita: ID di destinazione errato o codice non valido."
		)
		return
	var creature: Dictionary = (parsed as Dictionary).get("creature", {})
	_selected_id = String(creature.get("id", ""))
	_selected_kind = String(creature.get("kind", ""))
	_reload()
	_set_status("Ora sei il controllore di questa creatura.")


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _refresh_conditions(record: Dictionary) -> void:
	for child: Node in _condition_rows.get_children():
		_condition_rows.remove_child(child)
		child.queue_free()
	var active: Array = record.get("conditions", [])
	var definitions := ContentCatalog.condition_definitions(
		String(record.get("rules_version", "2014"))
	)
	for category: String in ["conditions", "effects", "diseases"]:
		var has_section := false
		for definition: Dictionary in definitions:
			if String(definition.get("category", "conditions")) != category:
				continue
			if not has_section:
				var heading := Label.new()
				heading.text = {
					"conditions": "Conditions",
					"diseases": "Diseases / magical diseases",
					"effects": "Other effects (5etools / homebrew)"
				}[category]
				heading.add_theme_font_size_override("font_size", 15)
				_condition_rows.add_child(heading)
				has_section = true
			var row := HBoxContainer.new()
			_condition_rows.add_child(row)
			var check := CheckButton.new()
			check.text = "%s %s" % [
				String(definition.get("icon", "•")),
				String(definition.get("name", String(definition.id)))
			]
			check.tooltip_text = ContentCatalog.description(definition)
			check.button_pressed = String(definition.id) in active
			check.toggled.connect(_set_sheet_condition.bind(String(definition.id)))
			row.add_child(check)
			var info := Button.new()
			info.text = "Leggi effetti"
			info.pressed.connect(_show_effect_description.bind(definition.duplicate(true)))
			row.add_child(info)


func _show_effect_description(definition: Dictionary) -> void:
	if _effect_dialog == null or _effect_text == null:
		return
	_effect_dialog.title = String(definition.get("name", "Effect"))
	_effect_text.text = ContentCatalog.description(definition)
	_effect_dialog.popup_centered(Vector2i(600, 450))


func _set_sheet_condition(enabled: bool, id: String) -> void:
	var record := _current()
	if record.is_empty():
		return
	var active: Array = record.get("conditions", []).duplicate()
	if enabled and id not in active:
		active.append(id)
	elif not enabled:
		active.erase(id)
	record["conditions"] = active
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_sync_token_health(record)


func _reload_homebrew() -> void:
	_save()
	ContentCatalog.reload_homebrew()
	_set_reference_choices(_species, Player5eTools.entries("races"))
	_refresh_class_choices()
	_reload()
	_on_catalog_ready(_client.call("catalog"))
	_set_status("Homebrew ricaricato. " + "\n".join(ContentCatalog.diagnostics))
