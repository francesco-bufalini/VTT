extends SceneTree

const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")

class TestCampaign extends Node:
	var selected_campaign_group_id := "creature_gui_layout"
	var active_campaign_id := ""
class TestBoard extends Node3D:
	var board_sync: Node
	func list_available_miniatures() -> Array[Dictionary]:
		return [{"id": "hero_test", "name": "Hero"}]
	func release_camera_control() -> void:
		pass
	func capture_camera_control() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func visible_rows(area: Node) -> Array[Button]:
	var result: Array[Button] = []
	for button: Button in area._creature_row_buttons:
		if (button.get_parent() as Control).visible:
			result.append(button)
	return result

# A scrollable child must consume wheel/touchpad scrolling at both limits;
# otherwise an outer ScrollContainer starts moving when the inner one ends.
func _assert_scroll_isolated(node: Node) -> int:
	var count := 0
	if node is ScrollContainer or node is ItemList or node is TextEdit or (node is RichTextLabel and (node as RichTextLabel).scroll_active):
		assert(not (node as Control).mouse_force_pass_scroll_events or _belongs_to_spell_sheet(node),
			"Wheel scroll must stop at nested scrollable control: " + str(node.get_path()))
		count += 1
	for child: Node in node.get_children():
		count += _assert_scroll_isolated(child)
	return count


# The spell sheet intentionally lets the wheel reach its enclosing scroll
# once a bounded list ends, so origin-granted spells remain reachable.
func _belongs_to_spell_sheet(node: Node) -> bool:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent.get_script() == preload("res://vtt/creature_spellcasting_tab.gd"):
			return true
		parent = parent.get_parent()
	return false


func run() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var campaign := TestCampaign.new()
	campaign.selected_campaign_group_id += "_%d" % Time.get_ticks_usec()
	root.add_child(campaign)
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	# The creature panel is placed under the board UI CanvasLayer, not under area.
	assert(_assert_scroll_isolated(area._panel) >= 10,
		"Creature GUI should isolate its lists, scroll panels and multiline editors")
	_assert_scroll_isolated(area)
	area._archive.setup(campaign)
	for label: String in ["Alpha", "Beta", "Gamma"]:
		var record: Dictionary = area._archive.create_character()
		record["name"] = label
		record["party_id"] = "Delta" if label == "Beta" else "Explorers"
		record["default_miniature_id"] = "hero_test"
		assert(area._archive.save(record) == OK)
	area._reload()
	# Loading a new sheet must resolve DEX before computing the first initiative readout.
	var init_record: Dictionary = area._current()
	init_record["abilities"]["dex"] = 18
	init_record["abilities"]["str"] = 15
	assert(area._archive.save(init_record) == OK)
	area._replace_current_record(init_record)
	area._load_form(init_record)
	# A normal sheet refresh used to reset the four-cell ability table to
	# five columns, breaking headers and forcing horizontal scrolling.
	area._update_sheet_layout()
	assert(area._abilities_grid.columns == 4,
		"Ability headers and each score/modifier/saving throw row must use four columns")
	assert(area._show_offhand_all.button_pressed
		and area._show_offhand_all.text in ["Only if finesse", "Solo se accurata"]
		and area._show_offhand_all.get_parent() == area._hand_off_picker.get_parent(),
		"Finesse-only offhand filter must be active by default and share the secondary hand row")
	# Only inner lists may stop scroll chaining; the two full-size columns
	# must continue to allow the surrounding sheet to scroll vertically.
	assert(not area._statistics_columns.get_child(0).has_meta("nested_scroll_boundary_guard")
		and not area._statistics_columns.get_child(1).has_meta("nested_scroll_boundary_guard"),
		"Full-size statistics columns must not intercept parent scrolling")
	var bar := VScrollBar.new()
	bar.max_value = 300.0
	bar.page = 100.0
	bar.value = 0.0
	assert(ScrollBoundaryGuard._at_boundary(bar, -1.0)
		and not ScrollBoundaryGuard._at_boundary(bar, 1.0),
		"Inner list consumes upward scroll only at its upper boundary")
	bar.value = 200.0
	assert(ScrollBoundaryGuard._at_boundary(bar, 1.0)
		and not ScrollBoundaryGuard._at_boundary(bar, -1.0),
		"Inner list consumes downward scroll only at its lower boundary")
	bar.max_value = 100.0
	assert(not ScrollBoundaryGuard._at_boundary(bar, 1.0),
		"An inner list that fits must pass scrolling to the sheet")
	bar.free()
	var movement_parent: Node = area._speed
	while movement_parent != null and not movement_parent is GridContainer:
		movement_parent = movement_parent.get_parent()
	var movement_grid := movement_parent as GridContainer
	assert(movement_grid != null and movement_grid.columns == 5
		and movement_grid.get_child_count() == 5,
		"All five movement speeds must have equal aligned cells")
	for speed_cell: Control in movement_grid.get_children():
		assert(speed_cell.custom_minimum_size.x <= 73.0,
			"Movement cells must be compact to fit the combat column")
	# Probe the responsive movement layout without changing the live sheet.
	var probe_physics := Control.new()
	var probe_speeds := Control.new()
	var probe_grid := GridContainer.new()
	probe_grid.name = "PhysicsSpeedGrid"
	probe_speeds.add_child(probe_grid)
	var probe_jumps := Control.new()
	for spec: Vector2i in [
		Vector2i(1000, 5), Vector2i(800, 3), Vector2i(660, 2),
		Vector2i(500, 5), Vector2i(320, 3), Vector2i(200, 2)
	]:
		probe_physics.size.x = spec.x
		area._layout_physics_movement(probe_physics, probe_speeds, probe_jumps)
		assert(probe_grid.columns == spec.y,
			"Movement grid must adapt to a %d px sheet" % spec.x)
		assert(probe_speeds.custom_minimum_size.x <= float(spec.x - 18),
			"Movement speed cells must fit the sheet width")
		if spec.x >= 610:
			assert(probe_speeds.custom_minimum_size.x + 16.0
				+ probe_jumps.custom_minimum_size.x <= float(spec.x - 18),
				"Movement speeds and jumps should share a row when wide enough")
	probe_physics.free()
	probe_speeds.free()
	probe_jumps.free()
	var combat_column: Node = area._tracker_rows.get_parent()
	var ac_panel: Node = area._ac_effective
	while ac_panel.get_parent() != null and ac_panel.get_parent() != combat_column:
		ac_panel = ac_panel.get_parent()
	assert(ac_panel.get_parent() == combat_column
		and area._tracker_rows.get_index() < ac_panel.get_index(),
		"Resources must be positioned before AC and initiative")
	# The statistics editors are mutually exclusive and default to no section.
	assert(area._editor_section_picker.item_count == 7
		and area._editor_section_picker.selected == 0
		and not area._proficiencies_ui.visible and not area._feats_ui.visible
		and not area._bonuses_ui.visible and not area._trackers_ui.visible
		and not area._damage_defenses_ui.visible,
		"Origins must start with the overview and all editors closed")
	for selection: int in range(1, 7):
		area._editor_section_picker.item_selected.emit(selection)
		assert(area._editor_section_picker.selected == selection,
			"The common section menu must reflect the selected editor")
		assert(int(area._proficiencies_ui.visible) + int(area._feats_ui.visible)
			+ int(area._bonuses_ui.visible) + int(area._trackers_ui.visible)
			+ int(area._damage_defenses_ui.visible) + int(area._origin_spells_ui.visible) == 1,
			"Exactly one statistics editor must be open at a time")
	area._editor_section_picker.item_selected.emit(0)
	assert(not area._proficiencies_ui.visible and not area._feats_ui.visible
		and not area._bonuses_ui.visible and not area._trackers_ui.visible
		and not area._damage_defenses_ui.visible,
		"Choosing the overview closes all editors")
	area._on_formula_bonus_requested("initiative")
	assert(area._editor_section_picker.selected == 3 and area._bonuses_ui.visible
		and not area._proficiencies_ui.visible and not area._feats_ui.visible
		and not area._trackers_ui.visible and not area._damage_defenses_ui.visible,
		"Clicking a formula must select Bonus in the common menu")
	area._editor_section_picker.item_selected.emit(5)
	assert(area._damage_defenses_ui.visible,
		"The defense editor must be available through Visualizza e modifica")
	assert(area._damage_defenses_ui._entry_cards.size() == 0,
		"An empty character has no defense rows until granted or manually added")
	area._editor_section_picker.item_selected.emit(0)
	assert(area._initiative_effective.text == "+4",
		"Initial initiative must use the loaded DEX score, not +0 or the prior creature.")
	assert("Con rincorsa (almeno 10 ft): 15 ft" in area._long_jump.text
		and "Da fermo (senza rincorsa): 7,5 ft" in area._long_jump.text
		and "Con rincorsa (almeno 10 ft): 5 ft" in area._high_jump.text
		and "Da fermo (senza rincorsa): 2,5 ft" in area._high_jump.text,
		"Jump UI must explicitly distinguish running and standing distances")
	for mode: String in ["climb", "swim", "fly", "burrow"]:
		assert(area._special_speed_labels.has(mode)
			and area._special_speed_labels[mode].text == "0",
			"Undeclared movement speed must be displayed as zero: " + mode)
	assert(area._formula_values["initiative"].get_parent().get_parent()
		== area._formula_values["ac"].get_parent().get_parent(),
		"Initiative bonus must share a single nonwrapping defense row with AC")
	assert(area._temp_hp.get_parent().get_child(0) is Label
		and (area._temp_hp.get_parent().get_child(0) as Label).text == "TEMP",
		"Temporary HP input must appear after its caption on a separate row")
	assert(not area._ac_proficiency_warning.visible,
		"Unarmored character should not receive missing armor proficiency warnings")
	var warning_record: Dictionary = init_record.duplicate(true)
	warning_record["inventory"] = [{
		"id": "test:untrained:armor", "name": "Test Leather", "type": "LA",
		"quantity": 1, "ac": 11, "equipped_slots": ["body"]
	}]
	warning_record["proficiency_choices"] = []
	warning_record["proficiency_origins"] = []
	area._replace_current_record(warning_record)
	area._update_defense_display()
	assert(area._ac_proficiency_warning.visible
		and area._ac_proficiency_warning.mouse_filter == Control.MOUSE_FILTER_STOP
		and "svantaggio" in area._ac_proficiency_warning.tooltip_text
		and "incantesimi" in area._ac_proficiency_warning.tooltip_text,
		"Equipped nonproficient armor must show the warning and its spellcasting penalty")
	area._replace_current_record(init_record)
	area._update_defense_display()
	var original_id: String = area._current().id
	area._creature_filter.text = " DELTA "
	area._creature_filter.text_changed.emit(area._creature_filter.text)
	assert(visible_rows(area).size() == 1 and "Beta" in visible_rows(area)[0].text,
		"Owned creature search must match factions without changing stable row indices")
	assert(area._current().id == original_id, "Searching must not switch or overwrite the selected sheet")
	visible_rows(area)[0].pressed.emit()
	var beta_id: String = area._current().id
	assert(beta_id != original_id and area._current().name == "Beta")
	area._name.text = "Omega"
	area._name.text_changed.emit("Omega")
	assert("Omega" in visible_rows(area)[0].text, "Edited names must update the archive row immediately")
	assert(area._archive._stored("character", beta_id).name == "Omega")
	area._creature_filter.text = "missing"
	area._creature_filter.text_changed.emit("missing")
	assert(visible_rows(area).is_empty() and area._creature_empty.visible)
	assert(area._current().id == beta_id, "No search results must preserve the selected sheet")
	area._creature_filter.text = ""
	area._creature_filter.text_changed.emit("")
	area._reload()
	assert(visible_rows(area).size() == 3 and area._current().id == beta_id)
	for index: int in range(12):
		var record: Dictionary = area._archive.create_character()
		record["name"] = "Extra %d" % index
		assert(area._archive.save(record) == OK)
	area._reload()
	for viewport_size: Vector2i in [Vector2i(1200, 720), Vector2i(800, 600)]:
		root.size = viewport_size
		area.show_panel()
		for index: int in range(4):
			await process_frame
		var bounds: Rect2 = root.get_visible_rect()
		var sheet_rect: Rect2 = area._panel.get_global_rect()
		assert(bounds.encloses(sheet_rect), "Creature sheet must fit the game viewport after resize")
		assert(area._level.size.x < 150.0, "Numeric class level must remain a compact input")
		var sidebar: Control = area._creature_list_scroll.get_parent()
		var add_bestiary: Control = sidebar.get_child(sidebar.get_child_count() - 1)
		assert(sheet_rect.encloses(add_bestiary.get_global_rect()),
			"A large archive must leave the bestiary creation button reachable")
		area._choose_miniature(area._current(), false)
		await process_frame
		await process_frame
		var dialog: ConfirmationDialog = area._miniature_dialog
		var confirm_rect: Rect2 = dialog.get_ok_button().get_global_rect()
		assert(Rect2(Vector2.ZERO, Vector2(dialog.size)).encloses(confirm_rect))
		assert(dialog.position.y + confirm_rect.end.y <= bounds.size.y,
			"First-open miniature Confirm must be on screen")
		dialog.hide()
	for store in [area._archive._characters, area._archive._monsters]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store._file_path()))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	await process_frame
	print("PASS: creature archive search, stable selection, live names, compact fields and first-open confirmation")
	quit()
