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

class TestBoard extends Node3D:
	var selected_tokens: Array = []
	var board_sync: Node
	var requested_creature_id: String = ""
	var camera_released: bool = false
	func is_2d_view_enabled() -> bool:
		return true
	func begin_creature_token_placement(record: Dictionary) -> bool:
		requested_creature_id = String(record.get("id", ""))
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
	area._create_character()
	assert(area._current().is_empty(), "Creation must wait for the mandatory miniature choice")
	assert(area._miniature_dialog.get_ok_button().disabled,
		"New character must explicitly select a default miniature")
	area._on_miniature_selected(0)
	assert(not area._miniature_dialog.get_ok_button().disabled)
	area._confirm_miniature()
	assert(area._current().default_miniature_id == "hero_test", "Default miniature must be saved with the creature")
	var original_id: String = area._current().id
	area._select_reference(area._class_name, "Wizard", "PHB")
	assert(area._level is SpinBox, "Base class level must use a numeric input")
	area._level.value = 5
	area._save()
	var sheet: Dictionary = area._current()
	assert(sheet.classes[0].source == "PHB" and sheet.rules_version == "2014")
	assert(sheet.classes[0].level == 5 and sheet.level == 5)
	assert(sheet.trackers.size() == 3)
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
	area._update_tracker("slot_1", "maximum", 7)
	area._update_tracker("slot_1", "current", 5)
	area._level.value = 6
	area._reload()
	sheet = area._current()
	assert(sheet.id == original_id and sheet.trackers[0].maximum == 7 and sheet.trackers[0].current == 5)
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
	# The creature sheet can initiate token placement; the board then handles
	# spawning or relocating without creating another creature.
	area._request_spawn_selected_creature()
	assert(board.requested_creature_id == original_id)
	assert(not area.is_panel_open())
	assert(overlay.visible, "Closing creature sheet must restore the 2D overlay")
	assert(not board.camera_released, "Returning to placement must restore camera control")
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
