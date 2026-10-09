extends SceneTree
const Owner = preload("res://vtt/creature_owner.gd")
const TokenScene = preload("res://token.tscn")

class TestCampaign extends Node:
	var selected_campaign_group_id := "creature_ui_regression"
	var active_campaign_id := ""
class TestSync extends Node:
	func get_sync_id_for_node(node: Node) -> String:
		return String(node.get_meta("sync_id", ""))
class OverlayStub extends Control:
	func set_2d_active(enabled: bool) -> void:
		visible = enabled

class TestDice extends Node:
	var last_expression := ""
	func roll_expression_from_sheet(_label: String, expression: String, _actor: Node3D = null) -> int:
		last_expression = expression
		return 4

class TestPresence extends Node:
	var peers: Array[Dictionary] = [
		{"id": "remote-player-0123456789abcdef", "label": "Giocatore remoto"}
	]
	func get_online_peers() -> Array[Dictionary]:
		return peers.duplicate(true)
	func request_refresh() -> void:
		pass

class TestBoard extends Node3D:
	var selected_tokens: Array = []
	var board_sync: Node
	var requested_creature_id: String = ""
	var requested_current_miniature_id: String = ""
	var camera_released: bool = false
	var focused_token: Node3D
	func focus_camera_on_token(token: CharacterBody3D) -> void:
		focused_token = token
	func is_2d_view_enabled() -> bool:
		return true
	func begin_creature_token_placement(record: Dictionary) -> bool:
		requested_creature_id = String(record.get("id", ""))
		requested_current_miniature_id = String(record.get("current_miniature_id", ""))
		return true
	func get_selected_tokens_for_creatures() -> Array:
		return selected_tokens.duplicate()
	func list_available_miniatures() -> Array[Dictionary]:
		return [{"id": "hero_test", "name": "Hero"}, {"id": "ape", "name": "Ape"}]
	func release_camera_control() -> void:
		camera_released = true
	func capture_camera_control() -> void:
		camera_released = false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var overlay := OverlayStub.new()
	overlay.name = "TopDownElevationOverlay"
	ui.add_child(overlay)
	board.board_sync = TestSync.new()
	board.add_child(board.board_sync)
	var presence := TestPresence.new()
	presence.name = "CreaturePresence"
	board.add_child(presence)
	var hp_roller := TestDice.new()
	hp_roller.name = "DiceRollerChat"
	board.add_child(hp_roller)
	var campaign := TestCampaign.new()
	root.add_child(campaign)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	area._archive.setup(campaign)
	# Search works from the bundled 5etools miniature references even
	# while the remote bestiary index has not been downloaded.
	area._on_catalog_ready([])
	area._filter_catalog("ape")
	assert(not area._filtered_catalog.is_empty(), "Offline name search must work")
	area._filter_catalog("Ape")
	assert(not area._filtered_catalog.is_empty(), "Search must ignore case")
	area._filter_catalog("ape mm")
	assert(not area._filtered_catalog.is_empty(), "Source-name search must work")

	area._reload()
	assert("ape" in area._associated_miniature_ids("Ape", "MM"))
	area._choose_miniature({"name": "Ape", "source": "MM", "kind": "monster", "id": "suggestion-probe"}, true)
	assert(area._visible_miniatures[0].id == "ape",
		"The curated bestiary association must rank the correct pack first")
	assert(area._miniature_dialog.get_ok_button().disabled,
		"Suggested pack must not bypass mandatory selection")
	area._miniature_dialog.hide()
	area.begin_add_creature()
	assert(area._current().is_empty(), "Creation must wait for the mandatory miniature choice")
	assert(not area._pending_miniature_record.is_empty(),
		"Add character must go directly to the required miniature selection")
	assert(area._miniature_dialog.get_ok_button().disabled,
		"New character must explicitly select a default miniature")
	area._miniature_filter.text = "Hero"
	area._on_miniature_selected(0)
	assert(not area._miniature_dialog.get_ok_button().disabled)
	area._confirm_miniature()
	assert(area._current().default_miniature_id == "hero_test", "Default miniature must be saved with the creature")
	assert(area._current().current_miniature_id == "hero_test", "First appearance inherits the base miniature")
	assert(area._creature_list_scroll.custom_minimum_size.y < 100.0,
		"One creature must occupy only one short list row")
	assert(area._creature_eye_buttons[0].visible
		and area._creature_eye_buttons[0].text == "+",
		"Missing token must show a + action instead of an eye")
	assert(area._tabs.get_tab_count() == 5, "Character sheet must expose spellcasting tab")
	area._choose_miniature(area._current(), false, true)
	area._miniature_filter.text = "ape"
	area._on_miniature_selected(0)
	area._confirm_miniature()
	assert(area._current().current_miniature_id == "ape" and area._current().default_miniature_id == "hero_test",
		"Changing current appearance without a live token must preserve default miniature")
	area._restore_default_appearance()
	assert(area._current().current_miniature_id == "hero_test", "Reset appearance must restore base")
	area._open_transfer_dialog()
	assert(area._transfer_users.item_count == 1)
	assert(area._transfer_users.get_item_metadata(0) == "remote-player-0123456789abcdef",
		"Transfer must offer connected users, not ask for a pasted owner ID")
	area._transfer_dialog.hide()
	var export_path: String = "user://creature_ui_export_test.json"
	area._save_exported_creature(export_path)
	var exported: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(exported is Dictionary and exported.format == "vtt_creature_export_v1")
	assert(exported.creature.id == area._current().id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	# Automatic calculation is opt-in: HP average d8 = 5 after first
	# level, and a selected calculation must not replace spell choices.
	var Rules = load("res://vtt/creature_rules.gd")
	assert(Rules.average_die(8) == 5)
	assert(Rules.average_die(6) == 4)
	assert(Rules.automatic_hit_points({
		"class": "Fighter", "level": 3,
		"abilities": {"con": 14}
	}).value == 28, "Fighter 3 with CON +2: 12 + 8 + 8")
	assert(Rules.proficiency_bonus({"class": "Wizard", "level": 5}) == 3)
	assert(Rules.spellcasting_limits({
		"class": "Bard", "level": 3, "rules_version": "2014"
	}).known_limits.bard == 6)
	assert(area._creature_context_menu.get_item_count() >= 3)
	assert(area._miniature_dialog.dialog_text.is_empty()
		and area._automatic_dialog.dialog_text.is_empty(),
		"Descriptions must not compete with popup custom controls")
	assert(area._miniature_filter.get_parent().get_parent() == area._miniature_dialog.get_vbox())
	assert(area._automatic_hp.get_parent().get_parent() == area._automatic_dialog.get_vbox())
	var original_id: String = area._current().id
	# Before any token exists, the + row action enters token placement.
	area._act_on_creature_token(original_id)
	assert(board.requested_creature_id == original_id)
	assert(not area.is_panel_open())
	area.show_panel()
	area._select_reference(area._class_name, "Wizard", "PHB")
	assert(area._level is SpinBox and area._level.update_on_text_changed,
		"Base class level must save edits while its input still has focus")
	assert(area._hp.update_on_text_changed and area._max_hp.update_on_text_changed)
	assert(area._ac.get_parent() == area._temp_hp.get_parent(),
		"Armor class must be alongside temporary HP")
	assert(area._party.get_parent() == area._name.get_parent(),
		"Faction must be alongside character name")
	assert(not area._current_miniature.is_inside_tree(),
		"No redundant current-appearance heading in appearance tab")
	area._level.value = 5
	area._save()
	var sheet: Dictionary = area._current()
	assert(sheet.classes[0].source == "PHB" and sheet.rules_version == "2014")
	assert(sheet.classes[0].level == 5 and sheet.level == 5)
	area._ability_bonus_spins["con"].value = 2
	area._save()
	assert(area._current().ability_bonuses.con == 2)
	assert(area._ability_modifier_labels["con"].text == "+1")
	assert(Rules.automatic_hit_points(area._current()).value == 27,
		"CON score bonus must change computed HP")
	area._ability_bonus_spins["con"].value = 0
	area._save()
	area._open_automatic_calculation()
	assert(not area._automatic_hp.button_pressed)
	area._automatic_hp.button_pressed = true
	area._automatic_proficiency.button_pressed = true
	area._automatic_spells.button_pressed = true
	area._apply_automatic_calculation()
	var automatically_calculated: Dictionary = area._current()
	assert(automatically_calculated.max_hp == 22, "Wizard 5, CON +0: 6 + 4 * 4")
	assert(automatically_calculated.proficiency_bonus == 3)
	assert(automatically_calculated.has("spellcasting_calculation"))
	assert(automatically_calculated.spells.is_empty() and automatically_calculated.prepared_spells.is_empty())
	assert(not sheet.has("trackers"), "Legacy trackers must not be created.")
	# Multiclass levels are independent; the primary level never decreases
	# because a secondary class is added.
	area._add_multiclass_row("Fighter", 2, "PHB")
	area._save()
	sheet = area._current()
	assert(sheet.classes.size() == 2)
	assert(sheet.classes[0].level == 5 and sheet.classes[1].level == 2)
	assert(sheet.level == 7, "Derived total must equal the class-level sum")
	area._level.value = 6
	area._save()
	sheet = area._current()
	assert(sheet.classes[0].level == 6 and sheet.classes[1].level == 2)
	assert(sheet.level == 8)
	# For the rest of the UI test, use a single-class wizard.
	area._clear_multiclass()
	area._save()
	area._level.value = 6
	area._reload()
	sheet = area._current()
	assert(sheet.id == original_id and sheet.classes[0].level == 6)
	var spells: Node = area._spellcasting_ui
	spells._search.text = "Magic Missile"
	assert(not spells._visible.is_empty(), "5etools spell catalog must be searchable")
	spells._available.select(0)
	spells._add_selected_known()
	spells._toggle_selected_prepared()
	assert(area._current().spells.size() == 1)
	assert(area._current().prepared_spells.size() == 1)
	spells._calculate_slot_totals()
	assert(area._current().spell_slots_total[1] == 4)
	spells._change_slot(1, 1)
	assert(area._current().spell_slots_spent[1] == 1)
	spells._change_slot(1, -1)
	assert(area._current().spell_slots_spent[1] == 0)
	spells._change_slot(1, 1)
	spells._restore_all()
	assert(area._current().spell_slots_spent[1] == 0)
	area._reload()
	assert(area._current().spells.size() == 1
		and area._current().prepared_spells.size() == 1,
		"Spell selections must survive character refresh")
	area._max_hp.value = 35
	area._hp.value = 7
	area._save()
	area._restore_full_hp()
	assert(area._current().current_hp == 35, "Restore HP button must update the persistent sheet")
	area._temp_hp.value = 2
	area._save()
	area._change_hit_points(-1)
	assert(area._current().temporary_hp == 1 and area._current().current_hp == 35)
	area._change_hit_points(-2)
	assert(area._current().temporary_hp == 0 and area._current().current_hp == 34,
		"Damage toolbar must consume temporary HP before current HP")
	area._change_hit_points(1)
	assert(area._current().current_hp == 35, "Healing toolbar must cap at max HP")
	area._open_hp_delta(-1)
	area._hp_delta_amount.value = 3
	area._confirm_hp_delta()
	assert(area._current().current_hp == 32, "Numeric damage popup must apply entered HP")
	area._open_hp_delta(1)
	area._hp_use_dice.button_pressed = true
	area._hp_dice_formula.text = "1d8"
	area._confirm_hp_delta()
	assert(area._current().current_hp == 35,
		"Dice-roller HP healing must apply the rolled result and cap at maximum")
	assert(hp_roller.last_expression == "1d8",
		"Dice HP popup must use the existing chat roller")
	area._size_choice.select(3)
	area._reach.value = 15
	area._front.select(2)
	area._party.text = "Explorers"
	area._save()
	area._reload()
	assert(area._current().size_name == "Large" and area._current().footprint == 2.0)
	assert(area._current().reach_feet == 15 and area._current().visual_front_quarter_turns == 2)
	assert(area._current().party_id == "Explorers")
	area._open_feat_dialog()
	area._search_feats("Alert")
	assert(not area._visible_feats.is_empty(), "5e.tools feats must be searchable.")
	area._feat_list.select(0)
	area._show_feat_details(0)
	area._confirm_feat()
	assert("Alert" in String(area._current().get("feats", "")),
		"Choosing a catalog feat must save it to the character.")
	area._set_sheet_condition(true, "poisoned")
	area._reload()
	assert("poisoned" in area._current().conditions)
	var token := TokenScene.instantiate()
	board.add_child(token)
	token.set_meta("sync_id", "ui-token")
	board.selected_tokens = [token]
	var appearance: Dictionary = token.get_appearance_state()
	area._link_selected_token()
	assert(token.get_meta("creature_id") == original_id and token.has_condition("poisoned"))
	area._refresh_creature_eye_buttons()
	assert(area._creature_eye_buttons[0].visible and area._creature_eye_buttons[0].text == "👁",
		"Linked token should show the eye button")
	area._focus_creature_token(original_id)
	assert(board.focused_token == token, "Eye must center the selected creature's token")
	assert(not area.is_panel_open(), "Eye action must reveal the board")
	assert(token.get_appearance_state().visual_asset == appearance.visual_asset)
	# "Edit token" and "Edit sheet" now open and update the same record.
	assert(area.open_for_token(token))
	assert(area.is_panel_open())
	assert(area._current().id == original_id)
	assert(not overlay.visible, "2D tactical portraits must not cover the sheet")
	assert(board.camera_released, "Opening sheet from token must release the mouse")
	area._name.text = "Renamed adventurer"
	area._save()
	assert(token.get_display_name() == "Renamed adventurer")
	# Once a token exists, the same row action is the eye that focuses it.
	area._act_on_creature_token(original_id)
	assert(board.focused_token == token)
	assert(not area.is_panel_open())
	assert(overlay.visible, "Closing creature sheet must restore the 2D overlay")
	assert(not board.camera_released, "Returning to the board must restore camera control")
	token.set_conditions(["blinded"])
	area.sync_linked_token_editor(token)
	assert("blinded" in area._current().conditions)
	assert(not ("poisoned" in area._current().conditions))
	area.hide_panel()
	token.push_transformation_state()
	token.set_size_category("Large", 2.0)
	assert(area._current().id == original_id and token.get_meta("creature_id") == original_id)
	assert(area.get_owned_health_bar_sync_entries().size() == 1)
	# A token taken over by another controller must stop publishing local health.
	token.set_meta("creature_owner_id", "another-controller-0123456789")
	assert(area.get_owned_health_bar_sync_entries().is_empty())
	area._link_selected_token()
	assert(token.get_meta("creature_owner_id") == "another-controller-0123456789")
	# Deleting a creature also removes every locally owned scene token.
	token.set_meta("creature_owner_id", Owner.local_id())
	area._delete_target = area._current()
	area._delete_selected_creature()
	assert(area._current().is_empty())
	assert(token.is_queued_for_deletion(), "Creature deletion must delete its token")
	assert(area._archive._stored("character", original_id).is_empty())
	await process_frame
	# Use a fresh unrelated token to test independent automatic-sheet creation.
	token = TokenScene.instantiate()
	board.add_child(token)
	token.set_meta("sync_id", "ui-token")
	board.selected_tokens = [token]
	# New tokens automatically get an owned private creature sheet using the
	# official miniature-to-bestiary map, even without a manual link action.
	token.set_token_pack_id("ape")
	token.set_display_name("Test Ape")
	token.set_conditions(["poisoned", "blinded"])
	area.ensure_sheet_for_token(token, true)
	var automatic_id := String(token.get_meta("creature_id", ""))
	assert(not automatic_id.is_empty())
	assert(token.get_meta("creature_owner_id") == Owner.local_id())
	var automatic: Dictionary = area._archive._stored("monster", automatic_id)
	assert(automatic.name == "Test Ape")
	assert(automatic.stat_block.name == "Ape")
	assert(automatic.stat_block.source == "MM")
	assert(automatic.linked_token_sync_id == "ui-token")
	assert("poisoned" in automatic.conditions and "blinded" in automatic.conditions,
		"Auto-generated creature sheet must preserve creation-time token conditions")
	assert(token.has_condition("poisoned") and token.has_condition("blinded"),
		"Saving the new sheet must not clear selected creation conditions")
	assert("Test Ape" in area.get_owned_creature_names())
	assert(area.get_owned_creature_names(automatic_id).is_empty())
	# A sheet refresh can race the creation dialog: if it registers a sheet
	# before the checkbox states are applied, the final creation state wins.
	var stale_initial: Dictionary = automatic.duplicate(true)
	stale_initial["conditions"] = []
	assert(area._archive.save(stale_initial) == OK)
	area.ensure_sheet_for_token(token, true)
	var after_creation: Dictionary = area._archive._stored("monster", automatic_id)
	assert("poisoned" in after_creation.conditions and "blinded" in after_creation.conditions,
		"Creation-time conditions must update any premature empty auto-sheet")
	area.ensure_sheet_for_token(token, true)
	assert(area._archive.list_owned().size() == 1, "Repeat linking must not duplicate a sheet")
	# Foreign-owned tokens are never claimed; transfer of their public owner
	# field gives the new owner a sheet automatically without confirmation.
	var received := TokenScene.instantiate()
	board.add_child(received)
	received.set_meta("sync_id", "received-token")
	received.set_token_pack_id("ape")
	received.set_meta("creature_id", "received-sheet")
	received.set_meta("creature_owner_id", "remote-installation-0123456789")
	area.ensure_sheet_for_token(received)
	assert(area._archive._stored("monster", "received-sheet").is_empty())
	received.set_meta("creature_owner_id", Owner.local_id())
	area.refresh_owned_sheets()
	assert(not area._archive._stored("monster", "received-sheet").is_empty())
	# No startup token claim: chat and initiative can open without a prompt,
	# and an unowned/foreign miniature is not available as our chat identity.
	var dice: Node = load("res://vtt/dice_roller_chat.gd").new()
	board.add_child(dice)
	dice.board_root = board
	assert(dice.ensure_scene_identity())
	assert(dice._scene_identity_tokens().has(token))
	assert(dice._scene_identity_tokens().has(received))
	received.set_meta("creature_owner_id", "remote-installation-0123456789")
	assert(not dice._scene_identity_tokens().has(received))
	assert(dice._identity_token() == token,
		"Chat must automatically identify the sole owned miniature without a dialog.")
	assert(not dice.has_method("request_change_scene_identity"),
		"The obsolete user-token reassociation action must be removed.")
	received.set_meta("creature_owner_id", Owner.local_id())
	# Removing a token never erases the independent sheet.
	token.queue_free()
	await process_frame
	assert(not area._archive._stored("monster", automatic_id).is_empty())
	received.queue_free()
	for path: String in ["user://player_characters/campaign_creature_ui_regression.json", "user://master_creatures/campaign_creature_ui_regression.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	print("PASS: independent sheet UI, progression, overrides, conditions, token identity and ownership boundaries")
	quit()
