extends Node

# Reusable creature sheet for players and GMs. No role-specific permissions.
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const QuickCustom = preload("res://vtt/quick_custom_catalog.gd")
const QuickCustomDialog = preload("res://vtt/quick_custom_catalog_dialog.gd")
const Archive = preload("res://vtt/creature_archive.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const DiceRoller = preload("res://vtt/dice_roller_chat.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const Bestiary = preload("res://vtt/bestiary_5etools_client.gd")
const PlayerReference = preload("res://vtt/player_reference_catalog.gd")
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")
const RaceRules = preload("res://vtt/creature_race_rules.gd")
const ActionEconomyTab = preload("res://vtt/creature_action_economy_tab.gd")
const BasicCombat = preload("res://vtt/combat_basic_actions.gd")
const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")
const OriginSpellsTab = preload("res://vtt/creature_origin_spells_tab.gd")
var _pending_metamagic_cast: Dictionary = {}
const Metamagic = preload("res://vtt/spell_metamagic.gd")
const ClassFeatures = preload("res://vtt/class_feature_activation.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const DiceBonuses = preload("res://vtt/creature_dice_bonuses.gd")
const FiveToolsText = preload("res://vtt/five_tools_rich_text.gd")
const StructuredTrackers = preload("res://vtt/structured_resource_trackers.gd")
const TrackerTab = preload("res://vtt/creature_trackers_tab.gd")
const FormulaValue = preload("res://vtt/formula_value.gd")
const BonusRules = preload("res://vtt/creature_bonus_rules.gd")
const BonusTab = preload("res://vtt/creature_bonus_tab.gd")
const PendingChoices = preload("res://vtt/creature_pending_choices.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const TraitsTab = preload("res://vtt/creature_traits_tab.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const Skills5e = preload("res://vtt/creature_skills_5etools.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const ProficiencyRules = preload("res://vtt/creature_proficiency_rules.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const FeatsTab = preload("res://vtt/creature_feats_tab.gd")
const DamageDefensesTab = preload("res://vtt/creature_damage_defenses_tab.gd")
const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const DocumentInbox = preload("res://vtt/document_inbox.gd")
const DocumentStore = preload("res://vtt/document_homebrew.gd")
const CreatureLocale = preload("res://vtt/creature_gui_locale.gd")
const CreaturePublicStatus = preload("res://vtt/creature_public_status.gd")
const SheetController = preload("res://vtt/creature_sheet_controller.gd")
const ALIGNMENT_OPTIONS = ["Legale buono","Neutrale buono","Caotico buono","Legale neutrale","Completamente neutrale","Caotico neutrale","Legale malvagio","Neutrale malvagio","Caotico malvagio"]
const LAST_CREATURE_SELECTION_PATH := "user://creature_gui_selection.cfg"

var board_root: Node
var ui_root: CanvasLayer
var _require_miniatures: bool = true
var _archive
var _client: Node
var _records: Array[Dictionary] = []
# Lightweight name index used by initiative snapshots. Rebuilt only when sheets change.
var _owned_name_index: Dictionary = {}
var _selected_id := ""
var _selected_kind := ""
var _last_selected_id := ""
var _last_selected_kind := ""
var _selection_config_path := LAST_CREATURE_SELECTION_PATH
# Hidden editors are rebuilt only when opened, not during every sheet switch.
var _traits_stale := true
var _proficiencies_stale := true
var _feats_stale := true
var _bonuses_stale := true
var _pending_origin_spell_cast: Dictionary = {}
var _origin_spells_stale := true
var _origin_spells_ui: Node
var _trackers_stale := true
var _damage_defenses_stale := true
var _catalog: Array[Dictionary] = []
var _filtered_catalog: Array[Dictionary] = []
var _loading := false

var _panel: PanelContainer
var _status: Label
var _creature_list: VBoxContainer
var _creature_filter: LineEdit
var _creature_empty: Label
var _abilities_grid: GridContainer
var _touch_combat_view: ScrollContainer
var _statistics_columns: BoxContainer
var _touch_layout := false
var _touch_library: Control
var _touch_editor: Control
var _touch_library_view: ScrollContainer
var _touch_section_drawer: PanelContainer
var _touch_section_toggle: Button
var _touch_section_buttons: Array[Button] = []
var _touch_section: OptionButton
signal touch_library_changed(show_library: bool)
var _touch_library_button: Button
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
var _creature_batch_checks: Array[CheckBox] = []
var _creature_batch_ids: Dictionary = {}
var _creature_batch_selection_row: HBoxContainer
var _creature_batch_actions_row: HBoxContainer
var _batch_export_button: Button
var _batch_delete_button: Button
var _batch_export_pending: Array[Dictionary] = []
var _batch_delete_pending: Array[Dictionary] = []
var _batch_delete_dialog: ConfirmationDialog
var _creature_eye_buttons: Array[Button] = []
var _creature_presence_elapsed := 0.0
var _creature_language := "it"
var _creature_language_picker: OptionButton
var _creature_context_menu: PopupMenu
var _automatic_dialog: ConfirmationDialog
var _automatic_hp: CheckBox
var _automatic_class_features: CheckBox
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
var _info_feats_list: VBoxContainer
var _subclass_caption: Label
var _level_caption: Label
var _total_level_display: Label
var _xp: SpinBox
var _initiative_effective: Label
var _ac_effective: Label
var _defense_summary: Label
var _ac_proficiency_warning: Label
var _special_speed_labels: Dictionary = {}
var _long_jump: Label
var _high_jump: Label
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
var _hand_main_picker: OptionButton
var _hand_off_picker: OptionButton
var _hand_options: Dictionary = {}
var _show_offhand_all: CheckButton
var _armor_picker: OptionButton
var _armor_options: Array[Dictionary] = []
var _natural_ac_formula: LineEdit
var _attack_rows: VBoxContainer
var _attack_hit_labels: Dictionary = {}
var _attack_damage_labels: Dictionary = {}
var _attack_damage_source_labels: Dictionary = {}
var _attack_range_labels: Dictionary = {}
var _attack_long_range_labels: Dictionary = {}
var _front: OptionButton
var _party: LineEdit
var _alignment: OptionButton
var _tabs: TabContainer
var _action_economy_ui: Node
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
var _delete_custom_background: Button
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
var _trackers_ui: Node
var _bonuses_ui: Node
var _proficiencies_ui: Node
var _feats_ui: Node
var _damage_defenses_ui: Node
var _editor_section_picker: OptionButton
var _editor_choice_warning: Label
var _origins_overview: VBoxContainer
var _origin_preview_cache: Dictionary = {}
var _origins_scroll: ScrollContainer
var _traits_ui: Node
var _condition_rows: VBoxContainer
var _effect_dialog: AcceptDialog
var _effect_text: RichTextLabel
var _transfer_users: OptionButton
var _transfer_hint: Label
var _export_dialog: FileDialog
var _creature_import_button: Button
var _creature_import_picker: FileDialog
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


func setup(root: Node, host_ui: CanvasLayer = null, require_miniatures: bool = true, allow_remote_catalog: bool = true) -> void:
	board_root = root
	ui_root = host_ui
	if ui_root == null and board_root != null:
		ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		push_error("CreatureArea: UI CanvasLayer non trovato")
		return
	_require_miniatures = require_miniatures
	_creature_language = CreatureLocale.read_locale()
	_restore_last_creature_selection()
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
	_build_batch_delete_dialog()
	_reload()
	_refresh_creature_language()
	_load_bestiary_catalog(allow_remote_catalog and DisplayServer.get_name() != "headless")
	call_deferred("refresh_owned_sheets")


# The selection is a device-local UI preference, independent of campaign saves.
# Persist by stable ID and kind, never by list index or creature name.
func _restore_last_creature_selection() -> void:
	var config := ConfigFile.new()
	if config.load(_selection_config_path) != OK:
		return
	var creature_id := String(config.get_value("selection", "id", "")).strip_edges()
	var kind := String(config.get_value("selection", "kind", ""))
	if creature_id.is_empty() or kind not in ["character", "monster"]:
		return
	_last_selected_id = creature_id
	_last_selected_kind = kind
	_selected_id = creature_id
	_selected_kind = kind


func _remember_creature_selection() -> void:
	if _selected_id.is_empty() or _selected_kind not in ["character", "monster"]:
		return
	if _selected_id == _last_selected_id and _selected_kind == _last_selected_kind:
		return
	var config := ConfigFile.new()
	config.set_value("selection", "id", _selected_id)
	config.set_value("selection", "kind", _selected_kind)
	var error: Error = config.save(_selection_config_path)
	if error != OK:
		push_warning("CreatureArea: impossibile salvare la selezione: " + error_string(error))
		return
	_last_selected_id = _selected_id
	_last_selected_kind = _selected_kind


func _load_bestiary_catalog(fetch_remote: bool) -> void:
	# A warm 5etools cache emits catalog_ready synchronously. Load the local
	# fallback first so the downloaded catalogue is never overwritten.
	_on_catalog_ready(ContentCatalog.home_entries("monsters"))
	if fetch_remote and _client != null:
		_client.call("load_catalog")


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


# Synchronize shared tactical spell state into the owning user's private
# creature sheet. Foreign users can affect a token without gaining access
# to, or mutating, somebody else's private archive.
func sync_linked_token_status(token: Node3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	if String(token.get_meta("creature_owner_id", "")) != Owner.local_id():
		return
	var creature_id: String = String(token.get_meta("creature_id", ""))
	if creature_id.is_empty():
		return
	for owned: Dictionary in _archive.list_owned():
		if String(owned.get("id", "")) != creature_id:
			continue
		var record: Dictionary = owned.duplicate(true)
		_copy_token_spell_status(record, token)
		if record == owned:
			return
		_recalculate_bonus_mirrors(record)
		if _archive.save(record) == OK:
			_update_external_record(record)
		return


func _copy_token_spell_status(record: Dictionary, token: Node3D) -> void:
	var status := {}
	if token.has_method("get_conditions"):
		status["conditions"] = token.call("get_conditions")
	if token.has_method("get_concentrating_spell_id"):
		status["concentrating_spell_id"] = String(token.call("get_concentrating_spell_id"))
	if token.has_method("get_active_spell_ids"):
		status["active_spell_ids"] = token.call("get_active_spell_ids")
	_copy_public_token_status(record, status)

func _copy_public_token_status(record: Dictionary, status: Dictionary) -> void:
	for key: String in ["conditions", "concentrating_spell_id"]:
		if status.has(key):
			record[key] = status[key]
	if not status.has("active_spell_ids"):
		return
	var spell_ids: Array = status.active_spell_ids
	# Preserve benefit-only origins; remove only spells explicitly applied
	# as ongoing effects and subsequently dispelled from the shared token.
	var previous: Array = record.get("proficiency_origins", [])
	var removed_ids: Array[String] = []
	for raw: Variant in previous:
		if not raw is Dictionary:
			continue
		var origin: Dictionary = raw
		var source_id: String = String(origin.get("id", ""))
		if (
			String(origin.get("group", "")) == "spell"
			and bool(origin.get("applied", false))
			and source_id.begins_with("spell:")
			and not (source_id.trim_prefix("spell:") in spell_ids)
		):
			removed_ids.append(source_id)
	for source_id: String in removed_ids:
		ActiveSpells.remove(record, source_id)
	for value: Variant in spell_ids:
		var spell_id: String = String(value)
		if not spell_id.is_empty():
			ActiveSpells.apply(record, spell_id)


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
		# A polymorphed token has a temporary size. Do not overwrite the
		# creature's base dimensions, which are needed when restoring it.
		var base_id := String(record.get("default_miniature_id", ""))
		var current_id := String(record.get("current_miniature_id", ""))
		if base_id.is_empty() or current_id == base_id:
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


# Claim an unlinked token already on the desktop board. Preserve its
# position and stable synchronization ID; the sheet owns all public identity.
func claim_free_scene_token(token: CharacterBody3D, creature_id: String) -> bool:
	if (token == null or not is_instance_valid(token)
		or not board_root.has_method("is_free_scene_token")
		or not bool(board_root.call("is_free_scene_token", token))):
		return false
	var record: Dictionary = {}
	for owned: Dictionary in _archive.list_owned():
		if String(owned.get("id", "")) == creature_id and Owner.is_owner(owned):
			record = owned
			break
	if record.is_empty() or find_linked_token_for_creature(creature_id) != null:
		return false
	var sync: Node = board_root.get("board_sync") as Node
	if sync == null:
		return false
	var sync_id: String = String(sync.call("get_sync_id_for_node", token))
	if sync_id.is_empty():
		return false
	var undo: Dictionary = board_root.call("begin_undo_transaction")
	var previous_appearance: Dictionary = token.call("get_appearance_state")
	var previous_transform: Transform3D = token.global_transform
	var bottom: float = token.global_position.y - float(token.get("token_height_cells")) * float(token.get("cell_size")) * 0.5
	# A missing/delayed miniature must not claim the target prematurely.
	if not bool(board_root.call("apply_creature_sheet_appearance", token, record, false)):
		return false
	record["linked_token_sync_id"] = sync_id
	record["linked_token_name"] = String(record.get("name", ""))
	if _archive.save(record) != OK:
		token.call("apply_appearance_state", previous_appearance)
		token.global_transform = previous_transform
		_set_status("Impossibile salvare l'associazione del token.")
		return false
	for field: String in ["player_character_id", "player_character_name",
		"master_creature_id", "master_creature_name", "master_creature_side"]:
		if token.has_meta(field):
			token.remove_meta(field)
	token.set_meta("creature_id", creature_id)
	token.set_meta("creature_owner_id", Owner.local_id())
	token.set_meta("default_miniature_id", String(record.get("default_miniature_id", "")))
	if String(record.get("kind", "")) == "character":
		token.set_meta("player_character_id", creature_id)
		token.set_meta("player_character_name", String(record.get("name", "")))
	else:
		token.set_meta("master_creature_id", creature_id)
		token.set_meta("master_creature_name", String(record.get("name", "")))
		token.set_meta("master_creature_side", String(record.get("side", "ally")))
	board_root.call("apply_creature_sheet_properties", token, record)
	token.global_position.y = bottom + float(token.get("token_height_cells")) * float(token.get("cell_size")) * 0.5
	_sync_token_health(record)
	board_root.call("commit_undo_transaction", undo)
	_replace_current_record(record)
	_refresh_creature_eye_buttons()
	_set_status("Token libero associato alla scheda; nome, condizioni, aspetto e taglia aggiornati.")
	return true


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
	_refresh_creature_language()
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


func _input(event: InputEvent) -> void:
	if (
		_panel == null or not _panel.visible
		or not event is InputEventKey
		or not event.pressed or event.echo or not event.ctrl_pressed
	):
		return
	var redo: bool = (
		event.keycode == KEY_Y
		or (event.keycode == KEY_Z and event.shift_pressed)
	)
	if event.keycode != KEY_Z and event.keycode != KEY_Y:
		return
	# Complete GUI input dispatch before reloading widgets and losing focus.
	get_viewport().set_input_as_handled()
	call_deferred("_apply_creature_history", redo)


func _apply_creature_history(redo: bool) -> void:
	# Native TextEdit undo would diverge from the saved sheet: use the
	# persisted creature revisions even when a field currently has focus.
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var result: Error = (
		_archive.redo_owned(record) if redo else _archive.undo_owned(record)
	)
	if result == OK:
		_reload()
		_set_status("Modifica ripristinata." if not redo else "Modifica ripetuta.")
	elif result != ERR_DOES_NOT_EXIST:
		_set_status("Cronologia non disponibile: " + error_string(result))


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not (
			_creature_import_picker.visible
			or _import_dialog.visible
			or _miniature_dialog.visible
			or _transfer_dialog.visible
			or _delete_dialog.visible
		):
			hide_panel()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	preload("res://vtt/scrollable_caption.gd").install(self)
	_panel = PanelContainer.new()
	_panel.name = "CreatureSheet"
	preload("res://vtt/creature_sheet_style.gd").install(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The visible sheet border should occupy the available desktop surface:
	# use internal sheet padding instead of leaving dark unusable gutters
	# outside the panel. Preserve a slim clearance for the game top bar.
	_panel.offset_left = 4
	_panel.offset_top = 44
	_panel.offset_right = -4
	_panel.offset_bottom = -4
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure UI sheets outrank any remaining tactical screen-space badges.
	_panel.z_index = 30
	_panel.hide()
	ui_root.add_child(_panel)

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
	_creature_import_button = Button.new()
	_creature_import_button.name = "ImportCreatures"
	_creature_import_button.text = "Importa creature…"
	_creature_import_button.tooltip_text = "Carica uno o più file JSON di creature esportate da VTT, anche da versioni precedenti."
	_creature_import_button.pressed.connect(_show_creature_import_picker)
	header.add_child(_creature_import_button)
	_creature_import_picker = FileDialog.new()
	_creature_import_picker.title = "Importa creature da JSON"
	_creature_import_picker.access = FileDialog.ACCESS_FILESYSTEM
	_creature_import_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_creature_import_picker.use_native_dialog = OS.has_feature("mobile")
	_creature_import_picker.add_filter("*.json", "Creature VTT")
	_creature_import_picker.files_selected.connect(_import_export_files)
	ui_root.add_child(_creature_import_picker)
	var language_label := Label.new()
	language_label.text = "Lingua scheda"
	header.add_child(language_label)
	_creature_language_picker = OptionButton.new()
	_creature_language_picker.tooltip_text = "Cambia solo la lingua della GUI delle schede creatura"
	_creature_language_picker.add_item("Italiano", 0)
	_creature_language_picker.add_item("English", 1)
	_creature_language_picker.select(1 if _creature_language == "en" else 0)
	_creature_language_picker.item_selected.connect(_on_creature_language_selected)
	header.add_child(_creature_language_picker)
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
	_creature_batch_selection_row = HBoxContainer.new()
	left.add_child(_creature_batch_selection_row)
	_creature_batch_selection_row.hide()
	var all_button := Button.new()
	all_button.text = "Tutte"
	all_button.pressed.connect(_mark_visible_creatures.bind(true))
	_creature_batch_selection_row.add_child(all_button)
	var none_button := Button.new()
	none_button.text = "Nessuna"
	none_button.pressed.connect(_mark_visible_creatures.bind(false))
	_creature_batch_selection_row.add_child(none_button)
	_creature_batch_actions_row = HBoxContainer.new()
	left.add_child(_creature_batch_actions_row)
	_creature_batch_actions_row.hide()
	_batch_export_button = Button.new()
	_batch_export_button.text = "Esporta selezione"
	_batch_export_button.disabled = true
	_batch_export_button.pressed.connect(_export_selected_creatures)
	_creature_batch_actions_row.add_child(_batch_export_button)
	_batch_delete_button = Button.new()
	_batch_delete_button.text = "Elimina selezione"
	_batch_delete_button.disabled = true
	_batch_delete_button.pressed.connect(_confirm_batch_delete)
	_creature_batch_actions_row.add_child(_batch_delete_button)
	_creature_empty = Label.new()
	_creature_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_creature_empty.add_theme_font_size_override("font_size", 13)
	_creature_empty.hide()
	left.add_child(_creature_empty)
	_creature_list_scroll = ScrollContainer.new()
	_creature_list_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(_creature_list_scroll)
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
	_creature_context_menu.add_separator("Scheda e controllo")
	_creature_context_menu.add_item("Ricalcoli manuali…", 2)
	_creature_context_menu.set_item_tooltip(_creature_context_menu.get_item_index(2), "Solo punti ferita e ripristino dei privilegi di classe in caso di anomalie.")
	_creature_context_menu.add_item("Cedi controllo…", 4)
	_creature_context_menu.set_item_tooltip(_creature_context_menu.get_item_index(4), "Trasferisci questa scheda e i suoi dati privati al destinatario scelto.")
	_creature_context_menu.add_separator("Eliminazione")
	_creature_context_menu.add_item("Elimina creatura…", 3)
	_creature_context_menu.set_item_tooltip(_creature_context_menu.get_item_index(3), "Elimina la scheda dopo conferma.")
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
	_catalog_list.mouse_force_pass_scroll_events = false
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
	_tabs.resized.connect(_fit_sheet_tabs)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.add_child(_tabs)
	var form := _add_sheet_tab(_tabs, "Info")
	var statistics_tab := _add_sheet_tab(_tabs, "Statistiche")
	var origins_tab := _add_sheet_tab(_tabs, "Modifica personaggio")
	_origins_scroll = origins_tab.get_parent().get_parent() as ScrollContainer
	# Keep the detailed editors exclusive without recreating them on each switch.
	# This preserves their existing interactions and deferred loading behavior.
	var editor_select_row := HBoxContainer.new()
	editor_select_row.add_theme_constant_override("separation", 8)
	origins_tab.add_child(editor_select_row)
	_origins_overview = VBoxContainer.new()
	origins_tab.add_child(_origins_overview)
	_origins_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origins_overview.custom_minimum_size.x = 420
	_add_label(editor_select_row, "Visualizza e modifica")
	_editor_choice_warning = Label.new()
	_editor_choice_warning.text = "⚠"
	_editor_choice_warning.visible = false
	_editor_choice_warning.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor_choice_warning.mouse_default_cursor_shape = Control.CURSOR_HELP
	_editor_choice_warning.add_theme_color_override("font_color", Color(1.0, 0.78, 0.30))
	_editor_choice_warning.tooltip_text = "Sono presenti scelte da completare."
	editor_select_row.add_child(_editor_choice_warning)
	_editor_section_picker = OptionButton.new()
	_editor_section_picker.fit_to_longest_item = false
	_editor_section_picker.custom_minimum_size = Vector2(285, 30)
	_editor_section_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_section_picker.tooltip_text = "Scegli una sezione da visualizzare o modificare"
	for section_name: String in ["Panoramica", "Competenze", "Talenti", "Bonus", "Tracker", "Resistenze, immunità e vulnerabilità", "Incantesimi da origini"]:
		_editor_section_picker.add_item(section_name)
	_editor_section_picker.select(0)
	_editor_section_picker.item_selected.connect(_select_details_editor)
	editor_select_row.add_child(_editor_section_picker)
	_proficiencies_ui = ProficiencyTab.new()
	_proficiencies_ui.hide()
	origins_tab.add_child(_proficiencies_ui)
	_proficiencies_ui.call("setup", Callable(self, "_on_proficiencies_updated"))
	_feats_ui = FeatsTab.new()
	_feats_ui.hide()
	origins_tab.add_child(_feats_ui)
	_feats_ui.call("setup", Callable(self, "_on_feats_updated"))
	_bonuses_ui = BonusTab.new()
	_bonuses_ui.hide()
	origins_tab.add_child(_bonuses_ui)
	_bonuses_ui.call("setup", Callable(self, "_on_bonuses_updated"))
	_trackers_ui = TrackerTab.new()
	_trackers_ui.hide()
	origins_tab.add_child(_trackers_ui)
	_trackers_ui.call("setup", Callable(self, "_on_trackers_updated"))
	_damage_defenses_ui = DamageDefensesTab.new()
	_damage_defenses_ui.hide()
	origins_tab.add_child(_damage_defenses_ui)
	_damage_defenses_ui.call("setup", Callable(self, "_on_damage_defenses_updated"))
	_origin_spells_ui = OriginSpellsTab.new()
	_origin_spells_ui.hide()
	origins_tab.add_child(_origin_spells_ui)
	_origin_spells_ui.call("setup", Callable(self, "_on_origin_spells_updated"))
	# Share the editor divider and give combat the width its contents need.
	# Local scrolling remains a fallback when neither column can fit.
	_statistics_columns = HBoxContainer.new()
	_statistics_columns.add_theme_constant_override("separation", 9)
	_statistics_columns.resized.connect(_update_statistics_widths)
	statistics_tab.get_parent().get_parent().resized.connect(func() -> void: call_deferred("_update_statistics_widths"))
	_statistics_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	statistics_tab.add_child(_statistics_columns)
	var skills_view := ScrollContainer.new()
	skills_view.mouse_force_pass_scroll_events = false
	skills_view.name = "SkillsColumnView"
	skills_view.size_flags_horizontal = Control.SIZE_FILL
	skills_view.custom_minimum_size.x = 0
	skills_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	skills_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skills_view.follow_focus = true
	_statistics_columns.add_child(skills_view)
	var skills_column := VBoxContainer.new()
	skills_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_view.add_child(skills_column)
	var combat_view := ScrollContainer.new()
	combat_view.mouse_force_pass_scroll_events = false
	combat_view.name = "CombatColumnView"
	combat_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combat_view.custom_minimum_size.x = 0
	combat_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	combat_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	combat_view.follow_focus = true
	_statistics_columns.add_child(combat_view)
	var combat_column := VBoxContainer.new()
	combat_column.add_theme_constant_override("separation", 5)
	combat_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combat_view.add_child(combat_column)
	var traits_tab := _add_sheet_tab(_tabs, "Tratti")
	var conditions_tab := _add_sheet_tab(_tabs, "Condizioni")
	var spellcasting_tab := _add_sheet_tab(_tabs, "Poteri")
	_spellcasting_ui = SpellcastingTab.new()
	_spellcasting_ui.class_feature_requested.connect(_on_class_feature_requested)
	spellcasting_tab.add_child(_spellcasting_ui)
	_spellcasting_ui.call(
		"setup",
		Callable(self, "_on_spellcasting_updated"),
		Callable(self, "_set_status"),
		Callable(self, "_on_spellcasting_cast_requested"),
		Callable(self, "_on_formula_bonus_requested"),
		Callable(self, "_edit_origin_spell_popup")
	)
	var actions_tab := _add_sheet_tab(_tabs, "Cosa posso fare?")
	_action_economy_ui = ActionEconomyTab.new()
	_action_economy_ui.class_feature_requested.connect(_on_class_feature_requested)
	actions_tab.add_child(_action_economy_ui)
	_action_economy_ui.skill_requested.connect(_on_formula_roll_requested)
	_action_economy_ui.attack_requested.connect(_roll_attack_from_sheet)
	_action_economy_ui.basic_action_requested.connect(_on_basic_action_requested)
	_action_economy_ui.tracker_change_requested.connect(_on_action_tracker_change)
	_action_economy_ui.cast_spell_requested.connect(_on_action_cast_requested)
	_action_economy_ui.class_spell_requested.connect(func(spell_id: String, class_id: String) -> void: _on_action_cast_requested(spell_id, "", class_id))
	_action_economy_ui.open_spellbook_requested.connect(func() -> void: _show_sheet_tab("Poteri"))
	var inventory_tab := _add_sheet_tab(_tabs, "Inventario")
	_inventory_ui = InventoryTab.new()
	inventory_tab.add_child(_inventory_ui)
	_inventory_ui.call(
		"setup", Callable(self, "_on_inventory_updated"), Callable(self, "_set_status"),
		Callable(self, "_on_documents_updated"),
		Callable(self, "_send_document_to_peer"), Callable(self, "_get_document_peers"),
		Callable(self, "_send_item_to_peer")
	)
	# The same stable tab order is used by the desktop TabContainer and touch drawer.
	var ordered_tabs := ["Info", "Statistiche", "Cosa posso fare?", "Poteri", "Inventario", "Tratti", "Condizioni", "Modifica personaggio"]
	for index: int in range(ordered_tabs.size()):
		for candidate_index: int in range(_tabs.get_tab_count()):
			var page: Control = _tabs.get_tab_control(candidate_index)
			if page.name == ordered_tabs[index]:
				_tabs.move_child(page, index)
				break
	for editor: Node in [_origins_overview, _proficiencies_ui, _feats_ui, _bonuses_ui, _trackers_ui, _damage_defenses_ui, _origin_spells_ui]:
		editor.set_meta("origin_navigate", Callable(self, "_open_origin_trait"))
		editor.set_meta("origin_preview", Callable(self, "_origin_summary"))
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
	_party.placeholder_text = "Gruppo predefinito"
	_party.text_changed.connect(func(_text: String) -> void: _save())
	name_row.add_child(_party)
	var alignment_row := HBoxContainer.new()
	alignment_row.add_theme_constant_override("separation", 8)
	identity_box.add_child(alignment_row)
	_add_label(alignment_row, "Allineamento")
	_alignment = OptionButton.new()
	_alignment.custom_minimum_size.x = 210
	_alignment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option_label: String in ALIGNMENT_OPTIONS:
		_alignment.add_item(option_label)
	_alignment.select(4)
	_alignment.item_selected.connect(func(_index: int) -> void: _save())
	alignment_row.add_child(_alignment)
	var physics_box := _info_panel(form, "FISICO")
	physics_box.add_theme_constant_override("separation", 7)
	# A field is always a label + control; never wrap those independently.
	var physics_fields := HFlowContainer.new()
	physics_fields.name = "PhysicsFields"
	physics_fields.add_theme_constant_override("h_separation", 14)
	physics_fields.add_theme_constant_override("v_separation", 8)
	physics_box.add_child(physics_fields)
	var miniature_group := VBoxContainer.new()
	miniature_group.name = "PhysicsMiniatures"
	miniature_group.add_theme_constant_override("separation", 4)
	physics_box.add_child(miniature_group)
	var miniature_heading := Label.new()
	miniature_heading.text = "MINIATURE"
	miniature_heading.add_theme_font_size_override("font_size", 13)
	miniature_heading.add_theme_color_override("font_color", Color(0.74, 0.86, 0.94))
	miniature_group.add_child(miniature_heading)
	var miniature_flow := HFlowContainer.new()
	miniature_flow.name = "PhysicsMiniatureFlow"
	miniature_flow.add_theme_constant_override("h_separation", 14)
	miniature_flow.add_theme_constant_override("v_separation", 5)
	miniature_group.add_child(miniature_flow)

	var health_panel := PanelContainer.new()
	health_panel.name = "TouchHitPoints"
	var health_style := preload("res://vtt/creature_sheet_style.gd").section_style()
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
	health.name = "TouchHealthLine"
	health.add_theme_constant_override("h_separation", 3)
	health.add_theme_constant_override("v_separation", 3)
	health_content.add_child(health)
	var damage := Button.new()
	damage.text = "−"
	damage.tooltip_text = "Sottrai PF: inserisci un valore o tira un dado"
	damage.custom_minimum_size.x = 30
	damage.pressed.connect(_open_hp_delta.bind(-1))
	_hp = _spin(health, -999, 99999)
	_hp.tooltip_text = "Punti ferita attuali"
	_hp.custom_minimum_size = Vector2(59, 34)
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_label(health, "/")
	_max_hp_effective = Label.new()
	_max_hp_effective.tooltip_text = "PF massimi effettivi"
	health.add_child(_max_hp_effective)
	_max_hp = _spin(health, 0, 99999)
	_max_hp.custom_minimum_size = Vector2(59, 34)
	_max_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_max_hp.tooltip_text = "PF massimi base, prima dei bonus"
	_install_formula("hp", _max_hp_effective, [_max_hp], ["Base"])
	# Temporary HP are a separate row, with the caption before the field.
	var health_actions := HBoxContainer.new()
	health.add_child(health_actions)
	var temp_row := HBoxContainer.new()
	temp_row.add_theme_constant_override("separation", 7)
	health_content.add_child(temp_row)
	_add_label(temp_row, "TEMP")
	_temp_hp = _spin(temp_row, 0, 99999)
	_temp_hp.tooltip_text = "Punti ferita temporanei: assorbono i danni prima delle altre forme."
	_temp_hp.custom_minimum_size.x = 60
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
	form_hp_row.name = "TouchFormHpLine"
	form_hp_row.add_theme_constant_override("separation", 6)
	health_content.add_child(form_hp_row)
	_add_label(form_hp_row, "Seconda forma")
	_second_form_hp = SpinBox.new()
	_second_form_hp.min_value = 0
	_second_form_hp.max_value = 99999
	_second_form_hp.step = 1
	_second_form_hp.rounded = true
	_second_form_hp.custom_minimum_size = Vector2(60, 30)
	_second_form_hp.value_changed.connect(_on_form_hp_changed)
	form_hp_row.add_child(_second_form_hp)
	_add_label(form_hp_row, "/")
	_second_form_max_hp = _spin(form_hp_row, 0, 99999)
	_second_form_max_hp.custom_minimum_size.x = 60
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
	# CA and initiative share a dedicated defense panel.
	var defense_panel := PanelContainer.new()
	defense_panel.name = "TouchDefense"
	var defense_style := health_style.duplicate() as StyleBoxFlat
	defense_style.draw_center = true
	defense_style.border_color = Color("c99750")
	defense_panel.add_theme_stylebox_override("panel", defense_style)
	combat_column.add_child(defense_panel)
	var defense_content := VBoxContainer.new()
	defense_content.add_theme_constant_override("separation", 6)
	defense_panel.add_child(defense_content)
	var defense_heading := Label.new()
	defense_heading.text = "CA E INIZIATIVA"
	defense_heading.add_theme_font_size_override("font_size", 15)
	defense_heading.add_theme_color_override("font_color", Color(0.75, 0.89, 0.98))
	defense_content.add_child(defense_heading)
	preload("res://vtt/creature_sheet_style.gd").heading(defense_heading, "shield")
	# A single non-wrapping row keeps initiative inside the AC panel.
	var defense_flow := HBoxContainer.new()
	defense_flow.name = "TouchDefenseLine"
	defense_flow.add_theme_constant_override("separation", 5)
	defense_content.add_child(defense_flow)
	_defense_summary = Label.new()
	_defense_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_defense_summary.add_theme_font_size_override("font_size", 12)
	defense_content.add_child(_defense_summary)
	var temp_health := HBoxContainer.new()
	temp_health.add_theme_constant_override("separation", 3)
	defense_flow.add_child(temp_health)
	_add_label(temp_health, "CA")
	_ac_effective = Label.new()
	_ac_effective.custom_minimum_size.x = 28
	temp_health.add_child(_ac_effective)
	_ac = _spin(temp_health, 0, 99)
	_ac.custom_minimum_size = Vector2(62, 36)
	_ac.tooltip_text = "Base precedente (compatibilità)"
	_ac.hide()
	_armor_picker = OptionButton.new()
	_armor_picker.custom_minimum_size.x = 82
	_armor_picker.tooltip_text = "Armatura indossata; scegli Naturale per utilizzare la formula senza armatura."
	_armor_picker.item_selected.connect(_on_armor_selected)
	temp_health.add_child(_armor_picker)
	_natural_ac_formula = LineEdit.new()
	_natural_ac_formula.custom_minimum_size.x = 100
	_natural_ac_formula.placeholder_text = "10 + dex_mod"
	_natural_ac_formula.tooltip_text = "Formula per la CA senza armatura: per esempio 10 + dex_mod, 13 + dex_mod o 16. Le variabili seguono le formule dei bonus."
	_natural_ac_formula.text_submitted.connect(func(_value: String) -> void: _save())
	_natural_ac_formula.focus_exited.connect(func() -> void: _save())
	var natural_row := HBoxContainer.new()
	natural_row.name = "TouchAcFormula"
	natural_row.add_theme_constant_override("separation", 4)
	defense_content.add_child(natural_row)
	_add_label(natural_row, "CA naturale · formula")
	natural_row.add_child(_natural_ac_formula)
	_install_formula("ac", _ac_effective, [_ac], ["Base"])
	_ac.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ac_proficiency_warning = Label.new()
	_ac_proficiency_warning.text = "⚠"
	_ac_proficiency_warning.mouse_filter = Control.MOUSE_FILTER_STOP
	_ac_proficiency_warning.mouse_default_cursor_shape = Control.CURSOR_HELP
	_ac_proficiency_warning.tooltip_text = "Equipaggiamento senza competenza: passa qui per vedere le penalità."
	_ac_proficiency_warning.visible = false
	_ac_proficiency_warning.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
	temp_health.add_child(_ac_proficiency_warning)
	defense_flow.add_child(VSeparator.new())
	var initiative_row := HBoxContainer.new()
	initiative_row.name = "TouchInitiativeLine"
	initiative_row.add_theme_constant_override("separation", 3)
	defense_flow.add_child(initiative_row)
	_add_label(initiative_row, "Bonus iniziativa")
	_initiative_effective = Label.new()
	_initiative_effective.custom_minimum_size.x = 32
	initiative_row.add_child(_initiative_effective)
	_install_formula("initiative", _initiative_effective, [], [])
	# Keep speeds and jumps side by side whenever both fit, with compact
	# speed cells and automatic wrapping on smaller sheets.
	var movement_panel := PanelContainer.new()
	movement_panel.name = "PhysicsMovement"
	var movement_style := health_style.duplicate() as StyleBoxFlat
	movement_style.draw_center = false
	movement_style.set_border_width_all(0)
	movement_style.set_content_margin_all(0)
	movement_panel.add_theme_stylebox_override("panel", movement_style)
	physics_box.add_child(movement_panel)
	var movement_box := VBoxContainer.new()
	movement_box.add_theme_constant_override("separation", 5)
	movement_panel.add_child(movement_box)
	var movement_heading := Label.new()
	movement_heading.text = "MOVIMENTO"
	movement_heading.add_theme_font_size_override("font_size", 13)
	movement_heading.add_theme_color_override("font_color", Color(0.74, 0.90, 0.77))
	movement_box.add_child(movement_heading)
	var movement_flow := HFlowContainer.new()
	movement_flow.name = "PhysicsMovementFlow"
	movement_flow.add_theme_constant_override("h_separation", 16)
	movement_flow.add_theme_constant_override("v_separation", 6)
	movement_box.add_child(movement_flow)
	var speeds_group := VBoxContainer.new()
	speeds_group.name = "PhysicsSpeeds"
	speeds_group.add_theme_constant_override("separation", 3)
	movement_flow.add_child(speeds_group)
	# Default to one compact row; resize adapts the columns to the sheet.
	var speed_grid := GridContainer.new()
	speed_grid.name = "PhysicsSpeedGrid"
	speed_grid.columns = 5
	speed_grid.add_theme_constant_override("h_separation", 8)
	speed_grid.add_theme_constant_override("v_separation", 4)
	speeds_group.add_child(speed_grid)
	_special_speed_labels.clear()
	for mode: String in ["walk", "climb", "swim", "fly", "burrow"]:
		var speed_cell := VBoxContainer.new()
		speed_cell.custom_minimum_size.x = 73
		speed_cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		speed_cell.add_theme_constant_override("separation", 2)
		speed_grid.add_child(speed_cell)
		var speed_name: String = {"walk": "Camminata", "climb": "Scalata",
			"swim": "Nuoto", "fly": "Volo", "burrow": "Scavo"}[mode]
		var speed_caption := Label.new()
		speed_caption.text = speed_name
		speed_caption.tooltip_text = speed_name + " (ft)"
		speed_caption.clip_text = true
		speed_caption.add_theme_font_size_override("font_size", 12)
		speed_cell.add_child(speed_caption)
		var speed_value_row := HBoxContainer.new()
		speed_value_row.custom_minimum_size.y = 29
		speed_cell.add_child(speed_value_row)
		var speed_label := Label.new()
		speed_label.custom_minimum_size.x = 40
		speed_value_row.add_child(speed_label)
		if mode == "walk":
			_speed_effective = speed_label
			_speed = SpinBox.new()
			_speed.min_value = 0
			_speed.max_value = 999
			_speed.step = 1
			_speed.update_on_text_changed = true
			_speed.custom_minimum_size = Vector2(66, 30)
			_speed.value_changed.connect(_on_speed_changed)
			speed_cell.add_child(_speed)
			_speed.tooltip_text = "Velocità base dalla razza/sottorazza; modificabile solo per i mostri"
			_install_formula("speed", _speed_effective, [_speed], ["Base"])
			_speed.value_changed.connect(func(_value: float) -> void: _update_speed_display())
		else:
			_special_speed_labels[mode] = speed_label
			_install_formula("speed:" + mode, speed_label, [], [])
	var jumps_group := VBoxContainer.new()
	jumps_group.name = "PhysicsJumps"
	jumps_group.add_theme_constant_override("separation", 4)
	movement_flow.add_child(jumps_group)
	var jumps_heading := Label.new()
	jumps_heading.text = "SALTI · DISTANZE MASSIME"
	jumps_heading.add_theme_font_size_override("font_size", 13)
	jumps_heading.add_theme_color_override("font_color", Color(0.77, 0.86, 0.94))
	jumps_group.add_child(jumps_heading)
	var jumps := HFlowContainer.new()
	jumps.add_theme_constant_override("h_separation", 12)
	jumps.add_theme_constant_override("v_separation", 3)
	jumps_group.add_child(jumps)
	_long_jump = Label.new()
	_long_jump.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_long_jump.custom_minimum_size.x = 210
	_long_jump.add_theme_font_size_override("font_size", 12)
	jumps.add_child(_long_jump)
	_high_jump = Label.new()
	_high_jump.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_high_jump.custom_minimum_size.x = 210
	_high_jump.add_theme_font_size_override("font_size", 12)
	jumps.add_child(_high_jump)
	# Explicit group widths keep nested HFlowContainers from collapsing into
	# single columns; recompute on resize so both groups can wrap responsively.
	physics_box.resized.connect(_layout_physics_movement.bind(physics_box, speeds_group, jumps_group))
	call_deferred("_layout_physics_movement", physics_box, speeds_group, jumps_group)
	_ac.value_changed.connect(func(_value: float) -> void: _update_defense_display())

	var abilities_panel := PanelContainer.new()
	var abilities_style := health_style.duplicate() as StyleBoxFlat
	abilities_style.draw_center = true
	abilities_style.border_color = Color("c99750")
	abilities_panel.add_theme_stylebox_override("panel", abilities_style)
	_abilities_grid = GridContainer.new()
	var abilities_row := _abilities_grid
	# Use separate cells for values and proficiency icons so headers and
	# numeric readouts stay aligned even when an inline editor opens.
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
		column_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if ability_column_title != "Car." else HORIZONTAL_ALIGNMENT_LEFT
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
		scores_row.alignment = BoxContainer.ALIGNMENT_CENTER
		abilities_row.add_child(scores_row)
		var spin := _spin(scores_row, 1, 30)
		spin.custom_minimum_size.x = 48
		spin.tooltip_text = "Punteggio base"
		_ability_spins[ability] = spin
		var total_score := Label.new()
		total_score.custom_minimum_size.x = 44
		total_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scores_row.add_child(total_score)
		_ability_total_labels[ability] = total_score
		_install_formula("ability:" + ability, total_score, [spin], ["Base"])
		var modifier := Label.new()
		modifier.custom_minimum_size.x = 44
		modifier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modifier.tooltip_text = "Modificatore calcolato dal punteggio e dal bonus"
		abilities_row.add_child(modifier)
		_ability_modifier_labels[ability] = modifier
		_install_formula("ability_mod:" + ability, modifier, [], [])
		_formula_values["ability_mod:" + ability].alignment = BoxContainer.ALIGNMENT_CENTER
		var saving_throw := Label.new()
		saving_throw.text = "+0"
		saving_throw.tooltip_text = "Tiro salvezza: modificatore caratteristica + competenza, se posseduta"
		# Keep proficiency icon and numeric formula in independent, aligned cells.
		var save_cell := HBoxContainer.new()
		save_cell.add_theme_constant_override("separation", 3)
		save_cell.alignment = BoxContainer.ALIGNMENT_CENTER
		abilities_row.add_child(save_cell)
		var save_icon := Label.new()
		save_icon.custom_minimum_size.x = 28
		save_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_saving_throw_icons[ability] = save_icon
		saving_throw.add_theme_font_size_override("font_size", 17)
		saving_throw.custom_minimum_size.x = 44
		saving_throw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_cell.add_child(saving_throw)
		save_cell.add_child(save_icon)
		_saving_throw_labels[ability] = saving_throw
		_install_formula("save:" + ability, saving_throw, [], [])
		spin.value_changed.connect(_on_ability_value_changed.bind(ability))

	# Compact quick-statistics panel immediately below characteristics.
	var quick_box := _info_panel(skills_column, "RIEPILOGO")
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
	var skills_section := _info_panel(skills_column, "ABILITÀ")
	var skills_header := VBoxContainer.new()
	skills_header.add_theme_constant_override("separation", 1)
	skills_section.add_child(skills_header)
	var skills_legend := Label.new()
	skills_legend.text = "🎓 Competenza  ·  🎓🎓 Maestria"
	skills_legend.add_theme_font_size_override("font_size", 11)
	skills_legend.add_theme_color_override("font_color", Color(0.77, 0.84, 0.90))
	skills_header.add_child(skills_legend)
	var skills_divider := HSeparator.new()
	skills_section.add_child(skills_divider)
	_skills_panel = VBoxContainer.new()
	_skills_panel.add_theme_constant_override("separation", 3)
	skills_section.add_child(_skills_panel)
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
	preference_row.add_theme_constant_override("separation", 4)
	combat_column.add_child(preference_row)
	_add_label(preference_row, "Caratteristica attacchi")
	_attack_ability = OptionButton.new()
	_attack_ability.add_item("Forza")
	_attack_ability.add_item("Destrezza")
	_attack_ability.tooltip_text = "Preferenza per armi Finesse: le armi da mischia normali usano Forza, quelle a distanza Destrezza. I valori del bestiario includono la competenza."
	_attack_ability.item_selected.connect(_on_attack_ability_changed)
	preference_row.add_child(_attack_ability)
	# Both weapon selectors have one fixed row. The finesse filter is
	# inline with the offhand selector, not on a separate row.
	var hand_bar := GridContainer.new()
	hand_bar.columns = 2
	hand_bar.add_theme_constant_override("h_separation", 4)
	hand_bar.add_theme_constant_override("v_separation", 5)
	combat_column.add_child(hand_bar)
	combat_column.move_child(hand_bar, attack_header.get_index())
	_add_label(hand_bar, "Mano principale")
	_hand_main_picker = OptionButton.new()
	_hand_main_picker.custom_minimum_size.x = 112
	_hand_main_picker.clip_text = true
	_hand_main_picker.item_selected.connect(_on_hand_selected.bind("main"))
	hand_bar.add_child(_hand_main_picker)
	_add_label(hand_bar, "Mano secondaria")
	var offhand_row := HBoxContainer.new()
	offhand_row.add_theme_constant_override("separation", 4)
	hand_bar.add_child(offhand_row)
	_hand_off_picker = OptionButton.new()
	_hand_off_picker.custom_minimum_size.x = 112
	_hand_off_picker.clip_text = true
	_hand_off_picker.item_selected.connect(_on_hand_selected.bind("off"))
	offhand_row.add_child(_hand_off_picker)
	_show_offhand_all = CheckButton.new()
	_show_offhand_all.text = "Solo armi accurate"
	_show_offhand_all.tooltip_text = "Filtra la lista della mano secondaria alle armi con proprietà Accurata (Finesse). Non è una regola per l'attacco con azione bonus."
	_show_offhand_all.button_pressed = true
	_show_offhand_all.toggled.connect(func(_enabled: bool) -> void:
		_refresh_equipment_pickers(_current())
	)
	offhand_row.add_child(_show_offhand_all)
	_attack_rows = VBoxContainer.new()
	_attack_rows.add_theme_constant_override("separation", 5)
	combat_column.add_child(_attack_rows)
	_attacks_description = RichTextLabel.new()
	_attacks_description.set_meta("creature_gui_text", true)
	_attacks_description.custom_minimum_size.y = 55
	_attacks_description.fit_content = false
	_attacks_description.scroll_active = false
	_attacks_description.selection_enabled = true
	FiveToolsText.style(_attacks_description)
	_attacks_description.scroll_active = false
	combat_column.add_child(_attacks_description)

	var species_field := _physics_field(physics_fields, "Razza / Specie", 216)
	_species = _reference_option(species_field, RaceRules.base_races(), true, false, "races")
	_species.custom_minimum_size.x = 216
	_species.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_species.item_selected.connect(func(_index: int) -> void: _on_species_changed())
	var subrace_field := _physics_field(physics_fields, "Sottorazza", 180)
	_subrace_caption = subrace_field.get_child(0) as Label
	_subrace_choice = _reference_option(subrace_field, [], true, false, "races")
	_subrace_choice.custom_minimum_size.x = 180
	_subrace_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subrace_choice.tooltip_text = "Solo le sottorazze della razza selezionata, in base a raceName e raceSource."
	_subrace_choice.item_selected.connect(func(_index: int) -> void: _on_subrace_changed())
	var challenge_field := _physics_field(physics_fields, "GS", 76)
	_challenge_caption = challenge_field.get_child(0) as Label
	_challenge_rating = LineEdit.new()
	_challenge_rating.custom_minimum_size.x = 76
	_challenge_rating.tooltip_text = "Grado sfida del bestiario, anche frazionario (es. 1/4). Non è un livello di classe."
	_challenge_rating.text_submitted.connect(func(_text: String) -> void: _save())
	_challenge_rating.text_changed.connect(func(_text: String) -> void: _refresh_xp_minimum())
	_challenge_rating.focus_exited.connect(_save)
	challenge_field.add_child(_challenge_rating)
	var type_field := _physics_field(physics_fields, "Tipo", 126)
	_creature_type_display = Label.new()
	_creature_type_display.custom_minimum_size = Vector2(126, 36)
	_creature_type_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_creature_type_display.add_theme_color_override("font_color", Color(0.81, 0.89, 0.94))
	type_field.add_child(_creature_type_display)
	var background_row := HBoxContainer.new()
	identity_box.add_child(background_row)
	_add_label(background_row, "Background")
	_background = _reference_option(background_row, _background_choices(), true, false, "backgrounds")
	_background.item_selected.connect(_on_background_chosen)
	_delete_custom_background = Button.new()
	_delete_custom_background.text = "Elimina"
	_delete_custom_background.tooltip_text = "Elimina il background personalizzato dal catalogo locale"
	_delete_custom_background.pressed.connect(_delete_selected_custom_background)
	_delete_custom_background.hide()
	background_row.add_child(_delete_custom_background)
	_update_reference_tooltip(_background)

	var classes_box := _info_panel(form, "CLASSI E PROGRESSIONE")
	# Reuse the decorated panel heading, with derived level and XP on its line.
	# Flow layout wraps the controls on narrow mobile screens.
	var classes_title_row := HFlowContainer.new()
	classes_title_row.add_theme_constant_override("h_separation", 12)
	classes_title_row.add_theme_constant_override("v_separation", 6)
	classes_box.add_child(classes_title_row)
	classes_box.move_child(classes_title_row, 0)
	var classes_heading := classes_box.get_child(1) as Label
	classes_heading.reparent(classes_title_row)
	classes_heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_total_level_display = Label.new()
	_total_level_display.name = "TotalClassLevel"
	_total_level_display.add_theme_font_size_override("font_size", 14)
	_total_level_display.add_theme_color_override("font_color", Color(0.96, 0.78, 0.54))
	_total_level_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	classes_title_row.add_child(_total_level_display)
	_add_label(classes_title_row, "XP")
	_xp = _spin(classes_title_row, 0, 999999999)
	_xp.custom_minimum_size.x = 130
	_xp.tooltip_text = "XP minimi dai livelli di classe o dal GS effettivo (GS del mostro + livelli di classe)"
	var classes_row := HFlowContainer.new()
	classes_row.add_theme_constant_override("h_separation", 7)
	classes_row.add_theme_constant_override("v_separation", 6)
	classes_box.add_child(classes_row)
	_add_label(classes_row, "Classe base")
	_class_name = _reference_option(classes_row, Player5eTools.class_choices(), false, false, "classes")
	_class_name.custom_minimum_size.x = 150
	_class_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_class_name.item_selected.connect(func(_i: int) -> void: _on_class_choice_changed())
	_subclass_caption = Label.new()
	_subclass_caption.text = "Sottoclasse"
	classes_row.add_child(_subclass_caption)
	_subclass_name = _reference_option(classes_row, [], false, true, "subclasses")
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
	var resource_section := _info_panel(combat_column, "RISORSE")
	_tracker_rows = VBoxContainer.new()
	resource_section.add_child(_tracker_rows)
	# Keep resources below the complete attack list, including its description.
	combat_column.move_child(resource_section.get_parent(), _attacks_description.get_index() + 1)
	var feats_info_box := _info_panel(form, "TALENTI")
	_info_feats_list = VBoxContainer.new()
	_info_feats_list.add_theme_constant_override("separation", 5)
	feats_info_box.add_child(_info_feats_list)

	var biography_box := _info_panel(form, "STORIA E PERSONALITÀ")
	var biography_label := Label.new()
	biography_label.text = "Note"
	_style_statistics_heading(biography_label)
	biography_label.add_theme_font_size_override("font_size", 17)
	biography_box.add_child(biography_label)
	_biography = TextEdit.new()
	_biography.mouse_force_pass_scroll_events = false
	_biography.custom_minimum_size.y = 150
	_biography.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biography.scroll_fit_content_height = false
	_biography.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_biography.placeholder_text = "Storia, carattere, ideali, legami, difetti e annotazioni…"
	_biography.text_changed.connect(_save)
	biography_box.add_child(_biography)

	# Keep both appearances stacked, before the geometry controls.
	var appearance_rows := VBoxContainer.new()
	appearance_rows.add_theme_constant_override("separation", 5)
	appearance_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	miniature_group.add_child(appearance_rows)
	miniature_group.move_child(appearance_rows, miniature_flow.get_index())

	var miniature_row := HBoxContainer.new()
	miniature_row.add_theme_constant_override("separation", 6)
	miniature_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_rows.add_child(miniature_row)
	_add_label(miniature_row, "Miniatura base")
	_default_miniature = LineEdit.new()
	_default_miniature.custom_minimum_size.x = 190
	_default_miniature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_default_miniature.placeholder_text = "Scegli una miniatura dal catalogo"
	_default_miniature.editable = false
	miniature_row.add_child(_default_miniature)
	var choose_miniature := Button.new()
	choose_miniature.text = "Scegli base…"
	choose_miniature.pressed.connect(func() -> void: _choose_miniature(_current(), false))
	miniature_row.add_child(choose_miniature)
	var edit_appearance := Button.new()
	edit_appearance.text = "Cambia aspetto…"
	edit_appearance.tooltip_text = "Cerca la miniatura attuale; funziona anche senza token in scena."
	edit_appearance.pressed.connect(_edit_linked_token_appearance)
	miniature_row.add_child(edit_appearance)

	_current_miniature_row = HBoxContainer.new()
	_current_miniature_row.add_theme_constant_override("separation", 6)
	_current_miniature_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_rows.add_child(_current_miniature_row)
	_add_label(_current_miniature_row, "Forma attuale")
	_current_miniature_name = LineEdit.new()
	_current_miniature_name.editable = false
	_current_miniature_name.custom_minimum_size.x = 190
	_current_miniature_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current_miniature_row.add_child(_current_miniature_name)
	var reset_appearance := Button.new()
	reset_appearance.text = "↺ Aspetto di base"
	reset_appearance.tooltip_text = "Ripristina aspetto e taglia della miniatura di base."
	reset_appearance.pressed.connect(_restore_default_appearance)
	_current_miniature_row.add_child(reset_appearance)
	_current_miniature_row.hide()

	# Token geometry belongs with the miniature settings, not the species row.
	var size_field := _physics_field(miniature_flow, "Taglia", 124)
	_size_choice = OptionButton.new()
	_size_choice.custom_minimum_size.x = 124
	for size_name: String in ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]:
		_size_choice.add_item(size_name)
	_size_choice.item_selected.connect(func(_i: int) -> void: _save())
	size_field.add_child(_size_choice)
	var facing_field := _physics_field(miniature_flow, "Fronte della miniatura", 200)
	_front = OptionButton.new()
	_front.custom_minimum_size.x = 200
	for direction: String in ["−Z · 0°", "+X · 90°", "+Z · 180°", "−X · 270°"]:
		_front.add_item(direction)
	_front.item_selected.connect(func(_i: int) -> void: _save())
	facing_field.add_child(_front)
	# Keep the three logical groups in reading order as controls are built later.
	physics_box.move_child(movement_panel, physics_box.get_child_count() - 1)
	# Fazione is edited beside the creature name on the Statistics tab.


	_condition_rows = VBoxContainer.new()
	var conditions_section := _info_panel(conditions_tab, "Condizioni")
	conditions_section.add_child(_condition_rows)

	# The traits pane has a fixed toolbar and a single dedicated scroll area.
	traits_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(traits_tab.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	(traits_tab.get_parent().get_parent() as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_traits_ui = TraitsTab.new()
	traits_tab.add_child(_traits_ui)
	_traits_ui.call("setup")
	_traits_ui.section_requested.connect(_open_trait_section)
	_effect_dialog = AcceptDialog.new()
	_effect_dialog.title = "Dettagli effetto"
	_effect_dialog.min_size = Vector2i(560, 420)
	add_child(_effect_dialog)
	_effect_text = RichTextLabel.new()
	_effect_text.mouse_force_pass_scroll_events = false
	_effect_text.custom_minimum_size = Vector2(530, 320)
	FiveToolsText.style(_effect_text)
	_effect_dialog.add_child(_effect_text)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina creatura"
	_delete_dialog.confirmed.connect(_delete_selected_creature)
	# Keep modal deletion within the board UI, not the sheet node.
	ui_root.add_child(_delete_dialog)
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



func get_panel_control() -> Control:
	return _panel


func configure_touch_layout() -> void:
	_touch_layout = true
	_spellcasting_ui.mobile_cast_dispatch = _request_mobile_spell_cast
	_configure_touch_statistics()
	var statistics_page := _tabs.get_tab_control(1)
	statistics_page.name = "Caratteristiche e abilità"
	_tabs.set_tab_title(1, "Caratteristiche e abilità")
	var battle := _add_sheet_tab(_tabs, "Battaglia")
	_tabs.move_child(battle.get_parent().get_parent(), 2)
	_touch_combat_view = _statistics_columns.get_child(1) as ScrollContainer
	_touch_combat_view.reparent(battle)
	var touch = preload("res://vtt/mobile/touch_layout.gd")
	var outer := _panel.get_child(0) as VBoxContainer
	var header := outer.get_child(0) as HBoxContainer
	(header.get_child(0) as Label).hide()
	for child: Node in header.get_children():
		if child is Label or child is Control and child.get_class() == "Control":
			child.hide()
		if child == _creature_language_picker or child is Button and child.text == "Chiudi":
			child.hide()
	var library_button := Button.new()
	_touch_library_button = library_button
	library_button.name = "TouchCreatureList"
	library_button.text = "Schede"
	library_button.pressed.connect(func() -> void: show_touch_library(not _touch_library.visible))
	header.add_child(library_button)
	_touch_section_toggle = Button.new()
	_touch_section_toggle.name = "TouchSectionToggle"
	_touch_section_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_touch_section_toggle.pressed.connect(func() -> void:
		_touch_section_drawer.visible = not _touch_section_drawer.visible)
	header.add_child(_touch_section_toggle)
	header.move_child(_creature_import_button, header.get_child_count() - 1)
	var old_columns := _tabs.get_parent() as HSplitContainer
	var pages := touch.replace_box(old_columns, VBoxContainer.new()) as VBoxContainer
	_touch_library = pages.get_child(0) as Control
	_touch_library.name = "TouchLibrary"
	_touch_library.custom_minimum_size.x = 0
	_touch_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_touch_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creature_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Only the library needs an outer scroll. The editor must give its active tab
	# a bounded viewport, especially Tratti with its own scrolling list.
	_touch_library_view = ScrollContainer.new()
	_touch_library_view.name = "TouchLibraryScroll"
	_touch_library_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_touch_library_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(_touch_library_view)
	_touch_library.reparent(_touch_library_view)
	pages.move_child(_touch_library_view, 0)
	pages.remove_child(_tabs)
	var editor := VBoxContainer.new()
	editor.name = "TouchSheetEditor"
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(editor)
	_touch_editor = editor
	_touch_section = OptionButton.new()
	_touch_section.name = "TouchSheetSection"
	for index: int in range(_tabs.get_tab_count()):
		_touch_section.add_item(_tabs.get_tab_title(index))
	_touch_section.item_selected.connect(func(index: int) -> void: _tabs.current_tab = index)
	_tabs.tab_changed.connect(func(index: int) -> void: _touch_section.select(index))
	editor.add_child(_touch_section)
	_touch_section.hide()
	# A right-hand drawer replaces the seven permanently visible tab buttons.
	_touch_section_drawer = PanelContainer.new()
	_touch_section_drawer.name = "TouchSheetSectionsDrawer"
	_touch_section_drawer.z_index = 110
	ui_root.add_child(_touch_section_drawer)
	_touch_section_drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_touch_section_drawer.offset_left = -232
	_touch_section_drawer.offset_right = -8
	_touch_section_drawer.offset_top = 52
	_touch_section_drawer.offset_bottom = -8
	var drawer_body := VBoxContainer.new()
	_touch_section_drawer.add_child(drawer_body)
	var close_sections := Button.new()
	close_sections.text = "✕  Sezioni"
	close_sections.pressed.connect(close_touch_section_drawer)
	drawer_body.add_child(close_sections)
	var drawer_scroll := ScrollContainer.new()
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_body.add_child(drawer_scroll)
	var sections := VBoxContainer.new()
	sections.name = "TouchSheetSections"
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_scroll.add_child(sections)
	var group := ButtonGroup.new()
	for index: int in range(_tabs.get_tab_count()):
		var button := Button.new()
		button.text = _tabs.get_tab_title(index)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_request_touch_section.bind(index))
		sections.add_child(button)
		_touch_section_buttons.append(button)
	_tabs.tab_changed.connect(_sync_touch_section_buttons)
	_sync_touch_section_buttons(_tabs.current_tab)
	touch.style_tree(_touch_section_drawer)
	_touch_section_drawer.hide()
	_spellcasting_ui.configure_touch_layout()
	_inventory_ui.configure_touch_layout()
	_tabs.tabs_visible = false
	_tabs.custom_minimum_size.x = 0
	_panel.custom_minimum_size.x = 0
	var compact_style: StyleBox = _panel.get_theme_stylebox("panel", "PanelContainer").duplicate()
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		compact_style.set_content_margin(side, 2)
	_panel.add_theme_stylebox_override("panel", compact_style)
	editor.add_child(_tabs)
	for index: int in range(_tabs.get_tab_count()):
		var tab_scroll := _tabs.get_tab_control(index) as ScrollContainer
		# Traits are a single vertical list; an outer horizontal scrollbar
		# steals space without providing useful content on a phone.
		tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var info := _tabs.get_tab_control(0).get_child(0).get_child(0)
	touch.wrap_fields(info)
	# A class is a labelled full-width field, not six independent flow items.
	# Otherwise the base class selector becomes unreadable on a phone.
	var original_classes := _class_name.get_parent() as HFlowContainer
	var class_fields := touch.replace_box(original_classes, VBoxContainer.new()) as VBoxContainer
	var class_captions: Array[Label] = [class_fields.get_child(0) as Label, _subclass_caption, _level_caption]
	var class_inputs: Array[Control] = [_class_name, _subclass_name, _level]
	for index: int in range(class_inputs.size()):
		var field := VBoxContainer.new()
		field.add_theme_constant_override("separation", 3)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		class_fields.add_child(field)
		class_captions[index].reparent(field)
		class_inputs[index].reparent(field)
		class_inputs[index].custom_minimum_size.x = 0
		class_inputs[index].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_statistics_columns = touch.replace_box(_statistics_columns, VBoxContainer.new()) as BoxContainer
	for columns: Node in _panel.find_children("EditorColumns", "HBoxContainer", true, false):
		var stacked := touch.replace_box(columns, VBoxContainer.new()) as VBoxContainer
		for child: Control in stacked.get_children():
			child.custom_minimum_size.x = 0
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		touch.wrap_fields(stacked)
	_origins_overview.custom_minimum_size.x = 0
	_editor_section_picker.custom_minimum_size.x = 0
	var catalog_group := VBoxContainer.new()
	catalog_group.name = "TouchBestiary"
	_touch_library.add_child(catalog_group)
	_catalog_filter.reparent(catalog_group, false)
	_catalog_list.reparent(catalog_group, false)
	_catalog_list.custom_minimum_size.y = 160
	for child: Node in _touch_library.get_children():
		if child is Button and child.text == "+ Dal bestiario":
			child.reparent(catalog_group, false)
	var catalog_button := Button.new()
	catalog_button.text = "Importa dal bestiario"
	catalog_button.pressed.connect(func() -> void:
		catalog_group.visible = not catalog_group.visible
		if catalog_group.visible and DisplayServer.get_name() != "headless":
			_client.load_catalog())
	_touch_library.add_child(catalog_button)
	catalog_group.hide()
	_creature_list.child_entered_tree.connect(func(_node: Node) -> void: call_deferred("_connect_touch_creature_rows"))
	_connect_touch_creature_rows()
	for child: Node in _touch_library.get_children():
		if child is Button and child.text == "+ Personaggio":
			child.pressed.connect(func() -> void: show_touch_library(false))
	_traits_ui.call("configure_touch_layout")
	touch.style_tree(_panel)
	for column: Control in _statistics_columns.get_children():
		column.custom_minimum_size.x = 0
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Preserve the horizontal ability grid, hit-point actions and resource
	# counters. Their internal groups already flow or wrap as units.
	var traits_scroll := _traits_ui.get("_scroll") as ScrollContainer
	if traits_scroll != null:
		traits_scroll.follow_focus = false
	# Initial sheets may have been populated before mobile mode was enabled.
	# Rebuild their dynamic multiclass/tracker rows with the touch layout too.
	var initial_record := _current()
	if not initial_record.is_empty():
		_load_form(initial_record)
		touch.style_tree(_multiclass_rows)
		touch.style_tree(_tracker_rows)
	show_touch_library(true)



# Only the statistics pane needs constrained, non-wrapping numeric cells.
# Restore the original desktop control signals; change presentation only.
func _configure_touch_statistics() -> void:
	var left_view := _statistics_columns.get_child(0) as ScrollContainer
	var right_view := _statistics_columns.get_child(1) as ScrollContainer
	for view: ScrollContainer in [left_view, right_view]:
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		view.custom_minimum_size.x = 0
		var content := view.get_child(0) as Control
		content.custom_minimum_size.x = 0
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key: Variant in _formula_values:
		var value: Control = _formula_values[key] as Control
		if value == null:
			continue
		value.size_flags_horizontal = Control.SIZE_SHRINK_END
		var number := value.get("value_label") as Label
		if number != null:
			number.autowrap_mode = TextServer.AUTOWRAP_OFF
			number.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			number.custom_minimum_size.x = maxf(number.custom_minimum_size.x, 54)
	for skill: String in _skill_buttons.keys():
		var name := _skill_buttons[skill] as Label
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.clip_text = true
		name.custom_minimum_size.x = 145
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var point_header := _abilities_grid.get_child(1) as Label
	point_header.text = "Punt."
	for heading_index: int in range(4):
		(_abilities_grid.get_child(heading_index) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF

	var combat := right_view.get_child(0) as VBoxContainer
	var health_panel := combat.get_node("TouchHitPoints") as PanelContainer
	var health_content := health_panel.get_child(0) as VBoxContainer
	var health := health_content.get_node("TouchHealthLine") as HFlowContainer
	var health_stack := preload("res://vtt/mobile/touch_layout.gd").replace_box(health, VBoxContainer.new()) as VBoxContainer
	var health_values := HBoxContainer.new()
	health_values.add_theme_constant_override("separation", 5)
	health_stack.add_child(health_values)
	var actions := health_stack.get_child(0) as HBoxContainer
	for child: Node in health_stack.get_children():
		if child != actions and child != health_values:
			child.reparent(health_values, false)
	health_stack.move_child(health_values, 0)
	_hp.custom_minimum_size.x = 90
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var second_form := health_content.get_node("TouchFormHpLine") as HBoxContainer
	var form_stack := preload("res://vtt/mobile/touch_layout.gd").replace_box(second_form, VBoxContainer.new()) as VBoxContainer
	var form_values := HBoxContainer.new()
	form_values.add_theme_constant_override("separation", 5)
	form_stack.add_child(form_values)
	for child: Node in form_stack.get_children():
		if child != form_values and child != form_stack.get_child(0):
			child.reparent(form_values, false)
	_second_form_hp.custom_minimum_size.x = 88
	_second_form_max_hp.custom_minimum_size.x = 88

	var defense := combat.get_node("TouchDefense") as PanelContainer
	var defense_content := defense.get_child(0) as VBoxContainer
	var defense_row := defense_content.get_node("TouchDefenseLine") as HBoxContainer
	var defense_stack := preload("res://vtt/mobile/touch_layout.gd").replace_box(defense_row, VBoxContainer.new()) as VBoxContainer
	for child: Node in defense_stack.get_children():
		if child is VSeparator:
			child.hide()
	var initiative_row := defense_stack.get_node("TouchInitiativeLine") as HBoxContainer
	(initiative_row.get_child(0) as Label).text = "Iniziativa"
	var natural_row := defense_content.get_node("TouchAcFormula") as HBoxContainer
	preload("res://vtt/mobile/touch_layout.gd").replace_box(natural_row, VBoxContainer.new())
	_armor_picker.custom_minimum_size.x = 114
	_armor_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_natural_ac_formula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_natural_ac_formula.custom_minimum_size.x = 0


func _show_creature_import_picker() -> void:
	DialogLayout.popup(_creature_import_picker, Vector2i(760, 600), 0.9)


func _import_export_files(paths: PackedStringArray) -> void:
	var failures: PackedStringArray = []
	var imported := 0
	for path: String in paths:
		var result := _import_export_path(path)
		if result == OK:
			imported += 1
		else:
			failures.append(path.get_file() + ": " + error_string(result))
	if imported > 0:
		_reload()
	var message := "File importati come copie locali: %d." % imported
	if not failures.is_empty():
		message += " Non importati: " + "; ".join(failures)
	_set_status(message)


func _import_export_file(path: String) -> void:
	_import_export_files(PackedStringArray([path]))


func _import_export_path(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_length() > 16 * 1024 * 1024:
		return ERR_INVALID_DATA
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return ERR_INVALID_DATA
	var payload: Variant = parser.data
	if not payload is Dictionary:
		return ERR_INVALID_DATA
	return (_archive.import_export_batch(payload)
		if String(payload.get("format", "")) == "vtt_creature_batch_export_v1"
		else _archive.import_export_copy(payload))


func _request_touch_section(index: int) -> void:
	# Complete the finger event before changing the layout/focus hierarchy.
	close_touch_section_drawer()
	_apply_touch_section.call_deferred(index)


func close_touch_section_drawer() -> bool:
	if _touch_section_drawer == null or not _touch_section_drawer.visible:
		return false
	_touch_section_drawer.hide()
	return true


func _apply_touch_section(index: int) -> void:
	if _tabs != null and index >= 0 and index < _tabs.get_tab_count():
		_tabs.current_tab = index


func _sync_touch_section_buttons(index: int) -> void:
	for i: int in range(_touch_section_buttons.size()):
		_touch_section_buttons[i].set_pressed_no_signal(i == index)
	if _touch_section_toggle != null and index >= 0 and index < _tabs.get_tab_count():
		_touch_section_toggle.text = _tabs.get_tab_title(index)


func is_touch_library_visible() -> bool:
	return _touch_library != null and _touch_library.visible


func show_touch_library(show_library: bool) -> void:
	if _touch_library == null:
		return
	close_touch_section_drawer()
	_touch_library.visible = show_library
	_touch_library_view.visible = show_library
	_touch_editor.visible = not show_library
	_touch_section_toggle.visible = not show_library
	_touch_library_button.text = "Apri" if show_library else "Schede"
	_touch_library_button.tooltip_text = "Apri la scheda selezionata" if show_library else "Torna all’elenco delle creature"
	_touch_library_button.disabled = show_library and _selected_id.is_empty()
	touch_library_changed.emit(show_library)


func _connect_touch_creature_rows() -> void:
	for index: int in range(_creature_row_buttons.size()):
		var button := _creature_row_buttons[index]
		if not button.pressed.is_connected(_open_touch_sheet):
			button.pressed.connect(_open_touch_sheet)
		var row := button.get_parent()
		if row.get_node_or_null("TouchActions") == null:
			var actions := Button.new()
			actions.name = "TouchActions"
			actions.text = "⋯"
			actions.tooltip_text = "Azioni della creatura"
			actions.custom_minimum_size = Vector2(48, 48)
			actions.pressed.connect(_open_touch_creature_actions.bind(index, actions))
			row.add_child(actions)
	for eye: Button in _creature_eye_buttons:
		eye.hide()


func _open_touch_creature_actions(index: int, button: Button) -> void:
	_select_creature_row(index)
	_creature_context_menu.position = Vector2i(button.get_global_rect().position + Vector2(0, 48))
	if _touch_layout and board_root.has_method("show_touch_popup"):
		board_root.show_touch_popup(_creature_context_menu)
	else:
		DialogLayout.popup_menu(_creature_context_menu, _creature_context_menu.position)


func _open_touch_sheet() -> void:
	show_touch_library(false)


func _fit_sheet_tabs() -> void:
	if _tabs == null or _touch_layout: return
	var bar := _tabs.get_tab_bar()
	bar.add_theme_constant_override("h_separation", 4)
	for slot: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var box := bar.get_theme_stylebox(slot).duplicate() as StyleBox
		box.content_margin_left = 6
		box.content_margin_right = 6
		bar.add_theme_stylebox_override(slot, box)
	var font := bar.get_theme_font("font")
	for font_size: int in [14, 13, 12, 11]:
		bar.add_theme_font_size_override("font_size", font_size)
		var required := 0.0
		for index: int in range(_tabs.get_tab_count()):
			required += font.get_string_size(_tabs.get_tab_title(index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 30
		if required <= _tabs.size.x: break


func _add_sheet_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(scroll)
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The creature sheet should only scroll vertically, never a few pixels
	# horizontally because a long bestiary reference expands a child.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var icon_key: String = {"Info": "information", "Statistiche": "skill", "Cosa posso fare?": "weapon",
		"Poteri": "spark", "Inventario": "inventory", "Tratti": "proficiency",
		"Condizioni": "condition", "Modifica personaggio": "settings"}.get(title, "book")
	tabs.set_tab_icon(tabs.get_tab_count() - 1, preload("res://vtt/creature_sheet_style.gd").icon(icon_key))
	tabs.set_tab_icon_max_width(tabs.get_tab_count() - 1, 14)
	tabs.get_tab_bar().set_tab_tooltip(tabs.get_tab_count() - 1, title)
	_fit_sheet_tabs.call_deferred()
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The breathing room is inside the bordered sheet, not around it.
	for edge: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(edge, 10)
	for edge: String in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 11)
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
		10, 11:
			var language_index := 0 if id == 10 else 1
			_creature_language_picker.select(language_index)
			_on_creature_language_selected(language_index)


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
	if _touch_layout and board_root.has_method("show_touch_popup"):
		board_root.show_touch_popup(_creature_context_menu)
	else:
		DialogLayout.popup_menu(_creature_context_menu, _creature_context_menu.position)
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
		action_button.visible = board_root.has_method("begin_creature_token_placement")
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
		_refresh_creature_language()



# This preference is private to the creature archive. It must not change the
# engine-wide locale, other VTT panels, imported 5etools text or saved sheets.
func _on_creature_language_selected(index: int) -> void:
	_creature_language = "en" if index == 1 else "it"
	CreatureLocale.write_locale(_creature_language)
	_refresh_creature_language()


func _refresh_creature_language() -> void:
	if _panel == null:
		return
	if _inventory_ui != null and _inventory_ui.has_method("set_gui_language"):
		_inventory_ui.call("set_gui_language", _creature_language)
	if _spellcasting_ui != null and _spellcasting_ui.has_method("set_gui_language"):
		_spellcasting_ui.call("set_gui_language", _creature_language)
	CreatureLocale.apply(_panel, _creature_language)
	_refresh_total_class_level_label()
	# The mobile section drawer lives under ui_root, outside the archive panel.
	# Its buttons must mirror the localized tabs rather than storing display
	# strings as the source of truth (the selection indices never change).
	if _touch_section_drawer != null and is_instance_valid(_touch_section_drawer):
		CreatureLocale.apply(_touch_section_drawer, _creature_language)
		for index: int in range(mini(_touch_section_buttons.size(), _tabs.get_tab_count())):
			_touch_section_buttons[index].text = _tabs.get_tab_title(index)
	if _touch_section != null and is_instance_valid(_touch_section):
		for index: int in range(mini(_touch_section.item_count, _tabs.get_tab_count())):
			_touch_section.set_item_text(index, _tabs.get_tab_title(index))
	# Dialogs are not all descendants of the archive panel.
	for dialog: Node in [
		_automatic_dialog, _delete_dialog, _miniature_dialog, _transfer_dialog,
		_export_dialog, _import_dialog, _hp_delta_dialog, _form_hp_dialog,
		_restore_form_dialog, _form_depleted_dialog, _effect_dialog
	]:
		if dialog != null and is_instance_valid(dialog):
			CreatureLocale.apply(dialog, _creature_language)
	# Also localize transient creature dialogs created after the panel initialized.
	for node: Node in get_children():
		if node is Window and bool(node.get_meta("creature_gui_dialog", false)):
			CreatureLocale.apply(node, _creature_language)


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
	_automatic_dialog.title = "Ricalcoli manuali"
	_automatic_dialog.get_ok_button().text = "Applica"
	_automatic_dialog.get_cancel_button().text = "Annulla"
	_automatic_dialog.min_size = Vector2i(520, 290)
	ui_root.add_child(_automatic_dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_automatic_dialog.add_child(content)
	var intro := Label.new()
	intro.text = "I valori derivati sono già aggiornati automaticamente. Queste opzioni servono solo in casi particolari."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	_automatic_hp = CheckBox.new()
	_automatic_hp.text = "Ricalcola i punti ferita massimi"
	_automatic_hp.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_hp)
	_automatic_class_features = CheckBox.new()
	_automatic_class_features.text = "Ripristina privilegi di classe (solo in caso di bug)"
	_automatic_class_features.toggled.connect(func(_enabled: bool) -> void: _refresh_automatic_preview())
	content.add_child(_automatic_class_features)
	_automatic_preview = RichTextLabel.new()
	_automatic_preview.custom_minimum_size.y = 95
	_automatic_preview.scroll_active = true
	_automatic_preview.set_meta("creature_gui_text", true)
	content.add_child(_automatic_preview)
	_automatic_dialog.confirmed.connect(_apply_automatic_calculation)


func _open_automatic_calculation() -> void:
	_save()
	var record: Dictionary = _current()
	if record.is_empty():
		return
	_automatic_target_id = String(record.get("id", ""))
	var hp_context: Dictionary = record.duplicate(true)
	hp_context["effective_con_modifier"] = BonusRules.value(record, "ability_mod:con")
	var hp_result: Dictionary = (
		Rules.automatic_hit_points(hp_context)
		if String(record.get("kind", "")) == "character"
		else Rules.automatic_monster_hit_points(record)
	)
	_automatic_hp.disabled = not bool(hp_result.get("available", false))
	_automatic_class_features.disabled = Rules.class_levels(record) == 0
	_automatic_hp.set_pressed_no_signal(false)
	_automatic_class_features.set_pressed_no_signal(false)
	_refresh_automatic_preview()
	_popup_sheet_dialog(_automatic_dialog, Vector2i(575, 365), 0.90)


func _refresh_automatic_preview() -> void:
	if _automatic_preview == null:
		return
	var record: Dictionary = _current()
	var lines := PackedStringArray()
	if _automatic_hp.button_pressed:
		var context: Dictionary = record.duplicate(true)
		context["effective_con_modifier"] = BonusRules.value(record, "ability_mod:con")
		var hp: Dictionary = (
			Rules.automatic_hit_points(context)
			if String(record.get("kind", "")) == "character"
			else Rules.automatic_monster_hit_points(record)
		)
		if bool(hp.get("available", false)):
			lines.append("Nuovi PF massimi: %d (%s)" % [int(hp.get("value", 0)), String(hp.get("detail", ""))])
	if _automatic_class_features.button_pressed:
		lines.append("Ricostruisce le concessioni automatiche delle classi senza cancellare le scelte e le modifiche alle origini ancora attive.")
	if lines.is_empty():
		lines.append("Scegli un ricalcolo manuale. XP, competenza, velocità, slot e altri valori derivati si aggiornano già da soli.")
	_automatic_preview.text = "\n".join(lines)
	_automatic_dialog.get_ok_button().disabled = (
		not _automatic_hp.button_pressed and not _automatic_class_features.button_pressed
	)


func _apply_automatic_calculation() -> void:
	var record: Dictionary = _current()
	if record.is_empty() or String(record.get("id", "")) != _automatic_target_id:
		return
	if _automatic_hp.button_pressed:
		var context: Dictionary = record.duplicate(true)
		context["effective_con_modifier"] = BonusRules.value(record, "ability_mod:con")
		var hp: Dictionary = (
			Rules.automatic_hit_points(context)
			if String(record.get("kind", "")) == "character"
			else Rules.automatic_monster_hit_points(record)
		)
		if bool(hp.get("available", false)):
			record["max_hp_base"] = int(hp.get("value", 1))
			record["max_hp"] = maxi(0, BonusRules.value(record, "hp"))
			record["current_hp"] = mini(int(record.get("current_hp", 0)), int(record["max_hp"]))
	if _automatic_class_features.button_pressed:
		ProficiencyRules.reconcile_origin_dependents(record)
		ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
		SheetController.sync_automatic_progression(record)
		SheetController.sync_origin_resources(record)
	_recalculate_bonus_mirrors(record)
	if _archive.save(record) != OK:
		_set_status("Ricalcolo eseguito ma non salvato.")
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)
	_set_status("Ricalcolo manuale applicato.")


func _build_transfer_request_dialog() -> void:
	_transfer_dialog = ConfirmationDialog.new()
	_transfer_dialog.title = "Cedi controllo della creatura"
	_transfer_dialog.dialog_text = ""
	_transfer_dialog.min_size = Vector2i(480, 220)
	ui_root.add_child(_transfer_dialog)
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
	ui_root.add_child(_export_dialog)


func _export_current_creature() -> void:
	_save()
	var record: Dictionary = _current()
	if record.is_empty():
		_set_status("Seleziona una creatura da scaricare.")
		return
	var filename: String = String(record.get("name", "creatura")).strip_edges()
	for forbidden: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		filename = filename.replace(forbidden, "_")
	_batch_export_pending.clear()
	_export_dialog.title = "Scarica creatura"
	_export_dialog.current_file = filename.substr(0, 75) + ".json"
	_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	DialogLayout.popup(_export_dialog, Vector2i(820, 550), 0.9)


func _save_exported_creature(path: String) -> void:
	if not _batch_export_pending.is_empty():
		_save_batch_export(path)
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var missing: Array[String] = PortableContent.unresolved(record)
	if not missing.is_empty():
		_set_status("Esportazione annullata: mancano %d definizioni homebrew usate dalla scheda (%s)." % [
			missing.size(), ", ".join(missing.slice(0, 3))])
		return
	var companions: Array[Dictionary] = PortableContent.bundle(record)
	if companions.size() > PortableContent.MAX_ENTRIES:
		_set_status("Esportazione annullata: troppe definizioni personalizzate per il formato portatile.")
		return
	if JSON.stringify(companions).to_utf8_buffer().size() > PortableContent.MAX_BYTES:
		_set_status("Esportazione annullata: contenuti personalizzati troppo voluminosi.")
		return
	var export_text: String = JSON.stringify({
		"format": "vtt_creature_export_v1",
		"version": 1,
		"creature": record,
		"homebrew_content": companions
	}, "  ")
	if export_text.to_utf8_buffer().size() > 16 * 1024 * 1024:
		_set_status("Esportazione annullata: il file supera il limite d'importazione di 16 MB.")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Esportazione non riuscita: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(export_text)
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
	_import_text.mouse_force_pass_scroll_events = false
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
	preload("res://vtt/creature_sheet_style.gd").heading(label, "information")
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("edbd77"))
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
	widget.set_rollable(key == "initiative" or key.begins_with("ability_mod:")
		or key.begins_with("skill:") or key.begins_with("save:")
		or key.begins_with("attack_hit:") or key.begins_with("attack_damage:"))
	widget.bonus_requested.connect(_on_formula_bonus_requested)
	widget.roll_requested.connect(_on_formula_roll_requested)
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


# Warn before opening a hidden editor; read from the saved/current sheet
# rather than the currently rendered tab, which may still be lazy-loaded.
func _refresh_choice_warnings(record: Dictionary) -> void:
	if _editor_section_picker == null:
		return
	var pending: Dictionary = PendingChoices.section_warnings(record)
	var lines: Array[String] = []
	for i: int in range(_editor_section_picker.item_count):
		var existing: String = _editor_section_picker.get_item_text(i)
		var section: String = existing.trim_prefix("⚠ ")
		var missing: Array = pending.get(i, [])
		_editor_section_picker.set_item_text(i,
			"⚠ " + section if not missing.is_empty() else section)
		if not missing.is_empty():
			lines.append(section + ":\n" + "\n".join(PackedStringArray(missing)))
	if _editor_choice_warning != null:
		_editor_choice_warning.visible = not lines.is_empty()
		_editor_choice_warning.tooltip_text = (
			"Scelte ancora da completare:\n\n" + "\n\n".join(lines)
			if not lines.is_empty() else ""
		)
	_editor_section_picker.tooltip_text = (
		"Scelte da completare:\n\n" + "\n\n".join(lines)
		if not lines.is_empty() else "Scegli una sezione da visualizzare o modificare"
	)


func _open_trait_section(section: int) -> void:
	_show_sheet_tab("Modifica personaggio")
	_select_details_editor(section)
	call_deferred("_scroll_origins_to_top")


func _select_details_editor(index: int) -> void:
	if _editor_section_picker == null:
		return
	var choice: int = clampi(index, 0, 6)
	_editor_section_picker.select(choice)
	_origins_overview.visible = choice == 0
	if choice == 0:
		_refresh_origins_overview()
	_proficiencies_ui.visible = choice == 1
	_feats_ui.visible = choice == 2
	_bonuses_ui.visible = choice == 3
	_trackers_ui.visible = choice == 4
	_damage_defenses_ui.visible = choice == 5
	_origin_spells_ui.visible = choice == 6
	if choice > 0:
		var record: Dictionary = _current()
		if not record.is_empty():
			match choice:
				1:
					if _proficiencies_stale:
						_proficiencies_ui.call("load_record", record)
						_proficiencies_stale = false
				2:
					if _feats_stale:
						_feats_ui.call("load_record", record)
						_feats_stale = false
				3:
					if _bonuses_stale:
						_bonuses_ui.call("load_record", record)
						_bonuses_stale = false
				4:
					if _trackers_stale:
						_trackers_ui.call("load_record", record)
						_trackers_stale = false
				5:
					if _damage_defenses_stale:
						_damage_defenses_ui.call("load_record", record)
						_damage_defenses_stale = false
				6:
					if _origin_spells_stale:
						_origin_spells_ui.call("load_record", record)
						_origin_spells_stale = false
	call_deferred("_update_stats_column_heights")


func _open_origin_spell_editor() -> void:
	_show_sheet_tab("Modifica personaggio")
	_select_details_editor(6)
	call_deferred("_scroll_origins_to_top")


func _on_origin_spells_updated(grants: Array, configs: Dictionary) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	SheetController.update_origin_spells(record, grants, configs)
	SheetController.sync_origin_resources(record)
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare gli incantesimi da origini.")
		return
	_replace_current_record(record)
	_origin_spells_stale = false
	_action_economy_ui.call("load_record", record)
	_spellcasting_ui.call("load_record", record)
	_refresh_choice_warnings(record)


func _on_damage_defenses_updated(damage_overrides: Dictionary, condition_overrides: Dictionary, defense_entries: Array = [], origins: Array = []) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	record["damage_defense_overrides"] = damage_overrides.duplicate(true)
	record["condition_immunity_overrides"] = condition_overrides.duplicate(true)
	record["damage_defense_entries"] = defense_entries.duplicate(true)
	if not origins.is_empty():
		record["proficiency_origins"] = origins.duplicate(true)
	ProficiencyRules.reconcile_origin_dependents(record)
	SheetController.sync_origin_resources(record)
	_recalculate_bonus_mirrors(record)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare resistenze/immunità: " + error_string(error))
		return
	_replace_current_record(record)
	_damage_defenses_stale = false
	_update_defense_display()
	_refresh_conditions(record)


func _on_formula_bonus_requested(key: String) -> void:
	if _bonuses_ui == null or key.is_empty():
		return
	_show_sheet_tab("Modifica personaggio")
	_select_details_editor(3)
	_bonuses_ui.call("select_target", key)
	# Keep the requested origin section visible after navigation.
	call_deferred("_scroll_origins_to_top")


func _scroll_origins_to_top() -> void:
	if _origins_scroll != null and is_instance_valid(_origins_scroll):
		_origins_scroll.scroll_vertical = 0


func _on_class_feature_requested(id: String) -> void:
	var record := _current()
	var feature: Dictionary = {}
	for row: Dictionary in ClassFeatures.entries(record):
		if row.id == id: feature = row; break
	if feature.is_empty(): return
	var dialog := ConfirmationDialog.new()
	dialog.title = String(feature.name)
	dialog.ok_button_text = "Termina" if bool(feature.get("active", false)) else "Attiva"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	dialog.add_child(body)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(400, 180)
	text.text = ActionEconomyTab._source_text(String(feature.detail))
	body.add_child(text)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 100
	amount.value = 1
	amount.visible = feature.mode in ["heal_pool", "conversion", "recovery"]
	if feature.mode in ["conversion", "recovery"]: amount.max_value = 5
	body.add_child(amount)
	var quantity_label := Label.new()
	quantity_label.text = "Punti ferita" if feature.mode == "heal_pool" else "Livello dello slot"
	quantity_label.visible = amount.visible
	body.add_child(quantity_label)
	body.move_child(quantity_label, amount.get_index())
	var target_picker := OptionButton.new()
	target_picker.visible = feature.mode == "heal_pool"
	var healing_targets: Array[Dictionary] = _archive.list_owned()
	for target: Dictionary in healing_targets:
		target_picker.add_item(String(target.get("name", "Creatura")))
		target_picker.set_item_metadata(target_picker.item_count - 1, target.get("id", ""))
		if String(target.get("id", "")) == String(record.get("id", "")): target_picker.select(target_picker.item_count - 1)
	body.add_child(target_picker)
	var recovery_picks: Array[SpinBox] = []
	if feature.mode == "recovery":
		amount.hide()
		quantity_label.text = "Slot da recuperare · massimo %d livelli totali" % ceili(float(ClassFeatures.class_level(record, "Wizard")) / 2.0)
		for level: int in range(1, 6):
			var row := HBoxContainer.new()
			body.add_child(row)
			var caption := Label.new()
			caption.text = "Slot %d° livello" % level
			row.add_child(caption)
			var count := SpinBox.new()
			var spent: Array = record.get("spell_slots_spent", [])
			count.max_value = int(spent[level]) if spent.size() > level else 0
			row.add_child(count)
			recovery_picks.append(count)
	var direction := CheckBox.new()
	direction.text = "Crea slot (disattiva per convertire uno slot in punti)"
	direction.button_pressed = true
	direction.visible = feature.mode == "conversion"
	body.add_child(direction)
	var enhanced := CheckBox.new()
	enhanced.text = "Versione potenziata · 1 punto Focus"
	enhanced.visible = feature.key in ["patient_defense", "step_of_the_wind"] and String(record.get("rules_version", "2014")) == "2024"
	body.add_child(enhanced)
	var reroll_count := SpinBox.new()
	reroll_count.min_value = 1
	reroll_count.max_value = maxi(1, BonusRules.value(record, "ability_mod:cha"))
	reroll_count.value = 1
	reroll_count.visible = feature.mode == "metamagic_roll" and feature.name == "Empowered Spell"
	body.add_child(reroll_count)
	var reroll_die := OptionButton.new()
	for sides: int in [4, 6, 8, 10, 12, 20, 100]:
		reroll_die.add_item("d%d" % sides, sides)
	reroll_die.visible = reroll_count.visible
	body.add_child(reroll_die)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = ("Conferma l'effetto con i bersagli e gli eventuali tiri previsti dal privilegio. Il consumo viene registrato alla conferma."
		if feature.mode == "context" else "Il privilegio rimane attivo fino a quando scegli Termina; rispetta durata e condizioni indicate sopra.")
	body.add_child(note)
	if feature.mode == "metamagic_roll":
		note.text = "Usa dopo un tiro per colpire fallito (Seeking) o dopo aver tirato i danni (Empowered). Seleziona i dadi da sostituire: devi utilizzare i nuovi risultati."
	if feature.mode == "metamagic":
		note.text = "Scegli Metamagia nella finestra di lancio dell’incantesimo."
		dialog.get_ok_button().disabled = true
	add_child(dialog)
	var source_id := String(record.get("id", ""))
	dialog.confirmed.connect(func() -> void:
		if String(_current().get("id", "")) != source_id: return
		var live := _current()
		if feature.mode == "metamagic_roll" and board_root.get_node_or_null("DiceRollerChat") == null:
			_set_status("Il lanciatore di dadi della chat non è disponibile.")
			return
		var recovery_levels: Array = []
		for index: int in range(recovery_picks.size()):
			for count: int in range(int(recovery_picks[index].value)): recovery_levels.append(index + 1)
		var target_id := String(target_picker.get_item_metadata(target_picker.selected)) if target_picker.item_count > 0 else source_id
		var result := (ClassFeatures.convert_slots(live, int(amount.value), direction.button_pressed)
			if feature.mode == "conversion" else Metamagic.reroll_plan(live, String(feature.name), int(reroll_count.value), reroll_die.get_selected_id()) if feature.mode == "metamagic_roll" else ClassFeatures.recover_slots(live, recovery_levels) if feature.mode == "recovery" else ClassFeatures.activate(live, id, {"amount": int(amount.value), "enhanced": enhanced.button_pressed, "apply_to_self": target_id == source_id}))
		if bool(result.get("ok", false)):
			var updated: Dictionary = result.record
			var updates: Array[Dictionary] = [updated]
			if feature.mode == "heal_pool" and target_id != source_id:
				for target: Dictionary in _archive.list_owned():
					if String(target.get("id", "")) != target_id: continue
					SheetController.change_hit_points(target, int(amount.value))
					updates.append(target)
					break
				if updates.size() != 2:
					_set_status("Bersaglio della cura non più disponibile.")
					return
			if _archive.update_owned_many(updates) != OK:
				_set_status("Impossibile salvare il privilegio.")
				return
			for saved: Dictionary in updates:
				_update_external_record(saved)
				_sync_token_health(saved)
			_update_external_record(updated)
			if result.has("expression"):
				var roller := board_root.get_node_or_null("DiceRollerChat")
				roller.call("roll_expression_from_sheet", String(feature.name) + " · nuovi risultati obbligatori", String(result.expression), find_linked_token_for_creature(source_id))
			_load_form(updated)
			_sync_token_health(updated)
		_set_status(String(result.get("message", "")))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	DialogLayout.popup(dialog, Vector2i(660, 430), 0.9)


func _on_action_tracker_change(tracker_id: String, delta: int, maximum: int) -> void:
	_change_tracker(tracker_id, delta, maximum)
	if _action_economy_ui != null:
		_action_economy_ui.call("load_record", _current())


func _on_action_cast_requested(spell_id: String, grant_id: String, class_id: String = "") -> void:
	if _spellcasting_ui == null or not _spellcasting_ui.has_method("request_cast_from_actions"):
		return
	if not bool(_spellcasting_ui.call("request_cast_from_actions", spell_id, grant_id, class_id)):
		_set_status("Incantesimo non più disponibile. Aggiorna la scheda Poteri.")


func _on_basic_action_requested(action_id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	# The Android shell uses its existing token-selectable 2D map snapshot.
	if board_root.has_method("request_mobile_basic_action"):
		board_root.call("request_mobile_basic_action", record, action_id)
		return
	var actor: CharacterBody3D = find_linked_token_for_creature(String(record.get("id", "")))
	if actor == null:
		_set_status("Associa prima la creatura a un token sulla mappa.")
		return
	var candidates: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if node is CharacterBody3D and board_root.is_ancestor_of(node) and node != actor and node.is_visible_in_tree():
			candidates.append(node)
	if candidates.is_empty():
		_set_status("Nessun token bersaglio presente.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Aiutare" if action_id == "help" else "Spingere" if action_id == "shove" else "Afferrare" if action_id == "grapple" else "Buttare prono"
	dialog.ok_button_text = "Applica" if action_id == "help" else "Confermo il successo"
	dialog.cancel_button_text = "Annulla"
	var body := VBoxContainer.new()
	dialog.add_child(body)
	var caption := Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if action_id == "help":
		caption.text = "Applica Aiutato al bersaglio. Nessun vantaggio o altro effetto viene calcolato automaticamente."
	else:
		var info: Dictionary = BasicCombat.shove_details(record,
			BonusRules.value(record, "skill:athletics"),
			BonusRules.value(record, "ability_mod:str"), BonusRules.value(record, "proficiency"))
		caption.text = String(info.get("check", "")) + "\n" + (("Afferrare: mano libera richiesta; applica Afferrato dopo il successo." if action_id == "grapple" else String(info.get("action", ""))) + "\n" + (
			"\nCD: %d" % int(info["dc"]) if info.has("dc") else
			"\nAtletica: %+d" % int(info.get("athletics_bonus", 0))
		)) + "\nApplica solo se la prova o il TS è stato risolto con successo."
	body.add_child(caption)
	if action_id != "help" and String(record.get("rules_version", "2014")) != "2024":
		var roll := Button.new()
		roll.text = "Tira Atletica con i dadi della scheda"
		roll.pressed.connect(func() -> void: _on_formula_roll_requested("skill:athletics"))
		body.add_child(roll)
	var picker := OptionButton.new()
	for target: CharacterBody3D in candidates:
		var target_name := String(target.call("get_display_name")) if target.has_method("get_display_name") else String(target.name)
		picker.add_item(target_name)
	body.add_child(picker)
	dialog.confirmed.connect(func() -> void:
		var index := picker.selected
		if index >= 0 and index < candidates.size():
			var victim: CharacterBody3D = candidates[index]
			var result: Dictionary = BasicCombat.execute(board_root, actor, victim, action_id, action_id != "help")
			_set_status("Azione eseguita." if bool(result.get("ok", false)) else String(result.get("error", "Azione non valida.")))
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)


func _on_formula_roll_requested(key: String) -> void:
	if key.begins_with("attack_hit:"):
		_roll_attack_from_sheet(key.trim_prefix("attack_hit:"), false)
		return
	if key.begins_with("attack_damage:"):
		_roll_attack_from_sheet(key.trim_prefix("attack_damage:"), true)
		return
	if key != "initiative" and not key.begins_with("ability_mod:") \
		and not key.begins_with("skill:") and not key.begins_with("save:"):
		return
	var record: Dictionary = _live_stats_record()
	if record.is_empty():
		return
	var label: String = String(record.get("name", "Creatura")) + " · "
	if key == "initiative":
		label += "Iniziativa"
	elif key.begins_with("ability_mod:"):
		label += "Caratteristica " + key.trim_prefix("ability_mod:").to_upper()
	elif key.begins_with("save:"):
		label += "Tiro salvezza " + key.trim_prefix("save:").to_upper()
	else:
		var skill_id: String = key.trim_prefix("skill:")
		label += skill_id.capitalize()
		for skill: Dictionary in Skills5e.SKILLS:
			if String(skill.get("id", "")) == skill_id:
				label = String(record.get("name", "Creatura")) + " · " + String(skill.get("label", skill_id))
				break
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller == null or not roller.has_method("roll_expression_from_sheet"):
		_set_status("Il lanciatore di dadi della chat non è disponibile.")
		return
	var modifier: int = BonusRules.value(record, key)
	_roll_with_optional_dice(label, "1d20%+d" % modifier, key, record)



func _roll_with_optional_dice(label: String, expression: String, key: String, record: Dictionary, forced_advantage: bool = false) -> void:
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller == null or not roller.has_method("roll_expression_from_sheet"):
		_set_status("Il lanciatore di dadi della chat non è disponibile.")
		return
	var applicable: Array[Dictionary] = DiceBonuses.applicable(record, key)
	# Bardic Inspiration is offered *after* the d20 has been rolled, as in
	# the rules. The base result remains visible in the shared roller chat.
	var feature_advantage := forced_advantage or ClassFeatures.roll_advantage(record, key)
	var base_result: int = (int(roller.call("roll_expression_from_sheet", label + " · Vantaggio (privilegio)", expression,
		find_linked_token_for_creature(_selected_id), "advantage")) if feature_advantage else int(roller.call(
		"roll_expression_from_sheet", label, expression, find_linked_token_for_creature(_selected_id))))
	if applicable.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Bonus al risultato · " + label
	dialog.ok_button_text = "Applica bonus"
	dialog.cancel_button_text = "Conserva il risultato"
	add_child(dialog)
	var panel := VBoxContainer.new()
	dialog.add_child(panel)
	var heading := Label.new()
	heading.text = "Risultato del tiro: %d. Scegli i dadi da aggiungere adesso; quelli monouso saranno consumati." % base_result
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(heading)
	var choices: Array[Dictionary] = []
	for entry: Dictionary in applicable:
		var checkbox := CheckBox.new()
		checkbox.text = "%s · %s" % [
			String(entry.get("origin_name", "Bonus")), String(entry.get("dice", ""))]
		panel.add_child(checkbox)
		choices.append({"check": checkbox, "entry": entry.duplicate(true)})
	dialog.confirmed.connect(_confirm_roll_with_dice.bind(label, base_result, key, choices, dialog))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	DialogLayout.popup(dialog, Vector2i(480, maxi(175, 110 + choices.size() * 38)))


func _confirm_roll_with_dice(label: String, base_result: int, key: String, choices: Array[Dictionary], dialog: ConfirmationDialog) -> void:
	var suffix := ""
	var consumed: Dictionary = {}
	var available: Dictionary = {}
	for current: Dictionary in DiceBonuses.applicable(_current(), key):
		available[String(current.get("id", ""))] = true
	for option: Dictionary in choices:
		var check: CheckBox = option.get("check")
		if check == null or not check.button_pressed:
			continue
		var entry: Dictionary = option.get("entry", {})
		var id: String = String(entry.get("id", ""))
		var dice: String = String(entry.get("dice", ""))
		if not available.has(id) or not DiceBonuses.valid_dice(dice):
			continue
		suffix += "+" + dice
		var spell_id: String = String(entry.get("consumes_spell", ""))
		if not spell_id.is_empty():
			consumed[spell_id] = true
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller == null or not roller.has_method("roll_expression_from_sheet") or suffix.is_empty():
		dialog.queue_free()
		return
	# A second roller event displays the *combined* result and its extra
	# dice explicitly; the original d20 roll remains inspectable.
	var total_expression: String = str(base_result) + suffix
	roller.call("roll_expression_from_sheet",
		label + " · risultato con bonus", total_expression,
		find_linked_token_for_creature(_selected_id))
	for spell_id: String in consumed.keys():
		_remove_active_spell("spell:" + spell_id)
	dialog.queue_free()


func _recalculate_bonus_mirrors(record: Dictionary) -> void:
	SheetController.recalculate_bonus_mirrors(record)


func _refresh_formula_dependents(record: Dictionary) -> void:
	var previous_loading: bool = _loading
	_loading = true
	for ability: String in _ability_spins.keys():
		_update_ability_modifier(ability)
	_loading = previous_loading
	_refresh_skill_values(record)
	if _action_economy_ui != null and _tabs != null and _tabs.get_tab_control(_tabs.current_tab).name == "Cosa posso fare?":
		_action_economy_ui.call("refresh_top_skills", _live_stats_record())
	_update_max_hp_display()
	_update_second_max_formula()
	_update_defense_display()
	_update_speed_display()
	_refresh_attacks(record)
	_refresh_trackers(record)



func _on_trackers_updated(trackers: Array, origins: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	SheetController.update_trackers(record, trackers, origins)
	SheetController.sync_origin_resources(record)
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare tracker e origini.")
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)
	_refresh_conditions(record)


func _on_bonuses_updated(rows: Array, origins: Array, feats: Array = [], dice_rows: Array = []) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	SheetController.update_bonuses(record, rows, origins, feats, dice_rows)
	SheetController.sync_origin_resources(record)
	SheetController.sync_automatic_progression(record)
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare i bonus.")
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)
	_refresh_conditions(record)


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
	if _natural_ac_formula != null:
		record["armor_natural_formula"] = _natural_ac_formula.text.strip_edges()
	if _max_hp != null:
		record["max_hp_base"] = int(_max_hp.value)
	if _second_form_max_hp != null:
		record["second_form_max_hp"] = int(_second_form_max_hp.value)
	if _speed != null:
		record["speed_base"] = (_speed_from_species()
			if String(record.get("kind", "character")) == "character" else int(_speed.value))
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


func _layout_physics_movement(physics: Control, speeds: Control, jumps: Control) -> void:
	if not is_instance_valid(physics) or not is_instance_valid(speeds) or not is_instance_valid(jumps):
		return
	# Account for the Physics panel's padding rather than sizing child groups
	# against its outer width (which could force an unnecessary wrap).
	var available: float = physics.size.x - 18.0
	if available < 1.0:
		return
	# Cell widths are 73 px plus 8 px of grid spacing. On medium widths,
	# arranging speeds in two rows lets the jumps occupy the otherwise empty
	# space to their right; on narrower sheets jumps wrap below all speeds.
	var columns: int = 5
	if available >= 865.0:
		columns = 5
	elif available >= 710.0:
		columns = 3
	elif available >= 610.0:
		columns = 2
	elif available < 397.0:
		columns = 3 if available >= 235.0 else 2
	var speed_grid: GridContainer = speeds.get_node_or_null("PhysicsSpeedGrid") as GridContainer
	if speed_grid != null and speed_grid.columns != columns:
		speed_grid.columns = columns
	var speeds_width: float = float(columns * 73 + (columns - 1) * 8)
	# The two jump captions need 210 px each with a 12 px gutter.
	# They can wrap separately at smaller widths without clipping values.
	var jumps_width: float = minf(432.0, available)
	if absf(speeds.custom_minimum_size.x - speeds_width) >= 1.0:
		speeds.custom_minimum_size.x = speeds_width
	if absf(jumps.custom_minimum_size.x - jumps_width) >= 1.0:
		jumps.custom_minimum_size.x = jumps_width


func _physics_field(parent: Node, caption: String, width: float) -> VBoxContainer:
	var field := VBoxContainer.new()
	field.custom_minimum_size.x = width
	field.add_theme_constant_override("separation", 3)
	parent.add_child(field)
	var heading := Label.new()
	heading.text = caption
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
	field.add_child(heading)
	return field


func _info_panel(parent: VBoxContainer, section: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	var frame_style := preload("res://vtt/creature_sheet_style.gd").section_style()
	frame.add_theme_stylebox_override("panel", frame_style)
	parent.add_child(frame)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	frame.add_child(content)
	var heading := Label.new()
	heading.text = section
	heading.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98))
	heading.add_theme_font_size_override("font_size", 17)
	var info_icons := {"IDENTITÀ": "identity", "FISICO": "physique", "CLASSI E PROGRESSIONE": "progression", "TALENTI": "talents", "STORIA E PERSONALITÀ": "biography"}
	if info_icons.has(section):
		preload("res://vtt/creature_sheet_style.gd").heading(heading, "info_" + String(info_icons[section]))
	else:
		_style_statistics_heading(heading)
	content.add_child(heading)
	return content


func _reference_option(
	parent: Node, choices: Array[Dictionary], show_source: bool = true,
	autosave: bool = true, category: String = ""
) -> OptionButton:
	var select := OptionButton.new()
	select.set_meta("catalog_category", category)
	select.item_selected.connect(func(_index: int) -> void: _update_reference_tooltip(select))
	select.get_popup().about_to_popup.connect(_populate_reference_popup.bind(select))
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
	option.set_meta("reference_popups_ready", false)
	_update_reference_tooltip(option)


func _reference_preview(option: OptionButton, entry: Dictionary) -> String:
	if entry.is_empty():
		return "Nessuna voce selezionata."
	var category: String = String(option.get_meta("catalog_category", ""))
	if category.is_empty():
		return String(entry.get("name", ""))
	var detailed: Dictionary = Player5eTools.detailed_entry(category, entry)
	var info: String = Player5eTools.info_text(
		detailed, Player5eTools.description_text(category, detailed)
	)
	# A tooltip is a preview; the compendium shows the entire text.
	if info.length() > 1500:
		info = info.substr(0, 1500) + "…"
	return info


func _update_reference_tooltip(option: OptionButton) -> void:
	if option == null or option.selected < 0:
		return
	var category: String = String(option.get_meta("catalog_category", ""))
	if category.is_empty():
		return
	option.tooltip_text = _reference_preview(option, _reference_entry(option))


func _populate_reference_popup(option: OptionButton) -> void:
	if bool(option.get_meta("reference_popups_ready", false)):
		return
	var category: String = String(option.get_meta("catalog_category", ""))
	if category.is_empty():
		return
	var popup: PopupMenu = option.get_popup()
	for i: int in range(1, option.item_count):
		var value: Variant = option.get_item_metadata(i)
		if value is Dictionary:
			popup.set_item_tooltip(i, _reference_preview(option, value))
	option.set_meta("reference_popups_ready", true)


func _background_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{
		"id": "__create_custom_background__", "name": "＋ Crea background personalizzato",
		"source": ""
	}]
	result.append_array(Player5eTools.entries("backgrounds"))
	return result


func _refresh_custom_background_actions() -> void:
	if _delete_custom_background != null:
		_delete_custom_background.visible = QuickCustom.is_custom(_reference_entry(_background))


func _on_background_chosen(index: int) -> void:
	if index == 1 and String(_reference_entry(_background).get("id", "")) == "__create_custom_background__":
		var selected: Dictionary = _current()
		_select_reference(_background, String(selected.get("background", "")),
			String(selected.get("background_source", "")), String(selected.get("background_id", "")))
		QuickCustomDialog.create_popup(_panel, "backgrounds", func(created: Dictionary) -> void:
			_set_reference_choices(_background, _background_choices())
			_select_reference(_background, String(created.get("name", "")),
				String(created.get("source", "")), String(created.get("id", "")))
			_refresh_custom_background_actions()
			_save()
		)
		return
	_refresh_custom_background_actions()
	_save()


func _delete_selected_custom_background() -> void:
	var selected: Dictionary = _reference_entry(_background)
	if not QuickCustom.is_custom(selected):
		return
	QuickCustomDialog.delete_popup(_panel, selected, func() -> void:
		_set_reference_choices(_background, _background_choices())
		_background.select(0)
		_refresh_custom_background_actions()
		_save()
	)


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
	var row: BoxContainer
	if _touch_layout:
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
	_multiclass_rows.add_child(row)
	if _touch_layout:
		_add_label(row, "Classe")
	var selector := _reference_option(row, Player5eTools.class_choices(_selected_rules_version()), false, false, "classes")
	_select_reference(selector, class_value, source, reference_id)
	selector.item_selected.connect(func(_i: int) -> void: _on_secondary_class_changed(row))
	if _touch_layout:
		_add_label(row, "Sottoclasse")
	var subclass := _reference_option(row, _subclass_choices(_reference_entry(selector)), false, true, "subclasses")
	subclass.item_selected.connect(func(_i: int) -> void: _save())
	if _touch_layout:
		row.add_theme_constant_override("separation", 4)
		for choice: OptionButton in [selector, subclass]:
			choice.custom_minimum_size.x = 0
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var action_row: Container = row
	if _touch_layout:
		action_row = HBoxContainer.new()
		row.add_child(action_row)
		_add_label(action_row, "Livello")
	action_row.add_child(level)
	var remove := Button.new()
	remove.text = "×"
	action_row.add_child(remove)
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


func _on_secondary_class_changed(row: BoxContainer) -> void:
	for definition: Dictionary in _multiclass_controls:
		if definition["row"] == row:
			_refresh_subclass_option(definition["subclass"], _reference_entry(definition["selector"]))
			_save()
			return


func _clear_multiclass() -> void:
	for definition: Dictionary in _multiclass_controls:
		var row: BoxContainer = definition["row"]
		_multiclass_rows.remove_child(row)
		row.queue_free()
	_multiclass_controls.clear()


func _select_reference(option: OptionButton, name: String, source: String = "", stable_id: String = "") -> void:
	option.select(0)
	if name.is_empty() and stable_id.is_empty():
		_update_reference_tooltip(option)
		return
	var fallback := -1
	for i: int in range(1, option.item_count):
		var row: Dictionary = option.get_item_metadata(i)
		if not stable_id.is_empty() and String(row.get("id", "")) == stable_id:
			option.select(i)
			_update_reference_tooltip(option)
			return
		if String(row.get("name", "")).nocasecmp_to(name) == 0:
			if source.is_empty() or String(row.get("source", "")) == source:
				option.select(i)
				_update_reference_tooltip(option)
				return
			if fallback < 0:
				fallback = i
	if fallback >= 0:
		option.select(fallback)
	_update_reference_tooltip(option)


func _reference_entry(option: OptionButton) -> Dictionary:
	var value: Variant = option.get_item_metadata(option.selected)
	return value as Dictionary if value is Dictionary else {}


func _reload() -> void:
	# Preserve the remembered choice if an earlier empty refresh cleared the UI.
	if _selected_id.is_empty() and not _last_selected_id.is_empty():
		_selected_id = _last_selected_id
		_selected_kind = _last_selected_kind
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
	_creature_batch_checks.clear()
	_creature_eye_buttons.clear()
	var live_keys: Dictionary = {}
	for record: Dictionary in _records:
		live_keys[_creature_batch_key(record)] = true
	for key: Variant in _creature_batch_ids.keys():
		if not live_keys.has(key):
			_creature_batch_ids.erase(key)

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
		var batch_check := CheckBox.new()
		batch_check.tooltip_text = "Seleziona per esportazione o eliminazione multipla"
		batch_check.custom_minimum_size.x = 24
		batch_check.button_pressed = _creature_batch_ids.has(_creature_batch_key(item))
		batch_check.toggled.connect(_on_creature_batch_toggled.bind(_creature_batch_key(item)))
		row.add_child(batch_check)
		_creature_batch_checks.append(batch_check)
		var select_button := Button.new()
		select_button.set_meta("creature_gui_data", true)
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
	_update_creature_batch_actions()
	_refresh_creature_eye_buttons()
	if selected_index < 0 and not _records.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_on_selected(selected_index)
	else:
		_selected_id = ""
		_selected_kind = ""
		_loading = true
		_traits_ui.call("load_record", {})
		_bonuses_ui.call("load_record", {})
		_trackers_ui.call("load_record", {})
		_loading = false


# Archive multi-selection is independent from the open sheet and the scene.
static func _creature_batch_key(record: Dictionary) -> String:
	return String(record.get("kind", "")) + ":" + String(record.get("id", ""))


func _on_creature_batch_toggled(checked: bool, key: String) -> void:
	if checked:
		_creature_batch_ids[key] = true
	else:
		_creature_batch_ids.erase(key)
	_update_creature_batch_actions()


func _mark_visible_creatures(checked: bool) -> void:
	for index: int in range(_creature_batch_checks.size()):
		var checkbox: CheckBox = _creature_batch_checks[index]
		if checked and not checkbox.get_parent().visible:
			continue
		var key := _creature_batch_key(_records[index])
		if checked:
			_creature_batch_ids[key] = true
		else:
			_creature_batch_ids.erase(key)
		checkbox.set_pressed_no_signal(_creature_batch_ids.has(key))
	_update_creature_batch_actions()


func _selected_creature_batch() -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	for record: Dictionary in _records:
		if _creature_batch_ids.has(_creature_batch_key(record)):
			batch.append(record.duplicate(true))
	return batch


func _update_creature_batch_actions() -> void:
	if _batch_export_button == null:
		return
	var count := _selected_creature_batch().size()
	# Bulk actions only occupy space after a checkbox is selected.
	_creature_batch_selection_row.visible = count > 0
	_creature_batch_actions_row.visible = count > 0
	_batch_export_button.disabled = count == 0
	_batch_delete_button.disabled = count == 0
	_batch_export_button.text = "Esporta (%d)" % count if count > 0 else "Esporta selezione"
	_batch_delete_button.text = "Elimina (%d)" % count if count > 0 else "Elimina selezione"


func _export_selected_creatures() -> void:
	_save()
	_batch_export_pending = _selected_creature_batch()
	if _batch_export_pending.is_empty():
		return
	_export_dialog.title = "Esporta creature selezionate"
	_export_dialog.current_file = "creature_selezionate.json"
	_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	DialogLayout.popup(_export_dialog, Vector2i(820, 550), 0.9)


func _save_batch_export(path: String) -> void:
	var entries: Array[Dictionary] = []
	for record: Dictionary in _batch_export_pending:
		var missing: Array[String] = PortableContent.unresolved(record)
		if not missing.is_empty():
			_set_status("Esportazione annullata: homebrew mancante in %s." % String(record.get("name", "")))
			_batch_export_pending.clear()
			return
		var companions: Array[Dictionary] = PortableContent.bundle(record)
		if companions.size() > PortableContent.MAX_ENTRIES or JSON.stringify(companions).to_utf8_buffer().size() > PortableContent.MAX_BYTES:
			_set_status("Esportazione annullata: homebrew troppo voluminoso in %s." % String(record.get("name", "")))
			_batch_export_pending.clear()
			return
		entries.append({"format": "vtt_creature_export_v1", "version": 1,
			"creature": record, "homebrew_content": companions})
	var export_text := JSON.stringify({"format": "vtt_creature_batch_export_v1",
		"version": 1, "entries": entries}, "  ")
	_batch_export_pending.clear()
	if export_text.to_utf8_buffer().size() > 16 * 1024 * 1024:
		_set_status("Esportazione annullata: il file supera 16 MB.")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Esportazione non riuscita: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(export_text)
	var error := file.get_error()
	file.close()
	_set_status("Esportate %d creature: %s" % [entries.size(), path] if error == OK
		else "Esportazione fallita: " + error_string(error))


func _build_batch_delete_dialog() -> void:
	_batch_delete_dialog = ConfirmationDialog.new()
	_batch_delete_dialog.title = "Elimina più creature"
	_batch_delete_dialog.confirmed.connect(_delete_creature_batch)
	ui_root.add_child(_batch_delete_dialog)


func _confirm_batch_delete() -> void:
	_save()
	_batch_delete_pending = _selected_creature_batch()
	if _batch_delete_pending.is_empty():
		return
	_batch_delete_dialog.dialog_text = (
		"Eliminare definitivamente %d creature dal tuo archivio?\n"
		+ "Verranno rimossi anche i relativi token in scena.\n"
		+ "Questa operazione non può essere annullata."
	) % _batch_delete_pending.size()
	_popup_sheet_dialog(_batch_delete_dialog, Vector2i(520, 285), 0.92)


func _delete_creature_batch() -> void:
	var batch := _batch_delete_pending.duplicate(true)
	_batch_delete_pending.clear()
	var completed := 0
	var failed := 0
	for record: Dictionary in batch:
		var result: Error = _archive.delete(record)
		if result != OK:
			failed += 1
			continue
		_remove_deleted_creature_tokens(record)
		_creature_batch_ids.erase(_creature_batch_key(record))
		completed += 1
		if _selected_id == String(record.get("id", "")) and _selected_kind == String(record.get("kind", "")):
			_selected_id = ""
			_selected_kind = ""
	_reload()
	_set_status("Eliminate %d creature e i loro token. Errori: %d." % [completed, failed])


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


func _update_statistics_widths() -> void:
	if _touch_layout:
		for child: Control in _statistics_columns.get_children():
			child.custom_minimum_size.x = 0
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return
	if _statistics_columns == null or _statistics_columns.get_child_count() != 2:
		return
	var left_view := _statistics_columns.get_child(0) as Control
	var right_view := _statistics_columns.get_child(1) as Control
	var margin := _statistics_columns.get_parent().get_parent() as MarginContainer
	var scroll := margin.get_parent() as ScrollContainer
	var viewport_width := scroll.size.x - margin.get_theme_constant("margin_left") - margin.get_theme_constant("margin_right")
	if scroll.get_v_scroll_bar().visible:
		viewport_width -= scroll.get_v_scroll_bar().size.x
	var available := maxf(0.0, viewport_width - 9.0)
	var left_needed := (left_view.get_child(0) as Control).get_combined_minimum_size().x
	var right_needed := (right_view.get_child(0) as Control).get_combined_minimum_size().x
	var editor_columns: Array[HBoxContainer] = []
	for editor: Control in [_proficiencies_ui, _feats_ui, _bonuses_ui, _trackers_ui, _damage_defenses_ui]:
		if not editor.visible:
			continue
		var columns := editor.get_node("EditorColumns") as HBoxContainer
		editor_columns.append(columns)
		# Ignore the width assigned on the previous layout pass.
		left_needed = maxf(left_needed, (columns.get_child(0) as Control).get_minimum_size().x)
		right_needed = maxf(right_needed, (columns.get_child(1) as Control).get_combined_minimum_size().x)
	var left_width := floorf(clampf(available * 0.45, minf(left_needed, available * 0.45), maxf(left_needed, available - right_needed)))
	# If both contents fit, reserve all the width needed on the right before
	# leaving spare space on the left. Very small windows retain local scrolling.
	if left_needed + right_needed <= available:
		left_width = floorf(clampf(available * 0.45, left_needed, available - right_needed))
	if not is_equal_approx(left_view.custom_minimum_size.x, left_width):
		left_view.custom_minimum_size.x = left_width
	for columns: HBoxContainer in editor_columns:
		var panel := columns.get_child(0) as Control
		if panel.size_flags_horizontal != Control.SIZE_FILL:
			panel.size_flags_horizontal = Control.SIZE_FILL
		if not is_equal_approx(panel.custom_minimum_size.x, left_width):
			panel.custom_minimum_size.x = left_width


func _update_stats_column_heights() -> void:
	_update_statistics_widths()
	if _touch_layout and _statistics_columns != null:
		var views: Array = _statistics_columns.get_children()
		if is_instance_valid(_touch_combat_view):
			views.append(_touch_combat_view)
		for view: ScrollContainer in views:
			view.custom_minimum_size.y = (view.get_child(0) as Control).get_combined_minimum_size().y + 18
		return
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
	# Header and each ability consist of four cells (ability, score, modifier,
	# saving throw). Forcing five here misaligns all rows and inflates the
	# column minimum width, causing unnecessary horizontal scrolling.
	if _abilities_grid.columns != 4:
		_abilities_grid.columns = 4


func _on_selected(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	var record := _records[index]
	_selected_id = String(record.get("id", ""))
	_selected_kind = String(record.get("kind", ""))
	_remember_creature_selection()
	for i: int in range(_creature_row_buttons.size()):
		_creature_row_buttons[i].set_pressed_no_signal(i == index)
	_load_form(record)
	# Some tabs rebuild their section headings when a creature is selected.
	# Reapply the selected locale after those dynamic controls exist.
	call_deferred("_refresh_creature_language")


func _load_form(record: Dictionary) -> void:
	_origin_preview_cache.clear()
	# Empty hands are intentional. Loading a sheet never auto-equips weapons.
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
	_refresh_info_feats(record)
	_ac.value = maxi(0, int(record.get("armor_class_base", record.get("armor_class", 10))))
	if _natural_ac_formula != null:
		var default_ac_formula: String = str(record.get("armor_class_base", 10))
		if String(record.get("kind", "")) == "monster":
			default_ac_formula = str(Rules.monster_armor_class(record.get("stat_block", {})))
		elif int(record.get("armor_class_base", 10)) == 10:
			default_ac_formula = "10 + dex_mod"
		_natural_ac_formula.text = String(record.get("armor_natural_formula", default_ac_formula))
	# Initiative depends on DEX: compute only after ability controls load.
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
	_update_defense_display()
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
	(_subrace_choice.get_parent() as Control).visible = is_character
	(_challenge_rating.get_parent() as Control).visible = not is_character
	var challenge: Variant = record.get("stat_block", {}).get("cr", "0")
	_challenge_rating.text = String(challenge.get("cr", "0") if challenge is Dictionary else challenge)
	_refresh_creature_type(record)
	_set_reference_choices(_background, _background_choices())
	_select_reference(_background, String(record.get("background", "")), String(record.get("background_source", "")), String(record.get("background_id", "")))
	_refresh_custom_background_actions()
	_speed_custom = bool(record.get("speed_is_custom", false))
	var source_speed: int = (Rules.walking_speed(_effective_species().get("speed", 30))
		if is_character else Rules.walking_speed(record.get("stat_block", {}).get("speed", 30)))
	_speed.value = maxi(0, int(record.get("speed_base", record.get("speed", source_speed))) if _speed_custom and not is_character else source_speed)
	_speed.editable = not is_character
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
	_xp.value = maxi(int(record.get("xp", 0)), Rules.minimum_experience(record))
	_level.tooltip_text = "Livello della classe base; per i mostri ogni livello aumenta il GS effettivo di 1"
	_default_miniature_id = String(record.get("default_miniature_id", ""))
	_default_miniature.text = _miniature_display_name(_default_miniature_id)
	_update_current_appearance_display(record)
	_select_sheet_size(String(record.get("size_name", "Medium")))
	_front.select(clampi(int(record.get("visual_front_quarter_turns", 0)), 0, 3))
	_party.text = String(record.get("party_id", ""))
	while _alignment.item_count > ALIGNMENT_OPTIONS.size():
		_alignment.remove_item(_alignment.item_count - 1)
	var saved_alignment: String = String(record.get("alignment", "")).strip_edges()
	if saved_alignment.is_empty():
		saved_alignment = "Completamente neutrale"
	var alignment_index: int = ALIGNMENT_OPTIONS.find(saved_alignment)
	if alignment_index < 0:
		# Preserve imported homebrew alignments until explicitly changed.
		_alignment.add_item(saved_alignment)
		alignment_index = _alignment.item_count - 1
	_alignment.select(alignment_index)
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
	_action_economy_ui.call("load_record", record)
	_spellcasting_ui.call("load_record", record)
	_origin_spells_stale = true
	if _origin_spells_ui != null and _origin_spells_ui.visible:
		_origin_spells_ui.call("load_record", record)
		_origin_spells_stale = false
	_inventory_ui.call("load_record", record)
	_feats_stale = true
	if _feats_ui != null and _feats_ui.visible:
		_feats_ui.call("load_record", record)
		_feats_stale = false
	_bonuses_stale = true
	if _bonuses_ui.visible:
		_bonuses_ui.call("load_record", record)
		_bonuses_stale = false
	_trackers_stale = true
	if _trackers_ui != null and _trackers_ui.visible:
		_trackers_ui.call("load_record", record)
		_trackers_stale = false
	_refresh_choice_warnings(record)
	_loading = false


func _on_info_feat_input(event: InputEvent, origin_id: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	get_viewport().set_input_as_handled()
	_show_sheet_tab("Modifica personaggio")
	_select_details_editor(2)
	_feats_ui.call("focus_origin", origin_id)
	call_deferred("_scroll_origins_to_top")


# Info is only a read-only index of feat grants. Editing, removing and muting
# all stay in Statistics → View and edit → Feats.
func _refresh_info_feats(record: Dictionary) -> void:
	if _info_feats_list == null:
		return
	for child: Node in _info_feats_list.get_children():
		_info_feats_list.remove_child(child)
		child.queue_free()
	var raw_feats: Variant = record.get("feats_catalog", [])
	if not raw_feats is Array or (raw_feats as Array).is_empty():
		var empty := Label.new()
		empty.text = "Nessun talento."
		_info_feats_list.add_child(empty)
		return
	var origin_names: Dictionary = {}
	for source: Dictionary in ProficiencyRules.origins(record):
		origin_names[String(source.get("id", ""))] = String(source.get("name", ""))
	var enabled: Dictionary = ProficiencyRules.origin_enabled_map(record)
	var grouped: Dictionary = {}
	var ordered: Array[String] = []
	for raw: Variant in raw_feats:
		if not raw is Dictionary:
			continue
		var feat: Dictionary = raw
		var feat_id: String = ProficiencyRules.feat_source_id(feat)
		if feat_id.is_empty():
			continue
		if not grouped.has(feat_id):
			grouped[feat_id] = {"feat": feat, "active": false,
				"origin_id": String(feat.get("origin_id", "")), "sources": []}
			ordered.append(feat_id)
		var row: Dictionary = grouped[feat_id]
		var parent_id: String = String(feat.get("origin_id", ""))
		var origin_label: String = String(origin_names.get(parent_id, feat.get(
			"origin_name", parent_id)))
		if parent_id.is_empty():
			origin_label = "Senza origine"
		elif origin_label.is_empty():
			origin_label = parent_id
		var is_active: bool = (not bool(feat.get("disabled", false))
			and bool(enabled.get(parent_id, true))
			and bool(enabled.get(feat_id, true)))
		var sources: Array = row["sources"]
		var source_line: String = ("✓ " if is_active else "○ ") + origin_label
		if source_line not in sources:
			sources.append(source_line)
		if is_active:
			row["active"] = true
			row["origin_id"] = parent_id
	if ordered.is_empty():
		var empty := Label.new()
		empty.text = "Nessun talento."
		_info_feats_list.add_child(empty)
		return
	for feat_id: String in ordered:
		var item: Dictionary = grouped[feat_id]
		var feat: Dictionary = item["feat"]
		var panel := PanelContainer.new()
		_info_feats_list.add_child(panel)
		var label := Label.new()
		label.text = ("• " if bool(item["active"]) else "○ ") + String(feat.get("name", "Talento"))
		var source_book: String = String(feat.get("source", ""))
		if not source_book.is_empty():
			label.text += " · " + source_book
		if not bool(item["active"]):
			label.modulate.a = 0.65
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.tooltip_text = String(_feats_ui.call("_feat_description", feat)) + (
			"\n\nOrigini:\n" + "\n".join(PackedStringArray(item["sources"]))
			+ "\n\nClic destro per vedere le origini nella sezione Talenti."
		)
		label.gui_input.connect(_on_info_feat_input.bind(String(item["origin_id"])))
		panel.add_child(label)


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


func _refresh_total_class_level_label() -> void:
	if _total_level_display != null:
		var title: String = "Total level" if _creature_language == "en" else "Livello totale"
		_total_level_display.text = "%s: %d" % [title, _class_xp_level()]


func _refresh_xp_minimum() -> void:
	_refresh_total_class_level_label()
	if _xp == null:
		return
	var record: Dictionary = _current()
	var minimum: int = Rules.experience_for_level(_class_xp_level())
	if String(record.get("kind", "character")) == "monster":
		var base_cr: float = Rules.monster_cr_value({"cr": _challenge_rating.text})
		var effective_cr: float = base_cr + float(_class_xp_level())
		minimum = Rules.monster_experience_for_cr(effective_cr)
		_challenge_caption.text = "GS · eff. %s" % str(effective_cr)
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
	if _loading or String(_current().get("kind", "")) == "character":
		return
	_speed_custom = true
	_save()


func _update_speed_display() -> void:
	if _speed_effective == null or _speed == null:
		return
	var live: Dictionary = _live_stats_record()
	if live.is_empty():
		return
	# The character's effective species/subrace is resolved from the active
	# 5etools selection, not from a stale serialized movement copy.
	if String(live.get("kind", "character")) != "monster":
		live["species_speed"] = _effective_species().get("speed", {})
	var walk_base: int = int(_speed.value)
	var walk_bonus: int = BonusRules.bonus(live, "speed")
	var walk_total: int = maxi(0, BonusRules.value(live, "speed"))
	_set_formula("speed", str(walk_total),
		"Camminata: base %d + bonus cumulabili %+d = %d ft" % [
			walk_base, walk_bonus, walk_total])
	for mode: String in Rules.SPECIAL_SPEEDS:
		if not _special_speed_labels.has(mode):
			continue
		var label: String = {"climb": "Scalata", "swim": "Nuoto",
			"fly": "Volo", "burrow": "Scavo"}[mode]
		var base: int = Rules.special_speed_base(live, mode)
		var specific: int = BonusRules.bonus(live, "speed:" + mode)
		var inherited: int = (walk_bonus
			if base > 0 and String(live.get("rules_version", "2014")) == "2024" else 0)
		var total: int = maxi(0, BonusRules.value(live, "speed:" + mode))
		var explanation := "%s: base %d + bonus specifici %+d" % [label, base, specific]
		if inherited != 0:
			explanation += " + modifica alla velocità (regole 2024) %+d" % inherited
		explanation += " = %d ft" % total
		if base == 0 and specific == 0:
			explanation += "\nNessuna velocità speciale concessa; scalare o nuotare è comunque possibile con il normale costo aggiuntivo di movimento."
		_set_formula("speed:" + mode, "%d" % total, explanation)
	if _long_jump == null or _high_jump == null:
		return
	var strength: int = maxi(0, BonusRules.value(live, "ability:str"))
	var modifier: int = BonusRules.value(live, "ability_mod:str")
	var running_high: int = maxi(0, 3 + modifier)
	var standing_long: String = str(float(strength) / 2.0).trim_suffix(".0").replace(".", ",")
	var standing_high: String = str(float(running_high) / 2.0).trim_suffix(".0").replace(".", ",")
	_long_jump.text = ("SALTO IN LUNGO\n"
		+ "Con rincorsa (almeno 10 ft): %d ft\n" % strength
		+ "Da fermo (senza rincorsa): %s ft" % standing_long)
	_long_jump.tooltip_text = ("Con almeno 10 ft di movimento a piedi immediatamente prima del salto, "
		+ "puoi saltare fino al punteggio di Forza (%d ft). Da fermo il massimo è la metà (%s ft). "
		% [strength, standing_long]
		+ "Ogni ft saltato consuma 1 ft del movimento disponibile.")
	_high_jump.text = ("SALTO IN ALTO\n"
		+ "Con rincorsa (almeno 10 ft): %d ft\n" % running_high
		+ "Da fermo (senza rincorsa): %s ft" % standing_high)
	_high_jump.tooltip_text = ("Con rincorsa di almeno 10 ft: max(0, 3 + modificatore FOR %+d) = %d ft. "
		% [modifier, running_high]
		+ "Senza rincorsa la distanza è dimezzata (%s ft). "
		% standing_high
		+ "Puoi raggiungere con le braccia altri 1,5 × la tua altezza. "
		+ "Il salto consuma il movimento disponibile.")


# The creature sheet casts from class, available and searched spells alike.
# When no linked token or VTT effect exists, casting still records slot use.
func _on_spellcasting_cast_requested(spell: Dictionary, slot_level: int, grant: Dictionary = {}) -> bool:
	if ClassFeatures.is_active(_current(), "rage") and String(spell.get("action_kind", "spell")) != "ability":
		_set_status("Non puoi lanciare incantesimi mentre sei in Ira.")
		return false
	if _current().is_empty():
		_mobile_cast_pending = false
		return false
	_pending_metamagic_cast.clear()
	if spell.get("metamagic", {}) is Dictionary and not (spell.get("metamagic", {}) as Dictionary).is_empty():
		var plan := Metamagic.plan(_current(), spell, slot_level, spell.metamagic)
		if not bool(plan.get("ok", false)):
			_set_status(String(plan.get("message", "")))
			return false
		spell = plan.spell
		_pending_metamagic_cast = {"creature_id": _selected_id, "spell_id": spell.get("id", ""),
			"cost": plan.cost, "tracker": plan.tracker}
	var spell_name: String = String(spell.get("name", "Incantesimo"))
	var spell_id: String = String(spell.get("id", ""))
	var source: String = String(spell.get("source", ""))
	if not grant.is_empty():
		# Only cast the entitlement from the currently active origin; never
		# trust a stale UI card after an item/feature has been removed.
		var current_record: Dictionary = _current()
		var skip_payment: bool = bool(grant.get("skip_payment", false))
		var valid := false
		for available: Dictionary in OriginSpells.all_grants(current_record):
			if String(available.get("id", "")) == String(grant.get("id", "")) and String(available.get("spell_id", "")) == spell_id:
				grant = available
				valid = true
				break
		grant["skip_payment"] = skip_payment
		if not valid or (not skip_payment and OriginSpells.remaining(current_record, grant) == 0):
			_set_status("Origine o utilizzi dell'incantesimo non disponibili.")
			_mobile_cast_pending = false
			return false
		_pending_origin_spell_cast = {
			"creature_id": String(current_record.get("id", "")),
			"spell_id": spell_id, "grant": grant.duplicate(true),
			"context": OriginSpells.cast_context(current_record, spell_id, grant)
		}
	else:
		_pending_origin_spell_cast.clear()
	if board_root.has_method("start_mobile_spell"):
		var queued: bool = bool(board_root.call("start_mobile_spell", _current(), spell, slot_level,
			_sheet_casting_context(_current(), spell, grant), _mobile_slot_choice))
		if not queued:
			_mobile_cast_pending = false
			_pending_origin_spell_cast.clear()
		return false
	var caster: CharacterBody3D = find_linked_token_for_creature(_selected_id)
	var runtime: Node = board_root.get_node_or_null("SpellSystem")
	# A targeted grant without a token cannot apply its effect: do not spend
	# its limited use pretending that the targeted ability was resolved.
	if not grant.is_empty() and (caster == null or runtime == null):
		_pending_origin_spell_cast.clear()
		_set_status("Collega la creatura a un token per applicare questo privilegio.")
		return false
	if caster == null or runtime == null or not runtime.has_method("has_runtime_spell_effect"):
		_start_sheet_concentration(spell)
		_complete_metamagic_cast(null, spell)
		if not grant.is_empty():
			_complete_origin_spell_cast(null, spell)
		_set_status("%s lanciato · effetto VTT non attivabile senza un token collegato." % spell_name)
		return true
	if not bool(runtime.call("has_runtime_spell_effect", spell_id, spell_name, source)):
		_start_sheet_concentration(spell)
		_complete_metamagic_cast(null, spell)
		if not grant.is_empty():
			_complete_origin_spell_cast(caster, spell)
		_set_status("%s lanciato · nessun effetto VTT associato." % spell_name)
		return true
	# Return to the board before entering the existing target-selection mode.
	hide_panel()
	var casting_context := _sheet_casting_context(_current(), spell, grant)
	var activated: bool = bool(runtime.call(
		"activate_spell_from_caster", spell_id, caster, spell_name, source, slot_level, casting_context
	))
	if not activated:
		_pending_metamagic_cast.clear()
		_pending_origin_spell_cast.clear()
		show_panel()
		_set_status("Impossibile attivare l'effetto VTT di %s." % spell_name)
	return activated



# SpellSystem calls the board only when target selection commits. Esc never
# reaches this method, so no tracker use is spent on a cancelled cast.
func _pending_cast_matches(caster: Node3D, spell: Dictionary) -> bool:
	if _pending_origin_spell_cast.is_empty():
		return false
	if String(_pending_origin_spell_cast.get("spell_id", "")) != String(spell.get("id", "")):
		return false
	if caster == null:
		return true
	return String(caster.get_meta("creature_id", "")) == String(_pending_origin_spell_cast.get("creature_id", ""))


func origin_spell_cast_context(caster: Node3D, spell: Dictionary) -> Dictionary:
	if _pending_cast_matches(caster, spell):
		return (_pending_origin_spell_cast.get("context", {}) as Dictionary).duplicate(true)
	return {}


func complete_origin_spell_cast(caster: Node3D, spell: Dictionary) -> void:
	_complete_origin_spell_cast(caster, spell)


func cancel_origin_spell_cast(caster: Node3D, spell: Dictionary) -> void:
	if _metamagic_cast_matches(caster, spell): _pending_metamagic_cast.clear()
	if _pending_cast_matches(caster, spell):
		_pending_origin_spell_cast.clear()


func _metamagic_cast_matches(caster: Node3D, spell: Dictionary) -> bool:
	return not _pending_metamagic_cast.is_empty() and String(_pending_metamagic_cast.get("spell_id", "")) == String(spell.get("id", "")) and (caster == null or String(caster.get_meta("creature_id", "")) == String(_pending_metamagic_cast.get("creature_id", "")))


func _complete_metamagic_cast(caster: Node3D, spell: Dictionary) -> void:
	if not _metamagic_cast_matches(caster, spell): return
	var pending := _pending_metamagic_cast.duplicate(true)
	_pending_metamagic_cast.clear()
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != String(pending.creature_id): continue
		if not ClassFeatures.spend(record, pending.tracker, int(pending.cost)):
			_set_status("Punti stregoneria non più disponibili.")
			return
		if _archive.save(record) == OK:
			_update_external_record(record)
			_set_status("Metamagia applicata · %d punti stregoneria." % int(pending.cost))
		return


func _complete_origin_spell_cast(caster: Node3D, spell: Dictionary) -> void:
	_complete_metamagic_cast(caster, spell)
	if not _pending_cast_matches(caster, spell):
		return
	var pending: Dictionary = _pending_origin_spell_cast.duplicate(true)
	_pending_origin_spell_cast.clear()
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != String(pending.get("creature_id", "")):
			continue
		var entitlement: Dictionary = pending.get("grant", {})
		if not OriginSpells.spend(record, entitlement):
			_set_status("Tracker esaurito: incantesimo concesso senza consumo.")
			return
		if _archive.save(record) != OK:
			_set_status("Impossibile salvare il consumo del tracker.")
			return
		_update_external_record(record)
		if String(record.get("id", "")) == _selected_id:
			_refresh_trackers(record)
			if _action_economy_ui != null:
				_action_economy_ui.call("load_record", record)
			if _spellcasting_ui != null:
				_spellcasting_ui.call("load_record", record)
		return


# A non-visual cast (or an unlinked caster) still starts concentration.
# Targeted VTT casts are committed by SpellSystem only after resolution.
func _start_sheet_concentration(spell: Dictionary) -> void:
	if not ActiveSpells.requires_concentration(spell):
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var spell_id: String = String(spell.get("id", ""))
	if spell_id.is_empty():
		return
	record["concentrating_spell_id"] = spell_id
	var active: Array = record.get("conditions", []).duplicate()
	if not ("concentrating" in active):
		active.append("concentrating")
	record["conditions"] = active
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_refresh_conditions(record)
		_spellcasting_ui.call("refresh_spell_state", record)
		_sync_token_health(record)


# The board invokes these methods for any cast/context change. Only locally
# owned sheets may be changed; foreign token appearances still synchronize.
func update_token_spell_effect(token: Node3D, spell_id: String, enabled: bool, context: Dictionary = {}) -> bool:
	if token == null or not is_instance_valid(token):
		return false
	if String(token.get_meta("creature_owner_id", "")) != Owner.local_id():
		return false
	var creature_id: String = String(token.get_meta("creature_id", ""))
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != creature_id:
			continue
		var changed: bool = (
			ActiveSpells.apply(record, spell_id, context) if enabled
			else ActiveSpells.remove(record, "spell:" + spell_id)
		)
		if not changed:
			return false
		_recalculate_bonus_mirrors(record)
		if _archive.save(record) != OK:
			return false
		_update_external_record(record)
		_sync_token_health(record)
		return true
	return false


func update_token_concentration(token: Node3D, spell_id: String) -> bool:
	if token == null or not is_instance_valid(token):
		return false
	if String(token.get_meta("creature_owner_id", "")) != Owner.local_id():
		return false
	var creature_id: String = String(token.get_meta("creature_id", ""))
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != creature_id:
			continue
		record["concentrating_spell_id"] = spell_id
		var conditions: Array = record.get("conditions", []).duplicate()
		conditions.erase("concentrating")
		if not spell_id.is_empty():
			conditions.append("concentrating")
		record["conditions"] = conditions
		if _archive.save(record) != OK:
			return false
		_update_external_record(record)
		_sync_token_health(record)
		return true
	return false


func _update_external_record(record: Dictionary) -> void:
	var creature_id: String = String(record.get("id", ""))
	for index: int in range(_records.size()):
		if String(_records[index].get("id", "")) == creature_id:
			_records[index] = record.duplicate(true)
			break
	if creature_id == _selected_id:
		_refresh_conditions(record)
		if _touch_layout:
			_update_current_appearance_display(record)
		if _spellcasting_ui != null:
			_spellcasting_ui.call("refresh_spell_state", record)


func _on_spellcasting_updated(values: Dictionary) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var concentration_changed: bool = (
		values.has("concentrating_spell_id") or values.has("conditions")
	)
	for key: String in [
		"spells", "prepared_spells", "spellbook_spells", "resource_tracker_spent",
		"resource_recovery_ready", "resource_recovery_used",
		"spell_slots_total", "spell_slots_spent", "spell_slots_manual", "spell_slots_automatic",
		"pact_slots_total", "pact_slots_spent", "pact_slot_level",
		"spell_slots_visible", "pact_slots_visible",
		"spellcasting_ability", "spellcasting_section_abilities", "concentrating_spell_id", "conditions", "origin_spell_grants", "origin_spell_configs"
	]:
		if values.has(key):
			record[key] = values[key]
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio incantesimi non riuscito: " + error_string(error))
		return
	_replace_current_record(record)
	if _spellcasting_ui != null:
		_spellcasting_ui.call("refresh_spell_state", record)
	if values.has("origin_spell_grants") or values.has("origin_spell_configs"):
		_origin_spells_stale = true
	if values.has("resource_tracker_spent"):
		_refresh_trackers(record)
	if concentration_changed:
		_refresh_conditions(record)
		_sync_token_health(record)


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
		(_skill_buttons[key] as Label).tooltip_text = ["Nessuna competenza", "Competenza", "Maestria"][clampi(rank, 0, 2)] + " · Modifica da Visualizza e modifica → Competenze"
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


# A hand is a separate choice of none, special strike, shield or owned item.
# Physical equipment remains stored in equipped_slots on the inventory row.
func _offhand_locked(record: Dictionary) -> bool:
	var main: Dictionary = ItemRules.occupying(record.get("inventory", []), "main")
	if main.is_empty():
		return false
	var entry: Dictionary = ItemRules.entry_for(main)
	return ItemRules.kind(entry) == "weapon" and (ItemRules.is_two_handed(entry) or bool(record.get("hand_grip_two_handed", false)))


func _refresh_weapon_picker(record: Dictionary) -> void:
	_refresh_equipment_pickers(record)


func _refresh_equipment_pickers(record: Dictionary) -> void:
	if _hand_main_picker == null or _hand_off_picker == null or _armor_picker == null:
		return
	var raw: Variant = record.get("inventory", [])
	var inventory: Array = raw if raw is Array else []
	_armor_picker.clear()
	_armor_options.clear()
	_armor_picker.add_item("Naturale")
	_armor_options.append({"kind": "none"})
	var selected_armor: int = 0
	for index: int in range(inventory.size()):
		if not inventory[index] is Dictionary:
			continue
		var owned: Dictionary = inventory[index]
		if int(owned.get("quantity", 0)) <= 0:
			continue
		var entry: Dictionary = ItemRules.entry_for(owned)
		if ItemRules.kind(entry) != "armor":
			continue
		_armor_picker.add_item(String(entry.get("name", owned.get("name", "Armatura"))))
		_armor_options.append({"kind": "item", "index": index})
		if "body" in ItemRules.slots(owned):
			selected_armor = _armor_options.size() - 1
	_armor_picker.select(selected_armor)
	for hand: String in ["main", "off"]:
		var picker: OptionButton = _hand_main_picker if hand == "main" else _hand_off_picker
		picker.clear()
		var choices: Array[Dictionary] = []
		if hand == "off" and _offhand_locked(record):
			picker.add_item("Occupata · due mani")
			picker.disabled = true
			_hand_options[hand] = choices
			continue
		picker.disabled = false
		for special: String in ["none", "unarmed", "improvised"]:
			var labels: Dictionary = {"none": "Niente", "unarmed": "Colpo senz'armi", "improvised": "Arma improvvisata"}
			var label: String = String(labels.get(special, special))
			picker.add_item(label)
			choices.append({"kind": "special", "value": special})
		var occupied_index: int = -1
		for index: int in range(inventory.size()):
			if not inventory[index] is Dictionary:
				continue
			var owned: Dictionary = inventory[index]
			if int(owned.get("quantity", 0)) <= 0:
				continue
			var entry: Dictionary = ItemRules.entry_for(owned)
			var item_kind: String = ItemRules.kind(entry)
			if item_kind not in ["weapon", "shield"] or not ItemRules.valid_slot(entry, hand):
				continue
			var is_selected: bool = hand in ItemRules.slots(owned)
			if hand == "off" and item_kind == "weapon" and _show_offhand_all.button_pressed and not ItemRules.has_property(entry, "F") and not is_selected:
				continue
			var item_name: String = String(entry.get("name", owned.get("name", "Oggetto")))
			var grips: Array = [false]
			if item_kind == "weapon" and hand == "main" and ItemRules.has_property(entry, "V"):
				grips = [false, true]
			elif item_kind == "weapon" and ItemRules.is_two_handed(entry):
				grips = [true]
			for grip: Variant in grips:
				var two_hands: bool = bool(grip)
				picker.add_item(item_name + (" · due mani" if two_hands else " · una mano") if item_kind == "weapon" else item_name)
				choices.append({"kind": "item", "index": index, "two_handed": two_hands})
				if is_selected and (item_kind != "weapon" or (two_hands == (bool(record.get("hand_grip_two_handed", false)) or ItemRules.is_two_handed(entry)))):
					occupied_index = choices.size() - 1
		var special_value: String = String(record.get("hand_" + hand + "_special", "none"))
		var selected: int = 0
		if occupied_index >= 0:
			selected = occupied_index
		elif special_value == "unarmed":
			selected = 1
		elif special_value == "improvised":
			selected = 2
		picker.select(selected)
		_hand_options[hand] = choices


func _on_hand_selected(index: int, hand: String) -> void:
	if _loading:
		return
	var options: Array = _hand_options.get(hand, [])
	if index < 0 or index >= options.size():
		return
	var record: Dictionary = _current()
	if record.is_empty() or (hand == "off" and _offhand_locked(record)):
		return
	var option: Dictionary = options[index]
	var rows: Array = record.get("inventory", []).duplicate(true)
	var chosen_index: int = int(option.get("index", -1)) if String(option.get("kind", "")) == "item" else -1
	var grip: bool = bool(option.get("two_handed", false))
	var target_kind: String = ""
	if chosen_index >= 0 and chosen_index < rows.size():
		target_kind = ItemRules.kind(ItemRules.entry_for(rows[chosen_index]))
	for i: int in range(rows.size()):
		if not rows[i] is Dictionary:
			continue
		var owned: Dictionary = rows[i]
		var slots: Array = ItemRules.slots(owned)
		slots.erase(hand)
		if hand == "main" and grip:
			slots.erase("off")
		if i == chosen_index:
			# One physical item cannot be held in both hands as two copies.
			if int(owned.get("quantity", 1)) < 2:
				slots.erase("off" if hand == "main" else "main")
			if not hand in slots:
				slots.append(hand)
		owned["equipped_slots"] = slots
		rows[i] = owned
	record["inventory"] = rows
	record["hand_" + hand + "_special"] = String(option.get("value", "none")) if chosen_index < 0 else "none"
	if hand == "main":
		record["hand_grip_two_handed"] = grip
		if grip:
			record["hand_off_special"] = "none"
	var active_id: String = ""
	if chosen_index >= 0 and target_kind == "weapon":
		active_id = "item:" + ("off:" if hand == "off" else "") + String(rows[chosen_index].get("id", ""))
	elif String(option.get("value", "")) in ["unarmed", "improvised"]:
		active_id = String(option.get("value", ""))
	elif String(record.get("kind", "")) == "monster":
		active_id = String(record.get("equipped_attack_id", ""))
	record["equipped_attack_id"] = active_id
	_save_equipment_record(record)


func _on_armor_selected(index: int) -> void:
	if _loading or index < 0 or index >= _armor_options.size():
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var rows: Array = record.get("inventory", []).duplicate(true)
	var chosen: int = int(_armor_options[index].get("index", -1))
	for i: int in range(rows.size()):
		if not rows[i] is Dictionary:
			continue
		var owned: Dictionary = rows[i]
		var slots: Array = ItemRules.slots(owned)
		slots.erase("body")
		if i == chosen:
			slots.append("body")
		owned["equipped_slots"] = slots
		rows[i] = owned
	record["inventory"] = rows
	_save_equipment_record(record)


func _save_equipment_record(record: Dictionary) -> void:
	_recalculate_bonus_mirrors(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Equipaggiamento non salvato: " + error_string(error))
		return
	_replace_current_record(record)
	if _inventory_ui != null:
		_inventory_ui.call("load_record", record)
	_refresh_formula_dependents(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	if _bonuses_ui != null:
		_bonuses_ui.call("load_record", record)


func _activate_attack(attack_id: String) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	record["equipped_attack_id"] = attack_id
	_save_equipment_record(record)


func _preview_attack_from_sheet(attack_id: String) -> void:
	var record: Dictionary = _current()
	var attack_data: Dictionary = {}
	for entry: Dictionary in AttackData.definitions(record):
		if String(entry.get("id", "")) == attack_id:
			attack_data = entry.duplicate(true)
			break
	if attack_data.is_empty():
		return
	attack_data["range_feet"] = AttackData.range_for(record, attack_data)
	attack_data["long_range_feet"] = AttackData.long_range_for(record, attack_data)
	if board_root.has_method("show_mobile_attack_range"):
		board_root.call("show_mobile_attack_range", record, attack_data)
		return
	var token: CharacterBody3D = find_linked_token_for_creature(_selected_id)
	if token == null:
		_set_status("Per visualizzare la gittata occorre una miniatura collegata alla creatura.")
		return
	var runtime: Node = board_root.get_node_or_null("AttackSystem")
	if runtime == null or not runtime.has_method("preview_attack_range"):
		_set_status("Visualizzazione tattica della gittata non disponibile.")
		return
	hide_panel()
	if not bool(runtime.call("preview_attack_range", token, attack_data)):
		show_panel()
		_set_status("Impossibile visualizzare la gittata.")


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
		_set_status("Il lanciatore di dadi della chat non è disponibile.")
		return
	var label: String = String(record.get("name", "Creatura")) + " · " + String(attack.get("name", "Attacco"))
	var expression := ""
	if damage:
		expression = AttackData.damage_expression(record, attack)
		label += " · Danni"
	else:
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) not in ["item", "unarmed", "improvised"] and not bool(attack.get("hit_known", false)):
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
	if damage:
		_roll_with_optional_dice(label, expression, "attack_damage:" + attack_id, record)
	else:
		var item: Dictionary = attack.get("item_entry", {})
		var ability := ItemRules.attack_ability(record, item, bool(attack.get("thrown", false))) if not item.is_empty() else "str"
		var attack_context := attack.duplicate()
		attack_context["weapon_kind"] = String(item.get("type", "")).split("|")[0]
		_roll_with_optional_dice(label, expression, "attack_hit:" + attack_id, record, ClassFeatures.attack_advantage(record, attack_context, ability))


func _refresh_attacks(record: Dictionary) -> void:
	if _attack_rows == null:
		return
	_refresh_weapon_picker(record)
	_attack_hit_labels.clear()
	_attack_damage_labels.clear()
	_attack_damage_source_labels.clear()
	_attack_range_labels.clear()
	_attack_long_range_labels.clear()
	for key: Variant in _formula_values.keys():
		if String(key).begins_with("attack_range:") or String(key).begins_with("attack_long_range:") or String(key).begins_with("attack_hit:") or String(key).begins_with("attack_damage:"):
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
		if attack_id.is_empty():
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active: bool = attack_id == actual_active_id
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.16, 0.21, 0.88)
		card_style.border_color = Color(0.54, 0.75, 0.82) if active else Color(0.30, 0.41, 0.49, 0.72)
		card_style.set_border_width_all(2 if active else 1)
		card_style.set_corner_radius_all(8)
		card_style.set_content_margin_all(7)
		card.add_theme_stylebox_override("panel", card_style)
		_attack_rows.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		# A dedicated name row keeps long bestiary action names from
		# stretching the combat column.
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 7)
		box.add_child(header)
		var name_label := Label.new()
		name_label.set_meta("creature_gui_data", true)
		name_label.text = String(attack.get("name", "Attacco"))
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(name_label)
		if active:
			var active_label := Label.new()
			active_label.text = "PORTATA ATTIVA"
			active_label.add_theme_font_size_override("font_size", 11)
			active_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.68))
			header.add_child(active_label)
		else:
			var select_reach := Button.new()
			select_reach.text = "Usa portata"
			select_reach.tooltip_text = "Attiva questo attacco per la portata tattica, senza cambiare l'equipaggiamento."
			select_reach.pressed.connect(_activate_attack.bind(attack_id))
			header.add_child(select_reach)
		# Hit and damage each have their own self-contained line. Click
		# the framed formula directly to roll without redundant buttons.
		var hit_row := HFlowContainer.new()
		hit_row.add_theme_constant_override("h_separation", 5)
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
		var inspect_range := Button.new()
		inspect_range.name = "PreviewRange_" + attack_id.validate_node_name()
		inspect_range.text = "Vedi gittata" if _touch_layout else "◎ Gittata"
		inspect_range.tooltip_text = "Chiude la scheda e mostra le creature raggiungibili da questo attacco. Clic per selezionare, Esc per chiudere, nessun danno automatico."
		if _touch_layout:
			inspect_range.tooltip_text = "Richiede al desktop un'anteprima della mappa centrata sulla creatura, con la gittata di questo attacco."
		inspect_range.pressed.connect(_preview_attack_from_sheet.bind(attack_id))
		hit_row.add_child(inspect_range)
		var damage_row := HFlowContainer.new()
		damage_row.add_theme_constant_override("h_separation", 5)
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
		var damage_sources := Label.new()
		damage_sources.add_theme_font_size_override("font_size", 12)
		damage_sources.add_theme_color_override("font_color", Color(0.86, 0.78, 0.53))
		damage_row.add_child(damage_sources)
		_attack_damage_source_labels[attack_id] = damage_sources
		box.add_child(HSeparator.new())
		var settings := HFlowContainer.new()
		settings.add_theme_constant_override("h_separation", 4)
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
		distance.custom_minimum_size.x = 60
		distance.tooltip_text = "Portata o gittata di questo attacco, indipendente dalle altre armi"
		distance.set_value_no_signal(int(AttackData.override_for(record, attack_id).get("range_feet", attack.get("range_feet", 5))))
		distance.value_changed.connect(_on_attack_range_changed.bind(attack_id))
		settings.add_child(distance)
		# Legacy range corrections are migrated to source grants, not inline.
		var range_label := Label.new()
		settings.add_child(range_label)
		_attack_range_labels[attack_id] = range_label
		_install_formula("attack_range:" + attack_id, range_label, [distance], ["Base (ft)"])
		var long_base: int = int(AttackData.override_for(record, attack_id).get(
			"long_range_feet", attack.get("long_range_feet", 0)))
		if not bool(attack.get("melee", false)) and long_base > 0:
			var long_caption := Label.new()
			long_caption.text = "Lunga"
			long_caption.add_theme_font_size_override("font_size", 11)
			settings.add_child(long_caption)
			var long_distance := SpinBox.new()
			long_distance.min_value = 5
			long_distance.max_value = 5000
			long_distance.step = 5
			long_distance.rounded = true
			long_distance.custom_minimum_size.x = 60
			long_distance.tooltip_text = "Gittata lunga base (ft) di questo attacco"
			long_distance.set_value_no_signal(long_base)
			long_distance.value_changed.connect(_on_attack_long_range_changed.bind(attack_id))
			settings.add_child(long_distance)
			var long_label := Label.new()
			settings.add_child(long_label)
			_attack_long_range_labels[attack_id] = long_label
			_install_formula("attack_long_range:" + attack_id, long_label,
				[long_distance], ["Base lunga (ft)"])
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
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) not in ["item", "unarmed", "improvised"]:
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
			details.mouse_force_pass_scroll_events = false
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
		if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) not in ["item", "unarmed", "improvised"] and not bool(attack.get("hit_known", false)):
			_set_formula("attack_hit:" + attack_id, "n.d.", "Bonus per colpire non presente nei dati del bestiario")
		else:
			_set_formula("attack_hit:" + attack_id, "%+d" % hit,
				AttackData.attack_bonus_formula(record, attack, _creature_proficiency(record)))
		var damage: String = AttackData.damage_label(record, attack)
		var damage_detail: String = "Danni: %s.\n%s" % [damage, AttackData.damage_modifier_description(record, attack)]
		var source_names := PackedStringArray()
		for part: Dictionary in AttackData.damage_modifier_breakdown(record, attack).get("parts", []):
			if not String(part.get("key", "")).is_empty() and int(part.get("amount", 0)) != 0:
				source_names.append("%s %+d" % [String(part.get("name", "Capacità")), int(part.get("amount", 0))])
		if _attack_damage_source_labels.has(attack_id):
			var source_label: Label = _attack_damage_source_labels[attack_id]
			source_label.text = " · ".join(source_names)
			source_label.visible = not source_names.is_empty()
			source_label.tooltip_text = damage_detail
		if String(attack.get("slot", "")) == "off":
			if AttackData.offhand_bonus_attack_allowed(record):
				damage_detail += " Attacco aggiuntivo a due armi: bonus al colpire normale; il modificatore di caratteristica ai danni si applica solo con lo stile Two-Weapon Fighting o se negativo."
			else:
				damage_detail += " Non soddisfa i requisiti dell'attacco aggiuntivo a due armi (normalmente due armi leggere da mischia o talento Dual Wielder). Resta possibile usarla con l'azione Attaccare."
		_set_formula("attack_damage:" + attack_id, damage, damage_detail)
		if _attack_range_labels.has(attack_id):
			var settings: Dictionary = AttackData.override_for(record, attack_id)
			var base: int = int(settings.get("range_feet", attack.get("range_feet", 5)))
			_set_formula("attack_range:" + attack_id, "%d ft" % AttackData.range_for(record, attack),
				"Gittata: base %d ft + bonus cumulabili %+d ft = %d ft" % [base,
					BonusRules.bonus(record, "attack_range:" + attack_id), AttackData.range_for(record, attack)])
		if _attack_long_range_labels.has(attack_id):
			var settings: Dictionary = AttackData.override_for(record, attack_id)
			var long_base: int = int(settings.get("long_range_feet", attack.get("long_range_feet", 0)))
			var long_total: int = AttackData.long_range_for(record, attack)
			_set_formula("attack_long_range:" + attack_id, "%d ft" % long_total,
				"Gittata lunga: base %d ft + bonus cumulabili %+d ft = %d ft" % [
					long_base, BonusRules.bonus(record, "attack_long_range:" + attack_id), long_total])


func _on_attack_ability_changed(_index: int) -> void:
	if _loading:
		return
	_save()


func _on_attack_range_changed(value: float, attack_id: String) -> void:
	_save_attack_setting(attack_id, "range_feet", int(value))



func _on_attack_long_range_changed(value: float, attack_id: String) -> void:
	_save_attack_setting(attack_id, "long_range_feet", int(value))


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
	if _defense_summary != null:
		var vulnerable: Array[String] = []
		var resistant: Array[String] = []
		var immune: Array[String] = []
		var conditions: Array[String] = []
		for kind: Dictionary in DamageDefensesTab.DAMAGE_TYPES:
			var key: String = String(kind["key"])
			var label: String = String(kind["label"])
			match DamageDefensesTab.rank(live, key):
				-1: vulnerable.append(label)
				1: resistant.append(label)
				2: immune.append(label)
		for condition: String in DamageDefensesTab.CONDITIONS:
			if DamageDefensesTab.condition_immune(live, condition):
				conditions.append(condition.capitalize())
		var lines: Array[String] = []
		if not vulnerable.is_empty(): lines.append("Vulnerabilità: " + ", ".join(vulnerable))
		if not resistant.is_empty(): lines.append("Resistenze: " + ", ".join(resistant))
		if not immune.is_empty(): lines.append("Immunità ai danni: " + ", ".join(immune))
		if not conditions.is_empty(): lines.append("Immunità alle condizioni: " + ", ".join(conditions))
		_defense_summary.text = "\n".join(lines)
		_defense_summary.visible = not lines.is_empty()
	if _ac != null and _ac_effective != null:
		var equipped: bool = not ItemRules.equipped_armor(live.get("inventory", [])).is_empty()
		_ac.editable = not equipped
		if _natural_ac_formula != null:
			_natural_ac_formula.visible = not equipped
			_natural_ac_formula.tooltip_text = "Formula di CA naturale (senza armatura), modificabile premendo Invio."
		_ac.tooltip_text = "L'armatura sostituisce la formula naturale" if equipped else "Base precedente"
		var armor_record: Dictionary = live.duplicate(false)
		armor_record["effective_armor_dex"] = BonusRules.value(live, "ability_mod:dex") if equipped else 0
		var base: Dictionary = ItemRules.armor_base(armor_record)
		if not equipped:
			base["description"] = "Naturale (%s)" % String(live.get("armor_natural_formula", "10 + dex_mod"))
		var ac: int = maxi(0, BonusRules.value(live, "ac"))
		_set_formula("ac", str(ac), "CA: %s + scudo %+d + bonus cumulabili %+d = %d" % [
			String(base.get("description", "Base manuale")),
			ItemRules.shield_bonus(live.get("inventory", [])),
			BonusRules.bonus(live, "ac"), ac])
	if _ac_proficiency_warning != null:
		var missing: PackedStringArray = []
		# Monster stat blocks do not explicitly enumerate armor training.
		# Player proficiency grants instead come from active origin choices.
		if String(live.get("kind", "character")) != "monster":
			var armor_owned: Dictionary = ItemRules.equipped_armor(live.get("inventory", []))
			if not armor_owned.is_empty():
				var armor: Dictionary = ItemRules.entry_for(armor_owned)
				var type_code: String = String(armor.get("type", "")).split("|")[0].to_upper()
				var category: String = {"LA": "light", "MA": "medium", "HA": "heavy"}.get(type_code, "")
				if not category.is_empty() and not ProficiencyRules.has_proficiency(live, "armor", category):
					missing.append(String(armor_owned.get("name", armor.get("name", "Armatura"))) + " (armatura " + category + ")")
			for hand: String in ["main", "off"]:
				var shield: Dictionary = ItemRules.occupying(live.get("inventory", []), hand)
				if not shield.is_empty() and ItemRules.kind(ItemRules.entry_for(shield)) == "shield":
					if not ProficiencyRules.has_proficiency(live, "armor", "shield"):
						missing.append(String(shield.get("name", "Scudo")) + " (scudo)")
		_ac_proficiency_warning.visible = not missing.is_empty()
		_ac_proficiency_warning.mouse_filter = Control.MOUSE_FILTER_STOP
		if not missing.is_empty():
			_ac_proficiency_warning.tooltip_text = ("Senza competenza: " + ", ".join(missing)
				+ "\nEffetti: svantaggio alle prove di caratteristica, ai tiri salvezza e ai tiri per colpire che usano Forza o Destrezza."
				+ "\nNon puoi lanciare incantesimi mentre indossi l’armatura o impugni lo scudo senza competenza.")
		else:
			_ac_proficiency_warning.tooltip_text = ""
	if _initiative_effective != null:
		var init: int = BonusRules.value(live, "initiative")
		_set_formula("initiative", "%+d" % init,
			"Iniziativa: modificatore DES %+d + bonus cumulabili %+d = %+d" % [
				BonusRules.value(live, "ability_mod:dex"),
				BonusRules.bonus(live, "initiative"), init])


func _update_max_hp_display() -> void:
	if _max_hp_effective == null or _max_hp == null:
		return
	var live: Dictionary = _live_stats_record()
	var maximum: int = maxi(0, BonusRules.value(live, "hp"))
	_set_formula("hp", str(maximum),
		"PF massimi: base %d + bonus cumulabili %+d = %d" % [
			int(_max_hp.value), BonusRules.bonus(live, "hp"), maximum])


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


# Shares are private; do not publish recipient names or titles to group chat.
func _send_document_to_peer(recipient_id: String, document: Dictionary) -> String:
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	if presence == null:
		return ""
	return String(presence.call("send_document", recipient_id, document))


func _send_item_to_peer(recipient_id: String, item: Dictionary,
		definitions: Array[Dictionary]) -> String:
	var presence: Node = board_root.get_node_or_null("CreaturePresence")
	if presence == null:
		return ""
	return String(presence.call("send_item", recipient_id, item, definitions))


func receive_shared_item(transfer: Dictionary, sender_id: String) -> void:
	var current: Dictionary = _current()
	if not current.is_empty() and _inventory_ui != null:
		_inventory_ui.call("receive_item")
	var raw: Dictionary = transfer.get("item", {})
	_set_status("Oggetto ricevuto da %s: %s" % [
		sender_id.substr(0, 8), String(raw.get("name", "Oggetto"))])
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller != null and roller.has_method("log_action"):
		roller.call("log_action", "📦 Oggetto '%s' ricevuto da %s" % [
			String(raw.get("name", "Oggetto")), sender_id.substr(0, 8)])


func receive_shared_document(document: Dictionary, sender_id: String) -> void:
	if not DocumentInbox.receive(document):
		_set_status("Documento non salvato: casella piena, file danneggiato o errore di scrittura.")
		return
	var current: Dictionary = _current()
	if not current.is_empty() and _inventory_ui != null:
		_inventory_ui.call("receive_document")
	_set_status("Documento ricevuto da giocatore %s: %s" % [
		sender_id.substr(0, 8), String(document.get("title", "Documento"))
	])
	var roller: Node = board_root.get_node_or_null("DiceRollerChat")
	if roller != null and roller.has_method("log_action"):
		roller.call("log_action", "📜 Documento '%s' ricevuto da %s" % [
			String(document.get("title", "Documento")), sender_id.substr(0, 8)])


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


func _on_feats_updated(feats: Array, origins: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	# Preserve the same proficiency/bonus/trait synchronization as the
	# competence editor; feat changes modify all downstream grant chains.
	# Feats displays a filtered origin list. Never overwrite unrelated
	# proficiency/bonus origin switches when the feat editor saves.
	var merged: Dictionary = {}
	for source: Variant in record.get("proficiency_origins", []):
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	for source: Variant in origins:
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	_on_proficiencies_updated(record.get("proficiency_choices", []), feats, merged.values())
	# The competence list can contain grants from newly added feats.
	_proficiencies_stale = true
	if _proficiencies_ui != null and _proficiencies_ui.visible:
		_proficiencies_ui.call("load_record", _current())
		_proficiencies_stale = false


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
	ProficiencyRules.reconcile_origin_dependents(record)
	SheetController.sync_origin_resources(record)
	SheetController.sync_automatic_progression(record)
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
	_refresh_info_feats(record)
	_refresh_formula_dependents(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
	_refresh_conditions(record)
	if _bonuses_ui != null:
		_bonuses_ui.call("load_record", record)
	if _traits_ui != null:
		_traits_ui.call("load_record", record)
	_feats_stale = true
	if _feats_ui != null and _feats_ui.visible:
		_feats_ui.call("load_record", record)
		_feats_stale = false
	_trackers_stale = true
	if _trackers_ui != null and _trackers_ui.visible:
		_trackers_ui.call("load_record", record)
		_trackers_stale = false
	_refresh_choice_warnings(record)


func _on_inventory_updated(inventory: Array) -> void:
	if _loading:
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var previous_main: Dictionary = ItemRules.occupying(record.get("inventory", []), "main")
	record["inventory"] = inventory.duplicate(true)
	if _inventory_ui != null and _inventory_ui.has_method("attunement_max_base"):
		record["attunement_max_base"] = int(_inventory_ui.call("attunement_max_base"))
	var current_main: Dictionary = ItemRules.occupying(record["inventory"], "main")
	if String(previous_main.get("id", "")) != String(current_main.get("id", "")):
		record["hand_grip_two_handed"] = false
	# The inventory editor also owns the existing optional-feature choices
	# when it edits artificer infusions. Preserve unrelated optional features.
	if _inventory_ui != null and _inventory_ui.has_method("optional_features"):
		record["optional_features_catalog"] = _inventory_ui.call("optional_features")
	# Inventory mutations never equip an item or choose a replacement attack.
	# A weapon removed from the inventory invalidates only its own attack ID.
	var known_attacks: Dictionary = {}
	for candidate: Dictionary in AttackData.definitions(record):
		known_attacks[String(candidate.get("id", ""))] = true
	var selected_attack: String = String(record.get("equipped_attack_id", ""))
	if not selected_attack.is_empty() and not known_attacks.has(selected_attack):
		record["equipped_attack_id"] = ""
	if ItemRules.occupying(record["inventory"], "main").is_empty():
		record["hand_grip_two_handed"] = false
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
	# Removing an item recursively removes only grants whose origins have
	# genuinely disappeared; unequipping merely deactivates their benefits.
	ProficiencyRules.reconcile_origin_dependents(record)
	ProficiencyRules.sync_legacy_fields(record, ProficiencyRules.choices(record))
	SheetController.sync_automatic_progression(record)
	SheetController.sync_origin_resources(record)
	_recalculate_bonus_mirrors(record)
	if String(record.get("kind", "")) == "monster":
		record["reach_is_custom"] = true
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare inventario: " + error_string(error))
		return
	_replace_current_record(record)
	# Never acknowledge incoming documents before the owning record exists on disk.
	# Failed inbox cleanup is safe to retry; the archived inventory is unchanged.
	if not DocumentInbox.acknowledge_inventory(inventory):
		_set_status("Inventario salvato, ma la casella dei documenti non è stata ripulita.")
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
		"%s: base %d + bonus cumulabili %+d = %d" % [
			ability.to_upper(), int((_ability_spins[ability] as SpinBox).value),
			BonusRules.bonus(live, "ability:" + ability), score])
	if ability == "dex" and _initiative_effective != null and not _loading:
		# Initiative is derived; changing the readout must not trigger a
		# second full archive save while updating the Dexterity field.
		_update_defense_display()
	if ability == "str" and _speed_effective != null and not _loading:
		# Both jump distances are derived from the current Strength score.
		_update_speed_display()
	if not _loading:
		_refresh_skill_values(live)


func _replace_current_record(record: Dictionary) -> void:
	_origin_preview_cache.clear()
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
	# Ordinary statistic edits must not rebuild the entire feat/trait graph.
	var previous_abilities: Dictionary = record.get("abilities", {}).duplicate(true)
	var previous_identity: Dictionary = {}
	for field: String in ["species", "species_source", "species_id",
		"subrace", "subrace_source", "subrace_id",
		"class", "class_source", "class_id", "subclass",
		"subclass_source", "subclass_id", "classes",
		"background", "background_source", "background_id", "rules_version"]:
		previous_identity[field] = record.get(field)
	record["name"] = _name.text.strip_edges()
	record["current_hp"] = int(_hp.value)
	record["max_hp_base"] = int(_max_hp.value)
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
	record["alignment"] = _alignment.get_item_text(_alignment.selected)
	record["armor_class_base"] = int(_ac.value)
	if _natural_ac_formula != null:
		record["armor_natural_formula"] = _natural_ac_formula.text.strip_edges()
	record["speed_base"] = (_speed_from_species()
		if String(record.get("kind", "character")) == "character" else int(_speed.value))
	record["speed_is_custom"] = _speed_custom if String(record.get("kind", "")) == "monster" else false
	var abilities: Dictionary = {}
	for ability: String in _ability_spins.keys():
		abilities[ability] = int((_ability_spins[ability] as SpinBox).value)
	record["abilities"] = abilities
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
	record["xp"] = maxi(int(_xp.value), Rules.minimum_experience(record))
	# Refresh grants only if actual identity/source selections changed,
	# not for HP, counters, weapon range or individual stat edits.
	var identity_changed := false
	for field: String in previous_identity.keys():
		if previous_identity[field] != record.get(field):
			identity_changed = true
			break
	if identity_changed:
		ProficiencyRules.reconcile_origin_dependents(record)
		SheetController.sync_origin_resources(record)
		# Identity changes also replace their structured, origin-backed
		# resistances/immunities immediately, preserving per-grant overrides.
		record["damage_defense_entries"] = DamageDefensesTab._entries_from_record(
			record, DamageDefensesTab._sources(record))
	if identity_changed or previous_abilities != abilities:
		SheetController.sync_automatic_progression(record)
	var current_grants: Array[Dictionary] = ProficiencyRules.choices(record)
	ProficiencyRules.sync_legacy_fields(record, current_grants)
	var saved_origins: Array[Dictionary] = []
	for origin: Dictionary in ProficiencyRules.origins(record):
		saved_origins.append({"id": origin.get("id", ""), "name": origin.get("name", ""),
			"group": origin.get("group", ""), "automatic": bool(origin.get("automatic", false)),
			"disabled": bool(origin.get("disabled", false)), "applied": bool(origin.get("applied", false))})
	record["proficiency_origins"] = saved_origins
	# Mirrors used by tokens/combat always include every active formula bonus.
	_recalculate_bonus_mirrors(record)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio non riuscito: %s" % error_string(error))
		return
	_replace_current_record(record)
	if identity_changed:
		# Rebuild the visible grants, skill proficiency ranks, formula readouts,
		# defensive summary and open origin editors from the new identity.
		# Ordinary field edits deliberately retain their cheap incremental path.
		_load_form(record)
	else:
		_refresh_skill_values(record)
		_refresh_attack_values(record)
		_refresh_reference(record)
		_refresh_trackers(record)
	_sync_token_health(record)
	_apply_sheet_properties(record)
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
	ui_root.add_child(_hp_delta_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_hp_delta_dialog.add_child(body)
	var explanation := Label.new()
	explanation.text = "Scegli una quantità oppure lancia i dadi."
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
			_set_status("Il lanciatore di dadi della chat non è disponibile.")
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
	# The pre-refactor damage flow resolved layers from the persisted sheet.
	# Only healing used the displayed current HP as its starting value.
	# Keep this distinction when the GUI momentarily lags behind a token edit.
	if delta >= 0:
		record["current_hp"] = int(_hp.value)
	SheetController.change_hit_points(record, delta)
	var hp: int = int(record.get("current_hp", 0))
	var temp: int = int(record.get("temporary_hp", 0)) if delta < 0 else int(_temp_hp.value)
	var form_hp: int = int(record.get("second_form_hp", 0)) if delta < 0 else old_form
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
	if _touch_layout and _map_data_controller != null and not String(record.get("linked_token_sync_id", "")).is_empty():
		var token_id := String(record.linked_token_sync_id)
		if int(_map_data_controller.get_map_data().get("mobile_protocol", 0)) < 3:
			_set_status("Aggiorna anche il desktop per sincronizzare l’aspetto.")
			return
		var request_id := _map_data_controller.request_action("set_appearance", {"token_id": token_id,
			"owner_id": Owner.local_id(), "miniature_id": record.get("current_miniature_id", record.get("default_miniature_id", ""))})
		if not request_id.is_empty():
			_mobile_appearance_requests[request_id] = token_id
		return
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
	ui_root.add_child(_form_hp_dialog)
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
	ui_root.add_child(_restore_form_dialog)
	_form_depleted_dialog = ConfirmationDialog.new()
	_form_depleted_dialog.title = "Seconda forma esaurita"
	_form_depleted_dialog.dialog_text = "I PF della seconda forma sono a 0. Ripristinare l'aspetto di base?"
	_form_depleted_dialog.get_ok_button().text = "Sì, ripristina"
	_form_depleted_dialog.get_cancel_button().text = "No, mantieni"
	_form_depleted_dialog.confirmed.connect(func() -> void:
		_restore_base_form(true, _form_depleted_target_id)
	)
	ui_root.add_child(_form_depleted_dialog)


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
			var packs: Node = get_node_or_null("/root/TokenPackManager")
			if packs == null:
				_set_status("Catalogo miniature non disponibile: scegli PF manuali.")
				_prompt_second_form_hp(record)
				return
			var identity: String = String(packs.call("miniature_identity", miniature_id, ""))
			var reference: Dictionary = packs.call("get_bestiary_reference", identity, "2014")
			if reference.is_empty():
				reference = packs.call("get_bestiary_reference", identity, "2024")
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


# The base miniature's profile (including its 5etools size) is the source of
# truth on restoration. The editable size field may have held the other form.
func _apply_base_miniature_size(record: Dictionary, miniature_id: String) -> void:
	if not board_root.has_method("list_available_miniatures"):
		return
	var profiles: Variant = board_root.call("list_available_miniatures")
	if not profiles is Array:
		return
	for value: Variant in profiles:
		if not value is Dictionary:
			continue
		var profile: Dictionary = value as Dictionary
		if String(profile.get("id", "")) != miniature_id:
			continue
		var size_name := String(profile.get("size_name", ""))
		if size_name not in ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]:
			return
		record["size_name"] = size_name
		record["footprint"] = maxf(0.5, float(profile.get("footprint", 1.0)))
		return


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
	_apply_base_miniature_size(record, original_id)
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
	var origin_enabled: Dictionary = ProficiencyRules.origin_enabled_map(record)
	for tracker: Dictionary in trackers:
		var row: Container
		if _touch_layout:
			row = VBoxContainer.new()
		else:
			row = HFlowContainer.new()
		if _touch_layout:
			row.add_theme_constant_override("separation", 4)
		else:
			row.add_theme_constant_override("h_separation", 5)
			row.add_theme_constant_override("v_separation", 3)
		_tracker_rows.add_child(row)
		var source_button := Button.new()
		var title: String = String(tracker.get("name", "Risorsa"))
		var source_label: String = String(tracker.get("source_label", ""))
		var tracker_source: String = String(tracker.get("origin_id", ""))
		var available: bool = not bool(tracker.get("disabled", false)) and bool(origin_enabled.get(tracker_source, true))
		if not available:
			row.modulate.a = 0.57
		source_button.set_meta("creature_gui_data", true)
		source_button.text = (title.substr(0, 23) + "…" if title.length() > 24 else title) + " ↗"
		source_button.tooltip_text = (
			"Vai al privilegio: " + String(tracker.get("origin", title))
			+ (" · " + source_label if not source_label.is_empty() else "")
		)
		source_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		source_button.clip_text = true
		source_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not tracker_source.is_empty():
			source_button.pressed.connect(
				_open_origin_trait.bind(tracker_source, String(tracker.get("origin", title)))
			)
		else:
			source_button.pressed.connect(_open_trait_section.bind(4))
		row.add_child(source_button)
		var id: String = String(tracker["id"])
		var base_maximum: int = int(tracker["max"])
		var maximum: int = maxi(0, BonusRules.add(record, "tracker:" + id,
			base_maximum))
		var used: int = clampi(int(spent.get(id, 0)), 0, maximum)
		var counter_group := HBoxContainer.new()
		counter_group.add_theme_constant_override("separation", 4)
		# On mobile the tracker name gets its own readable row, while all
		# actions stay together and wrap only between complete groups.
		var action_parent: Container = row
		if _touch_layout:
			var actions := HFlowContainer.new()
			actions.add_theme_constant_override("h_separation", 4)
			actions.add_theme_constant_override("v_separation", 3)
			row.add_child(actions)
			action_parent = actions
		action_parent.add_child(counter_group)
		var consume := Button.new()
		consume.text = "−"
		consume.tooltip_text = "Consuma un utilizzo"
		consume.disabled = not available
		consume.pressed.connect(_change_tracker.bind(id, 1, maximum))
		counter_group.add_child(consume)
		var remaining := Label.new()
		remaining.text = "%d /" % (maximum - used)
		remaining.custom_minimum_size.x = 68
		remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		counter_group.add_child(remaining)
		var maximum_label := Label.new()
		counter_group.add_child(maximum_label)
		var max_index: int = maximum_label.get_index()
		counter_group.remove_child(maximum_label)
		var formula := FormulaValue.new()
		counter_group.add_child(formula)
		counter_group.move_child(formula, max_index)
		formula.setup(maximum_label, [], [])
		formula.target_key = "tracker:" + id
		formula.bonus_requested.connect(_on_formula_bonus_requested)
		formula.set_formula(str(maximum),
			"%s: base %d + bonus cumulabili %+d = %d" % [
				title, base_maximum,
				BonusRules.bonus(record, "tracker:" + id), maximum
			] + ("\n" + BonusRules.description(record, "tracker:" + id)))
		var restore := Button.new()
		restore.text = "+"
		restore.tooltip_text = "Recupera un utilizzo"
		restore.disabled = not available
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
			roll.disabled = not available
			roll.pressed.connect(_roll_tracker_recharge.bind(id, threshold, title, maximum))
			action_parent.add_child(roll)
		var reset := Button.new()
		reset.text = "↺"
		reset.tooltip_text = (
			"Ripristina le azioni all'inizio del turno"
			if recharge == "turn" else "Ripristina tutti gli utilizzi (manuale)"
		)
		reset.disabled = not available
		reset.pressed.connect(_change_tracker.bind(id, -maximum, maximum))
		action_parent.add_child(reset)


func _roll_tracker_recharge(
	id: String, threshold: int, label: String, maximum: int
) -> void:
	var roll: int = randi_range(1, 6)
	if roll >= threshold:
		_change_tracker(id, -maximum, maximum)
	_set_status("%s · Ricarica d6: %d (%s, occorre %d–6)." % [
		label, roll, "riuscita" if roll >= threshold else "fallita", threshold
	])



func _change_tracker(id: String, delta: int, maximum: int) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	SheetController.change_tracker(record, id, delta, maximum)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Tracker non salvato: " + error_string(error))
		return
	_replace_current_record(record)
	_refresh_trackers(record)
	if _spellcasting_ui != null:
		_spellcasting_ui.call("refresh_spell_state", record)


func _open_tracker_trait(origin: String, source_label: String = "") -> void:
	for i: int in range(_tabs.get_tab_count()):
		if _tabs.get_tab_control(i).name == "Tratti":
			_tabs.current_tab = i
			call_deferred("_focus_tracker_trait", origin, source_label)
			return


func _focus_tracker_trait(origin: String, source_label: String = "") -> void:
	if _traits_ui != null and not origin.is_empty():
		_traits_ui.call("focus_feature", origin, source_label)


func _on_creature_tab_changed(index: int) -> void:
	# Trait categories, origin summaries and spell lists can be rebuilt here.
	call_deferred("_refresh_creature_language")
	if index >= 0 and _tabs.get_tab_control(index).name == "Cosa posso fare?" and _action_economy_ui != null:
		_action_economy_ui.call("refresh_top_skills", _live_stats_record())
	if index >= 0 and _tabs.get_tab_control(index).name == "Modifica personaggio" and _editor_section_picker.selected == 0:
		_refresh_origins_overview()
	if _traits_ui == null or index < 0 or index >= _tabs.get_tab_count():
		return
	if _tabs.get_tab_control(index).name == "Tratti" and _traits_stale:
		_traits_ui.call("load_record", _current())
		_traits_stale = false


func _refresh_reference(record: Dictionary) -> void:
	_traits_stale = true
	_proficiencies_stale = true
	_feats_stale = true
	_trackers_stale = true
	_damage_defenses_stale = true
	if _damage_defenses_ui != null and _damage_defenses_ui.visible:
		_damage_defenses_ui.call("load_record", record)
		_damage_defenses_stale = false
	if _trackers_ui != null and _trackers_ui.visible:
		_trackers_ui.call("load_record", record)
		_trackers_stale = false
	if _traits_ui != null and _tabs != null and _tabs.get_tab_control(_tabs.current_tab).name == "Tratti":
		_traits_ui.call("load_record", record)
		_traits_stale = false
	if _proficiencies_ui != null and _proficiencies_ui.visible:
		_proficiencies_ui.call("load_record", record)
		_proficiencies_stale = false
	if _feats_ui != null and _feats_ui.visible:
		_feats_ui.call("load_record", record)
		_feats_stale = false


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
	var packs: Node = get_node_or_null("/root/TokenPackManager")
	if packs != null:
		reference = packs.call("get_bestiary_reference", identity, "2014")
		if reference.is_empty():
			reference = packs.call("get_bestiary_reference", identity, "2024")
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
			owned["max_hp"] = maxi(0, BonusRules.value(owned, "hp"))
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
	if _touch_layout:
		preload("res://vtt/mobile/touch_layout.gd").fit_dialog(dialog)
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
	ui_root.add_child(_miniature_dialog)
	# The list scrolls by itself; avoid a parent scroll wrapper that shrinks
	# it to its 168px minimum and leaves most of the popup unused.
	var viewport_body := ScrollContainer.new()
	viewport_body.name = "MiniaturePickerViewport"
	viewport_body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_miniature_dialog.add_child(viewport_body)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_body.add_child(body)
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
	_miniature_list.mouse_force_pass_scroll_events = false
	_miniature_list.custom_minimum_size = Vector2(0, 168)
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
	# Standalone character management does not require a published 3D miniature.
	if not _require_miniatures and not _touch_layout:
		if not is_new:
			_set_status("Scelta miniature disponibile nell'app desktop.")
			return
		if _archive.save(record) != OK:
			_set_status("Impossibile creare la creatura nell'archivio.")
			return
		_selected_id = String(record.get("id", ""))
		_selected_kind = String(record.get("kind", ""))
		_reload()
		_set_status("Creatura creata: puoi associarle una miniatura in seguito.")
		return
	_pending_miniature_record = record.duplicate(true)
	_pending_new_creature = is_new
	_miniature_dialog.title = (
		"Scegli aspetto attuale" if _picker_current else "Miniatura di base"
	)
	_miniature_choices.clear()
	_suggested_miniature_ids.clear()
	var raw: Variant = []
	if board_root.has_method("list_available_miniatures"):
		raw = board_root.call("list_available_miniatures")
	if raw is Array:
		for candidate: Variant in raw:

			if candidate is Dictionary and not String(candidate.get("id", "")).is_empty():
				var profile: Dictionary = (candidate as Dictionary).duplicate(true)
				profile["_available_locally"] = _miniature_is_local(profile)
				_miniature_choices.append(profile)
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
		"✓ Scaricata · ★ Associata al bestiario"
		if not _suggested_miniature_ids.is_empty()
		else "✓ Scaricata · Cerca e seleziona una miniatura"
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
	_popup_sheet_dialog(_miniature_dialog, Vector2i(760, 570))


# Evaluate the real local PCK cache once per picker opening, rather than
# re-hashing downloaded files on each keystroke of the search field.
func _miniature_is_local(profile: Dictionary) -> bool:
	var origin := String(profile.get("_pack_origin", ""))
	if origin in ["local_pack", "character", "current"]:
		return true
	if origin != "remote":
		return false
	var packs := get_node_or_null("/root/TokenPackManager")
	if packs == null:
		return false
	var id := String(profile.get("id", ""))
	return bool(packs.call("is_mounted", id)) or bool(packs.call("is_downloaded", id))


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
		var available := bool(profile.get("_available_locally", false))
		_miniature_list.add_item("%s%s%s · %s" % [
			"✓ " if available else "",
			"★ " if id in _suggested_miniature_ids else "",
			name, String(profile.get("size_name", "Medium"))
		])
		_miniature_list.set_item_tooltip(index, "ID: %s\n%s" % [
			id, "Già scaricata" if available else "Non scaricata"
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
	var previous_default_id: String = String(record.get("default_miniature_id", ""))
	if _picker_current:
		record["current_miniature_id"] = _chosen_miniature_id
	else:
		record["default_miniature_id"] = _chosen_miniature_id
		# When editing the base form itself, keep current and base aligned.
		# Do not discard an independent, actively transformed appearance.
		if (
			_pending_new_creature
			or previous_current_id.is_empty()
			or previous_current_id == previous_default_id
		):
			record["current_miniature_id"] = _chosen_miniature_id
		# An explicitly selected base miniature defines the creature's base
		# size, including an existing creature whose base miniature changes.
		# Current/temporary appearance selection must not modify that base.
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
	var changed_current: bool = previous_current_id != String(
		record.get("current_miniature_id", "")
	)
	var explicitly_changed_form: bool = _picker_current and changed_current
	_pending_miniature_record.clear()
	_pending_new_creature = false
	_picker_current = false
	_reload()
	if changed_current:
		_apply_current_appearance(record)
		if explicitly_changed_form:
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
	if not board_root.has_method("get_selected_tokens_for_creatures"):
		_set_status("Collegamento ai token disponibile soltanto nella partita desktop.")
		return
	var selected_value: Variant = board_root.call("get_selected_tokens_for_creatures")
	if not selected_value is Array or (selected_value as Array).size() != 1:
		_set_status("Seleziona un solo token nella scena.")
		return
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var token: Node3D = (selected_value as Array)[0] as Node3D
	if token == null or not board_root.is_ancestor_of(token):
		return
	var creature_id: String = String(record.get("id", ""))
	var previous_id: String = String(token.get_meta("creature_id", ""))
	var previous_owner: String = String(token.get_meta("creature_owner_id", ""))
	# Never steal another sheet's live token, even if both sheets belong to
	# this desktop. An explicit unlinked token can be assigned instead.
	if not previous_id.is_empty() and previous_id != creature_id:
		_set_status("Il token appartiene già a un'altra scheda creatura.")
		return
	if not previous_owner.is_empty() and previous_owner != Owner.local_id():
		_set_status("Il token è associato a una creatura di un altro controllore.")
		return
	var sync: Node = board_root.get("board_sync") as Node
	if sync == null:
		_set_status("Sincronizzazione token non disponibile.")
		return
	var updated: Dictionary = record.duplicate(true)
	updated["linked_token_sync_id"] = String(sync.call("get_sync_id_for_node", token))
	updated["linked_token_name"] = String(token.call("get_display_name"))
	if updated["linked_token_sync_id"].is_empty() or _archive.save(updated) != OK:
		_set_status("Impossibile salvare l'associazione; nessun token modificato.")
		return
	# Only detach an earlier local representation AFTER the new link has
	# been persisted. Never strip foreign-owned scene metadata.
	for other: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (other == token or not board_root.is_ancestor_of(other)
			or String(other.get_meta("creature_id", "")) != creature_id
			or String(other.get_meta("creature_owner_id", "")) != Owner.local_id()):
			continue
		for field: String in ["creature_id", "creature_owner_id", "default_miniature_id",
			"player_character_id", "player_character_name",
			"master_creature_id", "master_creature_name", "master_creature_side"]:
			if other.has_meta(field):
				other.remove_meta(field)
	for field: String in ["player_character_id", "player_character_name",
		"master_creature_id", "master_creature_name", "master_creature_side"]:
		if token.has_meta(field):
			token.remove_meta(field)
	token.set_meta("creature_id", creature_id)
	token.set_meta("creature_owner_id", Owner.local_id())
	token.set_meta("default_miniature_id", String(record.get("default_miniature_id", "")))
	if String(record.get("kind", "")) == "character":
		token.set_meta("player_character_id", creature_id)
		token.set_meta("player_character_name", String(record.get("name", "")))
	else:
		token.set_meta("master_creature_id", creature_id)
		token.set_meta("master_creature_name", String(record.get("name", "")))
		token.set_meta("master_creature_side", String(record.get("side", "ally")))
	_replace_current_record(updated)
	_sync_token_health(updated)
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
	if token_id.is_empty() or not board_root is Node3D:
		# A mobile/standalone host has no 3D board synchronization object.
		# The stored token ID remains linked even when no local token exists.
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
		var prior_form: int = maxi(0, int(owned.get("second_form_hp", 0)))
		SheetController.change_hit_points(owned, -damage)
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
	# Restore the selected weapon's long range after loading a saved sheet.
	var active_attack: Dictionary = AttackData.active_attack(record)
	var normal_range: float = AttackData.active_range(record)
	var long_range: float = float(AttackData.long_range_for(record, active_attack))
	if bool(active_attack.get("melee", true)) or long_range <= normal_range:
		long_range = 0.0
	token.set_meta("active_weapon_long_range_feet", long_range)
	# Restore tactical reach from the saved attacks as well as on live edits.
	# This repairs tokens loaded from older maps with an aggregate reach.
	if token.has_method("get_reach_feet") and token.has_method("set_reach_feet"):
		var first_melee: float = AttackData.active_range(record)
		if absf(float(token.call("get_reach_feet")) - first_melee) > 0.01:
			token.call("set_reach_feet", first_melee, true)
	if token.has_method("set_display_name"):
		token.call("set_display_name", String(record.get("name", "")))
	if token.has_method("set_concentrating_spell_id"):
		token.call("set_concentrating_spell_id", String(record.get("concentrating_spell_id", "")))
	if token.has_method("set_conditions"):
		token.call("set_conditions", record.get("conditions", []))
	if token.has_method("set_active_spell_ids"):
		var ids: Array[String] = []
		for source: Dictionary in ActiveSpells.active_origins(record):
			ids.append(String(source.get("id", "")).trim_prefix("spell:"))
		token.call("set_active_spell_ids", ids)
	if token.has_method(method):
		var transformed: bool = int(record.get("second_form_hp", 0)) > 0
		token.call(method,
			int(record.get("second_form_hp", 0)) if transformed else int(record.get("current_hp", 1)),
			int(record.get("second_form_max_hp", 0)) if transformed else int(record.get("max_hp", 1))
		)


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in _records:
		var public_entry: Dictionary = CreaturePublicStatus.health_bar_entry(record)
		# Existing desktop behavior: only publish bars for live, locally-owned tokens.
		if public_entry.is_empty() or _find_linked_token(record) == null:
			continue
		rows.append(public_entry)
	return rows


# Future mobile/remote transport uses this without requiring a local 3D token.
# This function never exposes exact HP or the private creature sheet.
func get_public_status_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in _archive.list_owned():
		var status: Dictionary = CreaturePublicStatus.from_record(record)
		if not status.is_empty():
			rows.append(status)
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
		CreatureLocale.apply(_status, _creature_language)


func _refresh_conditions(record: Dictionary) -> void:
	if _condition_rows == null:
		return
	for child: Node in _condition_rows.get_children():
		_condition_rows.remove_child(child)
		child.queue_free()

	# The applied spells are true trait origins. Show them first, including
	# spells that were explicitly applied without adding a numeric benefit.
	var spell_heading := HBoxContainer.new()
	_condition_rows.add_child(spell_heading)
	var title := Label.new()
	title.text = "Incantesimi attivi"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_heading.add_child(title)
	var add_spell := Button.new()
	add_spell.text = "+" if _touch_layout else "+ Incantesimo"
	if _touch_layout:
		add_spell.set_meta("touch_compact_action", true)
		add_spell.custom_minimum_size = Vector2(34, 34)
	add_spell.tooltip_text = "Applica un incantesimo dal catalogo. Sarà visibile anche nei Tratti e utilizzabile come origine."
	add_spell.pressed.connect(_open_add_active_spell)
	spell_heading.add_child(add_spell)
	var applied: Array[Dictionary] = ActiveSpells.active_origins(record)
	applied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String((a.get("definition", {}) as Dictionary).get("name", "")).naturalnocasecmp_to(
			String((b.get("definition", {}) as Dictionary).get("name", ""))) < 0
	)
	if applied.is_empty():
		var empty := Label.new()
		empty.text = "Nessun incantesimo attivo."
		empty.modulate.a = 0.65
		_condition_rows.add_child(empty)
	for source: Dictionary in applied:
		var spell: Dictionary = source.get("definition", {})
		var sid: String = String(source.get("id", ""))
		var row := HBoxContainer.new()
		_condition_rows.add_child(row)
		var name_label := Label.new()
		name_label.text = "✨ " + String(spell.get("name", "Incantesimo"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var detail := Button.new()
		detail.text = "ⓘ" if _touch_layout else "Leggi effetti"
		detail.tooltip_text = "Leggi effetti"
		if _touch_layout:
			detail.set_meta("touch_compact_action", true)
		detail.pressed.connect(_show_effect_description.bind(spell.duplicate(true)))
		row.add_child(detail)
		var remove := Button.new()
		remove.text = "×"
		if _touch_layout:
			remove.set_meta("touch_compact_action", true)
			remove.custom_minimum_size = Vector2(34, 34)
		remove.tooltip_text = "Rimuovi l'incantesimo e i benefici che concede a questa creatura."
		remove.pressed.connect(_remove_active_spell.bind(sid))
		row.add_child(remove)

	# All persisted class-ability effects use the same active-state structure
	# used by the rule engine. They are distinct from D&D conditions.
	var feature_heading := Label.new()
	feature_heading.text = "Capacità attive"
	feature_heading.add_theme_font_size_override("font_size", 15)
	_condition_rows.add_child(feature_heading)
	var feature_effects: Array[Dictionary] = ClassFeatures.active_effects(record)
	if feature_effects.is_empty():
		var none := Label.new()
		none.text = "Nessuna capacità attiva."
		none.modulate.a = 0.65
		_condition_rows.add_child(none)
	for effect: Dictionary in feature_effects:
		var key := String(effect.get("key", ""))
		var name := String(effect.get("name", key))
		var summary := String(effect.get("summary", ""))
		var details := String(effect.get("description", ""))
		var origin := String(effect.get("origin_id", ""))
		var effective := bool(effect.get("effective", false))
		var row := HBoxContainer.new()
		_condition_rows.add_child(row)
		var name_label := Label.new()
		name_label.text = "✦ " + name + ("" if effective else " (sospesa)")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = summary + ("\nOrigine: " + origin if not origin.is_empty() else "")
		row.add_child(name_label)
		var detail := Button.new()
		detail.text = "ⓘ" if _touch_layout else "Leggi effetti"
		if _touch_layout:
			detail.set_meta("touch_compact_action", true)
			detail.custom_minimum_size = Vector2(34, 34)
		var description := summary + ("\n\n" + details if not details.is_empty() else "")
		if not origin.is_empty():
			description += "\n\nOrigine: " + origin
		detail.tooltip_text = "Leggi effetti della capacità"
		detail.pressed.connect(_show_effect_description.bind({"name": name, "description": description}))
		row.add_child(detail)
		var terminate := Button.new()
		terminate.text = "×"
		terminate.tooltip_text = "Termina " + name + " senza recuperare le risorse già spese."
		if _touch_layout:
			terminate.set_meta("touch_compact_action", true)
			terminate.custom_minimum_size = Vector2(34, 34)
		terminate.pressed.connect(_end_active_class_effect.bind(key))
		row.add_child(terminate)

	# Other Effects immediately follow the spell section; then Conditions and
	# diseases retain their ordinary checkbox-based management.
	var active: Array = record.get("conditions", [])
	var definitions := ContentCatalog.condition_definitions(
		String(record.get("rules_version", "2014"))
	)
	for category: String in ["effects", "conditions", "diseases"]:
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
			# Scope the non-clipping touch label to Conditions, not Statistics.
			if _touch_layout:
				check.set_meta("touch_full_condition", true)
				check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				check.clip_text = false
			check.toggled.connect(_set_sheet_condition.bind(String(definition.id)))
			row.add_child(check)
			var info := Button.new()
			info.text = "ⓘ" if _touch_layout else "Leggi effetti"
			info.tooltip_text = "Leggi effetti"
			if _touch_layout:
				info.set_meta("touch_compact_action", true)
				info.custom_minimum_size = Vector2(34, 34)
			info.pressed.connect(_show_effect_description.bind(definition.duplicate(true)))
			row.add_child(info)


func _end_active_class_effect(key: String) -> void:
	var current: Dictionary = _current()
	if current.is_empty():
		return
	var result: Dictionary = ClassFeatures.deactivate(current, key)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("message", "Impossibile terminare la capacità.")))
		return
	var updated: Dictionary = result.record
	if _archive.save(updated) != OK:
		_set_status("Impossibile salvare la disattivazione della capacità.")
		return
	_replace_current_record(updated)
	_update_external_record(updated)
	_load_form(updated)
	_sync_token_health(updated)
	_set_status(String(result.get("message", "Capacità terminata.")))


func _open_add_active_spell() -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.set_meta("creature_gui_dialog", true)
	dialog.title = "Aggiungi un incantesimo attivo"
	dialog.ok_button_text = "Applica"
	add_child(dialog)
	var content := VBoxContainer.new()
	dialog.add_child(content)
	var search := LineEdit.new()
	search.placeholder_text = "Cerca un incantesimo per nome…"
	content.add_child(search)
	var picker := OptionButton.new()
	# Entries are catalog spell names, never translate their stored names.
	picker.set_meta("catalog_category", "spells")
	picker.custom_minimum_size.x = 430
	picker.fit_to_longest_item = false
	content.add_child(picker)
	var count_hint := Label.new()
	content.add_child(count_hint)
	var options: Array[Dictionary] = SpellCatalog.all_spells_for_rules(
		String(record.get("rules_version", "2014"))
	)
	var fill := func(value: String) -> void:
		picker.clear()
		var query: String = value.strip_edges().to_lower()
		var matches := 0
		for spell: Dictionary in options:
			if not ActiveSpells.has_duration(spell):
				continue
			var name: String = String(spell.get("name", ""))
			var spell_id: String = String(spell.get("id", ""))
			if name.is_empty() or spell_id.is_empty() or (not query.is_empty() and query not in name.to_lower()):
				continue
			matches += 1
			if picker.item_count < 120:
				picker.add_item("%s · %s" % [name, String(spell.get("source", ""))])
				picker.set_item_metadata(picker.item_count - 1, spell_id)
		if picker.item_count > 0:
			picker.select(0)
		count_hint.text = "%d risultati" % matches + (" (mostrati i primi 120; affina la ricerca)" if matches > 120 else "")
		dialog.get_ok_button().disabled = picker.item_count == 0
	fill.call("")
	CreatureLocale.apply(dialog, _creature_language)
	search.text_changed.connect(func(value: String) -> void:
		fill.call(value)
		CreatureLocale.apply(dialog, _creature_language)
	)
	dialog.confirmed.connect(func() -> void:
		if picker.selected >= 0:
			_apply_active_spell(String(picker.get_selected_metadata()))
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	DialogLayout.popup(dialog, Vector2i(530, 205))


func _apply_active_spell(spell_id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty() or not ActiveSpells.apply(record, spell_id):
		return
	_save_active_spell_change(record)


func _remove_active_spell(origin_id: String) -> void:
	var record: Dictionary = _current()
	if record.is_empty() or not ActiveSpells.remove(record, origin_id):
		return
	_save_active_spell_change(record)


func _save_active_spell_change(record: Dictionary) -> void:
	_recalculate_bonus_mirrors(record)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Impossibile salvare gli incantesimi attivi: " + error_string(error))
		return
	_replace_current_record(record)
	_load_form(record)
	_apply_sheet_properties(record)
	_sync_token_health(record)


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
	SheetController.set_condition(record, id, enabled)
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_sync_token_health(record)
		_refresh_conditions(record)
		_refresh_formula_dependents(record)
		if _touch_layout and _map_data_controller != null and not String(record.get("linked_token_sync_id", "")).is_empty():
			_map_data_controller.request_action("set_condition", {"token_id": String(record.linked_token_sync_id), "condition_id": id, "enabled": enabled})
		if id == "concentrating" and _spellcasting_ui != null:
			_spellcasting_ui.call("refresh_spell_state", record)


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


func _open_origin_trait(sid: String, title: String) -> void:
	_open_tracker_trait(title)
	call_deferred("_focus_origin_trait", sid, title)


func _focus_origin_trait(sid: String, title: String) -> void:
	if _traits_ui != null:
		_traits_ui.call("focus_origin", sid, title)


func _origin_summary(sid: String) -> String:
	if _origin_preview_cache.has(sid):
		return String(_origin_preview_cache[sid])
	var record: Dictionary = _current()
	var lines: PackedStringArray = []
	for row: Dictionary in ProficiencyRules.choices(record):
		if String(row.get("origin_id", "")) == sid:
			lines.append("Competenza: " + String(row.get("key", "")) + (" · maestria" if bool(row.get("expertise", false)) else ""))
	for row: Dictionary in BonusRules.grants(record):
		if String(row.get("origin_id", "")) == sid:
			lines.append("Bonus " + String(row.get("target", "")) + ": " + String(row.get("expression", "0")))
	for row: Dictionary in StructuredTrackers.for_creature(record):
		if String(row.get("origin_id", "")) == sid:
			var formula: String = String(row.get("max_formula", ""))
			lines.append("Tracker " + String(row.get("name", "")) + " · max " + (formula if not formula.is_empty() else str(row.get("max", 0))))
	for row: Dictionary in OriginSpells.all_grants(record):
		if String(row.get("origin_id", "")) == sid:
			lines.append("Incantesimo: " + String(SpellCatalog.catalog_spell(String(row.get("spell_id", ""))).get("name", "")))
	for row: Dictionary in preload("res://vtt/structured_origin_spells_5etools.gd").for_creature(record).get("choices", []):
		if String(row.get("origin_id", "")) == sid:
			lines.append("Scegli %d incantesimi: " % int(row.get("count", 1)) + OriginSpellsTab._choice_formula(row))
	for field: String in ["feats_catalog", "damage_defense_entries", "dice_bonuses"]:
		for raw: Variant in record.get(field, []):
			if raw is Dictionary and String(raw.get("origin_id", "")) == sid:
				lines.append(String(raw.get("name", raw.get("key", raw.get("target", "")))) + " " + String(raw.get("dice", "")))
	for source: Dictionary in ProficiencyRules.origins(record):
		if String(source.get("id", "")) == sid:
			for requirement: Variant in source.get("requirements", []):
				lines.append("Scelta: " + JSON.stringify(requirement))
	var result: String = "Concessioni dell'origine:\n" + "\n".join(lines)
	_origin_preview_cache[sid] = result
	return result


func _refresh_origins_overview() -> void:
	if _origins_overview == null:
		return
	for child: Node in _origins_overview.get_children():
		_origins_overview.remove_child(child)
		child.queue_free()
	var intro := Label.new()
	intro.text = "Ogni origine mostra le concessioni registrate nella scheda. ↗ apre il tratto completo."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origins_overview.add_child(intro)
	for source: Dictionary in preload("res://vtt/creature_origin_choices.gd").available(_current()):
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or sid == preload("res://vtt/creature_origin_choices.gd").SPELL_PICKER_ID:
			continue
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", preload("res://vtt/creature_sheet_style.gd").card_style())
		_origins_overview.add_child(card)
		card.add_child(entry)
		var row := HBoxContainer.new()
		entry.add_child(row)
		var label := Label.new()
		label.text = String(source.get("name", sid))
		label.add_theme_color_override("font_color", preload("res://vtt/creature_sheet_style.gd").GOLD)
		label.add_theme_font_size_override("font_size", 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		preload("res://vtt/origin_editor_ui.gd").origin_link(label, row, sid, label.text)
		# Tooltips are inaccessible on a touchscreen: render the actual grants.
		var details := Label.new()
		var grants := _origin_summary(sid).trim_prefix("Concessioni dell'origine:\n").strip_edges()
		details.text = grants if not grants.is_empty() else "Nessuna concessione strutturata registrata; ↗ apre il tratto."
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_font_size_override("font_size", 14)
		details.add_theme_color_override("font_color", Color(0.76, 0.83, 0.88))
		entry.add_child(details)


func _show_sheet_tab(title: String) -> void:
	for index: int in range(_tabs.get_tab_count()):
		if _tabs.get_tab_control(index).name == title:
			_tabs.current_tab = index
			return

# Presentation-neutral map context. Mobile and desktop inject the same reader;
# callers receive data keyed by stable sync ID, never a remote token Node.
const MapDataReader = preload("res://vtt/map_data_controller.gd")
var _map_data_controller: MapDataReader
var _mobile_public_status_cache: Dictionary = {}
var _mobile_appearance_requests: Dictionary = {}

func set_map_data_controller(controller: MapDataReader) -> void:
	if is_instance_valid(_map_data_controller) and _map_data_controller.data_changed.is_connected(_sync_mobile_map_status):
		_map_data_controller.data_changed.disconnect(_sync_mobile_map_status)
	if is_instance_valid(_map_data_controller) and _map_data_controller.action_completed.is_connected(_mobile_appearance_completed):
		_map_data_controller.action_completed.disconnect(_mobile_appearance_completed)
	_map_data_controller = controller
	controller.action_completed.connect(_mobile_appearance_completed)
	_mobile_public_status_cache.clear()
	controller.data_changed.connect(_sync_mobile_map_status)

func get_linked_map_status(record: Dictionary) -> Dictionary:
	if not is_instance_valid(_map_data_controller):
		return {}
	var token_id := String(record.get("linked_token_sync_id", ""))
	if token_id.is_empty():
		return {}
	var data: Dictionary = _map_data_controller.get_map_data()
	for token: Dictionary in data.get("tokens", []):
		if String(token.get("id", "")) == token_id:
			return token.duplicate(true)
	return {}

func _edit_origin_spell_popup(origin_id: String = "", choice: Dictionary = {}) -> void:
	var record: Dictionary = _current()
	if record.is_empty():
		return
	_origin_spells_ui.call("load_record", record)
	_origin_spells_ui.call("open_for_origin", origin_id, choice)


# Only public miniature placement data crosses to the connected desktop.
func get_mobile_placement_creatures() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _archive.list_owned():
		var row := {"owner_id": Owner.local_id()}
		for key: String in ["id", "name", "kind", "default_miniature_id", "current_miniature_id", "size_name", "footprint", "visual_front_quarter_turns", "party_id", "rules_version"]:
			if record.has(key):
				row[key] = record[key]
		row["reach_feet"] = AttackData.active_range(record)
		row["conditions"] = record.get("conditions", []).duplicate()
		result.append(row)
	return result

func link_mobile_token(creature_id: String, token_id: String) -> void:
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) == creature_id:
			record["linked_token_sync_id"] = token_id
			if _archive.save(record) == OK:
				_replace_current_record(record)
			return


func _sync_mobile_map_status(data: Dictionary) -> void:
	if not _touch_layout or data.is_empty() or _archive == null:
		return
	var public_by_id := {}
	var current_statuses := {}
	for token: Dictionary in data.get("tokens", []):
		var token_id := String(token.id)
		var status := {}
		for key: String in ["conditions", "concentrating_spell_id", "active_spell_ids", "current_miniature_id", "default_miniature_id"]:
			if token.has(key):
				status[key] = token[key]
		current_statuses[token_id] = status.duplicate(true)
		if not _mobile_public_status_cache.has(token_id) or _mobile_public_status_cache[token_id] != status:
			public_by_id[token_id] = status
	_mobile_public_status_cache = current_statuses
	# Position/initiative polling must never reload and normalize every local
	# sheet. Read the archive only when a public condition/effect changed.
	if public_by_id.is_empty():
		return
	for owned: Dictionary in _archive.list_owned():
		var id := String(owned.get("linked_token_sync_id", ""))
		if not public_by_id.has(id):
			continue
		var record: Dictionary = owned.duplicate(true)
		_copy_public_token_status(record, public_by_id[id])
		if not _mobile_appearance_requests.values().has(id):
			for field: String in ["current_miniature_id", "default_miniature_id"]:
				var value := String(public_by_id[id].get(field, ""))
				if not value.is_empty():
					record[field] = value
		if record == owned:
			continue
		_recalculate_bonus_mirrors(record)
		if _archive.save(record) == OK:
			_update_external_record(record)

var _mobile_slot_choice := 0
var _mobile_cast_pending := false

func _request_mobile_spell_cast(spell: Dictionary, level: int, grant: Dictionary, choice: int) -> void:
	if _mobile_cast_pending:
		_set_status("Completa o annulla prima il lancio nello snapshot.")
		return
	_mobile_slot_choice = choice
	_mobile_cast_pending = true
	_on_spellcasting_cast_requested(spell, level, grant)

func accept_mobile_spell_start(creature_id: String, choice: int) -> void:
	for record: Dictionary in _archive.list_owned():
		if String(record.get("id", "")) != creature_id:
			continue
		if choice >= 100:
			record["pact_slots_spent"] = int(record.get("pact_slots_spent", 0)) + 1
		elif choice > 0 and choice <= 9:
			var spent: Array = record.get("spell_slots_spent", []).duplicate()
			while spent.size() < 10:
				spent.append(0)
			spent[choice] = int(spent[choice]) + 1
			record["spell_slots_spent"] = spent
		if choice != 0 and _archive.save(record) == OK:
			_update_external_record(record)
		return

func finish_mobile_spell(spell: Dictionary, completed: bool) -> void:
	if completed:
		_complete_origin_spell_cast(null, spell)
	else:
		_pending_origin_spell_cast.clear()
		_pending_metamagic_cast.clear()
	_mobile_cast_pending = false

func _sheet_casting_context(record: Dictionary, spell: Dictionary, grant: Dictionary) -> Dictionary:
	var spell_id := String(spell.get("id", ""))
	var casting_context: Dictionary = {}
	if not grant.is_empty():
		casting_context = OriginSpells.cast_context(record, spell_id, grant)
	else:
		var ability: String = String(spell.get("caster_spellcasting_ability", ""))
		if ability in ["str", "dex", "con", "int", "wis", "cha"]:
			var stats: Dictionary = record
			casting_context = {
				"spellcasting_ability": ability,
				"spell_attack_bonus": BonusRules.value(stats, "proficiency") + BonusRules.value(stats, "ability_mod:" + ability) + BonusRules.bonus(stats, "spell_attack"),
				"spell_save_dc": 8 + BonusRules.value(stats, "proficiency") + BonusRules.value(stats, "ability_mod:" + ability) + BonusRules.bonus(stats, "spell_dc")
			}
	if ClassFeatures.is_active(record, "innate_sorcery") and String(spell.get("source_class", "")) == "Sorcerer":
		casting_context["spell_save_dc"] = int(casting_context.get("spell_save_dc", 8)) + 1
		casting_context["spell_attack_advantage"] = true
	if spell.get("metamagic", {}) is Dictionary and not (spell.get("metamagic", {}) as Dictionary).is_empty():
		casting_context["metamagic"] = spell.metamagic.duplicate(true)
		casting_context["rules_version"] = record.get("rules_version", "2014")
	return casting_context

func _mobile_appearance_completed(id: String, action: String, result: Dictionary) -> void:
	if action != "set_appearance" or not _mobile_appearance_requests.has(id):
		return
	var token_id: String = _mobile_appearance_requests[id]
	_mobile_appearance_requests.erase(id)
	_mobile_public_status_cache.erase(token_id)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("error", "Aspetto non aggiornato.")))

func get_mobile_roll_creatures() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _archive.list_owned():
		result.append({"id": String(record.get("owner_id", Owner.local_id())) + ":" + String(record.get("id", "")), "name": String(record.get("name", "Creatura"))})
	return result
