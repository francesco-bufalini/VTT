extends SceneTree
const Owner = preload("res://vtt/creature_owner.gd")
const ProficiencyRules = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const TokenScene = preload("res://token.tscn")

class TestCampaign extends Node:
	var selected_campaign_group_id := "creature_ui_regression_" + str(Time.get_ticks_usec())
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
	# The published long weapon range must be a real formula widget, not
	# an ordinary Label that cannot open the origin bonus editor.
	var ranged_fixture: Dictionary = {
		"kind": "monster", "stat_block": {"action": [{
			"name": "Longbow", "entries": [
				"{@atk rw} Ranged Weapon Attack: {@hit +5} to hit, range 80/320 ft., one target. {@damage 1d8+3} piercing damage."
			]
		}]}
	}
	var ranged_definitions: Array[Dictionary] = AttackData.definitions(ranged_fixture)
	assert(not ranged_definitions.is_empty(), "Fixture must contain a ranged attack")
	area._refresh_attacks(ranged_fixture)
	var long_key: String = "attack_long_range:" + String(ranged_definitions[0]["id"])
	assert(area._formula_values.has(long_key)
		and area._attack_long_range_labels.has(String(ranged_definitions[0]["id"]))
		and area._formula_values[long_key].has_signal("bonus_requested"),
		"Long range must display the same actionable formula as normal range")
	var attack_preview_button: Button = area._attack_rows.find_child("PreviewRange_*", true, false) as Button
	assert(attack_preview_button != null and attack_preview_button.pressed.is_connected(
		Callable(area, "_preview_attack_from_sheet").bind(String(ranged_definitions[0]["id"]))),
		"Each available attack must have a button for its read-only range preview")
	area._refresh_attacks({})
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var icon: Label = area._saving_throw_icons[ability]
		var numeric: Label = area._saving_throw_labels[ability]
		var formula: Control = area._formula_values["save:" + ability]
		assert(icon.get_parent() == formula.get_parent()
			and formula.get_index() + 1 == icon.get_index()
			and formula.is_ancestor_of(numeric) and icon.custom_minimum_size.x >= 28,
			"Saving throw proficiency icons must be right of their fixed-width numeric formula")
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
	area._miniature_dialog.hide() # Native confirmation closes the window before emitting.
	area._confirm_miniature()
	area._miniature_dialog.hide()
	assert(area._current().default_miniature_id == "hero_test", "Default miniature must be saved with the creature")
	assert(area._current().current_miniature_id == "hero_test", "First appearance inherits the base miniature")
	assert(area._info_feats_list.get_parent().get_index() < area._biography.get_parent().get_index(),
		"Read-only feats must appear above personality text on the Info tab")
	assert((area._info_feats_list.get_child(0) as Label).text == "Nessun talento.",
		"A new sheet has no feats in its read-only Info summary")
	# Update via the editable Feats editor, then verify Info has no mutable
	# buttons and right-click focuses the matching granting origin.
	area._on_feats_updated([{
		"name": "Info Test Feat", "source": "HB", "origin_id": ""
	}], [])
	var summary_row: PanelContainer = area._info_feats_list.get_child(0) as PanelContainer
	assert(summary_row != null and summary_row.get_child_count() == 1)
	var feat_summary: Label = summary_row.get_child(0) as Label
	assert("Info Test Feat" in feat_summary.text and "Origini:" in feat_summary.tooltip_text,
		"Info displays feat name, description and origins without edit/toggle controls")
	var context_event := InputEventMouseButton.new()
	context_event.button_index = MOUSE_BUTTON_RIGHT
	context_event.pressed = true
	feat_summary.gui_input.emit(context_event)
	assert(area._tabs.current_tab == 6 and area._editor_section_picker.selected == 2
		and String(area._feats_ui.get("_selected_id")) == "",
		"Right-clicking an Info feat must navigate to its source in Feats editor")
	assert(area._current().feats_catalog.size() == 1,
		"Navigating from Info must not mutate or disable the feat")
	area._on_feats_updated([], [])
	area._tabs.current_tab = 0
	area._select_details_editor(0)
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
	assert(area._tabs.get_tab_count() == 7, "The seven sheet sections must remain available")
	var tab_titles: Array[String] = []
	for tab_index: int in range(area._tabs.get_tab_count()):
		tab_titles.append(area._tabs.get_tab_title(tab_index))
	assert(tab_titles == ["Info", "Statistiche", "Poteri", "Inventario", "Tratti", "Condizioni", "Modifica personaggio"],
		"Tabs must keep the same reading order on desktop and mobile")
	var info_root: Node = area._name.get_parent().get_parent().get_parent().get_parent()
	var physics_found := false
	for frame: Node in info_root.get_children():
		if frame is PanelContainer and frame.get_child_count() > 0:
			var body: Node = frame.get_child(0)
			if body is VBoxContainer and body.get_child_count() > 0:
				var title: Node = body.get_child(0)
				if title is Label and (title as Label).text == "FISICO":
					physics_found = true
					assert(frame.get_index() == 1, "Physics immediately follows Identity in Info")
					assert(body.is_ancestor_of(area._species) and body.is_ancestor_of(area._size_choice)
						and body.is_ancestor_of(area._speed) and body.is_ancestor_of(area._front),
						"Species, appearance and movement remain editable together in Physics")
					var fields: HFlowContainer = body.find_child("PhysicsFields", true, false) as HFlowContainer
					var miniatures: VBoxContainer = body.find_child("PhysicsMiniatures", true, false) as VBoxContainer
					var movement: PanelContainer = body.find_child("PhysicsMovement", true, false) as PanelContainer
					assert(fields != null and miniatures != null and movement != null
						and fields.get_index() + 1 == miniatures.get_index()
						and miniatures.get_index() + 1 == movement.get_index(),
						"Physics groups stay in reading order: fields, miniatures, movement")
					for widget: Control in [area._species, area._subrace_choice, area._creature_type_display]:
						var field: VBoxContainer = widget.get_parent() as VBoxContainer
						assert(field != null and field.get_parent() == fields
							and field.get_child(0) is Label and field.get_child(1) == widget,
							"Species, subrace and type form the compact identity row")
					var miniature_flow: HFlowContainer = miniatures.find_child("PhysicsMiniatureFlow", true, false) as HFlowContainer
					for widget: Control in [area._size_choice, area._front]:
						var miniature_field: VBoxContainer = widget.get_parent() as VBoxContainer
						assert(miniature_field != null and miniature_field.get_parent() == miniature_flow
							and miniature_field.get_child(0) is Label and miniature_field.get_child(1) == widget,
							"Size and facing are grouped with miniature controls, not the species fields")
					assert((area._subrace_choice.get_parent() as Control).visible
						and not (area._challenge_rating.get_parent() as Control).visible,
						"Characters show the whole subrace field and hide the monster CR field")
					assert(miniatures.is_ancestor_of(area._default_miniature)
						and miniatures.is_ancestor_of(area._current_miniature_row)
						and miniatures.find_child("PhysicsMiniatureFlow", true, false) is HFlowContainer,
						"Base and current miniature actions share a compact wrapping group")
					var speed_group: Node = movement.find_child("PhysicsSpeeds", true, false)
					var jumps_group: Node = movement.find_child("PhysicsJumps", true, false)
					assert(speed_group != null and jumps_group != null
						and speed_group.get_parent() == jumps_group.get_parent()
						and jumps_group.is_ancestor_of(area._long_jump)
						and jumps_group.is_ancestor_of(area._high_jump),
						"Speeds and jump distances sit side-by-side on wide sheets, wrapping on narrow ones")
	assert(physics_found, "Info contains a Physics section")
	assert(not area._proficiencies_ui.visible, "Competence editor starts collapsed")
	area._proficiencies_toggle_button.pressed.emit()
	assert(area._proficiencies_ui.visible, "Statistics button expands competence boxes")
	area._proficiencies_toggle_button.pressed.emit()
	assert(not area._proficiencies_ui.visible, "Statistics button collapses competence boxes")
	assert("Risorse" not in tab_titles and area._tracker_rows.get_parent() != area._name.get_parent().get_parent()
		and area._tracker_rows.get_parent() == area._attacks_description.get_parent(),
		"Trackers must be inside Statistics rather than Info or a separate tab")
	area._choose_miniature(area._current(), false, true)
	area._miniature_filter.text = "ape"
	area._miniature_filter.text_changed.emit("ape")
	area._on_miniature_selected(0)
	area._miniature_dialog.hide() # Native confirmation closes the window before emitting.
	area._confirm_miniature()
	area._miniature_dialog.hide()
	assert(area._form_hp_dialog.visible, "Switching current appearance should offer a transformed HP pool")
	area._form_hp_choice.select(0)
	area._form_hp_manual.value = 12
	area._form_hp_dialog.hide()
	area._apply_second_form_choice()
	assert(area._current().second_form_hp == 12)
	assert(area._current().current_miniature_id == "ape" and area._current().default_miniature_id == "hero_test",
		"Changing current appearance without a live token must preserve default miniature")
	area._restore_default_appearance()
	assert(area._restore_form_dialog.visible,
		"Returning to base appearance should ask about nonzero transformed HP")
	area._restore_form_dialog.hide()
	area._restore_base_form(true)
	assert(area._current().current_miniature_id == "hero_test" and area._current().second_form_hp == 0,
		"Reset appearance should restore base and clear the transformed HP pool when confirmed")
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
	assert(area._miniature_dialog.is_ancestor_of(area._miniature_filter))
	assert(area._automatic_dialog.is_ancestor_of(area._automatic_hp),
		"Dialog content must remain inside its scrollable body and native footer")
	var original_id: String = area._current().id
	# Before any token exists, the + row action enters token placement.
	area._act_on_creature_token(original_id)
	assert(board.requested_creature_id == original_id)
	assert(not area.is_panel_open())
	area.show_panel()
	var current_row: Button = area._creature_row_buttons[0]
	area.show_panel()
	assert(area._creature_row_buttons[0] == current_row,
		"Opening the already-visible Creature panel must not reload the archive")
	area._select_creature_row(0)
	assert(area._creature_row_buttons[0] == current_row,
		"Selecting the current creature must not recreate its form")
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
	assert(area._temp_hp.get_parent() == area._hp.get_parent()
		and area._ac.get_parent() != area._temp_hp.get_parent(),
		"Temporary HP share the health panel; armor class belongs to Statistics")
	var hp_row: Control = area._hp.get_parent()
	assert(hp_row.get_child(0) is HBoxContainer
		and (hp_row.get_child(1) as Label).text == "Attuali"
		and area._hp.get_index() == 2,
		"HP −/+ controls must precede the current HP label and value")
	assert((hp_row.get_child(area._temp_hp.get_index() - 1) as Label).text == "+"
		and (hp_row.get_child(area._temp_hp.get_index() + 1) as Label).text == "TEMP",
		"Temporary HP must display + [value] TEMP")
	assert(area._party.get_parent() == area._name.get_parent(),
		"Faction must be alongside character name")
	area._level.value = 5
	area._save()
	var sheet: Dictionary = area._current()
	assert(sheet.classes[0].source == "PHB" and sheet.rules_version == "2014")
	assert(sheet.classes[0].level == 5 and sheet.level == 5)
	assert(int(sheet.get("proficiency_bonus", 0)) == 3
		and Bonuses.value(sheet, "proficiency") == 3
		and area._proficiency_display.text == "+3",
		"Changing class level must immediately refresh the proficiency formula")
	# Selecting a race/subrace/background in the live sheet must materialize
	# origin-backed benefits without opening or applying Automatic Calculate.
	var Defenses = load("res://vtt/creature_damage_defenses_tab.gd")
	area._select_reference(area._species, "Dwarf", "PHB")
	area._on_species_changed()
	var dwarf_live: Dictionary = area._current()
	assert(Defenses.rank(dwarf_live, "poison") == 1)
	var found_dwarf_origin := false
	for row: Dictionary in dwarf_live.get("damage_defense_entries", []):
		if String(row.get("origin_id", "")) == "race|phb|dwarf" and String(row.get("key", "")) == "poison":
			found_dwarf_origin = true
	assert(found_dwarf_origin, "Selecting Dwarf must save its poison resistance origin")
	area._select_reference(area._subrace_choice, "Hill", "PHB")
	area._on_subrace_changed()
	assert(Defenses.rank(area._current(), "poison") == 1,
		"Selecting a dwarf subrace must retain parent race grants immediately")
	area._select_reference(area._species, "Elf", "PHB")
	area._on_species_changed()
	assert(Defenses.rank(area._current(), "poison") == 0,
		"Replacing a race must withdraw its structured defense origins")
	area._select_reference(area._background, "Acolyte", "PHB")
	area._save()
	assert(ProficiencyRules.has_proficiency(area._current(), "skill", "insight"),
		"Selecting a background must immediately grant structured proficiencies")
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
	var bonus_rows: Array = area._current().get("formula_bonuses", []).duplicate(true)
	bonus_rows.append({"id": "test-con", "target": "ability:con", "expression": "2",
		"origin_id": "", "origin_name": "UI test", "disabled": false})
	area._on_bonuses_updated(bonus_rows, area._current().get("proficiency_origins", []))
	assert(Bonuses.value(area._current(), "ability:con") == 12,
		"An originless CON grant must modify the effective score")
	assert(area._ability_modifier_labels["con"].text == "+1")
	assert(Rules.automatic_hit_points(area._with_effective_modifiers(area._current())).value == 27,
		"CON score bonus must change computed HP")
	area._on_bonuses_updated([], area._current().get("proficiency_origins", []))
	area._open_automatic_calculation()
	assert(not area._automatic_hp.button_pressed)
	area._automatic_hp.button_pressed = true
	area._automatic_proficiency.button_pressed = true
	area._automatic_spells.button_pressed = true
	area._apply_automatic_calculation()
	area._automatic_dialog.hide()
	var automatically_calculated: Dictionary = area._current()
	assert(automatically_calculated.max_hp == 22, "Wizard 5, CON +0: 6 + 4 * 4")
	area._on_bonuses_updated([{
		"id": "test-hp", "target": "hp", "expression": "5",
		"origin_id": "", "origin_name": "UI test"
	}], area._current().get("proficiency_origins", []))
	assert(area._max_hp_effective.text == "27", "Health formula shows effective max before base + bonus")
	assert(area._current().max_hp == 27 and area._current().max_hp_base == 22
		and Bonuses.bonus(area._current(), "hp") == 5,
		"Origin-scoped HP bonus must increase effective maximum")
	area._on_bonuses_updated([{
		"id": "test-speed", "target": "speed", "expression": "10",
		"origin_id": "", "origin_name": "UI test"
	}], area._current().get("proficiency_origins", []))
	assert(area._current().speed == area._current().speed_base + 10
		and area._speed_effective.text == str(area._current().speed),
		"Movement bonus must add to the structured speed base")
	area._on_bonuses_updated([], area._current().get("proficiency_origins", []))
	area._biography.text = "Storia e personalità di prova"
	area._save()
	assert(area._current().background_personality == "Storia e personalità di prova",
		"Freeform background and personality must persist")
	assert(area._background != null, "The Info tab must expose a background selector")
	area._select_reference(area._background, "Acolyte", "PHB")
	area._save()
	assert(String(area._current().get("background", "")) == "Acolyte"
		and String(area._current().get("background_source", "")) == "PHB",
		"Selecting a structured background must persist its name and source")
	area._reload()
	assert(ProficiencyRules.has_proficiency(area._current(), "skill", "insight"),
		"The selected Acolyte background must grant its structured Insight proficiency")
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
	assert(int(sheet.xp) >= Rules.experience_for_level(7), "XP must meet the total class-level threshold")
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
	assert(area._statistics_columns.get_child_count() == 2,
		"Statistics must have dedicated skill and combat columns")
	assert(area._feats_ui != null and area._feats_toggle_button != null
		and not area._feats_ui.visible,
		"Talenti is a separately collapsible Statistics section (hidden initially)")
	area._feats_toggle_button.emit_signal("pressed")
	assert(area._feats_ui.visible
		and area._feats_toggle_button.text == "▾ Nascondi talenti"
		and area._feats_ui.get_child(1) is HBoxContainer,
		"Talenti opens two matching origins/grants columns without moving the statistics columns")
	area._feats_toggle_button.emit_signal("pressed")
	assert(not area._feats_ui.visible
		and area._feats_toggle_button.text == "▸ Visualizza talenti",
		"Talenti can be collapsed like Competenze and Bonus")
	assert(area._skill_buttons.size() == 18,
		"All canonical 5etools/D&D 5e skills must be present")
	assert(int(area._passive_perception.text) >= 10,
		"Passive perception must be calculated from Wisdom and skill ranks")
	assert(area._saving_throw_labels.size() == 6,
		"Each ability shows a saving throw result")
	assert((area._saving_throw_icons["wis"] as Label).text == "🎓"
		and (area._saving_throw_labels["wis"] as Label).text.begins_with("+"),
		"Proficient Wisdom saving throw must separate its marker from the numeric formula")
	var wisdom_saving: Label = area._saving_throw_labels["wis"]
	var wisdom_formula: Node = area._formula_values["ability:wis"]
	assert(area._abilities_grid.columns == 5
		and area._formula_values["save:wis"].get_parent().get_parent() == area._abilities_grid
		and wisdom_formula.get_parent().get_parent() == area._abilities_grid,
		"Saving throws, scores and modifiers must share four aligned table columns")
	assert((area._abilities_grid.get_child(3) as Label).text == "TS",
		"TS should appear once as a table header, not beside every saving throw")
	assert(area._tools_proficiency_label != null and "Strumenti:" in area._tools_proficiency_label.text
		and area._languages_proficiency_label != null
		and "Linguaggi:" in area._languages_proficiency_label.text,
		"Statistics must display tool and language proficiencies together")
	assert(not area._formula_values.is_empty(), "Computed score formulas remain available")
	var formula_widget: Node = area._formula_values["ability:wis"]
	var frame: StyleBox = formula_widget.value_label.get_theme_stylebox("normal") as StyleBox
	assert(frame is StyleBoxFlat and not (frame as StyleBoxFlat).draw_center,
		"Formula indicator is a transparent outline, not an inline ƒ glyph")
	var rows: Array = area._current().get("proficiency_choices", []).duplicate(true)
	rows.append({"kind": "skill", "key": "perception", "origin_id": "custom|ui-regression",
		"origin_name": "Test source", "disabled": false})
	var sources: Array = area._current().get("proficiency_origins", []).duplicate(true)
	sources.append({"id": "custom|ui-regression", "name": "Test source", "disabled": false,
		"automatic": false})
	area._on_proficiencies_updated(rows, area._current().get("feats_catalog", []), sources)
	assert(int(area._skill_ranks["perception"]) == 1,
		"Adding skill competence through the origin editor updates Statistics")
	assert("🎓" in (area._skill_buttons["perception"] as Label).text,
		"Skill training appears as an emoji after the skill name")
	area._reload()
	assert(int(area._skill_ranks["perception"]) == 1,
		"Skill competence must survive reload")
	assert(area._statistics_columns is HBoxContainer
		and area._statistics_columns.get_child_count() == 2,
		"Statistics must always retain side-by-side skill and combat columns")
	area._update_sheet_layout()
	var skills_view: ScrollContainer = area._statistics_columns.get_child(0)
	var combat_view: ScrollContainer = area._statistics_columns.get_child(1)
	assert(skills_view.get_child(0) is VBoxContainer
		and combat_view.get_child(0) is VBoxContainer,
		"Skill and combat details must stay in separate columns")
	assert(is_equal_approx(skills_view.size_flags_stretch_ratio, 0.9)
		and is_equal_approx(combat_view.size_flags_stretch_ratio, 1.1),
		"Combat should get moderately more width, rather than a vertically stacked layout")
	assert(skills_view.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and combat_view.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and area._abilities_grid.columns == 5,
		"Oversized details should scroll inside their own columns while ability values remain tabular")
	area._update_stats_column_heights()
	assert(skills_view.custom_minimum_size.y > 0
		and is_equal_approx(skills_view.custom_minimum_size.y, combat_view.custom_minimum_size.y),
		"Both columns should expose the full height of their contents to the outer vertical scroll")
	var combat_stats: Node = area._attacks_description.get_parent()
	assert(area._tracker_rows.get_parent() == combat_stats
		and area._tracker_rows.get_index() < area._attacks_description.get_index(),
		"Trackers should appear above the list of available attacks")
	assert(area._hand_main_picker != null and area._hand_off_picker != null
		and area._hand_main_picker.item_count >= 3 and area._hand_off_picker.item_count >= 3,
		"Both hands must default to None and offer unarmed/improvised strikes")
	assert(area._hand_main_picker.get_item_text(0) == "Niente"
		and area._hand_off_picker.get_item_text(0) == "Niente",
		"Empty is the default hand choice, never automatic unarmed or an inventory weapon")
	assert(area._hand_main_picker.get_parent().get_index() < area._attack_rows.get_index()
		and area._armor_picker != null,
		"Hand selectors precede attack cards; armor selector is beside AC")
	assert(area._formula_values["hp"].value_label == area._max_hp_effective
		and area._formula_values["hp"]._editor.visible == false,
		"HP maximum should be a compact readout, not a permanently visible formula")
	assert(area._formula_values["initiative"]._fields.is_empty(),
		"Initiative is derived from DEX and has no editable base")
	# Readouts that represent rolls must use their displayed effective bonuses.
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	for roll_key: String in ["initiative", "ability_mod:str", "skill:perception", "save:wis"]:
		var roll_widget: Node = area._formula_values[roll_key]
		assert(roll_widget.roll_on_click, "Expected click-to-roll for " + roll_key)
		hp_roller.last_expression = ""
		roll_widget._on_readout_input(left_click)
		assert(hp_roller.last_expression == "1d20%+d" % Bonuses.value(area._live_stats_record(), roll_key),
			"Click-to-roll must evaluate current bonuses for " + roll_key)
	assert(not area._formula_values["ability:str"].roll_on_click,
		"Editable characteristic scores should not be rolled instead of modified")
	assert(area._formula_values["attack_hit:unarmed"].roll_on_click
		and area._formula_values["attack_damage:unarmed"].roll_on_click,
		"Attacks and damage should roll by clicking their formula readouts")
	area._formula_values["attack_hit:unarmed"]._on_readout_input(left_click)
	assert(hp_roller.last_expression.begins_with("1d20"),
		"Clicking hit values must reuse the attack roll logic")
	var first_card: PanelContainer = area._attack_rows.get_child(0)
	var attack_box: VBoxContainer = first_card.get_child(0)
	for row_index: int in [1, 2]:
		for child: Node in attack_box.get_child(row_index).get_children():
			assert(not (child is Button), "No dedicated roll buttons should remain in attack rows")
	area._on_formula_bonus_requested("initiative")
	assert(area._bonuses_ui.visible and String(area._bonuses_ui.get("_selected_target")) == "initiative",
		"Framed values must navigate to the selected cumulative bonus editor")
	assert(area._formula_values["ability:con"]._fields.size() == 1,
		"Ability scores retain only their static base editor")
	assert("Colpo senz'armi" in area._attacks_description.text
		and "Arma improvvisata" in area._attacks_description.text,
		"Unarmed and improvised attacks must appear while no weapon is equipped")
	assert(area._attack_rows.get_child_count() > 0,
		"The attack panel must show at least one complete card")
	var first_attack_card: PanelContainer = area._attack_rows.get_child(0) as PanelContainer
	var first_attack_content: VBoxContainer = first_attack_card.get_child(0) as VBoxContainer
	assert(first_attack_content.get_child(0) is HBoxContainer
		and first_attack_content.get_child(1) is HFlowContainer
		and first_attack_content.get_child(2) is HFlowContainer,
		"Attack names, hit and damage must occupy separate responsive rows")
	assert((area._attack_hit_labels["unarmed"] as Label).text.begins_with("+"),
		"Attack hit formulas use compact numeric readouts without repeated labels")
	var fallback_view_record: Dictionary = area._current().duplicate(true)
	var shield_only: Dictionary = {
		"id": "test:shield", "name": "Shield", "type": "S", "ac": 2,
		"source": "PHB", "quantity": 1, "equipped_slots": ["off"]
	}
	fallback_view_record["inventory"] = [shield_only]
	area._refresh_attacks(fallback_view_record)
	assert(area._attack_hit_labels.has("unarmed") and area._attack_hit_labels.has("improvised"),
		"Equipping only a shield must not hide either fallback attack")
	var test_weapon: Dictionary = {
		"id": "test:sword", "name": "Sword", "type": "M", "damage": "1d8",
		"source": "PHB", "quantity": 1, "equipped_slots": ["main"]
	}
	fallback_view_record["inventory"] = [test_weapon, shield_only]
	fallback_view_record["equipped_attack_id"] = "unarmed"
	assert(String(AttackData.active_attack(fallback_view_record).get("id", "")) == "item:test:sword",
		"A newly equipped weapon must replace an outdated unarmed active choice")
	area._refresh_attacks(fallback_view_record)
	assert(not area._attack_hit_labels.has("unarmed") and not area._attack_hit_labels.has("improvised")
		and "Colpo senz'armi" not in area._attacks_description.text
		and "Arma improvvisata" not in area._attacks_description.text,
		"Equipping a weapon must hide both fallback attacks from the combat UI")
	test_weapon["equipped_slots"] = []
	fallback_view_record["inventory"] = [test_weapon, shield_only]
	area._refresh_attacks(fallback_view_record)
	assert(area._attack_hit_labels.has("unarmed") and area._attack_hit_labels.has("improvised"),
		"Unequipping the last weapon must restore both attacks immediately")
	area._refresh_attacks(area._current())
	# Monster descriptions used to expand every card permanently and could
	# make the combat pane taller than the viewport.
	var monster_attacks: Dictionary = area._current().duplicate(true)
	monster_attacks["kind"] = "monster"
	monster_attacks["equipped_attack_id"] = "monster:action:0"
	monster_attacks["stat_block"] = {
		"action": [{"name": "Artiglio", "entries": [
			"{@atk mw} {@hit +5} to hit, reach 5 ft. {@damage 1d6+3} slashing damage."
		]}]
	}
	monster_attacks["inventory"] = []
	area._refresh_attacks(monster_attacks)
	var raw_card: PanelContainer = area._attack_rows.get_child(0) as PanelContainer
	var raw_content: VBoxContainer = raw_card.get_child(0) as VBoxContainer
	var raw_toggle: Button = null
	var raw_description: RichTextLabel = null
	for child: Node in raw_content.get_children():
		if child is Button and (child as Button).text.contains("Descrizione del bestiario"):
			raw_toggle = child as Button
		if child is RichTextLabel:
			raw_description = child as RichTextLabel
	assert(raw_toggle != null and raw_description != null
		and not raw_description.visible and raw_description.scroll_active,
		"Monster attack source text must be collapsed and scrollable by default")
	raw_toggle.pressed.emit()
	assert(raw_description.visible, "The original monster description should expand on demand")
	raw_toggle.pressed.emit()
	assert(not raw_description.visible, "The original monster description should collapse again")
	area._refresh_attacks(area._current())
	var spells: Node = area._spellcasting_ui
	assert(spells._known_list.custom_minimum_size.y == spells._prepared_list.custom_minimum_size.y,
		"Class and available spell boxes must have the same height")
	assert(spells._search_toggle.get_parent().get_index() > spells._known_list.get_parent().get_parent().get_index(),
		"Spell search button must be underneath both spell lists")
	assert(spells._description.get_parent().get_parent() == spells
		and spells._prepare.get_parent().get_parent() == spells
		and spells._description.get_parent().get_index() > spells._prepare.get_parent().get_index()
		and spells._description.scroll_active,
		"Spell details must occupy a scrollable row below the compact action button")
	assert(not spells._search_row.visible and spells._known_list.item_count > 0,
		"Class spell list must be automatic and search optional")
	assert(spells._slot_grid.columns == 1
		and spells._remaining_labels[1].get_parent() is HBoxContainer
		and spells._slot_grid.get_parent() is ScrollContainer,
		"Slots should use wrapped tracker rows with remaining/max and on-demand editing")
	assert(spells._slot_formula_values[1].value_label.text == str(spells._effective_slot_total(1))
		and spells._slot_formula_values[1]._readout.tooltip_text.contains("bonus"),
		"Spell slot maximum must expose a compact number and full hover formula")
	assert(spells._pact_remain.get_index() < spells._pact_formula_value.get_parent().get_index(),
		"Pact Magic remaining/max must precede its base-and-bonus formula")
	spells._known_list.select(0)
	spells._on_spell_list_selected("known")
	assert(spells._description.visible and not spells._description.text.is_empty(),
		"Class spell selection must always resolve a description")
	spells._deselect_spell_item("known", 0)
	assert(spells._known_list.get_selected_items().is_empty() and not spells._description.visible,
		"Clicking an already selected class spell must deselect it")
	assert(spells._class_spell_level_limits().get("wizard", -1) == 3,
		"Wizard 6 must unlock class spells through level 3")
	for class_spell: Dictionary in spells._known:
		assert(int(class_spell.get("level", 0)) <= 3,
			"Spells above the class's unlocked level must not appear")
	spells._set_search_visible(true)
	assert(spells._search_row.visible)
	spells._search.text = "Magic Missile"
	spells._search.text_changed.emit("Magic Missile")
	assert(not spells._visible.is_empty(), "5etools spell catalog must be searchable")
	var missile_index: int = -1
	for index: int in range(spells._visible.size()):
		if String(spells._visible[index].get("name", "")) == "Magic Missile":
			missile_index = index
			break
	assert(missile_index >= 0, "Search must include the exact requested spell alongside description matches")
	spells._available.select(missile_index)
	spells._on_spell_list_selected("catalog")
	assert(spells._description.visible and "Magic Missile" in spells._description.text,
		"Selecting a search result must display its detailed spell text")
	spells._toggle_selected_prepared()
	assert(spells._description.visible and "Magic Missile" in spells._description.text,
		"Updating prepared spells must not erase the description of a selected catalog spell")
	spells._prepared_list.select(0)
	spells._on_spell_list_selected("prepared")
	assert(spells._description.visible and "Magic Missile" in spells._description.text,
		"Available spell list must resolve the full description, not just saved metadata")
	spells._deselect_spell_item("prepared", 0)
	assert(spells._prepared_list.get_selected_items().is_empty() and not spells._description.visible,
		"Clicking the selected available spell must deselect it")
	assert(area._current().spells.size() == 1)
	assert(area._current().prepared_spells.size() == 1)
	spells._calculate_slot_totals()
	assert(area._current().spell_slots_total[1] == 4)
	area._on_bonuses_updated([{
		"id": "test-slot", "target": "slot:1", "expression": "2",
		"origin_id": "", "origin_name": "UI test"
	}], area._current().get("proficiency_origins", []))
	assert(Bonuses.bonus(area._current(), "slot:1") == 2
		and spells._remaining_labels[1].text == "6 /"
		and spells._slot_formula_values[1].value_label.text == "6",
		"Spell slot bonuses stack on the maximum and persist independently of the base")
	area._on_bonuses_updated([], area._current().get("proficiency_origins", []))
	spells._change_slot(1, 1)
	assert(area._current().spell_slots_spent[1] == 1)
	spells._change_slot(1, -1)
	assert(area._current().spell_slots_spent[1] == 0)
	spells._change_slot(1, 1)
	spells._calculate_slot_totals(true)
	assert(area._current().spell_slots_spent[1] == 0,
		"Automatic recharge must both recalculate class slots and restore availability")
	spells._restore_all()
	assert(area._current().spell_slots_spent[1] == 0)
	assert(spells._slot_grid.get_parent().visible and spells._pact_row.get_parent().visible,
		"Both resource groups are visible by default")
	spells._toggle_slots_visibility()
	assert(not spells._slot_grid.get_parent().visible and spells._pact_row.get_parent().visible,
		"Slot visibility must not affect Pact Magic")
	spells._toggle_pact_visibility()
	assert(not spells._pact_row.get_parent().visible and not spells._slot_grid.get_parent().visible,
		"Pact Magic must collapse independently")
	assert(not area._current().spell_slots_visible and not area._current().pact_slots_visible,
		"Resource visibility must be stored")
	area._reload()
	assert(not spells._slot_grid.get_parent().visible and not spells._pact_row.get_parent().visible,
		"Visibility must survive sheet reload")
	spells._toggle_slots_visibility()
	spells._toggle_pact_visibility()
	assert(area._current().spell_slots_visible and area._current().pact_slots_visible)
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
	var document_editor: Node = inventory._documents_tab
	assert(document_editor != null, "Inventario must contain a Documents subtab")
	document_editor._add_document()
	assert(area._current().documents.size() == 1,
		"Adding a document must persist its inventory reference")
	document_editor._title_edit.text = "Lettera d'invito"
	document_editor._body_edit.text = "Presentarsi al castello al tramonto."
	document_editor._update_document()
	assert("Lettera" in document_editor._paper_text.text,
		"Document parchment preview must be regenerated from text")
	assert(document_editor._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Document image should keep rendering even when the tab is not visible")
	assert(document_editor._image_button != null
		and document_editor._preview.texture == document_editor._full_image.texture
		and document_editor._paper.size == Vector2(640, 780),
		"Document thumbnail and zoom window must share the generated paper image")
	area._reload()
	assert(area._current().documents.size() == 1
		and String(area._current().documents[0].get("title", "")) == "Lettera d'invito",
		"Documents and contents must survive a creature reload")
	document_editor._remove_document()
	assert(area._current().documents.is_empty(),
		"Deleting a document must persist its removal")
	var image_helper: Script = load("res://vtt/item_image_preview.gd")
	assert(not String(image_helper.image_source({"name": "Bag of Holding", "source": "DMG"})).is_empty(),
		"Verified official item artwork must be indexed by source and name")
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
	area._ac.value = 15
	area._natural_ac_formula.text = "15"
	area._save()
	var combat_bonus_rows: Array = area._current().get("formula_bonuses", []).duplicate(true)
	combat_bonus_rows.append({"id": "ui-ac", "target": "ac", "expression": "2", "origin_id": ""})
	combat_bonus_rows.append({"id": "ui-initiative", "target": "initiative", "expression": "3", "origin_id": ""})
	area._on_bonuses_updated(combat_bonus_rows, area._current().get("proficiency_origins", []))
	assert(area._current().armor_class_base == 15
		and Bonuses.bonus(area._current(), "ac") == 2
		and area._current().armor_class == 17,
		"CA must persist its static base and additive origin bonus separately")
	assert(area._current().initiative == Bonuses.value(area._current(), "ability_mod:dex") + 3,
		"Initiative must include its originless grant")
	area._reload()
	assert(Bonuses.bonus(area._current(), "ac") == 2
		and Bonuses.bonus(area._current(), "initiative") == 3
		and area._ac_effective.text == "17",
		"Origin-backed AC and initiative bonuses must survive reloading the sheet")
	var transformation_preview: Dictionary = area._current().duplicate(true)
	transformation_preview["current_miniature_id"] = "alternate-form-test"
	area._update_current_appearance_display(transformation_preview)
	assert(area._current_miniature_row.visible and "alternate-form-test" in area._current_miniature_name.text,
		"A transformed creature must show the current appearance distinct from its base form")
	transformation_preview["current_miniature_id"] = transformation_preview.get("default_miniature_id", "")
	area._update_current_appearance_display(transformation_preview)
	assert(not area._current_miniature_row.visible,
		"The current-form row must hide when the base appearance is restored")
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
	area._second_form_max_hp.value = 6
	area._second_form_hp.value = 6
	area._temp_hp.value = 2
	area._save()
	area._change_hit_points(-5)
	assert(area._current().temporary_hp == 0 and area._current().second_form_hp == 3
		and area._current().current_hp == 34,
		"Damage must consume the form after temporary HP, but before base HP")
	area._change_hit_points(-5)
	assert(area._current().second_form_hp == 0 and area._current().current_hp == 32,
		"Excess damage from the depleted form must reach base HP")
	area._second_form_max_hp.value = 0
	area._save()
	area._restore_full_hp()
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
	area._save_attack_setting("unarmed", "range_feet", 15)
	area._front.select(2)
	area._party.text = "Explorers"
	area._save()
	var attack_bonus_rows: Array = area._current().get("formula_bonuses", []).duplicate(true)
	attack_bonus_rows.append({"id": "ui-hit", "target": "attack_hit:unarmed", "expression": "2", "origin_id": ""})
	attack_bonus_rows.append({"id": "ui-damage", "target": "attack_damage:unarmed", "expression": "2", "origin_id": ""})
	area._on_bonuses_updated(attack_bonus_rows, area._current().get("proficiency_origins", []))
	area._reload()
	assert(area._current().size_name == "Large" and area._current().footprint == 2.0)
	assert(area._current().reach_feet == 15 and area._current().visual_front_quarter_turns == 2)
	assert(area._current().attack_overrides.unarmed.range_feet == 15
		and Bonuses.bonus(area._current(), "attack_hit:unarmed") == 2
		and Bonuses.bonus(area._current(), "attack_damage:unarmed") == 2,
		"Each attack must persist its own range and cumulative hit/damage grants")
	assert((area._attack_hit_labels["unarmed"] as Label).text.begins_with("+"),
		"Unarmed attack must show its proficiency-adjusted hit modifier")
	area._attack_ability.select(1)
	area._on_attack_ability_changed(1)
	assert(area._current().attack_ability == "dex",
		"STR/DEX preference must be persisted on the creature")
	area._reload()
	assert(area._attack_ability.selected == 1,
		"Attack ability selection must survive reload")
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
	assert(automatic.reach_feet != 15.0,
		"Token editor must not replace the range owned by individual attacks")
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
