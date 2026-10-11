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
const RaceRules = preload("res://vtt/creature_race_rules.gd")
const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")
const FiveToolsText = preload("res://vtt/five_tools_rich_text.gd")
const StructuredTrackers = preload("res://vtt/structured_resource_trackers.gd")
const FormulaValue = preload("res://vtt/formula_value.gd")
const BonusRules = preload("res://vtt/creature_bonus_rules.gd")
const BonusTab = preload("res://vtt/creature_bonus_tab.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const TraitsTab = preload("res://vtt/creature_traits_tab.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const Skills5e = preload("res://vtt/creature_skills_5etools.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const ProficiencyRules = preload("res://vtt/creature_proficiency_rules.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const DocumentInbox = preload("res://vtt/document_inbox.gd")
const DocumentStore = preload("res://vtt/document_homebrew.gd")

var board_root: Node3D
var _archive
var _client: Node
var _records: Array[Dictionary] = []
# Lightweight name index used by initiative snapshots. Rebuilt only when sheets change.
var _owned_name_index: Dictionary = {}
var _selected_id := ""
var _selected_kind := ""
# Hidden editors are rebuilt only when opened, not during every sheet switch.
var _traits_stale := true
var _proficiencies_stale := true
var _bonuses_stale := true
var _catalog: Array[Dictionary] = []
var _filtered_catalog: Array[Dictionary] = []
var _loading := false

var _panel: PanelContainer
var _status: Label
var _creature_list: VBoxContainer
var _creature_filter: LineEdit
var _creature_empty: Label
var _abilities_grid: GridContainer
var _statistics_columns: HBoxContainer
var _skills_panel: VBoxContainer
var _skill_buttons: Dictionary = {}
var _skill_values: Dictionary = {}
var _skill_ranks: Dictionary = {}
var _skill_ranks_custom := false
var _proficiency_display: Label
var _passive_perception: Label
var _attacks_description: RichTextLabel
var _creature_list_scroll: ScrollContainer
var _creature_row_buttons: Array[Button] = []
var _creature_eye_buttons: Array[Button] = []
var _creature_presence_elapsed := 0.0
var _creature_context_menu: PopupMenu
var _automatic_dialog: ConfirmationDialog
var _automatic_hp: CheckBox
var _automatic_proficiency: CheckBox
var _automatic_spells: CheckBox
var _automatic_slots: CheckBox
var _automatic_derived: CheckBox
var _automatic_combat: CheckBox
var _automatic_trackers: CheckBox
var _automatic_preview: RichTextLabel
var _automatic_target_id := ""
var _delete_dialog: ConfirmationDialog
var _delete_target: Dictionary = {}
var _catalog_list: ItemList
var _catalog_filter: LineEdit
var _name: LineEdit
var _hp: SpinBox
var _max_hp: SpinBox
var _max_hp_effective: Label
var _second_form_hp: SpinBox
var _second_form_max_hp: SpinBox
var _biography: TextEdit
var _subclass_caption: Label
var _level_caption: Label
var _xp: SpinBox
var _initiative_effective: Label
var _ac_effective: Label
var _speed_custom := false
var _speed: SpinBox
var _speed_effective: Label
var _ability_total_labels: Dictionary = {}
var _formula_values: Dictionary = {}
# A single statistics refresh must reuse its already-built live record.
var _formula_snapshot_override: Dictionary = {}
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
var _attack_ability: OptionButton
var _weapon_picker: OptionButton
var _weapon_options: Array[Dictionary] = []
var _attack_rows: VBoxContainer
var _attack_hit_labels: Dictionary = {}
var _attack_damage_labels: Dictionary = {}
var _attack_range_labels: Dictionary = {}
var _front: OptionButton
var _party: LineEdit
var _tabs: TabContainer
var _spellcasting_ui: Node
var _inventory_ui: Node
var _ac: SpinBox
var _ability_spins: Dictionary = {}
var _ability_modifier_labels: Dictionary = {}
var _saving_throw_labels: Dictionary = {}
var _saving_throw_icons: Dictionary = {}
var _tools_proficiency_label: Label
var _languages_proficiency_label: Label
var _species: OptionButton
var _subrace_choice: OptionButton
var _subrace_caption: Label
var _challenge_caption: Label
var _challenge_rating: LineEdit
var _creature_type_display: Label
var _background: OptionButton
var _subclass_name: OptionButton
var _class_name: OptionButton
var _add_class_button: Button
var _rules_edition: OptionButton
var _rules_edition_caption: Label
var _additional_classes_title: Label
var _multiclass_rows: VBoxContainer
var _multiclass_controls: Array[Dictionary] = []
var _level: SpinBox
var _default_miniature: LineEdit
var _current_miniature_row: HBoxContainer
var _current_miniature_name: LineEdit
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
var _tracker_rows: VBoxContainer
var _bonuses_ui: Node
var _bonuses_toggle_button: Button
var _proficiencies_ui: Node
var _proficiencies_toggle_button: Button
var _traits_ui: Node
var _condition_rows: VBoxContainer
var _effect_dialog: AcceptDialog
var _effect_text: RichTextLabel
var _transfer_users: OptionButton
var _transfer_hint: Label
var _export_dialog: FileDialog
var _options_menu: MenuButton
var _transfer_dialog: ConfirmationDialog
var _suggested_miniature_ids: Array[String] = []
var _import_dialog: AcceptDialog
var _import_text: TextEdit
var _auto_reference_requests: Dictionary = {}
var _form_hp_requests: Dictionary = {}
var _form_hp_dialog: ConfirmationDialog
var _form_hp_choice: OptionButton
var _form_hp_manual: SpinBox
var _form_hp_pending_id := ""
var _form_depleted_target_id := ""
var _restore_form_dialog: ConfirmationDialog
var _form_depleted_dialog: ConfirmationDialog


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
	_build_export_dialog()
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


# Initiative serialization needs names only; never normalize full sheets on a poll.
func get_owned_creature_name_index() -> Dictionary:
	return _owned_name_index.duplicate()


# The board context menu must read the CURRENT owned archive, not the
# selected sheet or the last UI refresh. This includes creatures whose
# token is currently absent and creatures legitimately transferred to us.
func get_owned_creatures_for_placement() -> Array[Dictionary]:
	var owned: Array[Dictionary] = []
	for record: Dictionary in _archive.list_owned():
		if Owner.is_owner(record):
			owned.append(record.duplicate(true))
	return owned


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
	# The menu may be clicked while this sheet is already open. Re-reading and
	# re-normalizing every character here used to freeze the rendering thread.
	if _panel.visible:
		return
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
			or _transfer_dialog.visible
			or _delete_dialog.visible
		):
			hide_panel()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CreatureSheet"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Reduce outer gutters; keep the window entirely inside the viewport.
	_panel.offset_left = 12
	_panel.offset_top = 52
	_panel.offset_right = -12
	_panel.offset_bottom = -12
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure UI sheets outrank any remaining tactical screen-space badges.
	_panel.z_index = 30
	_panel.hide()
	(board_root.get_node("UI") as CanvasLayer).add_child(_panel)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	outer.add_child(header)

	var heading := Label.new()
	heading.text = "ARCHIVIO DELLE CREATURE"
	heading.clip_text = true
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.tooltip_text = heading.text
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override(
		"font_color", Color(0.96, 0.79, 0.51, 1.0)
	)
	header.add_child(heading)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_options_menu = MenuButton.new()
	_options_menu.text = "Opzioni ▾"
	var popup := _options_menu.get_popup()
	popup.add_item("Copia il mio ID", 1)
	popup.add_item("Cartella homebrew", 2)
	popup.add_item("Cartella integrazioni VTT", 9)
	popup.add_item("Ricarica homebrew", 3)
	popup.add_separator()
	popup.add_item("Associa a token selezionato", 4)
	popup.add_item("Cedi controllo…", 5)
	popup.add_item("Ricevi creatura…", 6)
	popup.add_item("Scarica creatura…", 8)
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
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override(
		"font_color", Color(0.78, 0.71, 0.63, 1.0)
	)
	outer.add_child(_status)

	var columns := HSplitContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 210
	outer.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(185, 0)
	left.add_theme_constant_override("separation", 5)
	columns.add_child(left)
	var creatures_title := Label.new()
	creatures_title.text = "Le mie creature"
	creatures_title.add_theme_font_size_override("font_size", 17)
	creatures_title.add_theme_color_override(
		"font_color", Color(0.94, 0.76, 0.46, 1.0)
	)
	left.add_child(creatures_title)
	_creature_filter = LineEdit.new()
	_creature_filter.placeholder_text = "Cerca tra le mie creature…"
	_creature_filter.clear_button_enabled = true
	_creature_filter.text_changed.connect(_filter_owned_creatures)
	left.add_child(_creature_filter)
	_creature_empty = Label.new()
	_creature_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_creature_empty.add_theme_font_size_override("font_size", 13)
	_creature_empty.hide()
	left.add_child(_creature_empty)
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
	_creature_context_menu.add_item("Calcola automaticamente…", 2)
	_creature_context_menu.add_item("Cedi controllo…", 4)
	_creature_context_menu.add_separator()
	_creature_context_menu.add_item("Elimina creatura…", 3)
	_creature_context_menu.id_pressed.connect(_on_creature_context_action)
	_creature_list.add_child(_creature_context_menu)

	var add_general := Button.new()
	add_general.text = "+ Personaggio"
	add_general.tooltip_text = "Crea una nuova scheda di personaggio"
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
	add_monster.text = "+ Dal bestiario"
	add_monster.tooltip_text = "Aggiungi una creatura dalla voce selezionata nel bestiario"
	add_monster.pressed.connect(_request_selected_monster)
	left.add_child(add_monster)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.add_child(_tabs)
	var form := _add_sheet_tab(_tabs, "Info")
	var statistics_tab := _add_sheet_tab(_tabs, "Statistiche")
	_proficiencies_toggle_button = Button.new()
	_proficiencies_toggle_button.text = "▸ Visualizza competenze"
	_proficiencies_toggle_button.tooltip_text = "Mostra o nasconde le origini e le competenze della creatura"
	statistics_tab.add_child(_proficiencies_toggle_button)
	_proficiencies_ui = ProficiencyTab.new()
	_proficiencies_ui.visible = false
	statistics_tab.add_child(_proficiencies_ui)
	_proficiencies_ui.call("setup", Callable(self, "_on_proficiencies_updated"))
	_proficiencies_toggle_button.pressed.connect(func() -> void:
		if not _proficiencies_ui.visible and _proficiencies_stale:
			var record: Dictionary = _current()
			_proficiencies_ui.call("load_record", record)
			_proficiencies_stale = false
		_proficiencies_ui.visible = not _proficiencies_ui.visible
		_proficiencies_toggle_button.text = "▾ Nascondi competenze" if _proficiencies_ui.visible else "▸ Visualizza competenze"
		call_deferred("_update_stats_column_heights")
	)
	_bonuses_toggle_button = Button.new()
	_bonuses_toggle_button.text = "▸ Visualizza bonus"
	_bonuses_toggle_button.tooltip_text = "Visualizza i bonus cumulabili di ogni valore con cornice blu"
	statistics_tab.add_child(_bonuses_toggle_button)
	_bonuses_ui = BonusTab.new()
	_bonuses_ui.hide()
	statistics_tab.add_child(_bonuses_ui)
	_bonuses_ui.call("setup", Callable(self, "_on_bonuses_updated"))
	_bonuses_toggle_button.pressed.connect(func() -> void:
		if not _bonuses_ui.visible and _bonuses_stale:
			_bonuses_ui.call("load_record", _current())
			_bonuses_stale = false
		_bonuses_ui.visible = not _bonuses_ui.visible
		_bonuses_toggle_button.text = "▾ Nascondi bonus" if _bonuses_ui.visible else "▸ Visualizza bonus"
		call_deferred("_update_stats_column_heights")
	)
	# Always keep skills and combat side by side (45% / 55%).  Scroll
	# their oversized contents locally instead of expanding the whole sheet.
	_statistics_columns = HBoxContainer.new()
	_statistics_columns.add_theme_constant_override("separation", 10)
	_statistics_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	statistics_tab.add_child(_statistics_columns)
	var skills_view := ScrollContainer.new()
	skills_view.name = "SkillsColumnView"
	skills_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_view.size_flags_stretch_ratio = 0.9
	skills_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	skills_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skills_view.follow_focus = true
	_statistics_columns.add_child(skills_view)
	var skills_column := VBoxContainer.new()
	skills_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_view.add_child(skills_column)
	var combat_view := ScrollContainer.new()
	combat_view.name = "CombatColumnView"
	combat_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combat_view.size_flags_stretch_ratio = 1.1
	combat_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	combat_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	combat_view.follow_focus = true
	_statistics_columns.add_child(combat_view)
	var combat_column := VBoxContainer.new()
	combat_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combat_view.add_child(combat_column)
	var appearance_tab := _add_sheet_tab(_tabs, "Aspetto")
	var traits_tab := _add_sheet_tab(_tabs, "Tratti")
	var conditions_tab := _add_sheet_tab(_tabs, "Stati")
	var spellcasting_tab := _add_sheet_tab(_tabs, "Incantesimi")
	_spellcasting_ui = SpellcastingTab.new()
	spellcasting_tab.add_child(_spellcasting_ui)
	_spellcasting_ui.call(
		"setup",
		Callable(self, "_on_spellcasting_updated"),
		Callable(self, "_set_status"),
		Callable(self, "_on_spellcasting_cast_requested"),
		Callable(self, "_on_formula_bonus_requested")
	)
	var inventory_tab := _add_sheet_tab(_tabs, "Inventario")
	_inventory_ui = InventoryTab.new()
	inventory_tab.add_child(_inventory_ui)
	_inventory_ui.call(
		"setup", Callable(self, "_on_inventory_updated"), Callable(self, "_set_status"),
		Callable(self, "_on_documents_updated"),
		Callable(self, "_send_document_to_peer"), Callable(self, "_get_document_peers")
	)
	_tabs.current_tab = 0

	var identity_box := _info_panel(form, "IDENTITÀ")
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	identity_box.add_child(name_row)
	_rules_edition_caption = Label.new()
	_rules_edition_caption.text = "Regole"
	_rules_edition_caption.tooltip_text = "Edizione delle regole del personaggio"
	name_row.add_child(_rules_edition_caption)
	_rules_edition = OptionButton.new()
	_rules_edition.fit_to_longest_item = false
	_rules_edition.custom_minimum_size = Vector2(76, 30)
	_rules_edition.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rules_edition.add_item("2014")
	_rules_edition.add_item("2024")
	_rules_edition.select(0)
	_rules_edition.item_selected.connect(_on_rules_edition_changed)
	name_row.add_child(_rules_edition)
	_add_label(name_row, "Nome")
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_v: String) -> void: _save())
	name_row.add_child(_name)
	_add_label(name_row, "Fazione")
	_party = LineEdit.new()
	_party.custom_minimum_size.x = 85
	_party.size_flags_horizontal = Control.SIZE_SHRINK_END
	_party.placeholder_text = "Default"
	_party.text_changed.connect(func(_text: String) -> void: _save())
	name_row.add_child(_party)

	var health_panel := PanelContainer.new()
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = Color(0.24, 0.14, 0.15, 0.96)
	health_style.border_color = Color(0.76, 0.50, 0.30, 0.90)
	health_style.set_border_width_all(1)
	health_style.set_corner_radius_all(7)
	health_style.set_content_margin_all(5)
	health_panel.add_theme_stylebox_override("panel", health_style)
	health_panel.tooltip_text = "Danni: prima temporanei, poi PF della seconda forma, infine PF normali."
	combat_column.add_child(health_panel)
	var health_content := VBoxContainer.new()
	health_panel.add_child(health_content)
	var health_title := Label.new()
	health_title.text = "PUNTI FERITA"
	health_title.add_theme_font_size_override("font_size", 17)
	health_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.65))
	_style_statistics_heading(health_title)
	health_content.add_child(health_title)
	var health := HFlowContainer.new()
	health.add_theme_constant_override("h_separation", 5)
	health.add_theme_constant_override("v_separation", 5)
	health_content.add_child(health)
	var damage := Button.new()
	damage.text = "−"
	damage.tooltip_text = "Sottrai PF: inserisci un valore o tira un dado"
	damage.custom_minimum_size.x = 30
	damage.pressed.connect(_open_hp_delta.bind(-1))
	_hp = _spin(health, -999, 99999)
	_hp.tooltip_text = "Punti ferita attuali"
	_hp.custom_minimum_size = Vector2(68, 36)
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_label(health, "/")
	_max_hp_effective = Label.new()
	_max_hp_effective.tooltip_text = "PF massimi effettivi"
	health.add_child(_max_hp_effective)
	_max_hp = _spin(health, 0, 99999)
	_max_hp.custom_minimum_size = Vector2(68, 36)
	_max_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_max_hp.tooltip_text = "PF massimi base, prima dei bonus"
	_install_formula("hp", _max_hp_effective, [_max_hp], ["Base"])
	# Current HP actions lead the row; the TEMP caption follows its input.
	var health_actions := HBoxContainer.new()
	health.add_child(health_actions)
	_add_label(health, "+")
	_temp_hp = _spin(health, 0, 99999)
	_temp_hp.custom_minimum_size.x = 68
	_add_label(health, "TEMP")
	_max_hp.value_changed.connect(func(_v: float) -> void: _update_max_hp_display())
	var heal := Button.new()
	heal.text = "+"
	heal.tooltip_text = "Aggiungi PF: inserisci un valore o tira un dado"
	heal.custom_minimum_size.x = 30
	heal.pressed.connect(_open_hp_delta.bind(1))
	# Adjacent − and + form a single compact health-action group.
	health_actions.add_child(damage)
	health_actions.add_child(heal)
	var restore_hp := Button.new()
	restore_hp.text = "↺"
	restore_hp.tooltip_text = "Ripristina i PF al valore massimo"
	restore_hp.custom_minimum_size.x = 30
	restore_hp.pressed.connect(_restore_full_hp)
	health_actions.add_child(restore_hp)
	health.move_child(health_actions, 0)
	_add_label(health, "Attuali")
	health.move_child(health.get_child(health.get_child_count() - 1), 1)
	var form_hp_row := HBoxContainer.new()
	form_hp_row.add_theme_constant_override("separation", 6)
	health_content.add_child(form_hp_row)
	_add_label(form_hp_row, "Seconda forma")
	_second_form_hp = SpinBox.new()
	_second_form_hp.min_value = 0
	_second_form_hp.max_value = 99999
	_second_form_hp.step = 1
	_second_form_hp.rounded = true
	_second_form_hp.custom_minimum_size = Vector2(68, 30)
	_second_form_hp.value_changed.connect(_on_form_hp_changed)
	form_hp_row.add_child(_second_form_hp)
	_add_label(form_hp_row, "/")
	_second_form_max_hp = _spin(form_hp_row, 0, 99999)
	_second_form_max_hp.custom_minimum_size.x = 68
	var second_max_label := Label.new()
	form_hp_row.add_child(second_max_label)
	_install_formula("second_max", second_max_label, [_second_form_max_hp], ["Massimo"])
	_second_form_max_hp.value_changed.connect(func(_v: float) -> void:
		if not _loading and int(_second_form_hp.value) > int(_second_form_max_hp.value):
			_second_form_hp.value = _second_form_max_hp.value
	)
	_second_form_hp.tooltip_text = "PF attuali della seconda forma; si consumano dopo quelli temporanei."
	_second_form_max_hp.value_changed.connect(func(_v: float) -> void: _update_second_max_formula())
	_second_form_max_hp.tooltip_text = "PF massimi della seconda forma (polimorfia o forma selvatica)"
	var defense_flow := HFlowContainer.new()
	defense_flow.add_theme_constant_override("h_separation", 8)
	defense_flow.add_theme_constant_override("v_separation", 5)
	combat_column.add_child(defense_flow)
	var temp_health := HBoxContainer.new()
	temp_health.add_theme_constant_override("separation", 6)
	defense_flow.add_child(temp_health)
	_add_label(temp_health, "CA")
	_ac_effective = Label.new()
	_ac_effective.custom_minimum_size.x = 28
	temp_health.add_child(_ac_effective)
	_ac = _spin(temp_health, 0, 99)
	_ac.custom_minimum_size = Vector2(62, 36)
	_ac.tooltip_text = "Classe Armatura base, prima dei bonus"
	_install_formula("ac", _ac_effective, [_ac], ["Base"])
	_ac.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var movement_row := HBoxContainer.new()
	movement_row.add_theme_constant_override("separation", 6)
	defense_flow.add_child(movement_row)
	_add_label(movement_row, "Iniziativa")
	_initiative_effective = Label.new()
	_initiative_effective.custom_minimum_size.x = 32
	movement_row.add_child(_initiative_effective)
	_install_formula("initiative", _initiative_effective, [], [])
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	defense_flow.add_child(speed_row)
	_add_label(speed_row, "Velocità (ft)")
	_speed_effective = Label.new()
	speed_row.add_child(_speed_effective)
	_speed = SpinBox.new()
	_speed.min_value = 0
	_speed.max_value = 999
	_speed.step = 1
	_speed.update_on_text_changed = true
	_speed.custom_minimum_size = Vector2(69, 36)
	_speed.value_changed.connect(_on_speed_changed)
	speed_row.add_child(_speed)
	_speed.tooltip_text = "Velocità dalla specie o dal bestiario, modificabile"
	_install_formula("speed", _speed_effective, [_speed], ["Base"])
	_speed.value_changed.connect(func(_value: float) -> void: _update_speed_display())
	_ac.value_changed.connect(func(_value: float) -> void: _update_defense_display())

	var abilities_panel := PanelContainer.new()
	var abilities_style := health_style.duplicate() as StyleBoxFlat
	# Keep the section outline but no tinted fill behind proficiency emojis.
	abilities_style.draw_center = false
	abilities_style.border_color = Color(0.39, 0.61, 0.67, 0.92)
	abilities_panel.add_theme_stylebox_override("panel", abilities_style)
	_abilities_grid = GridContainer.new()
	var abilities_row := _abilities_grid
	# One four-column table keeps characteristic, score, modifier and
	# saving throw aligned without repeating the TS label on every row.
	abilities_row.columns = 4
	abilities_row.add_theme_constant_override("h_separation", 8)
	abilities_row.add_theme_constant_override("v_separation", 7)
	var ability_title := Label.new()
	ability_title.text = "CARATTERISTICHE"
	ability_title.add_theme_font_size_override("font_size", 17)
	ability_title.add_theme_color_override("font_color", Color(0.72, 0.88, 0.96))
	_style_statistics_heading(ability_title)
	skills_column.add_child(abilities_panel)
	var abilities_content := VBoxContainer.new()
	abilities_content.add_theme_constant_override("separation", 8)
	abilities_panel.add_child(abilities_content)
	abilities_content.add_child(ability_title)
	abilities_content.add_child(abilities_row)
	for ability_column_title: String in ["Car.", "Punteggio", "Mod.", "TS"]:
		var column_heading := Label.new()
		column_heading.text = ability_column_title
		column_heading.add_theme_font_size_override("font_size", 12)
		column_heading.add_theme_color_override("font_color", Color(0.80, 0.88, 0.95))
		abilities_row.add_child(column_heading)
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var ability_label := Label.new()
		ability_label.text = ability.to_upper()
		ability_label.custom_minimum_size.x = 34
		abilities_row.add_child(ability_label)
		var scores_row := HBoxContainer.new()
		scores_row.add_theme_constant_override("separation", 4)
		abilities_row.add_child(scores_row)
		var spin := _spin(scores_row, 1, 30)
		spin.custom_minimum_size.x = 54
		spin.tooltip_text = "Punteggio base"
		_ability_spins[ability] = spin
		var total_score := Label.new()
		total_score.custom_minimum_size.x = 28
		scores_row.add_child(total_score)
		_ability_total_labels[ability] = total_score
		_install_formula("ability:" + ability, total_score, [spin], ["Base"])
		var modifier := Label.new()
		modifier.custom_minimum_size.x = 42
		modifier.tooltip_text = "Modificatore calcolato dal punteggio e dal bonus"
		abilities_row.add_child(modifier)
		_ability_modifier_labels[ability] = modifier
		_install_formula("ability_mod:" + ability, modifier, [], [])
		var saving_throw := Label.new()
		saving_throw.text = "+0"
		saving_throw.tooltip_text = "Tiro salvezza: modificatore caratteristica + competenza, se posseduta"
		# Keep proficiency icon and numeric formula in independent, aligned cells.
		var save_cell := HBoxContainer.new()
		save_cell.add_theme_constant_override("separation", 3)
		abilities_row.add_child(save_cell)
		var save_icon := Label.new()
		save_icon.custom_minimum_size.x = 28
		save_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_saving_throw_icons[ability] = save_icon
		saving_throw.add_theme_font_size_override("font_size", 17)
		saving_throw.custom_minimum_size.x = 50
		saving_throw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		save_cell.add_child(saving_throw)
		save_cell.add_child(save_icon)
		_saving_throw_labels[ability] = saving_throw
		_install_formula("save:" + ability, saving_throw, [], [])
		spin.value_changed.connect(_on_ability_value_changed.bind(ability))
		bonus.value_changed.connect(_on_ability_value_changed.bind(ability))

	# Compact quick-statistics panel immediately below characteristics.
	var quick_box := _info_panel(skills_column, "RIEPILOGO")
	movement_row.reparent(quick_box)
	var proficiency_row := HBoxContainer.new()
	quick_box.add_child(proficiency_row)
	_add_label(proficiency_row, "Bonus competenza")
	_proficiency_display = Label.new()
	_proficiency_display.add_theme_font_size_override("font_size", 18)
	proficiency_row.add_child(_proficiency_display)
	_install_formula("proficiency", _proficiency_display, [], [])
	var passive_row := HBoxContainer.new()
	quick_box.add_child(passive_row)
	_add_label(passive_row, "Percezione passiva")
	_passive_perception = Label.new()
	_passive_perception.add_theme_font_size_override("font_size", 18)
	passive_row.add_child(_passive_perception)
	_install_formula("passive_perception", _passive_perception, [], [])
	var skills_header := VBoxContainer.new()
	skills_header.add_theme_constant_override("separation", 1)
	skills_column.add_child(skills_header)
	var skills_heading := Label.new()
	skills_heading.text = "ABILITÀ"
	skills_heading.add_theme_font_size_override("font_size", 20)
	skills_heading.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	_style_statistics_heading(skills_heading)
	skills_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_header.add_child(skills_heading)
	var skills_legend := Label.new()
	skills_legend.text = "🎓 Competenza  ·  🎓🎓 Maestria"
	skills_legend.add_theme_font_size_override("font_size", 11)
	skills_legend.add_theme_color_override("font_color", Color(0.77, 0.84, 0.90))
	skills_header.add_child(skills_legend)
	var skills_divider := HSeparator.new()
	skills_column.add_child(skills_divider)
	_skills_panel = VBoxContainer.new()
	_skills_panel.add_theme_constant_override("separation", 3)
	skills_column.add_child(_skills_panel)
	for skill: Dictionary in Skills5e.SKILLS:
		var key: String = String(skill["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_skills_panel.add_child(row)
		var skill_label := Label.new()
		_skill_buttons[key] = skill_label
		skill_label.text = String(skill["label"]) + " · " + String(skill["ability"]).to_upper()
		skill_label.clip_text = true
		skill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(skill_label)
		var modifier_label := Label.new()
		modifier_label.custom_minimum_size.x = 42
		modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(modifier_label)
		_skill_values[key] = modifier_label
		_install_formula("skill:" + key, modifier_label, [], [])
	var prof_box := _info_panel(skills_column, "STRUMENTI E LINGUAGGI")
	_tools_proficiency_label = Label.new()
	_tools_proficiency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tools_proficiency_label.tooltip_text = "Competenze negli strumenti delle origini attive"
	prof_box.add_child(_tools_proficiency_label)
	_languages_proficiency_label = Label.new()
	_languages_proficiency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_languages_proficiency_label.tooltip_text = "Linguaggi delle origini attive"
	prof_box.add_child(_languages_proficiency_label)
	var attack_header := Label.new()
	attack_header.text = "ATTACCHI DISPONIBILI"
	_style_statistics_heading(attack_header)
	attack_header.add_theme_font_size_override("font_size", 16)
	combat_column.add_child(attack_header)
	var preference_row := HBoxContainer.new()
	preference_row.add_theme_constant_override("separation", 8)
	combat_column.add_child(preference_row)
	_add_label(preference_row, "Caratteristica attacchi")
	_attack_ability = OptionButton.new()
	_attack_ability.add_item("Forza")
	_attack_ability.add_item("Destrezza")
	_attack_ability.tooltip_text = "Preferenza per armi Finesse: le armi da mischia normali usano Forza, quelle a distanza Destrezza. I valori del bestiario includono la competenza."
	_attack_ability.item_selected.connect(_on_attack_ability_changed)
	preference_row.add_child(_attack_ability)
	var weapon_bar := HBoxContainer.new()
	weapon_bar.add_theme_constant_override("separation", 5)
	combat_column.add_child(weapon_bar)
	combat_column.move_child(weapon_bar, attack_header.get_index())
	var weapon_caption := Label.new()
	weapon_caption.text = "Arma attiva"
	weapon_bar.add_child(weapon_caption)
	var previous_weapon := Button.new()
	previous_weapon.text = "‹"
	previous_weapon.tooltip_text = "Arma / attacco precedente"
	previous_weapon.pressed.connect(_step_active_weapon.bind(-1))
	weapon_bar.add_child(previous_weapon)
	_weapon_picker = OptionButton.new()
	_weapon_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_picker.clip_text = true
	_weapon_picker.tooltip_text = "Scegli un'arma dall'inventario o un attacco naturale; la portata visibile sulla mappa seguirà questa scelta."
	_weapon_picker.item_selected.connect(_on_active_weapon_selected)
	weapon_bar.add_child(_weapon_picker)
	var next_weapon := Button.new()
	next_weapon.text = "›"
	next_weapon.tooltip_text = "Arma / attacco successivo"
	next_weapon.pressed.connect(_step_active_weapon.bind(1))
	weapon_bar.add_child(next_weapon)
	_attack_rows = VBoxContainer.new()
	_attack_rows.add_theme_constant_override("separation", 7)
	combat_column.add_child(_attack_rows)
	_attacks_description = RichTextLabel.new()
	_attacks_description.custom_minimum_size.y = 55
	_attacks_description.fit_content = false
	_attacks_description.scroll_active = false
	_attacks_description.selection_enabled = true
	FiveToolsText.style(_attacks_description)
	combat_column.add_child(_attacks_description)

	var species_row := HFlowContainer.new()
	species_row.add_theme_constant_override("h_separation", 6)
	identity_box.add_child(species_row)
	_add_label(species_row, "Razza / Specie")
	_species = _reference_option(species_row, RaceRules.base_races(), true, false)
	_species.custom_minimum_size.x = 150
	_species.item_selected.connect(func(_index: int) -> void: _on_species_changed())
	_subrace_caption = Label.new()
	_subrace_caption.text = "Sottorazza"
	species_row.add_child(_subrace_caption)
	_subrace_choice = _reference_option(species_row, [], true, false)
	_subrace_choice.custom_minimum_size.x = 135
	_subrace_choice.tooltip_text = "Solo le sottorazze della razza selezionata, in base a raceName e raceSource."
	_subrace_choice.item_selected.connect(func(_index: int) -> void: _on_subrace_changed())
	_challenge_caption = Label.new()
	_challenge_caption.text = "GS"
	species_row.add_child(_challenge_caption)
	_challenge_rating = LineEdit.new()
	_challenge_rating.custom_minimum_size.x = 63
	_challenge_rating.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_challenge_rating.tooltip_text = "Grado sfida del bestiario, anche frazionario (es. 1/4). Non è un livello di classe."
	_challenge_rating.text_submitted.connect(func(_text: String) -> void: _save())
	_challenge_rating.focus_exited.connect(_save)
	species_row.add_child(_challenge_rating)
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 7)
	identity_box.add_child(type_row)
	_add_label(type_row, "Tipo")
	_creature_type_display = Label.new()
	_creature_type_display.custom_minimum_size.x = 110
	type_row.add_child(_creature_type_display)
	var background_row := HBoxContainer.new()
	identity_box.add_child(background_row)
	_add_label(background_row, "Background")
	_background = _reference_option(background_row, Player5eTools.entries("backgrounds"))
	_background.tooltip_text = "Background strutturato del personaggio: competenze e scelte ottenute dai dati 5etools."

	var classes_box := _info_panel(form, "CLASSI E PROGRESSIONE")
	var classes_title_row := HBoxContainer.new()
	classes_title_row.add_theme_constant_override("separation", 12)
	classes_box.add_child(classes_title_row)
	var classes_title := Label.new()
	classes_title.text = "Progressione"
	classes_title.add_theme_font_size_override("font_size", 17)
	classes_title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.54))
	_style_statistics_heading(classes_title)
	classes_title_row.add_child(classes_title)
	_add_label(classes_title_row, "XP")
	_xp = _spin(classes_title_row, 0, 999999999)
	_xp.custom_minimum_size.x = 130
	_xp.tooltip_text = "XP calcolati unicamente dai livelli di classe effettivi; il GS è indipendente"
	var classes_row := HFlowContainer.new()
	classes_row.add_theme_constant_override("h_separation", 7)
	classes_row.add_theme_constant_override("v_separation", 6)
	classes_box.add_child(classes_row)
	_add_label(classes_row, "Classe base")
	_class_name = _reference_option(classes_row, Player5eTools.class_choices(), false, false)
	_class_name.custom_minimum_size.x = 150
	_class_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_class_name.item_selected.connect(func(_i: int) -> void: _on_class_choice_changed())
	_subclass_caption = Label.new()
	_subclass_caption.text = "Sottoclasse"
	classes_row.add_child(_subclass_caption)
	_subclass_name = _reference_option(classes_row, [], false)
	_subclass_name.custom_minimum_size.x = 150
	_subclass_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_subclass_name.item_selected.connect(func(_i: int) -> void: _save())
	_level_caption = Label.new()
	_level_caption.text = "Livello"
	classes_row.add_child(_level_caption)
	_level = SpinBox.new()
	_level.min_value = 1
	_level.max_value = 20
	_level.step = 1
	_level.update_on_text_changed = true
	_level.rounded = true
	_level.custom_minimum_size = Vector2(72, 30)
	_level.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_level.value_changed.connect(_on_level_changed)
	classes_row.add_child(_level)
	var multiclass_header := HBoxContainer.new()
	classes_box.add_child(multiclass_header)
	_additional_classes_title = Label.new()
	_additional_classes_title.text = "Classi aggiuntive (multiclasse)"
	multiclass_header.add_child(_additional_classes_title)
	_add_class_button = Button.new()
	_add_class_button.text = "+ Classe"
	_add_class_button.pressed.connect(_add_multiclass_row)
	multiclass_header.add_child(_add_class_button)
	_multiclass_rows = VBoxContainer.new()
	classes_box.add_child(_multiclass_rows)
	var tracker_caption := Label.new()
	tracker_caption.text = "RISORSE"
	tracker_caption.add_theme_font_size_override("font_size", 15)
	tracker_caption.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65))
	_style_statistics_heading(tracker_caption)
	combat_column.add_child(tracker_caption)
	_tracker_rows = VBoxContainer.new()
	combat_column.add_child(_tracker_rows)
	# Keep consumable resources above the attack list in combat statistics.
	combat_column.move_child(tracker_caption, attack_header.get_index())
	combat_column.move_child(_tracker_rows, attack_header.get_index())
	var biography_box := _info_panel(form, "STORIA E PERSONALITÀ")
	var biography_label := Label.new()
	biography_label.text = "Note"
	_style_statistics_heading(biography_label)
	biography_label.add_theme_font_size_override("font_size", 17)
	biography_box.add_child(biography_label)
	_biography = TextEdit.new()
	_biography.custom_minimum_size.y = 150
	_biography.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biography.scroll_fit_content_height = false
	_biography.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_biography.placeholder_text = "Storia, carattere, ideali, legami, difetti e annotazioni…"
	_biography.text_changed.connect(_save)
	biography_box.add_child(_biography)

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
	_current_miniature_row = HBoxContainer.new()
	_current_miniature_row.add_theme_constant_override("separation", 6)
	appearance_tab.add_child(_current_miniature_row)
	_add_label(_current_miniature_row, "Forma attuale")
	_current_miniature_name = LineEdit.new()
	_current_miniature_name.editable = false
	_current_miniature_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current_miniature_row.add_child(_current_miniature_name)
	_current_miniature_row.hide()
	var appearance_actions := HFlowContainer.new()
	appearance_actions.add_theme_constant_override("h_separation", 8)
	appearance_actions.add_theme_constant_override("v_separation", 5)
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
	geometry.add_theme_constant_override("h_separation", 7)
	geometry.add_theme_constant_override("v_separation", 10)
	appearance_tab.add_child(geometry)
	_add_label(geometry, "Taglia")
	_size_choice = OptionButton.new()
	for size_name: String in ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]:
		_size_choice.add_item(size_name)
	_size_choice.item_selected.connect(func(_i: int) -> void: _save())
	geometry.add_child(_size_choice)
	_add_label(geometry, "Fronte della miniatura")
	_front = OptionButton.new()
	for direction: String in ["−Z · 0°", "+X · 90°", "+Z · 180°", "−X · 270°"]:
		_front.add_item(direction)
	_front.item_selected.connect(func(_i: int) -> void: _save())
	geometry.add_child(_front)
	# Fazione is edited beside the creature name on the Statistics tab.


	_condition_rows = VBoxContainer.new()
	conditions_tab.add_child(_condition_rows)

	# The traits pane has a fixed toolbar and a single dedicated scroll area.
	traits_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(traits_tab.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	(traits_tab.get_parent().get_parent() as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_traits_ui = TraitsTab.new()
	traits_tab.add_child(_traits_ui)
	_traits_ui.call("setup")
	_effect_dialog = AcceptDialog.new()
	_effect_dialog.title = "Dettagli effetto"
	_effect_dialog.min_size = Vector2i(560, 420)
	add_child(_effect_dialog)
	_effect_text = RichTextLabel.new()
	_effect_text.custom_minimum_size = Vector2(530, 320)
	FiveToolsText.style(_effect_text)
	_effect_dialog.add_child(_effect_text)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina creatura"
	_delete_dialog.confirmed.connect(_delete_selected_creature)
	add_child(_delete_dialog)
	_build_automatic_dialog()
	_build_hp_delta_dialog()
	_build_second_form_dialogs()
	# The horizontal scrollers must expose the full content height to the
	# outer vertical sheet scroll; otherwise the bottom of an attack is clipped.
	skills_column.minimum_size_changed.connect(_update_stats_column_heights)
	combat_column.minimum_size_changed.connect(_update_stats_column_heights)
	call_deferred("_update_stats_column_heights")
	_tabs.item_rect_changed.connect(_update_sheet_layout)
	_tabs.tab_changed.connect(_on_creature_tab_changed)
	_panel.resized.connect(_update_sheet_layout)
	call_deferred("_update_sheet_layout")



func _add_sheet_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The creature sheet should only scroll vertically, never a few pixels
	# horizontally because a long bestiary reference expands a child.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(edge, 6)
	for edge: String in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 8)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
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
			_open_transfer_dialog()
		6:
			_show_import()
		7:
			_confirm_delete()
		8:
			_export_current_creature()
		9:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ContentCatalog.ENRICHMENT_USER_DIR))
			OS.shell_open(ProjectSettings.globalize_path(ContentCatalog.ENRICHMENT_USER_DIR))


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
		_selected_id == String(_records[index].get("id", ""))
		and _selected_kind == String(_records[index].get("kind", ""))
	):
		return # Selecting the current row must not rebuild the sheet.
	_save()
	_on_selected(index)


func _act_on_creature_token(creature_id: String) -> void:
	var token: CharacterBody3D = find_linked_token_for_creature(creature_id)
	if token == null or not is_instance_valid(token):
		for i: int in range(_records.size()):
			if String(_records[i].get("id", "")) == creature_id:
				_select_creature_row(i)
				_request_spawn_selected_creature()
				return
		return
	_focus_creature_token(creature_id)


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
		var has_token: bool = present.has(String(_records[i].get("id", "")))
		var action_button: Button = _creature_eye_buttons[i]
		action_button.visible = true
		action_button.text = "👁" if has_token else "+"
		action_button.tooltip_text = (
			"Centra la visuale sul token" if has_token
			else "Genera il token di questa creatura"
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
		2:
			_open_automatic_calculation()
		3:
			_confirm_delete()
		4:
			_open_transfer_dialog()


func _build_automatic_dialog() -> void:
	_automatic_dialog = ConfirmationDialog.new()
	_automatic_dialog.title = "Calcola automaticamente"
	_automatic_dialog.get_ok_button().text = "Applica"
	_automatic_dialog.get_cancel_button().text = "Annulla"
	_automatic_dialog.dialog_text = ""
	_automatic_dialog.min_size = Vector2i(560, 360)
	(board_root.get_node("UI") as CanvasLayer).add_child(_automatic_dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_automatic_dialog.add_child(content)
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
	_automatic_slots = CheckBox.new()
	_automatic_slots.text = "Slot incantesimo e Magia del Patto dal livello di classe"
	_automatic_slots.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_slots)
	_automatic_trackers = CheckBox.new()
	_automatic_trackers.text = "Aggiorna i massimi dei tracker strutturati e limita gli utilizzi"
	_automatic_trackers.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_trackers)
	_automatic_derived = CheckBox.new()
	_automatic_derived.text = "Dadi vita, XP minimo, iniziativa e velocità base"
	_automatic_derived.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_derived)
	_automatic_combat = CheckBox.new()
	_automatic_combat.text = "Difese, iniziativa, competenze e portata attiva da dati strutturati"
	_automatic_combat.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_combat)
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
	_automatic_slots.disabled = not character
	_automatic_trackers.disabled = _structured_trackers(record).is_empty()
	_automatic_derived.disabled = not character
	_automatic_combat.disabled = false
	_automatic_hp.set_pressed_no_signal(false)
	_automatic_proficiency.set_pressed_no_signal(false)
	_automatic_spells.set_pressed_no_signal(false)
	_automatic_slots.set_pressed_no_signal(false)
	_automatic_trackers.set_pressed_no_signal(false)
	_automatic_derived.set_pressed_no_signal(false)
	_automatic_combat.set_pressed_no_signal(false)
	_refresh_automatic_preview()
	_popup_sheet_dialog(_automatic_dialog, Vector2i(675, 545), 0.90)


func _automatic_combat_values(record: Dictionary) -> Dictionary:
	var active_attack: Dictionary = AttackData.active_attack(record)
	return {
		"armor_class": maxi(0, BonusRules.value(record, "ac")),
		"initiative_base": BonusRules.value(record, "ability_mod:dex"),
		"initiative": BonusRules.value(record, "initiative"),
		"attack_id": String(active_attack.get("id", "")),
		"reach_feet": int(AttackData.active_range(record))
	}


func _refresh_automatic_preview() -> void:
	if _automatic_preview == null:
		return
	var record: Dictionary = _current()
	var lines := PackedStringArray()
	var is_character: bool = String(record.get("kind", "")) == "character"
	var hp_context: Dictionary = record.duplicate(true)
	hp_context["effective_con_modifier"] = BonusRules.value(record, "ability_mod:con")
	var hp: Dictionary = (
		Rules.automatic_hit_points(hp_context)
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
			var limits: Dictionary = Rules.spellcasting_limits(_with_effective_modifiers(record))
			lines.append(String(limits.get("detail", "Nessuna classe magica.")))
		if _automatic_derived.button_pressed:
			var dice: String = Rules.automatic_hit_dice(record)
			lines.append("Dadi vita: %s · XP minimi: %d · Iniziativa: %+d" % [
				dice if not dice.is_empty() else "non disponibili",
				Rules.experience_for_level(int(record.get("level", 1))),
				BonusRules.value(record, "initiative")
			])
	if _automatic_combat.button_pressed:
		var combat: Dictionary = _automatic_combat_values(record)
		lines.append("CA %d (scudo compreso) · Iniziativa %+d · Portata %d ft" % [
			int(combat["armor_class"]), int(combat["initiative"]), int(combat["reach_feet"])
		])
		lines.append("Competenze e abilità: risincronizzate dalle origini; TS, abilità e modificatori si aggiornano dalle formule.")
	if _automatic_slots.button_pressed:
		var slot_result: Dictionary = Rules.spell_slot_progression(record)
		var slots: Array = slot_result.get("slots", [])
		lines.append("Slot dal livello: %s · Patto %d (livello %d)" % [
			str(slots.slice(1)), int(slot_result.get("pact_total", 0)),
			int(slot_result.get("pact_level", 1))
		])
		if not String(slot_result.get("warnings", "")).is_empty():
			lines.append(String(slot_result["warnings"]))
	if _automatic_trackers.button_pressed:
		lines.append("Massimi derivati dai dati strutturati: %d tracker; i bonus manuali restano invariati." % _structured_trackers(record).size())
	if lines.is_empty():
		lines.append("Seleziona almeno un valore per vedere l'anteprima.")
	_automatic_preview.text = "\n".join(lines)
	_automatic_dialog.get_ok_button().disabled = (
		not _automatic_hp.button_pressed
		and not _automatic_proficiency.button_pressed
		and not _automatic_spells.button_pressed
		and not _automatic_slots.button_pressed
		and not _automatic_trackers.button_pressed
		and not _automatic_derived.button_pressed
		and not _automatic_combat.button_pressed
	)


func _apply_automatic_calculation() -> void:
	var record: Dictionary = _current()
	if record.is_empty() or String(record.get("id", "")) != _automatic_target_id:
		return
	if _automatic_hp.button_pressed:
		var hp_context: Dictionary = record.duplicate(true)
		hp_context["effective_con_modifier"] = BonusRules.value(record, "ability_mod:con")
		var hp: Dictionary = (
			Rules.automatic_hit_points(hp_context)
			if String(record.get("kind", "")) == "character"
			else Rules.automatic_monster_hit_points(record)
		)
		if bool(hp.get("available", false)):
			var base_maximum: int = int(hp.get("value", 1))
			record["max_hp_base"] = base_maximum
			var maximum: int = maxi(0, BonusRules.value(record, "hp"))
			record["max_hp"] = maximum
			record["current_hp"] = mini(int(record.get("current_hp", maximum)), maximum)
	if _automatic_proficiency.button_pressed:
		record["proficiency_bonus"] = BonusRules.value(record, "proficiency")
	if _automatic_spells.button_pressed:
		record["spellcasting_calculation"] = Rules.spellcasting_limits(_with_effective_modifiers(record))
	if _automatic_slots.button_pressed:
		var progression: Dictionary = Rules.spell_slot_progression(record)
		var derived_slots: Array = progression.get("slots", [])
		if derived_slots is Array and derived_slots.size() >= 10:
			record["spell_slots_total"] = derived_slots.duplicate()
			var spent: Array = record.get("spell_slots_spent", []).duplicate()
			var bonuses: Array = record.get("spell_slots_bonus", []).duplicate()
			for index: int in range(1, mini(10, spent.size())):
				var bonus: int = int(bonuses[index]) if index < bonuses.size() else 0
				spent[index] = clampi(int(spent[index]), 0, maxi(0, int(derived_slots[index]) + bonus))
			record["spell_slots_spent"] = spent
		record["pact_slots_total"] = int(progression.get("pact_total", 0))
		record["pact_slot_level"] = int(progression.get("pact_level", 1))
		record["pact_slots_spent"] = mini(int(record.get("pact_slots_spent", 0)),
			maxi(0, int(record["pact_slots_total"]) + int(record.get("pact_slots_bonus", 0))))
	if _automatic_derived.button_pressed:
		record["hit_dice"] = Rules.automatic_hit_dice(record)
		record["xp"] = maxi(int(record.get("xp", 0)), Rules.experience_for_level(int(record.get("level", 1))))
		record["initiative_base"] = BonusRules.value(record, "ability_mod:dex")
		record["initiative"] = BonusRules.value(record, "initiative")
		if not bool(record.get("speed_is_custom", false)):
			for race: Dictionary in Player5eTools.entries("races"):
				if (String(race.get("id", "")) == String(record.get("species_id", ""))
					or (String(race.get("name", "")) == String(record.get("species", ""))
					and String(race.get("source", "")) == String(record.get("species_source", "")))):
					record["speed_base"] = Rules.walking_speed(race.get("speed", 30))
					record["speed"] = maxi(0, BonusRules.value(record, "speed"))
					break
	if _automatic_combat.button_pressed:
		var combat: Dictionary = _automatic_combat_values(record)
		record["armor_class"] = int(combat["armor_class"])
		record["initiative_base"] = int(combat["initiative_base"])
		record["initiative"] = int(combat["initiative"])
		record["equipped_attack_id"] = String(combat["attack_id"])
		record["reach_feet"] = int(combat["reach_feet"])
		# Only legacy mirrors are persisted: the normalized origin grants
		# remain the authority for skill and saving-throw calculations.
		ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
	if _automatic_trackers.button_pressed:
		var spent_values: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
		var bonus_values: Dictionary = record.get("resource_tracker_bonuses", {})
		for tracker: Dictionary in _structured_trackers(record):
			var tracker_id: String = String(tracker.get("id", ""))
			var cap: int = maxi(0, BonusRules.add(record, "tracker:" + tracker_id,
				int(tracker.get("max", 0)) + int(bonus_values.get(tracker_id, 0))))
			spent_values[tracker_id] = clampi(int(spent_values.get(tracker_id, 0)), 0, cap)
		record["resource_tracker_spent"] = spent_values
	# Normalize all mirrors even when recalculating a subset of base inputs.
	record["max_hp"] = maxi(0, BonusRules.value(record, "hp"))
	record["armor_class"] = maxi(0, BonusRules.value(record, "ac"))
	record["initiative_base"] = BonusRules.value(record, "ability_mod:dex")
	record["initiative"] = BonusRules.value(record, "initiative")
	record["proficiency_bonus"] = BonusRules.value(record, "proficiency")
	record["speed"] = maxi(0, BonusRules.value(record, "speed"))
	if _archive.save(record) != OK:
		_set_status("Calcolo riuscito ma salvataggio non completato.")
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)
	_set_status("Calcoli selezionati applicati alla creatura.")


func _build_transfer_request_dialog() -> void:
	_transfer_dialog = ConfirmationDialog.new()
	_transfer_dialog.title = "Cedi controllo della creatura"
	_transfer_dialog.dialog_text = ""
	_transfer_dialog.min_size = Vector2i(480, 220)
	(board_root.get_node("UI") as CanvasLayer).add_child(_transfer_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	_transfer_dialog.add_child(body)
	_transfer_hint = Label.new()
	_transfer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_transfer_hint.text = "Seleziona un giocatore con il VTT aperto nella stessa partita Tailscale."
	body.add_child(_transfer_hint)
	_transfer_users = OptionButton.new()
	_transfer_users.custom_minimum_size.x = 420
	_transfer_users.item_selected.connect(
		func(_index: int) -> void: _update_transfer_confirmation()
	)
	body.add_child(_transfer_users)
	var refresh := Button.new()
	refresh.text = "Aggiorna giocatori online"
	refresh.pressed.connect(_refresh_transfer_users)
	body.add_child(refresh)
	_transfer_dialog.confirmed.connect(_transfer)


func _open_transfer_dialog() -> void:
	if _current().is_empty():
		_set_status("Seleziona una creatura da cedere.")
		return
	_refresh_transfer_users()
	_popup_sheet_dialog(_transfer_dialog, Vector2i(540, 270), 0.90)


func _refresh_transfer_users() -> void:
	_transfer_users.clear()
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	var peers: Array[Dictionary] = []
	if presence != null:
		if presence.has_method("request_refresh"):
			presence.call("request_refresh")
		if presence.has_method("get_online_peers"):
			var result: Variant = presence.call("get_online_peers")
			if result is Array:
				for peer: Variant in result:
					if peer is Dictionary:
						peers.append(peer as Dictionary)
	for peer: Dictionary in peers:
		var id: String = String(peer.get("id", ""))
		if id.length() < 16 or id == Owner.local_id():
			continue
		_transfer_users.add_item(String(peer.get("label", "Giocatore online")))
		_transfer_users.set_item_metadata(_transfer_users.item_count - 1, id)
	if _transfer_users.item_count == 0:
		_transfer_users.add_item("Nessun altro giocatore VTT online")
		_transfer_users.set_item_disabled(0, true)
		_transfer_users.select(0)
		_transfer_hint.text = (
			"Nessun VTT della stessa partita ha risposto. Verifica Tailscale "
			+ "e riprova con Aggiorna dopo qualche secondo."
		)
	else:
		_transfer_users.select(0)
		_transfer_hint.text = (
			"Scegli un destinatario online. Il codice privato di recupero "
			+ "sarà copiato negli appunti, senza inviare la scheda attraverso la mappa."
		)
	_update_transfer_confirmation()


func _update_transfer_confirmation() -> void:
	var index: int = _transfer_users.selected
	_transfer_dialog.get_ok_button().disabled = (
		index < 0
		or _transfer_users.is_item_disabled(index)
		or String(_transfer_users.get_item_metadata(index)).is_empty()
	)


func _build_export_dialog() -> void:
	_export_dialog = FileDialog.new()
	_export_dialog.title = "Scarica creatura"
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.add_filter("*.json", "Scheda creatura JSON")
	_export_dialog.file_selected.connect(_save_exported_creature)
	(board_root.get_node("UI") as CanvasLayer).add_child(_export_dialog)


func _export_current_creature() -> void:
	_save()
	var record: Dictionary = _current()
	if record.is_empty():
		_set_status("Seleziona una creatura da scaricare.")
		return
	var filename: String = String(record.get("name", "creatura")).strip_edges()
	for forbidden: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		filename = filename.replace(forbidden, "_")
	_export_dialog.current_file = filename.substr(0, 75) + ".json"
	_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_export_dialog.popup_centered_clamped(Vector2i(820, 550), 0.9)


func _save_exported_creature(path: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Esportazione non riuscita: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({
		"format": "vtt_creature_export_v1",
		"version": 1,
		"creature": record
	}, "  "))
	var error: Error = file.get_error()
	file.close()
	_set_status(
		"Creatura esportata: " + path
		if error == OK else "Esportazione non completata: " + error_string(error)
	)


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
	_import_dialog.add_child(_import_text)


func _add_formula_label(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.y = 36.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 30 if value in ["(", ")"] else 18)
	parent.add_child(label)


func _style_statistics_heading(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.97))
	label.add_theme_color_override("font_shadow_color", Color(0.03, 0.05, 0.08, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 1)


func _add_label(parent: Node, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


# Existing controls keep their save signals; only their display is compacted.
func _install_formula(key: String, label: Label, inputs: Array, captions: Array) -> void:
	var parent: Node = label.get_parent()
	var index: int = label.get_index()
	parent.remove_child(label)
	var widget := FormulaValue.new()
	parent.add_child(widget)
	parent.move_child(widget, index)
	widget.setup(label, inputs, captions)
	widget.target_key = key
	widget.bonus_requested.connect(_on_formula_bonus_requested)
	_formula_values[key] = widget


func _set_formula(key: String, text_value: String, explanation: String) -> void:
	if _formula_values.has(key):
		var source: Dictionary = (
			_formula_snapshot_override if not _formula_snapshot_override.is_empty()
			else _live_stats_record()
		)
		var detail: String = BonusRules.description(source, key)
		_formula_values[key].set_formula(text_value, explanation + ("\n" + detail if not detail.is_empty() else ""))


func _with_effective_modifiers(record: Dictionary) -> Dictionary:
	var context: Dictionary = record.duplicate(true)
	var modifiers: Dictionary = {}
	for ability: String in BonusRules.ABILITIES:
		modifiers[ability] = BonusRules.value(record, "ability_mod:" + ability)
	context["effective_ability_modifiers"] = modifiers
	context["effective_con_modifier"] = int(modifiers.get("con", 0))
	return context


func _on_formula_bonus_requested(key: String) -> void:
	if _bonuses_ui == null or key.is_empty():
		return
	_tabs.current_tab = 1
	if _bonuses_stale:
		_bonuses_ui.call("load_record", _current())
		_bonuses_stale = false
	_bonuses_ui.show()
	_bonuses_toggle_button.text = "▾ Nascondi bonus"
	_bonuses_ui.call("select_target", key)
	call_deferred("_update_stats_column_heights")


func _recalculate_bonus_mirrors(record: Dictionary) -> void:
	record["max_hp"] = maxi(0, BonusRules.value(record, "hp"))
	record["armor_class"] = maxi(0, BonusRules.value(record, "ac"))
	record["initiative_base"] = BonusRules.value(record, "ability_mod:dex")
	record["initiative"] = BonusRules.value(record, "initiative")
	record["proficiency_bonus"] = BonusRules.value(record, "proficiency")
	record["speed"] = maxi(0, BonusRules.value(record, "speed"))
	record["reach_feet"] = AttackData.active_range(record)


func _refresh_formula_dependents(record: Dictionary) -> void:
	var previous_loading: bool = _loading
	_loading = true
	for ability: String in _ability_spins.keys():
		_update_ability_modifier(ability)
	_loading = previous_loading
	_refresh_skill_values(record)
	_update_max_hp_display()
	_update_second_max_formula()
	_update_defense_display()
	_update_speed_display()
	_refresh_attacks(record)
	_refresh_trackers(record)


func _on_bonuses_updated(rows: Array, origins: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	record["formula_bonuses"] = rows.duplicate(true)
	record["proficiency_origins"] = origins.duplicate(true)
	# Recalculate every dependent field from its base and active grants.
	_recalculate_bonus_mirrors(record)
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare i bonus.")
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)


func _live_stats_record() -> Dictionary:
	# _current() already returns an independent deep copy.
	var record: Dictionary = _current()
	if record.is_empty() or _ability_spins.is_empty():
		return record
	var abilities: Dictionary = record.get("abilities", {}).duplicate(true)
	for ability: String in _ability_spins.keys():
		abilities[ability] = int((_ability_spins[ability] as SpinBox).value)
	record["abilities"] = abilities
	if _ac != null:
		record["armor_class_base"] = int(_ac.value)
	if _max_hp != null:
		record["max_hp_base"] = int(_max_hp.value)
	if _second_form_max_hp != null:
		record["second_form_max_hp"] = int(_second_form_max_hp.value)
	if _speed != null:
		record["speed_base"] = int(_speed.value)
	return record


func _spin(parent: Node, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.update_on_text_changed = true
	spin.custom_minimum_size = Vector2(76, 30)
	spin.value_changed.connect(func(_v: float) -> void: _save())
	parent.add_child(spin)
	return spin


func _info_panel(parent: VBoxContainer, section: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.11, 0.15, 0.20, 0.56)
	frame_style.border_color = Color(0.33, 0.47, 0.58, 0.80)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(7)
	frame_style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", frame_style)
	parent.add_child(frame)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	frame.add_child(content)
	var heading := Label.new()
	heading.text = section
	heading.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98))
	heading.add_theme_font_size_override("font_size", 17)
	_style_statistics_heading(heading)
	content.add_child(heading)
	return content


func _reference_option(
	parent: Node, choices: Array[Dictionary], show_source: bool = true,
	autosave: bool = true
) -> OptionButton:
	var select := OptionButton.new()
	select.fit_to_longest_item = false
	select.clip_text = true
	select.custom_minimum_size = Vector2(150, 30)
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_reference_choices(select, choices, show_source)
	if autosave:
		select.item_selected.connect(func(_i: int) -> void: _save())
	parent.add_child(select)
	return select


func _set_reference_choices(
	option: OptionButton, choices: Array[Dictionary], show_source: bool = true
) -> void:
	# Godot otherwise bases the widget's minimum width on the longest
	# 5etools name, pushing the entire creature tab beyond the viewport.
	option.fit_to_longest_item = false
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


func _subclass_choices(class_ref: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wanted: String = String(class_ref.get("name", "")).strip_edges()
	var source: String = String(class_ref.get("source", "")).to_upper()
	if wanted == "Mostro":
		# The monster's type/subtype belongs to its species, not its class.
		return result
	if wanted.is_empty():
		return result
	for entry: Dictionary in Player5eTools.entries("subclasses"):
		var parent: String = String(entry.get("class_name", entry.get("className", "")))
		if parent.nocasecmp_to(wanted) != 0:
			continue
		var parent_source: String = String(entry.get("class_source", entry.get("classSource", ""))).to_upper()
		# A 2024 class can still use compatible 2014 subclasses, including
		# those published in supplements. The subclass book is NOT its class source.
		if source == "XPHB" and parent_source not in ["XPHB", ""]:
			continue
		if source == "EFA" and parent_source not in ["EFA", ""]:
			continue
		if source not in ["XPHB", "EFA"] and not parent_source.is_empty() and parent_source != source:
			continue
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0)
	return result


func _refresh_subclass_option(option: OptionButton, class_ref: Dictionary) -> void:
	var old: Dictionary = _reference_entry(option)
	_set_reference_choices(option, _subclass_choices(class_ref), false)
	_select_reference(option, String(old.get("name", "")), String(old.get("source", "")), String(old.get("id", "")))


func _on_class_choice_changed() -> void:
	_refresh_multiclass_availability()
	_level.editable = _class_name.selected > 0
	_refresh_subclass_option(_subclass_name, _reference_entry(_class_name))
	_refresh_xp_minimum()
	_save()


func _refresh_multiclass_availability() -> void:
	if _add_class_button != null:
		_add_class_button.disabled = _class_name.selected <= 0


func _refresh_class_choices() -> void:
	var primary := _reference_entry(_class_name)
	var choices := Player5eTools.class_choices(_selected_rules_version())
	_set_reference_choices(_class_name, choices, false)
	_select_reference(_class_name, String(primary.get("name", "")), String(primary.get("source", "")), String(primary.get("id", "")))
	_refresh_subclass_option(_subclass_name, _reference_entry(_class_name))
	for definition: Dictionary in _multiclass_controls:
		var option: OptionButton = definition["selector"]
		var old := _reference_entry(option)
		_set_reference_choices(option, choices, false)
		_select_reference(option, String(old.get("name", "")), String(old.get("source", "")), String(old.get("id", "")))
		_refresh_subclass_option(definition["subclass"], _reference_entry(option))


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
	if not _loading and _class_name.selected <= 0:
		return
	var row := HBoxContainer.new()
	_multiclass_rows.add_child(row)
	var selector := _reference_option(row, Player5eTools.class_choices(_selected_rules_version()), false, false)
	_select_reference(selector, class_value, source, reference_id)
	selector.item_selected.connect(func(_i: int) -> void: _on_secondary_class_changed(row))
	var subclass := _reference_option(row, _subclass_choices(_reference_entry(selector)), false)
	subclass.item_selected.connect(func(_i: int) -> void: _save())
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = 20
	level.step = 1
	level.update_on_text_changed = true
	level.value = clampi(class_level, 1, 20)
	level.custom_minimum_size = Vector2(72, 30)
	level.value_changed.connect(func(_v: float) -> void:
		_refresh_xp_minimum()
		_save()
	)
	row.add_child(level)
	var remove := Button.new()
	remove.text = "×"
	row.add_child(remove)
	var definition := {"row": row, "selector": selector, "subclass": subclass, "level": level}
	_multiclass_controls.append(definition)
	remove.pressed.connect(
		func() -> void:
			_multiclass_controls.erase(definition)
			_multiclass_rows.remove_child(row)
			row.queue_free()
			_save()
	)
	_save()


func _on_secondary_class_changed(row: HBoxContainer) -> void:
	for definition: Dictionary in _multiclass_controls:
		if definition["row"] == row:
			_refresh_subclass_option(definition["subclass"], _reference_entry(definition["selector"]))
			_save()
			return


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
	_owned_name_index.clear()
	for record: Dictionary in _records:
		var creature_id: String = String(record.get("id", "")).strip_edges()
		if not creature_id.is_empty():
			_owned_name_index[creature_id] = String(record.get("name", "")).strip_edges()
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
		select_button.tooltip_text = String(item.get("name", ""))
		select_button.toggle_mode = true
		select_button.custom_minimum_size.y = 34
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.pressed.connect(_select_creature_row.bind(i))
		select_button.gui_input.connect(_on_creature_row_gui_input.bind(i))
		row.add_child(select_button)
		_creature_row_buttons.append(select_button)
		var eye := Button.new()
		eye.name = "CreatureTokenAction"
		eye.text = "+"
		eye.tooltip_text = "Genera il token di questa creatura"
		eye.custom_minimum_size = Vector2(35, 34)
		eye.size_flags_horizontal = Control.SIZE_SHRINK_END
		eye.pressed.connect(_act_on_creature_token.bind(creature_id))
		eye.gui_input.connect(_on_creature_row_gui_input.bind(i))
		row.add_child(eye)
		_creature_eye_buttons.append(eye)
		if (
			creature_id == _selected_id
			and kind == _selected_kind
		):
			selected_index = i

	_filter_owned_creatures(_creature_filter.text)
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
		_traits_ui.call("load_record", {})
		_bonuses_ui.call("load_record", {})
		_loading = false


func _current() -> Dictionary:
	for item: Dictionary in _records:
		if (
			String(item.get("id", "")) == _selected_id
			and String(item.get("kind", "")) == _selected_kind
		):
			return item.duplicate(true)
	return {}


func _filter_owned_creatures(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	var visible_count := 0
	for index: int in range(_creature_row_buttons.size()):
		var record: Dictionary = _records[index]
		var searchable := "%s %s" % [record.get("name", ""), record.get("party_id", "")]
		var matches := needle.is_empty() or needle in searchable.to_lower()
		_creature_row_buttons[index].get_parent().visible = matches
		if matches:
			visible_count += 1
	_creature_empty.text = "Crea o importa una creatura." if _records.is_empty() else "Nessuna creatura corrispondente."
	_creature_empty.visible = visible_count == 0
	_update_sheet_layout()


func _update_stats_column_heights() -> void:
	if _statistics_columns == null or _statistics_columns.get_child_count() != 2:
		return
	var left_view := _statistics_columns.get_child(0) as ScrollContainer
	var right_view := _statistics_columns.get_child(1) as ScrollContainer
	if left_view == null or right_view == null:
		return
	var left_contents := left_view.get_child(0) as Control
	var right_contents := right_view.get_child(0) as Control
	var needed_height: float = maxf(
		left_contents.get_combined_minimum_size().y,
		right_contents.get_combined_minimum_size().y
	) + 18.0
	if absf(left_view.custom_minimum_size.y - needed_height) > 1.0:
		left_view.custom_minimum_size.y = needed_height
		right_view.custom_minimum_size.y = needed_height


func _update_sheet_layout() -> void:
	if _panel == null or _creature_list_scroll == null:
		return
	# Leave room for search, creation buttons and the bestiary even when
	# many owned creatures are listed in a short game window.
	var sidebar := _creature_list_scroll.get_parent() as VBoxContainer
	var reserved_height := 100.0
	var visible_rows := 0
	for child: Node in sidebar.get_children():
		if child is Control and child.visible and child != _creature_list_scroll:
			reserved_height += (child as Control).get_combined_minimum_size().y + sidebar.get_theme_constant("separation")
	for button: Button in _creature_row_buttons:
		if button.get_parent().visible:
			visible_rows += 1
	var viewport_size := _panel.get_viewport_rect().size
	var row_budget := maxf(40.0, viewport_size.y - _panel.offset_top + _panel.offset_bottom - reserved_height)
	_creature_list_scroll.custom_minimum_size.y = minf(float(mini(maxi(visible_rows, 1), 7) * 37 + 6), row_budget)
	if _abilities_grid == null or _abilities_grid.get_child_count() == 0:
		return
	# Keep the ability grid as a four-column table in every window size.
	_abilities_grid.columns = 4


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
	# Initialize once for old sheets. Afterwards intentional sheathing and
	# natural-attack selections must never be undone on a later load.
	if String(record.get("equipped_attack_id", "")).is_empty():
		AttackData.equip_first_inventory_weapon(record)
		record["equipped_attack_id"] = String(AttackData.active_attack(record).get("id", ""))
		record["reach_feet"] = AttackData.active_range(record)
		if String(record.get("kind", "")) == "monster":
			record["reach_is_custom"] = true
		if _archive.save(record) == OK:
			_replace_current_record(record)
	_refresh_trackers(record)
	_loading = true
	_name.text = String(record.get("name", ""))
	_hp.value = int(record.get("current_hp", 1))
	_max_hp.value = maxi(0, int(record.get("max_hp_base", record.get("max_hp", 1))))
	_update_max_hp_display()
	_temp_hp.value = int(record.get("temporary_hp", 0))
	_second_form_max_hp.value = int(record.get("second_form_max_hp", record.get("second_form_hp", 0)))
	_second_form_hp.value = int(record.get("second_form_hp", 0))
	_update_second_max_formula()
	var biography: String = String(record.get("background_personality", ""))
	if biography.strip_edges().is_empty():
		var legacy_parts: PackedStringArray = []
		for field: String in ["background", "personality_traits", "ideals", "bonds", "flaws"]:
			var value: String = String(record.get(field, "")).strip_edges()
			if not value.is_empty():
				legacy_parts.append(field.capitalize().replace("_", " ") + ": " + value)
		biography = "\n\n".join(legacy_parts)
	_biography.text = biography
	_ac.value = maxi(0, int(record.get("armor_class_base", record.get("armor_class", 10))))
	_update_defense_display()
	_skill_ranks.clear()
	_skill_ranks_custom = bool(record.get("skill_ranks_custom", false))
	var sheet_skills: Dictionary = record.duplicate(true)
	ProficiencyRules.sync_legacy_fields(sheet_skills, ProficiencyRules.choices(record))
	var known_proficiencies: Variant = sheet_skills.get("skill_proficiencies", [])
	var known_expertise: Variant = sheet_skills.get("skill_expertise", [])
	for skill: Dictionary in Skills5e.SKILLS:
		var key: String = String(skill["id"])
		_skill_ranks[key] = (
			2 if known_expertise is Array and key in known_expertise
			else 1 if known_proficiencies is Array and key in known_proficiencies
			else 0
		)
	_attack_ability.select(1 if String(record.get("attack_ability", "str")) == "dex" else 0)
	_refresh_attacks(record)
	var abilities_value: Variant = record.get("abilities", {})
	var abilities: Dictionary = (
		abilities_value as Dictionary if abilities_value is Dictionary else {}
	)
	for ability: String in _ability_spins.keys():
		(_ability_spins[ability] as SpinBox).value = int(abilities.get(ability, 10))
	for ability: String in _ability_spins.keys():
		_update_ability_modifier(ability)
	if String(record.get("kind", "")) == "monster" and not bool(record.get("skill_ranks_custom", false)):
		var inferred: Dictionary = Skills5e.ranks_from_bestiary(record, _creature_proficiency(record), abilities)
		for skill_id: String in inferred.keys():
			_skill_ranks[skill_id] = int(inferred[skill_id])
	_refresh_skill_values(record)
	var is_character: bool = String(record.get("kind", "")) == "character"
	_additional_classes_title.text = "Classi aggiuntive (multiclasse)" if is_character else "Classi principali aggiuntive"
	if is_character:
		_set_reference_choices(_species, RaceRules.base_races())
	else:
		var bestiary_species: Array[Dictionary] = [{
			"id": String(record.get("species", "")),
			"name": String(record.get("species", "")),
			"source": String(record.get("species_source", ""))
		}]
		_set_reference_choices(_species, bestiary_species)
	_select_reference(_species, String(record.get("species", "")), String(record.get("species_source", "")), String(record.get("species_id", "")))
	_refresh_subrace_choices()
	_select_reference(_subrace_choice, String(record.get("subrace", "")),
		String(record.get("subrace_source", "")), String(record.get("subrace_id", "")))
	_subrace_caption.visible = is_character
	_subrace_choice.visible = is_character
	_challenge_caption.visible = not is_character
	_challenge_rating.visible = not is_character
	var challenge: Variant = record.get("stat_block", {}).get("cr", "0")
	_challenge_rating.text = String(challenge.get("cr", "0") if challenge is Dictionary else challenge)
	_refresh_creature_type(record)
	_set_reference_choices(_background, Player5eTools.entries("backgrounds"))
	_select_reference(_background, String(record.get("background", "")), String(record.get("background_source", "")), String(record.get("background_id", "")))
	_speed_custom = bool(record.get("speed_is_custom", false))
	var source_speed: int = (Rules.walking_speed(_effective_species().get("speed", 30))
		if is_character else Rules.walking_speed(record.get("stat_block", {}).get("speed", 30)))
	_speed.value = maxi(0, int(record.get("speed_base", record.get("speed", source_speed))) if _speed_custom else source_speed)
	_update_speed_display()
	var class_source := String(record.get("class_source", ""))
	var edition := String(record.get("rules_version", ""))
	# Existing sheets with an explicit edition are authoritative. Infer the
	# edition from the class book only for older imported records without it.
	if edition not in ["2014", "2024"]:
		edition = "2024" if class_source in ["XPHB", "EFA"] else "2014"
	_rules_edition.select(1 if edition == "2024" else 0)
	_refresh_class_choices()
	# All sheets use real classes; challenge rating is not a class level.
	_select_reference(_class_name, String(record.get("class", "")), class_source,
		String(record.get("class_id", "")))
	_refresh_multiclass_availability()
	_refresh_subclass_option(_subclass_name, _reference_entry(_class_name))
	_select_reference(_subclass_name, String(record.get("subclass", "")),
		String(record.get("subclass_source", "")), String(record.get("subclass_id", "")))
	_subclass_caption.text = "Sottoclasse"
	_subclass_caption.show()
	_subclass_name.show()
	_level_caption.text = "Livello"
	_clear_multiclass()
	var classes_value: Variant = record.get("classes", [])
	if classes_value is Array:
		for i: int in range(1, (classes_value as Array).size()):
			var class_value: Variant = (classes_value as Array)[i]
			if class_value is Dictionary:
				_add_multiclass_row(String(class_value.get("name", "")),
					int(class_value.get("level", 1)), String(class_value.get("source", "")),
					String(class_value.get("id", "")))
				var last: Dictionary = _multiclass_controls.back()
				_select_reference(last["subclass"], String(class_value.get("subclass", "")),
					String(class_value.get("subclass_source", "")), String(class_value.get("subclass_id", "")))
	var primary_level: int = 1
	if classes_value is Array and not (classes_value as Array).is_empty():
		var first_class: Variant = (classes_value as Array)[0]
		if first_class is Dictionary:
			primary_level = int((first_class as Dictionary).get("level", 1))
	elif not String(record.get("class", "")).is_empty():
		primary_level = int(record.get("level", 1))
	_level.min_value = 1
	_level.max_value = 20
	_level.step = 1
	_level.rounded = true
	_level.value = clampi(primary_level, 1, 20)
	_refresh_xp_minimum()
	_xp.value = maxi(int(record.get("xp", 0)), Rules.experience_for_level(_class_xp_level()))
	_level.tooltip_text = "Livello della classe base (il GS dei mostri è indipendente)"
	_default_miniature_id = String(record.get("default_miniature_id", ""))
	_default_miniature.text = _miniature_display_name(_default_miniature_id)
	_update_current_appearance_display(record)
	_select_sheet_size(String(record.get("size_name", "Medium")))
	_front.select(clampi(int(record.get("visual_front_quarter_turns", 0)), 0, 3))
	_party.text = String(record.get("party_id", ""))
	_default_miniature.tooltip_text = (
		"ID catalogo: " + _default_miniature_id
		if not _default_miniature_id.is_empty()
		else "Scegli una miniatura con il pulsante Cerca…"
	)
	_species.disabled = not is_character
	_subrace_choice.disabled = not is_character or _subrace_choice.item_count <= 1
	_class_name.disabled = false
	_rules_edition.visible = true
	_rules_edition_caption.visible = true
	_level.editable = _class_name.selected > 0
	_refresh_conditions(record)
	_refresh_reference(record)
	_spellcasting_ui.call("load_record", record)
	_inventory_ui.call("load_record", record)
	_bonuses_stale = true
	if _bonuses_ui.visible:
		_bonuses_ui.call("load_record", record)
		_bonuses_stale = false
	_loading = false


func _on_level_changed(_value: float) -> void:
	_refresh_xp_minimum()
	_save()


func _class_xp_level() -> int:
	var level: int = 0
	if _class_name.selected > 0:
		level += int(_level.value)
	for definition: Dictionary in _multiclass_controls:
		var extra_ref: Dictionary = _reference_entry(definition["selector"])
		if not String(extra_ref.get("name", "")).is_empty():
			level += int((definition["level"] as SpinBox).value)
	return clampi(level, 0, 20)


func _refresh_xp_minimum() -> void:
	if _xp == null:
		return
	var minimum: int = Rules.experience_for_level(_class_xp_level())
	# Avoid another save when changing the floor programmatically.
	var previously_loading: bool = _loading
	_loading = true
	_xp.min_value = minimum
	if int(_xp.value) < minimum:
		_xp.set_value_no_signal(minimum)
	_loading = previously_loading


func _effective_species() -> Dictionary:
	return RaceRules.effective_race(_reference_entry(_species), _reference_entry(_subrace_choice))


func _refresh_subrace_choices() -> void:
	var available: Array[Dictionary] = RaceRules.subraces_for(_reference_entry(_species))
	_set_reference_choices(_subrace_choice, available)
	_subrace_choice.disabled = available.is_empty()


func _speed_from_species() -> int:
	return Rules.walking_speed(_effective_species().get("speed", 30))


func _on_species_changed() -> void:
	if _loading:
		return
	_speed_custom = false
	_loading = true
	_refresh_subrace_choices()
	_speed.value = _speed_from_species()
	_refresh_creature_type({"kind": "character"})
	_loading = false
	_update_speed_display()
	_save()


func _on_subrace_changed() -> void:
	if _loading:
		return
	_loading = true
	_speed_custom = false
	_speed.value = _speed_from_species()
	_refresh_creature_type({"kind": "character"})
	_loading = false
	_update_speed_display()
	_save()


func _refresh_creature_type(record: Dictionary) -> void:
	if _creature_type_display == null:
		return
	if String(record.get("kind", "")) == "monster":
		_creature_type_display.text = String(Rules.monster_type_reference(record.get("stat_block", {})).get("name", "Non definito"))
	else:
		_creature_type_display.text = Rules.species_creature_type(_effective_species())


func _on_speed_changed(_value: float) -> void:
	_update_speed_display()
	if _loading:
		return
	_speed_custom = true
	_save()


func _update_speed_display() -> void:
	if _speed_effective != null and _speed != null:
		var live: Dictionary = _live_stats_record()
		var base: int = int(_speed.value)
		var total: int = maxi(0, BonusRules.value(live, "speed"))
		_set_formula("speed", str(total),
			"Velocità: base %d + bonus cumulabili %+d = %d ft" % [
				base, BonusRules.bonus(live, "speed"), total])


# The creature sheet casts from class, available and searched spells alike.
# When no linked token or VTT effect exists, casting still records slot use.
func _on_spellcasting_cast_requested(spell: Dictionary, slot_level: int) -> bool:
	if _current().is_empty():
		return false
	var spell_name: String = String(spell.get("name", "Incantesimo"))
	var spell_id: String = String(spell.get("id", ""))
	var source: String = String(spell.get("source", ""))
	var caster: CharacterBody3D = find_linked_token_for_creature(_selected_id)
	var runtime: Node = board_root.get_node_or_null("SpellSystem")
	if caster == null or runtime == null or not runtime.has_method("has_runtime_spell_effect"):
		_set_status("%s lanciato · effetto VTT non attivabile senza un token collegato." % spell_name)
		return true
	if not bool(runtime.call("has_runtime_spell_effect", spell_id, spell_name, source)):
		_set_status("%s lanciato · nessun effetto VTT associato." % spell_name)
		return true
	# Return to the board before entering the existing target-selection mode.
	hide_panel()
	var activated: bool = bool(runtime.call(
		"activate_spell_from_caster", spell_id, caster, spell_name, source, slot_level
	))
	if not activated:
		show_panel()
		_set_status("Impossibile attivare l'effetto VTT di %s." % spell_name)
	return activated


func _on_spellcasting_updated(values: Dictionary) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	for key: String in [
		"spells", "prepared_spells", "spellbook_spells",
		"spell_slots_total", "spell_slots_bonus", "spell_slots_spent",
		"pact_slots_total", "pact_slots_bonus", "pact_slots_spent", "pact_slot_level",
		"spell_slots_visible", "pact_slots_visible"
	]:
		if values.has(key):
			record[key] = values[key]
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio incantesimi non riuscito: " + error_string(error))
		return
	_replace_current_record(record)


func _creature_proficiency(record: Dictionary) -> int:
	return BonusRules.value(record, "proficiency")


func _refresh_skill_values(record: Dictionary) -> void:
	if _proficiency_display == null:
		return
	var live: Dictionary = record.duplicate(true)
	# The sheet may have unsaved characteristic edits when signals fire.
	if String(record.get("id", "")) == _selected_id:
		live = _live_stats_record()
	_formula_snapshot_override = live
	var proficiency: int = BonusRules.value(live, "proficiency")
	_set_formula("proficiency", "%+d" % proficiency,
		"Competenza: base %+d %+d bonus da origini = %+d" % [
			proficiency - BonusRules.bonus(live, "proficiency"),
			BonusRules.bonus(live, "proficiency"), proficiency])
	for skill: Dictionary in Skills5e.SKILLS:
		var key: String = String(skill["id"])
		var ability: String = String(skill["ability"])
		var rank: int = int(_skill_ranks.get(key, 0))
		var value: int = BonusRules.value(live, "skill:" + key)
		var marker: String = "" if rank == 0 else " 🎓" if rank == 1 else " 🎓🎓"
		(_skill_buttons[key] as Label).text = String(skill["label"]) + " · " + ability.to_upper() + marker
		(_skill_buttons[key] as Label).tooltip_text = ["Nessuna competenza", "Competenza", "Maestria"][clampi(rank, 0, 2)] + " · Modifica da Visualizza competenze"
		var ability_modifier: int = BonusRules.value(live, "ability_mod:" + ability)
		var extra: int = BonusRules.bonus(live, "skill:" + key)
		_set_formula("skill:" + key, "%+d" % value,
			"%s: mod. %s %+d + competenza %d × %+d + bonus origini %+d = %+d" % [
				String(skill["label"]), ability.to_upper(), ability_modifier, rank, proficiency, extra, value])
	var enabled: Dictionary = ProficiencyRules.origin_enabled_map(live)
	var all_grants: Array[Dictionary] = ProficiencyRules.choices(live)
	for ability: String in _saving_throw_labels.keys():
		var trained: bool = ProficiencyRules.has_proficiency(live, "save", ability)
		var stat: Dictionary = live.get("stat_block", {})
		var published: Variant = stat.get("save", {})
		if String(live.get("kind", "")) == "monster" and published is Dictionary and String((published as Dictionary).get(ability, "")).is_valid_int():
			trained = true
		var modifier: int = BonusRules.value(live, "save:" + ability)
		var save_mod: int = BonusRules.value(live, "ability_mod:" + ability)
		var save_extra: int = BonusRules.bonus(live, "save:" + ability)
		var save_source: int = modifier - save_mod - save_extra
		_set_formula("save:" + ability, "%+d" % modifier,
			"%s: mod. %+d + competenza o bestiario %+d + origini %+d = %+d" % [
				ability.to_upper(), save_mod, save_source, save_extra, modifier])
		var save_icon: Label = _saving_throw_icons[ability]
		save_icon.text = "🎓" if trained else ""
		save_icon.tooltip_text = "Competente" if trained else "Nessuna competenza"
	if _tools_proficiency_label != null:
		var tools: Array[String] = []
		for grant: Dictionary in all_grants:
			if String(grant.get("kind", "")) != "tool" or bool(grant.get("disabled", false)):
				continue
			if not bool(enabled.get(String(grant.get("origin_id", "")), true)):
				continue
			var tool_name: String = String(grant.get("key", "")).capitalize()
			if tool_name not in tools:
				tools.append(tool_name)
		_tools_proficiency_label.text = "Strumenti: " + (", ".join(tools) if not tools.is_empty() else "nessuna competenza")
	if _languages_proficiency_label != null:
		var languages: Array[String] = []
		for grant: Dictionary in all_grants:
			if String(grant.get("kind", "")) != "language" or bool(grant.get("disabled", false)):
				continue
			if not bool(enabled.get(String(grant.get("origin_id", "")), true)):
				continue
			var language: String = String(grant.get("key", "")).capitalize()
			if language not in languages:
				languages.append(language)
		_languages_proficiency_label.text = "Linguaggi: " + (", ".join(languages) if not languages.is_empty() else "nessuno")
	var passive: int = BonusRules.value(live, "passive_perception")
	_set_formula("passive_perception", str(passive),
		"Percezione passiva: 10 + Percezione %+d + bonus propri %+d = %d" % [
			BonusRules.value(live, "skill:perception"),
			BonusRules.bonus(live, "passive_perception"), passive])
	_formula_snapshot_override = {}


func _refresh_weapon_picker(record: Dictionary) -> void:
	if _weapon_picker == null:
		return
	_weapon_picker.clear()
	_weapon_options.clear()
	var inventory: Variant = record.get("inventory", [])
	# Inventory weapons appear even when sheathed. Selecting one equips it.
	if inventory is Array:
		for index: int in range((inventory as Array).size()):
			var value: Variant = (inventory as Array)[index]
			if not value is Dictionary:
				continue
			var owned: Dictionary = value
			if int(owned.get("quantity", 0)) <= 0:
				continue
			var entry: Dictionary = ItemRules.entry_for(owned)
			if ItemRules.kind(entry) != "weapon":
				continue
			_weapon_picker.add_item(String(entry.get("name", owned.get("name", "Arma"))))
			_weapon_options.append({"kind": "item", "index": index, "id": "item:" + String(owned.get("id", ""))})
	# All bestiary attacks remain selectable for monsters, including natural
	# weapons that have no corresponding entry in the inventory.
	for attack: Dictionary in AttackData.definitions(record):
		if String(attack.get("source", "")) == "item":
			continue
		if ItemRules.has_equipped_weapon(inventory) and String(attack.get("id", "")) in ["unarmed", "improvised"]:
			continue
		_weapon_picker.add_item(String(attack.get("name", "Attacco")))
		_weapon_options.append({"kind": "attack", "id": String(attack.get("id", ""))})
	if _weapon_options.is_empty():
		_weapon_picker.add_item("Nessuna arma")
		_weapon_picker.disabled = true
		return
	_weapon_picker.disabled = false
	var active: String = String(AttackData.active_attack(record).get("id", ""))
	var selected_inventory_index: int = int(record.get("equipped_inventory_index", -1))
	for i: int in range(_weapon_options.size()):
		var option: Dictionary = _weapon_options[i]
		if String(option.get("id", "")) == active and (
			String(option.get("kind", "")) != "item"
			or selected_inventory_index < 0
			or int(option.get("index", -1)) == selected_inventory_index
		):
			_weapon_picker.select(i)
			return
	_weapon_picker.select(0)


func _step_active_weapon(direction: int) -> void:
	if _weapon_options.is_empty() or _weapon_picker == null:
		return
	var next: int = posmod(_weapon_picker.selected + direction, _weapon_options.size())
	_weapon_picker.select(next)
	_on_active_weapon_selected(next)


func _on_active_weapon_selected(index: int) -> void:
	if _loading or index < 0 or index >= _weapon_options.size():
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var choice: Dictionary = _weapon_options[index]
	if String(choice.get("kind", "")) == "item":
		var inventory: Array = record.get("inventory", []).duplicate(true)
		var selected: int = int(choice.get("index", -1))
		if selected < 0 or selected >= inventory.size():
			return
		var chosen: Dictionary = inventory[selected]
		var two_handed: bool = ItemRules.is_two_handed(ItemRules.entry_for(chosen))
		# Exactly one main-hand weapon; keep an unrelated shield or offhand
		# weapon unless the new weapon requires both hands.
		for i: int in range(inventory.size()):
			var owned: Dictionary = inventory[i]
			var slots: Array = ItemRules.slots(owned)
			slots.erase("main")
			if two_handed or (i == selected and int(owned.get("quantity", 1)) == 1):
				slots.erase("off")
			if i == selected:
				slots.append("main")
			owned["equipped_slots"] = slots
			inventory[i] = owned
		record["inventory"] = inventory
		record["equipped_inventory_index"] = selected
	else:
		# Bestiary natural attacks can be selected without deleting gear.
		record.erase("equipped_inventory_index")
	record["equipped_attack_id"] = String(choice.get("id", ""))
	record["reach_feet"] = AttackData.active_range(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Arma attiva non salvata: " + error_string(error))
		return
	_replace_current_record(record)
	if _inventory_ui != null:
		_inventory_ui.call("load_record", record)
	_refresh_attacks(record)
	_refresh_attack_values(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)


func _roll_attack_from_sheet(attack_id: String, damage: bool) -> void:
	var record: Dictionary = _current()
	var attack: Dictionary = {}
	for candidate: Dictionary in AttackData.definitions(record):
		if String(candidate.get("id", "")) == attack_id:
			attack = candidate
			break
	if attack.is_empty():
		return
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller == null or not roller.has_method("roll_expression_from_sheet"):
		_set_status("Il roller della chat non è disponibile.")
		return
	var label: String = String(record.get("name", "Creatura")) + " · " + String(attack.get("name", "Attacco"))
	var expression := ""
	if damage:
		expression = AttackData.damage_expression(record, attack)
		label += " · Danni"
	else:
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) != "item" and not bool(attack.get("hit_known", false)):
			_set_status("Tiro per colpire non specificato nel bestiario.")
			return
		var bonus: int = AttackData.attack_bonus(record, attack, _creature_proficiency(record))
		expression = "1d20%+d" % bonus
		label += " · Colpire"
	if expression.is_empty():
		# Fixed unarmed damage does not involve a die. Report the result via
		# the roller log rather than inventing a random roll.
		var fixed: String = AttackData.damage_label(record, attack)
		if roller.has_method("log_action"):
			roller.call("log_action", label + " · " + fixed)
		else:
			_set_status("Nessuna formula di danno per questo attacco.")
		return
	roller.call("roll_expression_from_sheet", label, expression, find_linked_token_for_creature(_selected_id))


func _refresh_attacks(record: Dictionary) -> void:
	if _attack_rows == null:
		return
	_refresh_weapon_picker(record)
	_attack_hit_labels.clear()
	_attack_damage_labels.clear()
	_attack_range_labels.clear()
	for key: Variant in _formula_values.keys():
		if String(key).begins_with("attack_range:") or String(key).begins_with("attack_hit:") or String(key).begins_with("attack_damage:"):
			_formula_values.erase(key)
	for child: Node in _attack_rows.get_children():
		_attack_rows.remove_child(child)
		child.queue_free()
	var summary: PackedStringArray = []
	var has_equipped_weapon: bool = ItemRules.has_equipped_weapon(record.get("inventory", []))
	var available_attacks: Array[Dictionary] = AttackData.definitions(record)
	var actual_active_id: String = String(AttackData.active_attack(record).get("id", ""))
	# Stable presentation: the active attack first, then all remaining
	# attacks in bestiary/inventory order without an unstable partial sort.
	var attacks: Array[Dictionary] = []
	for candidate: Dictionary in available_attacks:
		if String(candidate.get("id", "")) == actual_active_id:
			attacks.append(candidate)
	for candidate: Dictionary in available_attacks:
		if String(candidate.get("id", "")) != actual_active_id:
			attacks.append(candidate)
	for attack: Dictionary in attacks:
		var attack_id: String = String(attack.get("id", ""))
		if attack_id.is_empty() or (has_equipped_weapon and attack_id in ["unarmed", "improvised"]):
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active: bool = attack_id == actual_active_id
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.16, 0.21, 0.88)
		card_style.border_color = Color(0.54, 0.75, 0.82) if active else Color(0.30, 0.41, 0.49, 0.72)
		card_style.set_border_width_all(2 if active else 1)
		card_style.set_corner_radius_all(8)
		card_style.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", card_style)
		_attack_rows.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		# A dedicated name row prevents long bestiary action names from
		# pushing the dice buttons out of the combat column.
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 7)
		box.add_child(header)
		var name_label := Label.new()
		name_label.text = String(attack.get("name", "Attacco"))
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(name_label)
		if active:
			var active_label := Label.new()
			active_label.text = "IN USO"
			active_label.add_theme_font_size_override("font_size", 11)
			active_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.68))
			header.add_child(active_label)
		# Hit and damage each have their own self-contained line. HFlow
		# wraps the dice button if the pane is narrow, without clipping it.
		var hit_row := HFlowContainer.new()
		hit_row.add_theme_constant_override("h_separation", 8)
		hit_row.add_theme_constant_override("v_separation", 4)
		box.add_child(hit_row)
		var hit_caption := Label.new()
		hit_caption.text = "Colpire"
		hit_caption.add_theme_font_size_override("font_size", 12)
		hit_row.add_child(hit_caption)
		var hit_label := Label.new()
		hit_row.add_child(hit_label)
		_attack_hit_labels[attack_id] = hit_label
		_install_formula("attack_hit:" + attack_id, hit_label, [], [])
		var roll_hit := Button.new()
		roll_hit.text = "Tira per colpire"
		roll_hit.tooltip_text = "Tira 1d20 e il bonus per colpire nel roller"
		roll_hit.pressed.connect(_roll_attack_from_sheet.bind(attack_id, false))
		hit_row.add_child(roll_hit)
		var damage_row := HFlowContainer.new()
		damage_row.add_theme_constant_override("h_separation", 8)
		damage_row.add_theme_constant_override("v_separation", 4)
		box.add_child(damage_row)
		var damage_caption := Label.new()
		damage_caption.text = "Danni"
		damage_caption.add_theme_font_size_override("font_size", 12)
		damage_row.add_child(damage_caption)
		var damage_label := Label.new()
		damage_label.add_theme_font_size_override("font_size", 17)
		damage_row.add_child(damage_label)
		_attack_damage_labels[attack_id] = damage_label
		_install_formula("attack_damage:" + attack_id, damage_label, [], [])
		var roll_damage := Button.new()
		roll_damage.text = "Tira danni"
		roll_damage.tooltip_text = "Tira i danni dell'attacco nel roller"
		roll_damage.pressed.connect(_roll_attack_from_sheet.bind(attack_id, true))
		damage_row.add_child(roll_damage)
		box.add_child(HSeparator.new())
		var settings := HFlowContainer.new()
		settings.add_theme_constant_override("h_separation", 6)
		settings.add_theme_constant_override("v_separation", 3)
		box.add_child(settings)
		var distance_caption := Label.new()
		distance_caption.text = "Gittata"
		distance_caption.add_theme_font_size_override("font_size", 11)
		distance_caption.modulate.a = 0.70
		settings.add_child(distance_caption)
		var distance := SpinBox.new()
		distance.min_value = 5
		distance.max_value = 1000
		distance.step = 5
		distance.rounded = true
		distance.custom_minimum_size.x = 68
		distance.tooltip_text = "Portata o gittata di questo attacco, indipendente dalle altre armi"
		distance.set_value_no_signal(int(AttackData.override_for(record, attack_id).get("range_feet", attack.get("range_feet", 5))))
		distance.value_changed.connect(_on_attack_range_changed.bind(attack_id))
		settings.add_child(distance)
		# Legacy range corrections are migrated to source grants, not inline.
		var range_label := Label.new()
		settings.add_child(range_label)
		_attack_range_labels[attack_id] = range_label
		_install_formula("attack_range:" + attack_id, range_label, [distance], ["Base (ft)"])
		if int(attack.get("long_range_feet", 0)) > int(attack.get("range_feet", 5)):
			var long_range := Label.new()
			long_range.text = "Lunga: %d ft" % int(attack.get("long_range_feet", 0))
			long_range.tooltip_text = "Oltre la gittata normale si applica svantaggio (regole 2014)"
			settings.add_child(long_range)
		if String(attack.get("source", "")) == "item":
			var item_data: Dictionary = attack.get("item_entry", {})
			var properties: PackedStringArray = []
			for code: String in ["F", "R", "T", "V", "2H", "L", "H", "A", "LD"]:
				if ItemRules.has_property(item_data, code):
					properties.append(code)
			var property_names := {
				"F": "Accurata", "R": "Portata", "T": "Lancio",
				"V": "Versatile", "2H": "Due mani", "L": "Leggera",
				"H": "Pesante", "A": "Munizioni", "LD": "Ricarica"
			}
			var chips := HFlowContainer.new()
			chips.add_theme_constant_override("h_separation", 5)
			chips.add_theme_constant_override("v_separation", 4)
			box.add_child(chips)
			for code: String in properties:
				var chip := PanelContainer.new()
				var chip_style := StyleBoxFlat.new()
				chip_style.bg_color = Color(0.18, 0.23, 0.29, 0.90)
				chip_style.border_color = Color(0.37, 0.47, 0.53, 0.80)
				chip_style.set_border_width_all(1)
				chip_style.set_corner_radius_all(6)
				chip_style.set_content_margin_all(5)
				chip.add_theme_stylebox_override("panel", chip_style)
				var chip_text := Label.new()
				chip_text.text = String(property_names.get(code, code))
				chip_text.add_theme_font_size_override("font_size", 12)
				chip.add_child(chip_text)
				chips.add_child(chip)
			var weapon_size: String = String(attack.get("weapon_size", "Medium"))
			var size_chip := Label.new()
			size_chip.text = "Taglia · " + weapon_size
			size_chip.add_theme_font_size_override("font_size", 12)
			size_chip.modulate.a = 0.78
			size_chip.tooltip_text = "Modificabile nell'inventario; in assenza di scelta segue la taglia della creatura."
			chips.add_child(size_chip)
			if ItemRules.has_property(item_data, "V") and String(attack.get("slot", "")) == "main":
				var versatile := CheckBox.new()
				versatile.text = "Due mani (versatile)"
				versatile.tooltip_text = "Usa il dado versatile solo quando la mano secondaria è libera"
				versatile.button_pressed = bool(AttackData.override_for(record, attack_id).get("two_handed", false))
				versatile.disabled = not ItemRules.occupying(record.get("inventory", []), "off").is_empty()
				versatile.toggled.connect(_on_attack_two_handed_changed.bind(attack_id))
				settings.add_child(versatile)
		var extra := SpinBox.new()
		extra.min_value = -99
		extra.max_value = 99
		extra.rounded = true
		extra.custom_minimum_size.x = 75
		extra.tooltip_text = "Bonus manuale di questo attacco, oltre a competenza e caratteristica"
		ManualBonus.decorate(extra)
		var overrides: Dictionary = AttackData.override_for(record, attack_id)
		extra.set_value_no_signal(int(overrides.get("bonus", 0)))
		extra.value_changed.connect(_on_attack_bonus_changed.bind(attack_id))
		settings.add_child(extra)
		extra.hide() # Legacy shared hit/damage bonus is migrated into two grants.
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) != "item":
			var fixed := Label.new()
			fixed.text = "Competenza inclusa (bestiario)"
			fixed.tooltip_text = "Il bonus al tiro per colpire pubblicato da 5etools include già la competenza"
			settings.add_child(fixed)
		elif attack_id == "unarmed":
			var trained := Label.new()
			trained.text = "✓ Competente"
			settings.add_child(trained)
		else:
			var proficiency := Label.new()
			var trained := false
			if String(attack.get("source", "")) == "item":
				var item_info: Dictionary = attack.get("item_entry", {})
				trained = ProficiencyRules.weapon_proficient(record, item_info)
			else:
				trained = bool(attack.get("proficient", false))
			proficiency.text = "✓ Competente" if trained else "○ Non competente"
			proficiency.tooltip_text = "Gestisci competenze e origini nella scheda Competenze, non sul singolo attacco."
			settings.add_child(proficiency)
		if attack.has("raw"):
			var details_toggle := Button.new()
			details_toggle.text = "▸ Descrizione del bestiario"
			details_toggle.flat = true
			details_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			details_toggle.tooltip_text = "Mostra il testo originale di 5etools"
			box.add_child(details_toggle)
			var details := RichTextLabel.new()
			details.custom_minimum_size.y = 100
			details.custom_minimum_size.x = 0
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.fit_content = false
			details.scroll_active = true
			details.visible = false
			FiveToolsText.style(details)
			details.text = FiveToolsText.blocks(attack.get("raw", {}))
			box.add_child(details)
			details_toggle.pressed.connect(func() -> void:
				details.visible = not details.visible
				details_toggle.text = "▾ Nascondi descrizione" if details.visible else "▸ Descrizione del bestiario"
				call_deferred("_update_stats_column_heights")
			)
		summary.append(String(attack.get("name", "Attacco")))
	_attacks_description.text = "\n".join(summary) if not summary.is_empty() else "Nessun attacco disponibile."
	# Show an empty state instead of a blank panel when there are no attacks.
	_attacks_description.visible = summary.is_empty()
	_refresh_attack_values(record)
	call_deferred("_update_stats_column_heights")


func _refresh_attack_values(record: Dictionary) -> void:
	for attack: Dictionary in AttackData.definitions(record):
		var attack_id: String = String(attack.get("id", ""))
		if not _attack_hit_labels.has(attack_id):
			continue
		var hit: int = AttackData.attack_bonus(record, attack, _creature_proficiency(record))
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) != "item" and not bool(attack.get("hit_known", false)):
			_set_formula("attack_hit:" + attack_id, "n.d.", "Bonus per colpire non presente nei dati del bestiario")
		else:
			_set_formula("attack_hit:" + attack_id, "%+d" % hit,
				AttackData.attack_bonus_formula(record, attack, _creature_proficiency(record)))
		var damage: String = AttackData.damage_label(record, attack)
		_set_formula("attack_damage:" + attack_id, damage,
			"Danni: %s. Include bonus di caratteristica e arma quando applicabili, oltre al bonus manuale dell'attacco." % damage)
		if _attack_range_labels.has(attack_id):
			var settings: Dictionary = AttackData.override_for(record, attack_id)
			var base: int = int(settings.get("range_feet", attack.get("range_feet", 5)))
			var bonus: int = int(settings.get("range_bonus", 0))
			_set_formula("attack_range:" + attack_id, "%d ft" % AttackData.range_for(record, attack),
				"Gittata: base %d ft %+d ft manuale %+d ft origini = %d ft" % [base, bonus,
					BonusRules.bonus(record, "attack_range:" + attack_id), AttackData.range_for(record, attack)])


func _on_attack_ability_changed(_index: int) -> void:
	if _loading:
		return
	_save()


func _on_attack_range_changed(value: float, attack_id: String) -> void:
	_save_attack_setting(attack_id, "range_feet", int(value))


func _on_attack_range_bonus_changed(value: float, attack_id: String) -> void:
	_save_attack_setting(attack_id, "range_bonus", int(value))


func _on_attack_bonus_changed(value: float, attack_id: String) -> void:
	_save_attack_setting(attack_id, "bonus", int(value))


func _on_attack_two_handed_changed(enabled: bool, attack_id: String) -> void:
	_save_attack_setting(attack_id, "two_handed", enabled)


func _save_attack_setting(attack_id: String, setting: String, value: Variant) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var updated: Dictionary = record.get("attack_overrides", {}).duplicate(true)
	var attack_settings: Dictionary = updated.get(attack_id, {})
	attack_settings[setting] = value
	updated[attack_id] = attack_settings
	record["attack_overrides"] = updated
	record["reach_feet"] = AttackData.active_range(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare attacco: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_attack_values(record)
	_apply_sheet_properties(record)


func _update_defense_display() -> void:
	var live: Dictionary = _live_stats_record()
	if _ac != null and _ac_bonus != null and _ac_effective != null:
		var equipped: bool = not ItemRules.equipped_armor(live.get("inventory", [])).is_empty()
		_ac.editable = not equipped
		_ac.tooltip_text = "La CA base viene dall'armatura indossata nell'inventario" if equipped else "Classe Armatura base manuale"
		var armor_record: Dictionary = live.duplicate(false)
		armor_record["effective_armor_dex"] = BonusRules.value(live, "ability_mod:dex") if equipped else 0
		var base: Dictionary = ItemRules.armor_base(armor_record)
		var ac: int = maxi(0, BonusRules.value(live, "ac"))
		_set_formula("ac", str(ac), "CA: %s + scudo %+d + bonus manuale %+d + origini %+d = %d" % [
			String(base.get("description", "Base manuale")),
			ItemRules.shield_bonus(live.get("inventory", [])), int(_ac_bonus.value),
			BonusRules.bonus(live, "ac"), ac])
	if _initiative != null and _initiative_bonus != null and _initiative_effective != null:
		var init: int = BonusRules.value(live, "initiative")
		_set_formula("initiative", "%+d" % init,
			"Iniziativa: modificatore DES %+d, bonus manuale %+d, bonus da origini %+d = %+d" % [
				BonusRules.value(live, "ability_mod:dex"), int(_initiative_bonus.value),
				BonusRules.bonus(live, "initiative"), init])


func _update_max_hp_display() -> void:
	if _max_hp_effective == null or _max_hp_bonus == null or _max_hp == null:
		return
	var live: Dictionary = _live_stats_record()
	var maximum: int = maxi(0, BonusRules.value(live, "hp"))
	_set_formula("hp", str(maximum),
		"PF massimi: base %d %+d manuale %+d origini = %d" % [
			int(_max_hp.value), int(_max_hp_bonus.value),
			BonusRules.bonus(live, "hp"), maximum])


func _update_second_max_formula() -> void:
	if _second_form_max_hp != null:
		var live: Dictionary = _live_stats_record()
		var maximum: int = maxi(0, BonusRules.value(live, "second_max"))
		_set_formula("second_max", str(maximum),
			"PF seconda forma: base %d %+d origini = %d" % [
				int(_second_form_max_hp.value), BonusRules.bonus(live, "second_max"), maximum])


func _get_document_peers() -> Array[Dictionary]:
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	if presence == null:
		return []
	presence.call("request_refresh")
	return presence.call("get_online_peers")


func _send_document_to_peer(recipient_id: String, document: Dictionary) -> String:
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	if presence == null:
		return ""
	return String(presence.call("send_document", recipient_id, document))


func receive_shared_document(document: Dictionary, sender_id: String) -> void:
	if not DocumentInbox.receive(document):
		_set_status("Documento ricevuto ma non salvato: controlla i permessi dei file.")
		return
	var current: Dictionary = _current()
	if not current.is_empty() and _inventory_ui != null:
		_inventory_ui.call("receive_document")
	_set_status("Lettera ricevuta da giocatore %s: %s" % [
		sender_id.substr(0, 8), String(document.get("title", "Documento"))
	])


func _on_documents_updated(documents: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	record["documents"] = documents.duplicate(true)
	var err: Error = _archive.save(record)
	if err == OK:
		_replace_current_record(record)
	else:
		_set_status("Impossibile salvare i documenti: " + error_string(err))


func _on_proficiencies_updated(rows: Array, feats: Array, origins: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var typed_rows: Array[Dictionary] = []
	for raw: Variant in rows:
		if raw is Dictionary:
			typed_rows.append((raw as Dictionary).duplicate(true))
	var previous_skills: Variant = record.get("skill_proficiencies", [])
	var previous_expertise: Variant = record.get("skill_expertise", [])
	record["proficiency_origins"] = origins.duplicate(true)
	record["feats_catalog"] = feats.duplicate(true)
	record["proficiency_choices"] = typed_rows.duplicate(true)
	# Reconcile the saved editor state with the current traits and the
	# unremovable grants before persisting it.
	ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
	if previous_skills != record.get("skill_proficiencies", []) or previous_expertise != record.get("skill_expertise", []):
		# Do not re-infer deliberately edited monster skills from the bestiary.
		record["skill_ranks_custom"] = true
	for definition: Dictionary in Skills5e.SKILLS:
		var key := String(definition["id"])
		_skill_ranks[key] = (
			2 if key in record.get("skill_expertise", [])
			else 1 if key in record.get("skill_proficiencies", [])
			else 0
		)
	_skill_ranks_custom = bool(record.get("skill_ranks_custom", false))
	_recalculate_bonus_mirrors(record)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare competenze: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_formula_dependents(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	if _bonuses_ui != null:
		_bonuses_ui.call("load_record", record)
	if _traits_ui != null:
		_traits_ui.call("load_record", record)


func _on_inventory_updated(inventory: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var prior_main: Dictionary = ItemRules.occupying(record.get("inventory", []), "main")
	record["inventory"] = inventory.duplicate(true)
	# Equipment changes made on the inventory page also select the weapon
	# displayed above attacks. Unrelated quantity/armor changes do not.
	var new_main: Dictionary = ItemRules.occupying(record.get("inventory", []), "main")
	# Ignore quantity changes: they do not mean the user switched weapons.
	var previous_signature: String = String(prior_main.get("id", "")) + "|" + String(prior_main.get("instance_id", "")) + "|" + JSON.stringify(prior_main.get("instance_overrides", {}))
	var current_signature: String = String(new_main.get("id", "")) + "|" + String(new_main.get("instance_id", "")) + "|" + JSON.stringify(new_main.get("instance_overrides", {}))
	if previous_signature != current_signature:
		if not new_main.is_empty() and ItemRules.kind(ItemRules.entry_for(new_main)) == "weapon":
			record["equipped_attack_id"] = "item:" + String(new_main.get("id", ""))
			var rows: Array = record.get("inventory", [])
			for i: int in range(rows.size()):
				if rows[i] is Dictionary and "main" in ItemRules.slots(rows[i]):
					record["equipped_inventory_index"] = i
					break
		else:
			record.erase("equipped_inventory_index")
			if String(record.get("equipped_attack_id", "")).begins_with("item:"):
				record.erase("equipped_attack_id")
	var active: Dictionary = AttackData.active_attack(record)
	if not active.is_empty():
		record["equipped_attack_id"] = String(active.get("id", ""))
	# Delete the legacy documents array only after each entry is in inventory
	# and its definition has been written to the homebrew directory.
	var legacy: Variant = record.get("documents", [])
	if legacy is Array:
		var all_migrated := true
		for raw: Variant in legacy:
			if not raw is Dictionary:
				continue
			var target_id: String = DocumentStore.legacy_id(raw as Dictionary)
			var found := false
			for item: Variant in inventory:
				if item is Dictionary and String((item as Dictionary).get("id", "")) == target_id:
					found = true
					break
			if not found:
				all_migrated = false
				break
		if all_migrated:
			record.erase("documents")
	record["armor_class"] = maxi(0, BonusRules.value(record, "ac"))
	# Removing an item also revokes proficiencies assigned to that item.
	ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
	_recalculate_bonus_mirrors(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare inventario: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_formula_dependents(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	_refresh_reference(record)
	if _bonuses_ui != null:
		_bonuses_ui.call("load_record", record)


func _on_ability_value_changed(_value: float, ability: String) -> void:
	_update_ability_modifier(ability)
	_save()


func _update_ability_modifier(ability: String) -> void:
	if not _ability_spins.has(ability):
		return
	var live: Dictionary = _live_stats_record()
	var score: int = BonusRules.value(live, "ability:" + ability)
	var value: int = BonusRules.value(live, "ability_mod:" + ability)
	_set_formula("ability_mod:" + ability, "%+d" % value,
		"%s: floor((%d - 10) / 2) %+d bonus sul modificatore = %+d" % [
			ability.to_upper(), score, BonusRules.bonus(live, "ability_mod:" + ability), value])
	_set_formula("ability:" + ability, str(score),
		"%s: base %d %+d manuale %+d bonus da origini = %d" % [
			ability.to_upper(), int((_ability_spins[ability] as SpinBox).value),
			int((_ability_bonus_spins[ability] as SpinBox).value),
			BonusRules.bonus(live, "ability:" + ability), score])
	if ability == "dex" and _initiative != null and not _loading:
		# Initiative is derived; changing the readout must not trigger a
		# second full archive save while updating the Dexterity field.
		_initiative.set_value_no_signal(value)
		_update_defense_display()
	if not _loading:
		_refresh_skill_values(live)


func _replace_current_record(record: Dictionary) -> void:
	for i: int in range(_records.size()):
		if (
			String(_records[i].get("id", "")) == _selected_id
			and String(_records[i].get("kind", "")) == _selected_kind
		):
			_records[i] = record
			var creature_id: String = String(record.get("id", "")).strip_edges()
			if not creature_id.is_empty():
				_owned_name_index[creature_id] = String(record.get("name", "")).strip_edges()
			var icon := "◇" if String(record.get("kind", "")) == "monster" else "♙"
			_creature_row_buttons[i].text = "%s %s" % [icon, record.get("name", "")]
			_creature_row_buttons[i].tooltip_text = String(record.get("name", ""))
			_filter_owned_creatures(_creature_filter.text)
			break


func _save() -> void:
	if _loading:
		return
	var record := _current()
	if record.is_empty():
		return
	record["name"] = _name.text.strip_edges()
	record["current_hp"] = int(_hp.value)
	record["max_hp_base"] = int(_max_hp.value)
	record["max_hp_bonus"] = int(_max_hp_bonus.value)
	record["max_hp"] = maxi(0, int(_max_hp.value) + int(_max_hp_bonus.value)) # Effective value updated after all inputs
	record["temporary_hp"] = int(_temp_hp.value)
	record["second_form_max_hp"] = int(_second_form_max_hp.value)
	record["second_form_hp"] = clampi(int(_second_form_hp.value), 0, int(_second_form_max_hp.value))
	record["background_personality"] = _biography.text
	var background_entry: Dictionary = _reference_entry(_background)
	record["background"] = String(background_entry.get("name", ""))
	record["background_source"] = String(background_entry.get("source", ""))
	record["background_id"] = String(background_entry.get("id", ""))
	record["size_name"] = _size_choice.get_item_text(_size_choice.selected)
	if _inventory_ui != null:
		_inventory_ui.call("update_creature_size", String(record["size_name"]))
	record["footprint"] = _selected_size_footprint()
	record["visual_front_quarter_turns"] = _front.selected
	record["party_id"] = _party.text.strip_edges()
	record["armor_class_base"] = int(_ac.value)
	record["armor_class_bonus"] = int(_ac_bonus.value)
	record["armor_class"] = maxi(0, int(_ac.value) + int(_ac_bonus.value) + ItemRules.shield_bonus(record.get("inventory", [])))
	record["initiative_base"] = int(_initiative.value)
	record["initiative_bonus"] = int(_initiative_bonus.value)
	record["initiative"] = int(_initiative.value) + int(_initiative_bonus.value)
	record["speed_base"] = int(_speed.value)
	record["speed_bonus"] = int(_speed_bonus.value)
	record["speed"] = maxi(0, int(_speed.value) + int(_speed_bonus.value))
	record["speed_is_custom"] = _speed_custom
	var abilities: Dictionary = {}
	for ability: String in _ability_spins.keys():
		abilities[ability] = int((_ability_spins[ability] as SpinBox).value)
	record["abilities"] = abilities
	var ability_bonuses: Dictionary = {}
	for ability: String in _ability_bonus_spins.keys():
		ability_bonuses[ability] = int((_ability_bonus_spins[ability] as SpinBox).value)
	record["ability_bonuses"] = ability_bonuses
	record["attack_ability"] = "dex" if _attack_ability.selected == 1 else "str"
	record["reach_feet"] = AttackData.active_range(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	# Proficiencies are now owned exclusively by the origin editor.
	# Saving unrelated statistics must never change expertise or resurrect
	# rows that were deliberately disabled.
	ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
	if _skill_ranks_custom:
		record["skill_ranks_custom"] = true
	record["default_miniature_id"] = _default_miniature_id
	var is_monster: bool = String(record.get("kind", "")) == "monster"
	if is_monster:
		# Keep fractional CR independent of classes and level.
		var stat: Dictionary = record.get("stat_block", {}).duplicate(true)
		var cr_text: String = _challenge_rating.text.strip_edges()
		var valid_cr := cr_text.is_valid_float() and float(cr_text) >= 0.0
		if "/" in cr_text:
			var fraction: PackedStringArray = cr_text.split("/")
			valid_cr = (fraction.size() == 2 and fraction[0].is_valid_int()
				and fraction[1].is_valid_int() and int(fraction[0]) >= 0 and int(fraction[1]) > 0)
		if not valid_cr:
			_set_status("GS non valido: inserisci un numero o una frazione come 1/4.")
			return
		var old_cr: Variant = stat.get("cr", 0)
		if old_cr is Dictionary:
			var updated_cr: Dictionary = (old_cr as Dictionary).duplicate(true)
			updated_cr["cr"] = cr_text
			stat["cr"] = updated_cr
		else:
			stat["cr"] = cr_text
		record["stat_block"] = stat
		record["species"] = String(stat.get("name", record.get("base_name", "")))
		record["species_source"] = String(stat.get("source", ""))
	else:
		var species: Dictionary = _reference_entry(_species)
		var subrace: Dictionary = _reference_entry(_subrace_choice)
		record["species_id"] = String(species.get("id", ""))
		record["species"] = String(species.get("name", ""))
		record["species_source"] = String(species.get("source", ""))
		record["subrace"] = String(subrace.get("name", ""))
		record["subrace_source"] = String(subrace.get("source", ""))
		record["subrace_id"] = String(subrace.get("id", ""))
	var class_ref: Dictionary = _reference_entry(_class_name)
	record["class_id"] = String(class_ref.get("id", ""))
	record["class"] = String(class_ref.get("name", ""))
	record["class_source"] = String(class_ref.get("source", ""))
	var primary_subclass: Dictionary = _reference_entry(_subclass_name)
	record["subclass"] = String(primary_subclass.get("name", ""))
	record["subclass_source"] = String(primary_subclass.get("source", ""))
	record["subclass_id"] = String(primary_subclass.get("id", ""))
	record["rules_version"] = _selected_rules_version()
	var primary_level: int = clampi(int(_level.value), 1, 20)
	var classes: Array[Dictionary] = []
	var extras_level := 0
	if String(record["class"]).is_empty() and not _multiclass_controls.is_empty():
		_set_status("Seleziona la classe base prima di aggiungere altre classi.")
		return
	for definition: Dictionary in _multiclass_controls:
		var extra_ref: Dictionary = _reference_entry(definition["selector"])
		if String(extra_ref.get("name", "")).is_empty():
			continue
		var extra_level: int = int((definition["level"] as SpinBox).value)
		var extra_subclass: Dictionary = _reference_entry(definition["subclass"])
		extras_level += extra_level
		classes.append({
			"name": String(extra_ref.get("name", "")),
			"source": String(extra_ref.get("source", "")),
			"id": String(extra_ref.get("id", "")),
			"level": extra_level,
			"subclass": String(extra_subclass.get("name", "")),
			"subclass_source": String(extra_subclass.get("source", "")),
			"subclass_id": String(extra_subclass.get("id", ""))
		})
	var actual_primary_level: int = primary_level if not String(record["class"]).is_empty() else 0
	if actual_primary_level + extras_level > 20:
		_set_status("La somma dei livelli delle classi non può superare 20.")
		return
	record["level"] = actual_primary_level + extras_level
	if actual_primary_level > 0:
		classes.push_front({
			"name": record["class"], "source": record["class_source"],
			"id": record["class_id"], "level": primary_level,
			"subclass": record["subclass"],
			"subclass_source": record["subclass_source"],
			"subclass_id": record["subclass_id"]
		})
	record["classes"] = classes
	_refresh_xp_minimum()
	record["xp"] = maxi(int(_xp.value), Rules.experience_for_level(_class_xp_level()))
	# Refresh the normalized grants only after species, background and classes
	# have all been updated. This removes superseded racial origins immediately.
	var current_grants: Array[Dictionary] = ProficiencyRules.choices(record)
	ProficiencyRules.sync_legacy_fields(record, current_grants)
	var saved_origins: Array[Dictionary] = []
	for origin: Dictionary in ProficiencyRules.origins(record):
		saved_origins.append({"id": origin.get("id", ""), "name": origin.get("name", ""),
			"group": origin.get("group", ""), "automatic": bool(origin.get("automatic", false)),
			"disabled": bool(origin.get("disabled", false))})
	record["proficiency_origins"] = saved_origins
	# Mirrors used by tokens/combat always include every active formula bonus.
	_recalculate_bonus_mirrors(record)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio non riuscito: %s" % error_string(error))
		return
	_replace_current_record(record)
	_refresh_skill_values(record)
	_refresh_attack_values(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	# A visible sheet follows current level and race/class immediately.
	_refresh_reference(record)
	_refresh_trackers(record)
	if _spellcasting_ui != null:
		_spellcasting_ui.call("update_character_context", record)


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
	_hp_delta_dialog.get_cancel_button().text = "Annulla"
	_hp_delta_dialog.dialog_text = ""
	_hp_delta_dialog.min_size = Vector2i(390, 235)
	(board_root.get_node("UI") as CanvasLayer).add_child(_hp_delta_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_hp_delta_dialog.add_child(body)
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
	_popup_sheet_dialog(_hp_delta_dialog, Vector2i(500, 300), 0.90)


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
	var old_form: int = int(_second_form_hp.value)
	var record: Dictionary = _current()
	var hp: int = int(_hp.value)
	var temp: int = int(_temp_hp.value)
	var form_hp: int = old_form
	if delta < 0:
		var damage_result: Dictionary = Rules.apply_damage_layers(record, -delta)
		temp = int(damage_result.get("temporary_hp", temp))
		form_hp = int(damage_result.get("second_form_hp", form_hp))
		hp = int(damage_result.get("current_hp", hp))
	else:
		hp = mini(maxi(0, int(_max_hp.value) + int(_max_hp_bonus.value)), hp + delta)
	_loading = true
	_temp_hp.value = temp
	_second_form_hp.value = form_hp
	_hp.value = hp
	_loading = false
	_save()
	if old_form > 0 and form_hp == 0:
		_offer_restore_after_form_depleted()


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


func _build_second_form_dialogs() -> void:
	_form_hp_dialog = ConfirmationDialog.new()
	_form_hp_dialog.title = "PF della seconda forma"
	_form_hp_dialog.dialog_text = ""
	_form_hp_dialog.min_size = Vector2i(500, 265)
	_form_hp_dialog.get_ok_button().text = "Applica"
	_form_hp_dialog.get_cancel_button().text = "Annulla"
	(board_root.get_node("UI") as CanvasLayer).add_child(_form_hp_dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	_form_hp_dialog.add_child(content)
	var description := Label.new()
	description.text = "Vuoi assegnare PF alla nuova forma?"
	content.add_child(description)
	_form_hp_choice = OptionButton.new()
	_form_hp_choice.add_item("Sì · Inserisci manualmente", 0)
	_form_hp_choice.add_item("Sì · Prendi dal bestiario", 1)
	_form_hp_choice.add_item("No · Senza PF di seconda forma", 2)
	content.add_child(_form_hp_choice)
	_form_hp_manual = SpinBox.new()
	_form_hp_manual.min_value = 0
	_form_hp_manual.max_value = 99999
	_form_hp_manual.step = 1
	_form_hp_manual.rounded = true
	_form_hp_manual.value = 1
	content.add_child(_form_hp_manual)
	_form_hp_choice.item_selected.connect(func(index: int) -> void:
		_form_hp_manual.visible = index == 0
	)
	_form_hp_dialog.confirmed.connect(_apply_second_form_choice)
	_restore_form_dialog = ConfirmationDialog.new()
	_restore_form_dialog.title = "Ripristino della forma base"
	_restore_form_dialog.dialog_text = "Rimuovere anche i PF della seconda forma?"
	_restore_form_dialog.get_ok_button().text = "Sì, rimuovi"
	_restore_form_dialog.get_cancel_button().text = "No, conserva"
	_restore_form_dialog.confirmed.connect(func() -> void: _restore_base_form(true))
	_restore_form_dialog.canceled.connect(func() -> void: _restore_base_form(false))
	(board_root.get_node("UI") as CanvasLayer).add_child(_restore_form_dialog)
	_form_depleted_dialog = ConfirmationDialog.new()
	_form_depleted_dialog.title = "Seconda forma esaurita"
	_form_depleted_dialog.dialog_text = "I PF della seconda forma sono a 0. Ripristinare l'aspetto di base?"
	_form_depleted_dialog.get_ok_button().text = "Sì, ripristina"
	_form_depleted_dialog.get_cancel_button().text = "No, mantieni"
	_form_depleted_dialog.confirmed.connect(func() -> void:
		_restore_base_form(true, _form_depleted_target_id)
	)
	(board_root.get_node("UI") as CanvasLayer).add_child(_form_depleted_dialog)


func _prompt_second_form_hp(record: Dictionary) -> void:
	_form_hp_pending_id = String(record.get("id", ""))
	_form_hp_choice.select(0)
	_form_hp_manual.visible = true
	_form_hp_manual.value = maxi(1, int(record.get("second_form_max_hp", 1)))
	_popup_sheet_dialog(_form_hp_dialog, Vector2i(530, 290), 0.88)


func _apply_second_form_choice() -> void:
	var record: Dictionary = _current()
	if record.is_empty() or String(record.get("id", "")) != _form_hp_pending_id:
		return
	match _form_hp_choice.selected:
		0:
			_set_second_form_hp(maxi(0, int(_form_hp_manual.value)))
		1:
			var miniature_id: String = String(record.get("current_miniature_id", ""))
			var identity: String = TokenPackManager.miniature_identity(miniature_id, "")
			var reference: Dictionary = TokenPackManager.get_bestiary_reference(identity, "2014")
			if reference.is_empty():
				reference = TokenPackManager.get_bestiary_reference(identity, "2024")
			if reference.is_empty():
				_set_status("La miniatura non ha una voce del bestiario associata: scegli PF manuali.")
				_prompt_second_form_hp(record)
				return
			var request_key := "form_hp_%d" % Time.get_ticks_usec()
			_form_hp_requests[request_key] = {
				"id": _form_hp_pending_id, "miniature_id": miniature_id
			}
			_client.call("request_creature", String(reference.get("name", "")),
				String(reference.get("source", "")), request_key)
			_set_status("Caricamento PF della forma dal bestiario…")
		2:
			_set_second_form_hp(0)


func _set_second_form_hp(maximum: int) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	record["second_form_max_hp"] = maxi(0, maximum)
	record["second_form_hp"] = maxi(0, maximum)
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare i PF della seconda forma.")
		return
	_replace_current_record(record)
	_load_form(record)
	_sync_token_health(record)


func _restore_base_form(clear_hp: bool, target_id: String = "") -> void:
	var record: Dictionary = _current()
	if not target_id.is_empty() and String(record.get("id", "")) != target_id:
		record = {}
		for owned: Dictionary in _archive.list_owned():
			if String(owned.get("id", "")) == target_id:
				record = owned
				break
	if record.is_empty():
		return
	var original_id: String = String(record.get("default_miniature_id", ""))
	if original_id.is_empty():
		return
	record["current_miniature_id"] = original_id
	if clear_hp:
		record["second_form_hp"] = 0
		record["second_form_max_hp"] = 0
	if _archive.save(record) != OK:
		_set_status("Impossibile ripristinare l'aspetto.")
		return
	_replace_current_record(record)
	if String(record.get("id", "")) == _selected_id:
		_load_form(record)
	_apply_current_appearance(record)
	_sync_token_health(record)


func _offer_restore_after_form_depleted(record: Dictionary = {}) -> void:
	var target: Dictionary = record if not record.is_empty() else _current()
	if target.is_empty() or String(target.get("current_miniature_id", "")).is_empty():
		return
	if String(target.get("current_miniature_id", "")) == String(target.get("default_miniature_id", "")):
		return
	_form_depleted_target_id = String(target.get("id", ""))
	_form_depleted_dialog.dialog_text = "I PF della seconda forma di %s sono a 0. Ripristinare l'aspetto di base?" % String(target.get("name", "Creatura"))
	_popup_sheet_dialog(_form_depleted_dialog, Vector2i(525, 215))


func _restore_default_appearance() -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	if String(record.get("default_miniature_id", "")).is_empty():
		_set_status("Questa creatura non ha ancora una miniatura di base.")
		return
	if int(record.get("second_form_hp", 0)) > 0:
		_popup_sheet_dialog(_restore_form_dialog, Vector2i(510, 200))
	else:
		_restore_base_form(true)


func _set_current_miniature(miniature_id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty() or miniature_id.is_empty():
		return
	record["current_miniature_id"] = miniature_id
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare l'aspetto attuale.")
		return
	_replace_current_record(record)
	_update_current_appearance_display(record)
	_apply_current_appearance(record)


func _on_form_hp_changed(value: float) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var previous: int = int(record.get("second_form_hp", 0))
	if int(value) > int(_second_form_max_hp.value):
		_loading = true
		_second_form_max_hp.value = int(value)
		_loading = false
	_save()
	if previous > 0 and int(value) == 0:
		_offer_restore_after_form_depleted()


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

func _structured_trackers(record: Dictionary) -> Array[Dictionary]:
	return StructuredTrackers.for_creature(record)


func _refresh_trackers(record: Dictionary) -> void:
	if _tracker_rows == null:
		return
	for child: Node in _tracker_rows.get_children():
		_tracker_rows.remove_child(child)
		child.queue_free()
	var trackers: Array[Dictionary] = _structured_trackers(record)
	if trackers.is_empty():
		var hint := Label.new()
		hint.text = "Nessuna risorsa con utilizzi espliciti nei dati strutturati."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tracker_rows.add_child(hint)
		return
	var spent_value: Variant = record.get("resource_tracker_spent", {})
	var spent: Dictionary = spent_value as Dictionary if spent_value is Dictionary else {}
	var bonus_value: Variant = record.get("resource_tracker_bonuses", {})
	var bonuses: Dictionary = bonus_value as Dictionary if bonus_value is Dictionary else {}
	for tracker: Dictionary in trackers:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 5)
		row.add_theme_constant_override("v_separation", 3)
		_tracker_rows.add_child(row)
		var source_button := Button.new()
		var title: String = String(tracker.get("name", "Risorsa"))
		var source_label: String = String(tracker.get("source_label", ""))
		source_button.text = (title.substr(0, 23) + "…" if title.length() > 24 else title) + " ↗"
		source_button.tooltip_text = (
			"Vai al privilegio: " + String(tracker.get("origin", title))
			+ (" · " + source_label if not source_label.is_empty() else "")
		)
		source_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		source_button.clip_text = true
		source_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		source_button.pressed.connect(
			_open_tracker_trait.bind(String(tracker.get("origin", title)), source_label)
		)
		row.add_child(source_button)
		var id: String = String(tracker["id"])
		var base_maximum: int = int(tracker["max"])
		var maximum: int = maxi(0, BonusRules.add(record, "tracker:" + id,
			base_maximum + int(bonuses.get(id, 0))))
		var used: int = clampi(int(spent.get(id, 0)), 0, maximum)
		var counter_group := HBoxContainer.new()
		counter_group.add_theme_constant_override("separation", 4)
		# HFlowContainer may wrap the whole counter but never split its buttons.
		row.add_child(counter_group)
		var consume := Button.new()
		consume.text = "−"
		consume.tooltip_text = "Consuma un utilizzo"
		consume.disabled = used >= maximum
		consume.pressed.connect(_change_tracker.bind(id, 1, maximum))
		counter_group.add_child(consume)
		var remaining := Label.new()
		remaining.text = "%d /" % (maximum - used)
		remaining.custom_minimum_size.x = 68
		remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		counter_group.add_child(remaining)
		var maximum_label := Label.new()
		counter_group.add_child(maximum_label)
		var manual_bonus := SpinBox.new()
		manual_bonus.min_value = -999
		manual_bonus.max_value = 9999
		manual_bonus.step = 1
		manual_bonus.rounded = true
		manual_bonus.update_on_text_changed = false
		manual_bonus.custom_minimum_size = Vector2(63, 36)
		manual_bonus.tooltip_text = "Di cui bonus al massimo (%d utilizzi base)" % base_maximum
		manual_bonus.set_value_no_signal(int(bonuses.get(id, 0)))
		ManualBonus.decorate(manual_bonus)
		manual_bonus.hide()
		manual_bonus.value_changed.connect(_change_tracker_bonus.bind(id))
		row.add_child(manual_bonus)
		var max_index: int = maximum_label.get_index()
		counter_group.remove_child(maximum_label)
		var formula := FormulaValue.new()
		counter_group.add_child(formula)
		counter_group.move_child(formula, max_index)
		formula.setup(maximum_label, [], [])
		formula.target_key = "tracker:" + id
		formula.bonus_requested.connect(_on_formula_bonus_requested)
		formula.set_formula(str(maximum),
			"%s: base %d %+d manuale %+d origini = %d" % [
				title, base_maximum, int(bonuses.get(id, 0)),
				BonusRules.bonus(record, "tracker:" + id), maximum
			] + ("\n" + BonusRules.description(record, "tracker:" + id)))
		var restore := Button.new()
		restore.text = "+"
		restore.tooltip_text = "Recupera un utilizzo"
		restore.disabled = used <= 0
		restore.pressed.connect(_change_tracker.bind(id, -1, maximum))
		counter_group.add_child(restore)
		counter_group.move_child(restore, consume.get_index() + 1)
		# Keep both resource adjustments immediately before remaining / max.
		var recharge: String = String(tracker.get("recharge", "manual"))
		if recharge == "d6":
			var threshold: int = clampi(int(tracker.get("recharge_min", 6)), 1, 6)
			var roll := Button.new()
			roll.text = "d6"
			roll.tooltip_text = "Tira d6: ricarica con %d–6" % threshold
			roll.disabled = used == 0
			roll.pressed.connect(_roll_tracker_recharge.bind(id, threshold, title, maximum))
			row.add_child(roll)
		var reset := Button.new()
		reset.text = "↺"
		reset.tooltip_text = (
			"Ripristina le azioni all'inizio del turno"
			if recharge == "turn" else "Ripristina tutti gli utilizzi (manuale)"
		)
		reset.disabled = used == 0
		reset.pressed.connect(_change_tracker.bind(id, -maximum, maximum))
		row.add_child(reset)


func _roll_tracker_recharge(
	id: String, threshold: int, label: String, maximum: int
) -> void:
	var roll: int = randi_range(1, 6)
	if roll >= threshold:
		_change_tracker(id, -maximum, maximum)
	_set_status("%s · Ricarica d6: %d (%s, occorre %d–6)." % [
		label, roll, "riuscita" if roll >= threshold else "fallita", threshold
	])


func _change_tracker_bonus(value: float, id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var bonuses: Dictionary = record.get("resource_tracker_bonuses", {}).duplicate(true)
	bonuses[id] = clampi(int(value), -999, 9999)
	record["resource_tracker_bonuses"] = bonuses
	var maximum: int = 0
	for tracker: Dictionary in _structured_trackers(record):
		if String(tracker.get("id", "")) == id:
			maximum = maxi(0, int(tracker.get("max", 0)) + int(bonuses[id]))
			break
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	spent[id] = clampi(int(spent.get(id, 0)), 0, maximum)
	record["resource_tracker_spent"] = spent
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Bonus tracker non salvato: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_trackers(record)


func _change_tracker(id: String, delta: int, maximum: int) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	spent[id] = clampi(int(spent.get(id, 0)) + delta, 0, maximum)
	record["resource_tracker_spent"] = spent
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Tracker non salvato: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_trackers(record)


func _open_tracker_trait(origin: String, source_label: String = "") -> void:
	for i: int in range(_tabs.get_tab_count()):
		if _tabs.get_tab_title(i) == "Tratti":
			_tabs.current_tab = i
			call_deferred("_focus_tracker_trait", origin, source_label)
			return


func _focus_tracker_trait(origin: String, source_label: String = "") -> void:
	if _traits_ui != null and not origin.is_empty():
		_traits_ui.call("focus_feature", origin, source_label)


func _on_creature_tab_changed(index: int) -> void:
	if _traits_ui == null or index < 0 or index >= _tabs.get_tab_count():
		return
	if _tabs.get_tab_title(index) == "Tratti" and _traits_stale:
		_traits_ui.call("load_record", _current())
		_traits_stale = false


func _refresh_reference(record: Dictionary) -> void:
	_traits_stale = true
	_proficiencies_stale = true
	if _traits_ui != null and _tabs != null and _tabs.get_tab_title(_tabs.current_tab) == "Tratti":
		_traits_ui.call("load_record", record)
		_traits_stale = false
	if _proficiencies_ui != null and _proficiencies_ui.visible:
		_proficiencies_ui.call("load_record", record)
		_proficiencies_stale = false


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
	_set_status("Caricamento creatura dal bestiario…")


func _on_monster_received(request_key: String, stat: Dictionary) -> void:
	if _form_hp_requests.has(request_key):
		var pending: Dictionary = _form_hp_requests[request_key]
		_form_hp_requests.erase(request_key)
		for owned: Dictionary in _archive.list_owned():
			if (String(owned.get("id", "")) != String(pending.get("id", ""))
				or String(owned.get("current_miniature_id", "")) != String(pending.get("miniature_id", ""))):
				continue
			var hp_result: Dictionary = Rules.automatic_monster_hit_points({"stat_block": stat})
			if not bool(hp_result.get("available", false)):
				_set_status("Bestiario senza PF medi strutturati: inserisci PF manualmente.")
				return
			owned["second_form_max_hp"] = int(hp_result.get("value", 0))
			owned["second_form_hp"] = int(hp_result.get("value", 0))
			if _archive.save(owned) == OK:
				_replace_current_record(owned)
				if String(owned.get("id", "")) == _selected_id:
					_load_form(owned)
				_sync_token_health(owned)
				_set_status("PF della seconda forma caricati dal bestiario.")
			return
		return
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
	if token == null or not is_instance_valid(token) or token.is_queued_for_deletion() or not board_root.is_ancestor_of(token):
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
		if int(owned.get("max_hp_base", 1)) == 1:
			owned["max_hp_base"] = completed.get("max_hp_base", 1)
			owned["max_hp"] = maxi(0, int(owned["max_hp_base"]) + int(owned.get("max_hp_bonus", 0)))
			if int(owned.get("current_hp", 1)) == 1:
				owned["current_hp"] = owned["max_hp"]
		if int(owned.get("armor_class", 10)) == 10:
			owned["armor_class"] = completed.get("armor_class", 10)
		if _archive.save(owned) == OK:
			_reload()
			_sync_token_health(owned)
		return


func _on_creature_request_failed(request_key: String, message: String) -> void:
	if _form_hp_requests.has(request_key):
		_form_hp_requests.erase(request_key)
		_set_status("PF della forma non disponibili: " + message + " · Inserisci PF manualmente.")
		return
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


# Keep all creature confirmations on the same first-open layout path.
func _popup_sheet_dialog(
	dialog: ConfirmationDialog,
	preferred: Vector2i,
	ratio: float = 0.88
) -> void:
	if dialog == null:
		return
	dialog.get_ok_button().show()
	dialog.get_cancel_button().show()
	DialogLayout.popup(dialog, preferred, ratio)


func _build_miniature_dialog() -> void:
	_miniature_dialog = ConfirmationDialog.new()
	_miniature_dialog.title = "Miniatura predefinita"
	_miniature_dialog.get_ok_button().text = "Conferma"
	_miniature_dialog.get_cancel_button().text = "Annulla"
	_miniature_dialog.get_ok_button().custom_minimum_size = Vector2(112, 38)
	_miniature_dialog.get_cancel_button().custom_minimum_size = Vector2(112, 38)
	_miniature_dialog.dialog_text = ""
	_miniature_dialog.min_size = Vector2i(540, 340)
	(board_root.get_node("UI") as CanvasLayer).add_child(_miniature_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The picker must not grow past the dialog action row on first opening.
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_miniature_dialog.add_child(body)
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
	_miniature_list.custom_minimum_size = Vector2(0, 168)
	_miniature_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_miniature_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	_popup_sheet_dialog(_miniature_dialog, Vector2i(650, 450))


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
	var previous_current_id: String = String(record.get("current_miniature_id", ""))
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
				break
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare la miniatura della creatura.")
		return
	_selected_id = String(record.get("id", ""))
	_selected_kind = String(record.get("kind", ""))
	var changed_current: bool = _picker_current and previous_current_id != _chosen_miniature_id
	_pending_miniature_record.clear()
	_pending_new_creature = false
	_picker_current = false
	_reload()
	if changed_current:
		_apply_current_appearance(record)
		if (String(record.get("current_miniature_id", ""))
			!= String(record.get("default_miniature_id", ""))):
			_prompt_second_form_hp(record)
		elif int(record.get("second_form_hp", 0)) > 0:
			_popup_sheet_dialog(_restore_form_dialog, Vector2i(510, 200))
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
	_popup_sheet_dialog(_delete_dialog, Vector2i(520, 270), 0.90)


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


func _update_current_appearance_display(record: Dictionary) -> void:
	if _current_miniature_row == null:
		return
	var base_id: String = String(record.get("default_miniature_id", ""))
	var current_id: String = String(record.get("current_miniature_id", base_id))
	var changed: bool = not current_id.is_empty() and current_id != base_id
	_current_miniature_row.visible = changed
	if changed:
		_current_miniature_name.text = _miniature_display_name(current_id)
		_current_miniature_name.tooltip_text = "ID catalogo: " + current_id
	else:
		_current_miniature_name.text = ""
		_current_miniature_name.tooltip_text = ""


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


# Combat damage uses the same persistent creature sheet as the token health bar.
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
		if hp_max <= 0 and int(owned.get("second_form_hp", 0)) <= 0:
			return {"applied": false}
		var hp_now := clampi(int(owned.get("current_hp", hp_max)), 0, hp_max)
		var prior_form: int = maxi(0, int(owned.get("second_form_hp", 0)))
		var resolved: Dictionary = Rules.apply_damage_layers(owned, damage)
		owned["current_hp"] = int(resolved.get("current_hp", hp_now))
		owned["temporary_hp"] = int(resolved.get("temporary_hp", 0))
		owned["second_form_hp"] = int(resolved.get("second_form_hp", 0))
		if _archive.save(owned) != OK:
			return {"applied": false}
		_replace_current_record(owned)
		_sync_token_health(owned)
		if String(owned.get("id", "")) == _selected_id and is_panel_open():
			_load_form(owned)
		if prior_form > 0 and int(owned["second_form_hp"]) == 0:
			_offer_restore_after_form_depleted(owned)
		return {
			"applied": true,
			"current_hp": int(owned["current_hp"]),
			"max_hp": hp_max,
			"temporary_hp": int(owned["temporary_hp"]),
			"second_form_hp": int(owned["second_form_hp"]),
			"second_form_max_hp": int(owned.get("second_form_max_hp", 0))
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
	# Restore tactical reach from the saved attacks as well as on live edits.
	# This repairs tokens loaded from older maps with an aggregate reach.
	if token.has_method("get_reach_feet") and token.has_method("set_reach_feet"):
		var first_melee: float = AttackData.active_range(record)
		if absf(float(token.call("get_reach_feet")) - first_melee) > 0.01:
			token.call("set_reach_feet", first_melee, true)
	if token.has_method("set_display_name"):
		token.call("set_display_name", String(record.get("name", "")))
	if token.has_method("set_conditions"):
		token.call("set_conditions", record.get("conditions", []))
	if token.has_method(method):
		var transformed: bool = int(record.get("second_form_hp", 0)) > 0
		token.call(method,
			int(record.get("second_form_hp", 0)) if transformed else int(record.get("current_hp", 1)),
			int(record.get("second_form_max_hp", 0)) if transformed else int(record.get("max_hp", 1))
		)


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in _records:
		var id := String(record.get("linked_token_sync_id", ""))
		var transformed: bool = int(record.get("second_form_hp", 0)) > 0
		var maximum: int = int(record.get("second_form_max_hp", 0)) if transformed else int(record.get("max_hp", 0))
		if id.is_empty() or maximum <= 0 or _find_linked_token(record) == null:
			continue
		rows.append({
			"token_id": id,
			"percent": clampf(
				float(record.get("second_form_hp", 0) if transformed else record.get("current_hp", 0)) / float(maximum) * 100.0,
				0.0, 100.0
			)
		})
	return rows


func _transfer() -> void:
	var record := _current()
	if record.is_empty() or _transfer_users.selected < 0:
		return
	if _transfer_users.is_item_disabled(_transfer_users.selected):
		return
	var recipient_id: String = String(_transfer_users.get_item_metadata(
		_transfer_users.selected
	))
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	var still_online := false
	if presence != null and presence.has_method("get_online_peers"):
		for peer: Dictionary in presence.call("get_online_peers"):
			if String(peer.get("id", "")) == recipient_id:
				still_online = true
				break
	if not still_online:
		_set_status("Destinatario non più online: aggiorna l'elenco.")
		return
	var package: Dictionary = _archive.relinquish(record, recipient_id)
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
	DialogLayout.popup(_import_dialog, Vector2i(720, 340), 0.9)


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
					"effects": "Altri effetti"
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
	_effect_text.text = FiveToolsText.blocks(definition.get(
		"entries", definition.get("description", ContentCatalog.description(definition))
	))
	DialogLayout.popup(_effect_dialog, Vector2i(600, 450))


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
	if _inventory_ui != null:
		_inventory_ui.call("reload_catalog")
	_set_reference_choices(_species, Player5eTools.entries("races"))
	_refresh_class_choices()
	_reload()
	_on_catalog_ready(_client.call("catalog"))
	_set_status("Cataloghi e integrazioni ricaricati. " + "\n".join(ContentCatalog.diagnostics + ContentCatalog.enrichment_diagnostics()))
