extends SceneTree
const Tab = preload("res://vtt/creature_spellcasting_tab.gd")
const Choices = preload("res://vtt/class_spell_selection.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
class Sink extends Node:
	var values: Dictionary = {}
	func changed(update: Dictionary) -> void:
		values = update.duplicate(true)
	func cast(_spell: Dictionary, _level: int, _grant: Dictionary = {}) -> bool:
		return true
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 850)
	var sink := Sink.new()
	root.add_child(sink)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var tab := Tab.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tab)
	tab.setup(Callable(sink,"changed"), Callable(), Callable(sink,"cast"))
	var record: Dictionary = {"kind":"character", "rules_version":"2014", "abilities":{"int":16,"cha":16},
		"classes":[{"name":"Wizard","source":"PHB","level":3}, {"name":"Bard","source":"PHB","level":3}, {"name":"Warlock","source":"PHB","level":2}]}
	tab.load_record(record)
	assert(tab._view._rows.size() >= 2)
	assert(tab._view.find_children("Class_*", "VBoxContainer", true, false).size() == 3)
	var class_abilities: Array[String] = []
	for picker: Node in tab._view.find_children("CastingAbility", "OptionButton", true, false):
		class_abilities.append(String((picker as OptionButton).get_selected_metadata()))
	assert("int" in class_abilities and "cha" in class_abilities,
		"Multiclass sections have independent selectable casting abilities")
	assert(tab._spell_summary.get_parent() == tab._drop_concentration_button.get_parent()
		and tab._spell_summary.get_index() + 1 == tab._drop_concentration_button.get_index(),
		"Stop concentration is directly beside the current spell")
	assert(tab._concentration_row.get_parent() == tab and
		tab._spell_ability_choice.get_parent().get_parent().name == "LegacySpellControls",
		"Global casting settings no longer appear in the sheet")
	var wizard: Dictionary = Choices.classes(record)[0]
	assert(tab._section_ability(wizard.id, ["int"]) == "int")
	tab._change_section_ability(wizard.id, "cha")
	assert(tab._section_ability(wizard.id, ["int"]) == "cha"
		and sink.values.get("spellcasting_section_abilities", {}).get(wizard.id) == "cha",
		"Each class has one editable, persisted casting ability")
	assert(tab._section_ability("origin:shadow", ["wis", "", "int"]) == "wis",
		"An origin with conflicting grants has exactly one inferred ability")
	tab._change_section_ability("origin:shadow", "cha")
	assert(tab._section_ability("origin:shadow", ["wis", "int"]) == "cha",
		"A single origin selection supersedes conflicting per-spell suggestions")
	assert("Modifier:" in tab._section_casting_stats("int") or "Modificatore:" in tab._section_casting_stats("int"))
	tab._view_edit_class(wizard)
	assert(tab._selection_dialog.visible and not tab._selection_dialog._details.visible)
	await process_frame
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		assert(tab._selection_dialog.size.y <= root.size.y - 30, "Selection popup stays inside the viewport")
		assert(tab._selection_dialog._rows.get_parent().size.y <= 440, "The results list has a bounded scrolling viewport")
		root.get_texture().get_image().save_png("user://spellcasting_selector_review.png")
	var pick := ""
	for spell: Dictionary in tab._selection_dialog._catalog:
		if int(spell.get("level",0)) == 1:
			pick = String(spell.id)
			break
	assert(not pick.is_empty())
	assert(tab._selection_dialog._checks.has(pick))
	var real_checkbox: CheckBox = tab._selection_dialog._checks[pick]
	await process_frame
	var result_scroll: ScrollContainer = tab._selection_dialog._rows.get_parent()
	var selector_wheel := InputEventMouseButton.new()
	selector_wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	selector_wheel.pressed = true
	selector_wheel.position = result_scroll.get_global_rect().get_center()
	selector_wheel.global_position = selector_wheel.position
	tab._selection_dialog.push_input(selector_wheel, true)
	await process_frame
	assert(result_scroll.scroll_vertical > 0, "The actual selection popup scrolls its result list")
	result_scroll.scroll_vertical = 0
	await process_frame
	await process_frame
	real_checkbox.button_pressed = true
	assert(tab._selection_dialog._selected.has(pick) and tab._selection_dialog._book.has(pick),
		"Preparing from the wizard popup also records the spell in the book")
	assert(is_instance_valid(real_checkbox), "Selecting does not rebuild the list or lose its scroll position")
	tab._selection_dialog._save()
	tab._selection_dialog.hide()
	assert(tab._prepared.size() == 1 and tab._spellbook.size() == 1)
	assert(wizard.id in tab._prepared[0].casting_classes)
	assert(sink.values.prepared_spells.size() == 1)
	assert(tab._view._rows[0].get_child_count() == 2)
	tab._open_resource_settings()
	await process_frame
	await process_frame
	assert(tab._resource_settings.visible and tab._slot_formula_values[1].value_label.is_visible_in_tree(),
		"Slot maxima remain visible in their editing popup")
	tab._slot_formula_values[1].open_editor()
	assert(tab._slot_totals[1].is_visible_in_tree(), "Explicitly editing a maximum reveals the original input")
	tab._slot_formula_values[1].close_editor()
	tab._resource_settings.hide()
	tab._view_edit_manual()
	var manual_pick := ""
	for spell: Dictionary in tab._selection_dialog._catalog:
		if String(spell.id) != pick:
			manual_pick = String(spell.id)
			break
	tab._selection_dialog._selected[manual_pick] = true
	tab._selection_dialog._save()
	tab._selection_dialog.hide()
	var manual_found := false
	for entry: Dictionary in tab._prepared:
		if String(entry.id) == manual_pick:
			manual_found = "manual" in entry.casting_classes
	assert(manual_found, "Manual/monster selections remain usable alongside class selections")
	tab._view_slot(1, 1)
	assert(int(tab._spent[1]) == 1)
	tab._view_pact(1)
	assert(tab._pact_spent == 1)
	var grant: Dictionary = {}
	for entry: Dictionary in Grants.all_grants(tab._view_record()):
		if String(entry.get("spell_id","")) == Grants.BARDIC:
			grant = entry
	assert(not grant.is_empty())
	var id: String = String(grant.tracker_id)
	tab._view_tracker(1, id, 3)
	assert(int(sink.values.resource_tracker_spent[id]) == 1)
	var external: Dictionary = tab._view_record()
	external.resource_tracker_spent[id] = 2
	tab.refresh_spell_state(external)
	assert(int(tab._view_record().resource_tracker_spent[id]) == 2)
	await process_frame
	await process_frame
	for label: Node in tab._view.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and not label.text.is_empty():
			assert(label.size.x > 10, "Every caption and counter has a usable width: %s (%s), width %s" % [label.name, label.text, str(label.size.x)])
	# The panel may be taller now to show a complete first power; check the
	# actual slot headings instead of imposing a fixed height on both columns.
	var slot_headers: GridContainer = tab._view._rows[0].get_child(1).get_child(0).get_node("SlotGrid")
	for column: int in range(3):
		var heading: Label = slot_headers.get_child(column) as Label
		assert(heading != null and heading.size.x >= 20 and heading.size.y < 70,
			"Slot headings stay readable and do not wrap into vertical letters")
	var conflict: Dictionary = tab._view_record()
	conflict["proficiency_origins"] = [{"id": "custom:example", "name": "Example", "group": "custom"}]
	conflict["origin_spell_grants"] = [
		{"id": "one", "origin_id": "custom:example", "origin_name": "Example",
			"spell_id": "bless", "payment_mode": "free", "spellcasting_ability": "wis"},
		{"id": "two", "origin_id": "custom:example", "origin_name": "Example",
			"spell_id": "cure_wounds", "payment_mode": "free", "spellcasting_ability": ""}
	]
	tab.refresh_spell_state(conflict)
	var free_group_count: int = 0
	for section_row: HBoxContainer in tab._view._rows:
		var left_section: VBoxContainer = section_row.get_child(0).get_child(0)
		if left_section.get_child_count() == 0:
			continue
		var header: Label = left_section.get_child(0) as Label
		if header == null or header.text != "Senza consumo":
			continue
		free_group_count += 1
		assert(left_section.find_children("CastingAbility", "OptionButton", true, false).size() == 1
			and left_section.find_children("CastingStatistics", "Label", true, false).size() == 1,
			"Free powers from one origin retain a single spellcasting ability inside the resource group")
	assert(free_group_count == 1, "Free spells share one box instead of an origin box")
	# Two different origins spending the very same tracker must appear together.
	var shared: Dictionary = conflict.duplicate(true)
	shared["proficiency_origins"] = [
		{"id": "custom:example", "name": "Example", "group": "custom"},
		{"id": "custom:other", "name": "Other", "group": "custom"}
	]
	shared["resource_trackers"] = [{"id": "shared-uses", "name": "Cariche condivise", "max": 3}]
	shared["origin_spell_grants"] = [
		{"id": "one", "origin_id": "custom:example", "origin_name": "Example",
			"spell_id": "bless", "payment_mode": "tracker", "tracker_id": "shared-uses"},
		{"id": "two", "origin_id": "custom:other", "origin_name": "Other",
			"spell_id": "cure_wounds", "payment_mode": "tracker", "tracker_id": "shared-uses"}
	]
	tab.refresh_spell_state(shared)
	var shared_boxes := 0
	for section_row: HBoxContainer in tab._view._rows:
		var left: VBoxContainer = section_row.get_child(0).get_child(0)
		if left.get_child_count() == 0:
			continue
		var heading: Label = left.get_child(0) as Label
		if heading == null or heading.text != "Cariche condivise":
			continue
		shared_boxes += 1
		assert(left.find_children("CastingAbility", "OptionButton", true, false).size() == 2,
			"Each casting origin retains its spellcasting ability even when sharing a tracker")
		var power_rows: Array[Node] = left.find_children("PowerRow", "HBoxContainer", true, false)
		assert(power_rows.size() >= 2,
			"Different origins contribute powers to the same tracker box; got %d rows" % power_rows.size())
		assert(section_row.get_child(1).find_children("TrackerRow", "HBoxContainer", true, false).size() == 1,
			"The tracker counter only appears once per shared resource")
	assert(shared_boxes == 1, "Powers are grouped by tracker ID rather than origin")
	# A class/prepared spell list has level headings and alphabetic rows, never
	# a level or source suffix appended to the action button.
	var examples: Array[Dictionary] = [
		{"spell": {"name": "Zephyr", "level": 2}, "member": {}, "grant": {}},
		{"spell": {"name": "Breeze", "level": 1}, "member": {}, "grant": {}},
		{"spell": {"name": "Arcane Spark", "level": 0}, "member": {}, "grant": {}},
		{"spell": {"name": "Aegis", "level": 1}, "member": {}, "grant": {}}
	]
	var ordered: VBoxContainer = tab._view._leveled_spell_list(tab._view, examples)
	var headings: Array[String] = []
	var buttons: Array[String] = []
	for node: Node in ordered.get_children():
		if node.name == "SpellLevelHeader":
			headings.append((node as Label).text)
		elif node is HBoxContainer:
			buttons.append((node.get_child(0) as Button).text)
	assert(headings == ["Trucchetti", "Livello 1", "Livello 2"])
	assert(buttons == ["Arcane Spark", "Aegis", "Breeze", "Zephyr"])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://spellcasting_columns_review.png")
		print("REVIEW_IMAGE ",ProjectSettings.globalize_path("user://spellcasting_columns_review.png"))
	var caption: Node = root.get_node("ScrollableCaptions")
	var target := Button.new()
	target.text = "Descrizione lunga"
	target.tooltip_text = "Dettaglio dell'incantesimo.\n".repeat(80)
	target.position = Vector2(10,10)
	root.add_child(target)
	caption._target = target
	caption._text = target.tooltip_text
	caption._show_caption()
	await process_frame
	assert(caption._panel.size.y <= 340)
	assert(caption._body.get_v_scroll_bar().max_value > caption._body.get_v_scroll_bar().page)
	var before: float = caption._body.get_v_scroll_bar().value
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = caption._body.get_global_rect().get_center()
	wheel.global_position = wheel.position
	root.push_input(wheel,true)
	await process_frame
	assert(caption._body.get_v_scroll_bar().value > before, "The hover caption responds to the actual wheel")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://spell_caption_review.png")
	caption._panel.hide()
	caption._restore_target()
	var item_list := ItemList.new()
	item_list.position = Vector2(20,20)
	item_list.size = Vector2(240,80)
	item_list.add_item("Voce con descrizione")
	item_list.set_item_tooltip(0, "Caption dell'elemento della lista")
	root.add_child(item_list)
	caption._target = item_list
	caption._kind = "item"
	caption._item_index = 0
	caption._item_label = item_list.get_item_text(0)
	caption._text = item_list.get_item_tooltip(0)
	item_list.set_item_tooltip(0, "")
	caption._show_caption()
	await process_frame
	assert(caption._body.text == "Caption dell'elemento della lista", "List item captions use the same scrollable presenter")
	caption._restore_target()
	assert(item_list.get_item_tooltip(0) == "Caption dell'elemento della lista")
	var origin_button := preload("res://vtt/bounded_tooltip_button.gd").new() as Button
	origin_button.tooltip_text = "Descrizione di un'origine.\n".repeat(60)
	root.add_child(origin_button)
	caption._target = origin_button
	caption._text = origin_button.tooltip_text
	caption._show_caption()
	await process_frame
	assert(caption._body.text == origin_button.tooltip_text,
		"Origin buttons use the same hover presenter as spell descriptions")
	assert(caption._body.get_v_scroll_bar().max_value > caption._body.get_v_scroll_bar().page,
		"Long origin descriptions also scroll")
	caption._panel.hide()
	caption._restore_target()
	assert(origin_button.tooltip_text.begins_with("Descrizione di un'origine."))
	origin_button.free()
	item_list.free()
	target.free()
	scroll.free()
	sink.free()
	await process_frame
	print("PASS two-column spellcasting, multiclass selection, spellbook, resource sync and scrollable captions")
	quit()
