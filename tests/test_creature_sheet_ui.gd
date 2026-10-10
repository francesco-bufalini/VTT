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
	campaign.selected_campaign_group_id += "_%d" % Time.get_ticks_usec()
	root.add_child(campaign)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	area._archive.setup(campaign)
	# Search works from the bundled 5etools miniature references even
	# while the remote bestiary index has not been downloaded.
	var empty_catalog: Array[Dictionary] = []
	area._on_catalog_ready(empty_catalog)
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
	area._miniature_filter.text_changed.emit("Hero")
	area._on_miniature_selected(0)
	assert(not area._miniature_dialog.get_ok_button().disabled)
	area._confirm_miniature()
	area._miniature_dialog.hide()
	assert(area._current().default_miniature_id == "hero_test", "Default miniature must be saved with the creature")
	assert(area._current().current_miniature_id == "hero_test", "First appearance inherits the base miniature")
	assert(area._creature_list_scroll.custom_minimum_size.y < 100.0,
		"One creature must occupy only one short list row")
	assert(area._creature_eye_buttons[0].visible
		and area._creature_eye_buttons[0].text == "+",
		"Missing token must show a + action instead of an eye")
	# Right-click placement must enumerate private owned creature sheets,
	# including a character that has not been placed on the map yet.
	var placeable: Array = area.get_owned_creatures_for_placement()
	assert(placeable.size() == 1
		and placeable[0].id == area._current().id
		and placeable[0].current_miniature_id == "hero_test",
		"Context placement must include unspawned owned creatures and their saved appearance")
	assert(area._tabs.get_tab_count() == 6, "Character sheet must expose inventory and spellcasting tabs")
	var tab_titles: Array[String] = []
	for tab_index: int in range(area._tabs.get_tab_count()):
		tab_titles.append(area._tabs.get_tab_title(tab_index))
	assert("Inventario" in tab_titles and "Incantesimi" in tab_titles)
	assert("Risorse" not in tab_titles and area._tracker_rows.get_parent() == area._name.get_parent().get_parent(),
		"Trackers must be inside Statistics, not a separate resources tab")
	area._choose_miniature(area._current(), false, true)
	area._miniature_filter.text = "ape"
	area._miniature_filter.text_changed.emit("ape")
	area._on_miniature_selected(0)
	area._confirm_miniature()
	area._miniature_dialog.hide()
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
	assert(area._miniature_filter.get_parent().get_parent() == area._miniature_dialog)
	assert(area._automatic_hp.get_parent().get_parent() == area._automatic_dialog,
		"Godot 4 dialog content must use direct children, not nonexistent get_vbox()")
	var original_id: String = area._current().id
	# Before any token exists, the + row action enters token placement.
	area._act_on_creature_token(original_id)
	assert(board.requested_creature_id == original_id)
	assert(not area.is_panel_open())
	area.show_panel()
	assert(area._add_class_button.disabled, "Cannot multiclass before selecting a base class")
	area._add_multiclass_row("Fighter", 2, "PHB")
	assert(area._multiclass_controls.is_empty(),
		"Secondary class row is forbidden without a base class")
	area._select_reference(area._class_name, "Wizard", "PHB")
	area._on_class_choice_changed()
	assert(area._subclass_name.item_count > 1, "2014 Wizard subclasses must be selectable")
	area._subclass_name.select(1)
	area._save()
	var selected_subclass: String = String(area._current().get("subclass", ""))
	assert(not selected_subclass.is_empty())
	area._reload()
	assert(String(area._current().get("subclass", "")) == selected_subclass,
		"Primary subclass selection must survive archive normalization and reload")
	area._refresh_multiclass_availability()
	assert(not area._add_class_button.disabled)
	assert(area._level is SpinBox and area._level.update_on_text_changed,
		"Base class level must save edits while its input still has focus")
	assert(area._hp.update_on_text_changed and area._max_hp.update_on_text_changed)
	assert(area._ac.get_parent() == area._temp_hp.get_parent(),
		"Armor class must be alongside temporary HP")
	assert(area._party.get_parent() == area._name.get_parent(),
		"Faction must be alongside character name")
	assert(area._current_miniature.is_inside_tree() and not area._current_miniature.visible,
		"No redundant current-appearance heading in appearance tab")
	area._level.value = 5
	area._save()
	var sheet: Dictionary = area._current()
	assert(sheet.classes[0].source == "PHB" and sheet.rules_version == "2014")
	assert(sheet.classes[0].level == 5 and sheet.level == 5)
	# Traits from species, class and subclass must interleave by level;
	# filters must use the actual class/subclass rather than data provider.
	var Traits = load("res://vtt/creature_traits_tab.gd")
	var multiclass_sheet: Dictionary = {
		"kind": "character", "name": "Trait Test",
		"species": "Elf", "species_id": "5etools:races:phb:elf",
		"species_source": "PHB",
		"classes": [
			{"name": "Wizard", "source": "PHB", "level": 5,
			 "subclass": "School of Abjuration", "subclass_source": "PHB"},
			{"name": "Fighter", "source": "PHB", "level": 2}
		]
	}
	var ordered_traits: Array[Dictionary] = Traits.collect_features(multiclass_sheet)
	assert(not ordered_traits.is_empty(), "Trait catalog must supply real features")
	var previous_level: int = -1
	var trait_origins: Dictionary = {}
	var has_action_surge := false
	for feature_data: Dictionary in ordered_traits:
		assert(int(feature_data["level"]) >= previous_level,
			"Traits must sort by level regardless of their origin")
		previous_level = int(feature_data["level"])
		trait_origins[String(feature_data["origin"])] = true
		if String(feature_data["name"]) == "Action Surge":
			has_action_surge = true
		if String(feature_data.get("class_name", "")) == "Wizard":
			assert(String(feature_data["book"]) != "XPHB",
				"2014 characters must not acquire 2024 features")
	assert(trait_origins.has("Specie · Elf") and trait_origins.has("Classe · Wizard")
		and trait_origins.has("Classe · Fighter")
		and trait_origins.has("Sottoclasse · Wizard / School of Abjuration"),
		"All sources must appear in a single ordered timeline")
	assert(has_action_surge, "Fighter feature should be available to its tracker")
	area._traits_ui.call("load_record", multiclass_sheet)
	var traits_pane: Node = area._traits_ui
	var trait_origin_filter: OptionButton = traits_pane.get("_origin_choice") as OptionButton
	assert(trait_origin_filter.item_count >= 5,
		"Origin filter must include all selected class and subclass sources")
	area._traits_ui.call("focus_feature", "Action Surge", "Fighter · PHB")
	assert(String(traits_pane.get("_active_origin")).begins_with("class|fighter|phb"),
		"Tracker links must reveal the feature even when another origin was filtered")
	area._traits_ui.call("load_record", {
		"kind": "monster",
		"stat_block": {"source": "MM", "legendary": [
			{"name": "Tail Attack", "entries": ["A legendary action."]}
		]}
	})
	area._traits_ui.call("focus_feature", "Azioni leggendarie")
	assert(String(traits_pane.get("_active_origin")) == "monster|legendary",
		"Section-level legendary trackers must focus their bestiary actions")
	area._traits_ui.call("load_record", area._current())
	area._ability_bonus_spins["con"].value = 2
	area._save()
	assert(area._current().ability_bonuses.con == 2)
	assert(area._ability_bonus_spins["con"].get_line_edit().has_theme_stylebox_override("normal"))
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
	area._automatic_dialog.hide()
	var automatically_calculated: Dictionary = area._current()
	assert(automatically_calculated.max_hp == 22, "Wizard 5, CON +0: 6 + 4 * 4")
	area._max_hp_bonus.value = 5
	area._save()
	assert(area._current().max_hp == 27 and area._current().max_hp_base == 22)
	assert(area._current().max_hp_bonus == 5, "Manual HP bonus must increase effective maximum")
	area._max_hp_bonus.value = 0
	area._save()
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
	assert(spells._description.get_parent() == spells._prepare.get_parent().get_parent() and spells._description.scroll_active,
		"Spell details must occupy a scrollable row below the compact action button")
	assert(not spells._search_row.visible and spells._known_list.item_count > 0,
		"Class spell list must be automatic and search optional")
	assert(spells._class_spell_level_limits().get("wizard", -1) == 3,
		"Wizard 6 must unlock class spells through level 3")
	for class_spell: Dictionary in spells._known:
		assert(int(class_spell.get("level", 0)) <= 3,
			"Spells above the class's unlocked level must not appear")
	spells._on_options_selected(1)
	assert(spells._search_row.visible)
	spells._search.text = "Magic Missile"
	spells._search.text_changed.emit("Magic Missile")
	assert(not spells._visible.is_empty(), "5etools spell catalog must be searchable")
	spells._available.select(0)
	spells._toggle_selected_prepared()
	assert(area._current().spells.size() == 1)
	assert(area._current().prepared_spells.size() == 1)
	spells._calculate_slot_totals()
	assert(area._current().spell_slots_total[1] == 4)
	spells._slot_bonus_controls[1].value = 2
	assert(area._current().spell_slots_bonus[1] == 2)
	assert(spells._remaining_labels[1].text == "6 / 6")
	assert(spells._slot_bonus_controls[1].get_line_edit().has_theme_stylebox_override("normal"))
	spells._slot_bonus_controls[1].value = 0
	spells._change_slot(1, 1)
	assert(area._current().spell_slots_spent[1] == 1)
	spells._change_slot(1, -1)
	assert(area._current().spell_slots_spent[1] == 0)
	spells._change_slot(1, 1)
	spells._on_options_selected(3)
	assert(area._current().spell_slots_spent[1] == 0,
		"Automatic recharge must both recalculate class slots and restore availability")
	spells._restore_all()
	assert(area._current().spell_slots_spent[1] == 0)
	area._reload()
	assert(area._current().spells.size() == 1
		and area._current().prepared_spells.size() == 1,
		"Spell selections must survive character refresh")
	# Optional search may add spells OUTSIDE the class list, without ever
	# changing the automatic class spell selection.
	spells._class_only.button_pressed = false
	spells._search.text = "Cure Wounds"
	spells._search.text_changed.emit("Cure Wounds")
	var foreign_spell_index: int = -1
	for index: int in range(spells._visible.size()):
		if String(spells._visible[index].get("name", "")).to_lower() == "cure wounds":
			foreign_spell_index = index
			break
	assert(foreign_spell_index >= 0, "Optional search must expose off-class spells")
	spells._available.select(foreign_spell_index)
	spells._on_spell_list_selected("catalog")
	spells._toggle_selected_prepared()
	assert(area._current().prepared_spells.size() == 2,
		"An off-class spell can be added directly to available spells")
	spells._toggle_selected_prepared()
	assert(area._current().prepared_spells.size() == 1,
		"Available spells can be removed independently from class spells")
	var references = load("res://vtt/player_5etools_catalog.gd")
	assert(references.entries("subclasses").size() > 0,
		"Subclasses must be loaded from the bundled 5etools references")
	assert(not area._subclass_choices({"name": "Wizard", "source": "PHB"}).is_empty(),
		"Subclass selection must include Wizard 2014 choices")
	var inventory: Node = area._inventory_ui
	assert(inventory._catalog.size() > 250,
		"All five 5etools item categories must be included")
	inventory._catalog_list.select(0)
	inventory._add_selected()
	assert(area._current().inventory.size() == 1)
	area._reload()
	assert(area._current().inventory.size() == 1, "Inventory must survive reload")
	inventory._inventory_list.select(0)
	inventory._remove_selected()
	assert(area._current().inventory.is_empty())
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
	# The obsolete feat picker was removed, but existing saved feats must
	# survive an edit and save of the unified creature sheet.
	var previous_feats: Dictionary = area._current().duplicate(true)
	previous_feats["feats"] = "Alert [PHB]"
	previous_feats["feats_catalog"] = [{"id": "alert|phb", "name": "Alert", "source": "PHB"}]
	assert(area._archive.save(previous_feats) == OK)
	area._reload()
	area._save()
	assert("Alert" in String(area._current().get("feats", "")),
		"Legacy feat data must survive a creature sheet save.")
	assert(not (area._current().get("feats_catalog", []) as Array).is_empty(),
		"Saved feat catalog references must not be discarded.")
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
	area.refresh_owned_sheets()
	assert(area._archive.list_owned().is_empty(),
		"Queued deleted tokens must not recreate their creature sheets")
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
	token.set_reach_feet(15.0)
	area.sync_linked_token_editor(token)
	automatic = area._archive._stored("monster", automatic_id)
	assert(automatic.reach_feet == 15.0 and automatic.reach_is_custom,
		"Token editor must persist explicit monster reach instead of reverting to bestiary reach")
	assert(automatic.stat_block.name == "Ape")
	assert(automatic.stat_block.source == "MM")
	assert(automatic.linked_token_sync_id == "ui-token")
	assert("poisoned" in automatic.conditions and "blinded" in automatic.conditions,
		"Auto-generated creature sheet must preserve creation-time token conditions")
	assert(token.has_condition("poisoned") and token.has_condition("blinded"),
		"Saving the new sheet must not clear selected creation conditions")
	assert("Test Ape" in area.get_owned_creature_names())
	assert(area.get_owned_creature_names(automatic_id).is_empty())
	placeable = area.get_owned_creatures_for_placement()
	assert(placeable.size() == 1
		and placeable[0].id == automatic_id
		and placeable[0].current_miniature_id == automatic.current_miniature_id,
		"Context placement must also enumerate already-present creatures")
	# A sheet refresh can race the creation dialog: if it registers a sheet
	# before the checkbox states are applied, the final creation state wins.
	var stale_initial: Dictionary = automatic.duplicate(true)
	stale_initial["kind"] = "monster"
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
	for path: String in [area._archive._characters._file_path(), area._archive._monsters._file_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	board.queue_free()
	campaign.queue_free()
	await process_frame
	print("PASS: independent sheet UI, progression, overrides, conditions, token identity and ownership boundaries")
	quit()
