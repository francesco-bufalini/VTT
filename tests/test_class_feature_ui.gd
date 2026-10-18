extends SceneTree
const Area = preload("res://vtt/creature_area.gd")
const Store = preload("res://vtt/player_character_store.gd")
var area: Node
var isolated_path := "user://class_feature_ui_%d.json" % Time.get_ticks_usec()
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1440, 960)
	root.title = "VTT - Verifica privilegi di classe (archivio isolato)"
	var board := Node3D.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	board.add_child(ui)
	area = Area.new()
	board.add_child(area)
	area.setup(board, ui, false, false)
	area._archive._storage.path = isolated_path
	var barbarian := Store.new().create_character()
	barbarian["kind"] = "character"
	barbarian.name = "Ira e attacchi - prova"
	barbarian["classes"] = [{"name": "Barbarian", "source": "PHB", "level": 9}, {"name": "Fighter", "source": "PHB", "level": 11}]
	barbarian["rules_version"] = "2014"
	barbarian["abilities"] = {"str": 18, "dex": 14, "con": 16, "int": 10, "wis": 12, "cha": 14}
	assert(area._archive.save(barbarian) == OK)
	var sorcerer := Store.new().create_character()
	sorcerer["kind"] = "character"
	sorcerer.name = "Metamagia - prova"
	sorcerer["classes"] = [{"name": "Sorcerer", "source": "PHB", "level": 6}]
	sorcerer["optional_features_catalog"] = [{"name": "Distant Spell", "source": "PHB"}, {"name": "Subtle Spell", "source": "PHB"}]
	assert(area._archive.save(sorcerer) == OK)
	area._reload()
	area.show_panel()
	for index: int in range(4): await process_frame
	assert(area._tracker_rows.get_parent().get_parent().get_index() > area._attacks_description.get_index())
	var features: Array[Dictionary] = preload("res://vtt/class_feature_activation.gd").entries(area._current())
	assert(features.any(func(row: Dictionary) -> bool: return row.key == "rage"))
	area._on_class_feature_requested("class_feature:rage")
	await process_frame
	var dialogs: Array[Node] = area.find_children("*", "ConfirmationDialog", false, false)
	var activation: ConfirmationDialog
	for dialog: Node in dialogs:
		if dialog.title == "Ira": activation = dialog
	assert(activation != null)
	assert(area._current().get("resource_tracker_spent", {}).is_empty())
	activation.confirmed.emit()
	await process_frame
	assert(preload("res://vtt/class_feature_activation.gd").is_active(area._current(), "rage"))
	var has_rage_effect := false
	for row: Node in area._condition_rows.get_children():
		if row is HBoxContainer:
			for control: Node in row.get_children():
				if control is Label and String(control.text).begins_with("✦ Ira"):
					has_rage_effect = true
	assert(has_rage_effect, "Rage must appear among active ability effects in Conditions")
	var damage_label: Label = area._attack_damage_source_labels.get("unarmed")
	assert(damage_label != null and "Ira +3" in damage_label.text, "Attack damage must visibly explain its Rage contribution")
	area._end_active_class_effect("rage")
	assert(not preload("res://vtt/class_feature_activation.gd").is_active(area._current(), "rage"))
	var after: Label = area._attack_damage_source_labels.get("unarmed")
	assert(after != null and not after.visible, "Ending Rage must remove the damage origin annotation")
	assert(preload("res://vtt/class_feature_activation.gd").active_effects(area._current()).is_empty())
	area._tabs.current_tab = 2
	area._action_economy_ui.load_record(area._current())
	if "--visual" in OS.get_cmdline_user_args():
		root.close_requested.connect(finish)
		return
	await process_frame
	print("PASS: real sheet class activation, resource order, isolated persistence and action controls")
	finish()
func finish() -> void:
	area.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(isolated_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path + suffix))
	quit()
