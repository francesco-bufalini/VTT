extends SceneTree
const Owner = preload("res://vtt/creature_owner.gd")
const TokenScene = preload("res://token.tscn")

class TestCampaign extends Node:
	var selected_campaign_group_id := "creature_ui_regression"
	var active_campaign_id := ""
class TestSync extends Node:
	func get_sync_id_for_node(node: Node) -> String:
		return String(node.get_meta("sync_id", ""))
class TestBoard extends Node3D:
	var selected_tokens: Array = []
	var board_sync: Node
	func get_selected_tokens_for_creatures() -> Array:
		return selected_tokens.duplicate()
	func release_camera_control() -> void:
		pass
	func capture_camera_control() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	board.board_sync = TestSync.new()
	board.add_child(board.board_sync)
	var campaign := TestCampaign.new()
	root.add_child(campaign)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	area._archive.setup(campaign)
	area._reload()
	area._create_character()
	var original_id: String = area._current().id
	area._select_reference(area._class_name, "Wizard", "PHB")
	area._level.value = 5
	area._save()
	var sheet: Dictionary = area._current()
	assert(sheet.classes[0].source == "PHB" and sheet.rules_version == "2014")
	assert(sheet.trackers.size() == 3)
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
	token.push_transformation_state()
	token.set_size_category("Large", 2.0)
	assert(area._current().id == original_id and token.get_meta("creature_id") == original_id)
	assert(area.get_owned_health_bar_sync_entries().size() == 1)
	# A token taken over by another controller must stop publishing local health.
	token.set_meta("creature_owner_id", "another-controller-0123456789")
	assert(area.get_owned_health_bar_sync_entries().is_empty())
	area._link_selected_token()
	assert(token.get_meta("creature_owner_id") == "another-controller-0123456789")
	# Deleting a sheet detaches its token without deleting or changing the token.
	token.set_meta("creature_owner_id", Owner.local_id())
	area._delete_target = area._current()
	area._delete_selected_creature()
	assert(area._current().is_empty())
	assert(not token.has_meta("creature_id"))
	assert(not token.has_meta("creature_owner_id"))
	assert(token.get_parent() == board)
	assert(token.get_player_hit_points().max == 0)
	assert(area._archive._stored("character", original_id).is_empty())
	for path: String in ["user://player_characters/campaign_creature_ui_regression.json", "user://master_creatures/campaign_creature_ui_regression.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	print("PASS: independent sheet UI, progression, overrides, conditions, token identity and ownership boundaries")
	quit()
