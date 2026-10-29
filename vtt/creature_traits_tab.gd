extends VBoxContainer

const ScrollBoundaryGuard = preload("res://vtt/nested_scroll_boundary_guard.gd")
const CreatureFeatures = preload("res://vtt/creature_features.gd")

# The traits sheet is a unified, level-ordered list. The data retains its
# catalog identifiers and source books; the UI exposes only useful origins.
const TraitText = preload("res://vtt/five_tools_rich_text.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")

signal section_requested(section: int)

var _origin_choice: OptionButton
var _search: LineEdit
var _counter: Label
var _scroll: ScrollContainer
var _cards_container: VBoxContainer
var _features: Array[Dictionary] = []
var _cards: Dictionary = {}
var _expanded: Dictionary = {}
var _active_origin := ""
var _record_id := ""
var _record: Dictionary = {}
var _monster_trackers: Array[Dictionary] = []
var _touch_filters: VBoxContainer
var _touch_filter_toggle: Button


func setup() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var explanation := Label.new()
	explanation.text = "Leggi i tratti per origine. Nelle descrizioni aperte trovi i collegamenti alle sezioni che gestiscono i benefici."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explanation)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	add_child(toolbar)
	var origin_caption := Label.new()
	origin_caption.text = "Origine"
	toolbar.add_child(origin_caption)
	_origin_choice = OptionButton.new()
	_origin_choice.fit_to_longest_item = false
	_origin_choice.custom_minimum_size.x = 190
	_origin_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_choice.item_selected.connect(_on_origin_selected)
	toolbar.add_child(_origin_choice)

	_search = LineEdit.new()
	_search.placeholder_text = "Cerca un tratto…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _rebuild())
	add_child(_search)
	var actions := HBoxContainer.new()
	add_child(actions)
	_counter = Label.new()
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.add_theme_color_override("font_color", Color(0.74, 0.68, 0.60))
	actions.add_child(_counter)
	var expand := Button.new()
	expand.text = "Espandi tutti"
	expand.pressed.connect(func() -> void: _set_all_expanded(true))
	actions.add_child(expand)
	var collapse := Button.new()
	collapse.text = "Comprimi"
	collapse.pressed.connect(func() -> void: _set_all_expanded(false))
	actions.add_child(collapse)

	_scroll = ScrollContainer.new()
	_scroll.mouse_force_pass_scroll_events = false
	ScrollBoundaryGuard.install(_scroll)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Rebuilding expanded cards must not drag the scroll to the focused button.
	_scroll.follow_focus = false
	add_child(_scroll)
	_cards_container = VBoxContainer.new()
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.add_theme_constant_override("separation", 7)
	_scroll.add_child(_cards_container)
	load_record({})


# On phones, leave only the result count and a filter toggle above the traits.
# Reparent the existing controls to preserve selection, search and signals.
func configure_touch_layout() -> void:
	(get_child(0) as Label).hide()
	var origin_row := _origin_choice.get_parent() as HBoxContainer
	var actions := _counter.get_parent() as HBoxContainer
	_touch_filters = VBoxContainer.new()
	_touch_filters.name = "TouchTraitFilters"
	add_child(_touch_filters)
	move_child(_touch_filters, 1)
	origin_row.reparent(_touch_filters)
	_search.reparent(_touch_filters)
	actions.reparent(_touch_filters)
	(origin_row.get_child(0) as Label).hide()
	_origin_choice.custom_minimum_size.x = 0

	var toolbar := HBoxContainer.new()
	toolbar.name = "TouchTraitToolbar"
	add_child(toolbar)
	move_child(toolbar, 1)
	_counter.reparent(toolbar)
	_counter.clip_text = true
	_touch_filter_toggle = Button.new()
	_touch_filter_toggle.name = "ToggleTraitFilters"
	_touch_filter_toggle.pressed.connect(func() -> void:
		_touch_filters.visible = not _touch_filters.visible
		_update_touch_filter_label())
	toolbar.add_child(_touch_filter_toggle)
	_touch_filters.hide()
	_scroll.follow_focus = false
	_update_touch_filter_label()


func _update_touch_filter_label() -> void:
	if _touch_filter_toggle == null:
		return
	var active := not _active_origin.is_empty() or not _search.text.strip_edges().is_empty()
	_touch_filter_toggle.text = ("Filtri • " if active else "Filtri ") + ("▴" if _touch_filters.visible else "▾")


func load_record(record: Dictionary) -> void:
	_record = record
	_monster_trackers.clear()
	if record.get("kind", "") == "monster":
		_monster_trackers = preload("res://vtt/structured_resource_trackers.gd").for_creature(record)
	var record_id: String = String(record.get("id", ""))
	if record_id != _record_id:
		_expanded.clear()
		_active_origin = ""
		_search.clear()
	_record_id = record_id
	_features = collect_features(record)
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	for feature: Dictionary in _features:
		var sid: String = "feature:" + String(feature.get("key", ""))
		feature["inactive"] = bool(feature.get("inactive", false)) or not bool(enabled.get(sid, true))
	var previous_origin: String = _active_origin
	_origin_choice.clear()
	_origin_choice.add_item("Tutte le origini")
	_origin_choice.set_item_metadata(0, "")
	var origins: Dictionary = {}
	for feature: Dictionary in _features:
		origins[String(feature["origin_key"])] = String(feature["origin"])
	var labels: Array = origins.keys()
	labels.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(origins[a]).naturalnocasecmp_to(String(origins[b])) < 0
	)
	for key: Variant in labels:
		_origin_choice.add_item(String(origins[key]))
		_origin_choice.set_item_metadata(_origin_choice.item_count - 1, String(key))
	_active_origin = ""
	for i: int in range(_origin_choice.item_count):
		if String(_origin_choice.get_item_metadata(i)) == previous_origin:
			_origin_choice.select(i)
			_active_origin = previous_origin
			break
	if _active_origin.is_empty():
		_origin_choice.select(0)
	_rebuild()
	_update_touch_filter_label()


func _on_origin_selected(index: int) -> void:
	_active_origin = String(_origin_choice.get_item_metadata(index))
	_rebuild()


func _set_all_expanded(opened: bool) -> void:
	for feature: Dictionary in _features:
		_expanded[String(feature["key"])] = opened
	_rebuild()


func _visible_features() -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var query: String = _search.text.strip_edges().to_lower()
	for feature: Dictionary in _features:
		if not _active_origin.is_empty() and String(feature["origin_key"]) != _active_origin:
			continue
		if not query.is_empty() and query not in (
			String(feature["name"]) + " " + String(feature["origin"])
		).to_lower():
			continue
		matches.append(feature)
	return matches


func _rebuild() -> void:
	for child: Node in _cards_container.get_children():
		_cards_container.remove_child(child)
		child.queue_free()
	_cards.clear()
	var visible: Array[Dictionary] = _visible_features()
	_counter.text = "%d tratti" % visible.size() if _touch_filters != null else "%d tratti e descrizioni" % visible.size()
	_update_touch_filter_label()
	if visible.is_empty():
		var hint := Label.new()
		hint.text = "Nessun privilegio da mostrare."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards_container.add_child(hint)
		return

	var last_group := ""
	var last_level := -1
	for feature: Dictionary in visible:
		var group: String = String(feature.get("category", "altro"))
		var level: int = int(feature["level"])
		if group != last_group:
			var section := PanelContainer.new()
			var band := preload("res://vtt/creature_sheet_style.gd").section_style()
			band.bg_color = Color("221d1cf7")
			band.set_content_margin_all(10)
			band.set_corner_radius_all(5)
			section.add_theme_stylebox_override("panel", band)
			var category_heading := Label.new()
			category_heading.text = {"razza": "RAZZA E SOTTORAZZA", "background": "BACKGROUND",
				"classi": "CLASSI E SOTTOCLASSI", "talenti": "TALENTI",
				"oggetti": "OGGETTI", "incantesimi": "INCANTESIMI ATTIVI", "mostro": "TRATTI DEL MOSTRO"}.get(group, "ALTRI TRATTI")
			category_heading.add_theme_font_size_override("font_size", 17)
			category_heading.add_theme_color_override("font_color", Color(0.82, 0.90, 0.94))
			section.add_child(category_heading)
			preload("res://vtt/creature_sheet_style.gd").heading(category_heading, "proficiency")
			_cards_container.add_child(section)
			last_group = group
			last_level = -1
		if group == "classi" and level != last_level:
			var level_label := Label.new()
			level_label.text = "LIVELLO %d" % level
			level_label.add_theme_font_size_override("font_size", 13)
			level_label.add_theme_color_override("font_color", Color(0.87, 0.71, 0.49))
			_cards_container.add_child(level_label)
			last_level = level

		var key: String = String(feature["key"])
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var background := preload("res://vtt/creature_sheet_style.gd").card_style()
		background.bg_color = Color(0.17, 0.14, 0.14, 0.94)
		background.border_color = Color(0.42, 0.32, 0.26, 0.82)
		background.set_border_width_all(1)
		background.set_corner_radius_all(6)
		background.set_content_margin_all(9)
		if bool(feature.get("inactive", false)):
			background.border_color = Color(0.45, 0.40, 0.40, 0.45)
			card.modulate.a = 0.64
		card.add_theme_stylebox_override("panel", background)
		_cards_container.add_child(card)
		_cards[key] = card
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 5)
		card.add_child(body)
		var opened: bool = bool(_expanded.get(key, false))
		var heading := Button.new()
		heading.set_meta("creature_gui_data", true)
		heading.text = ("%s  %s" % ["▾" if opened else "▸", String(feature["name"])])
		heading.tooltip_text = "Mostra o nascondi la descrizione di questo tratto"
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.clip_text = true
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.pressed.connect(_toggle.bind(key))
		body.add_child(heading)
		var source := Label.new()
		source.text = String(feature["origin"]) + (
			" · " + String(feature["book"]) if not String(feature["book"]).is_empty() else ""
		)
		source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		source.add_theme_font_size_override("font_size", 12)
		source.add_theme_color_override("font_color", Color(0.73, 0.66, 0.57))
		body.add_child(source)
		for benefit: String in _monster_benefits(feature):
			var label := Label.new()
			label.text = benefit
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 13)
			body.add_child(label)
		if opened:
			var details := RichTextLabel.new()
			TraitText.style(details)
			details.fit_content = true
			details.scroll_active = false
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var raw: Variant = feature.get("entries", "")
			var description: String = TraitText.blocks(raw).strip_edges()
			details.text = description if not description.is_empty() else TraitText.meta(
				"Descrizione non disponibile nel catalogo."
			)
			body.add_child(details)
			var links := HFlowContainer.new()
			links.add_theme_constant_override("h_separation", 8)
			body.add_child(links)
			for destination: Dictionary in [
				{"section": 0, "label": "Origini e benefici", "help": "Esamina le origini attive e i benefici della creatura."},
				{"section": 1, "label": "Competenze", "help": "Gestisci abilità, tiri salvezza, strumenti e linguaggi concessi dalle origini."},
				{"section": 3, "label": "Bonus", "help": "Controlla le formule e i bonus concessi dalle origini."},
				{"section": 4, "label": "Utilizzi e tracker", "help": "Gestisci utilizzi, risorse e recuperi dei privilegi."},
				{"section": 6, "label": "Incantesimi da origini", "help": "Controlla gli incantesimi e le scelte concessi dai tratti."}
			]:
				var link := Button.new()
				link.text = String(destination["label"])
				link.tooltip_text = String(destination["help"])
				link.pressed.connect(_request_section.bind(int(destination["section"])))
				links.add_child(link)


func _monster_benefits(feature: Dictionary) -> PackedStringArray:
	var benefits: PackedStringArray = []
	for id: String in feature.get("monster_attack_ids", []):
		var parts: PackedStringArray = id.split(":")
		var raw: Dictionary = _record.get("stat_block", {}).get(parts[1], [])[int(parts[2])]
		var attack: Dictionary = raw.get("vtt_attack", {})
		benefits.append("Attacco · " + String(raw.get("name", "")) + (" · " + String(attack.get("damage", "")) if not String(attack.get("damage", "")).is_empty() else ""))
	for action: Dictionary in feature.get("monster_actions", []):
		var timing: String = {"action": "Azione", "bonus": "Azione bonus", "reaction": "Reazione", "legendary": "Azione leggendaria", "lair": "Azione di tana"}.get(String(action.action_type), String(action.action_type))
		var cost: int = int(action.cost)
		if cost == 0:
			for tracker: Dictionary in _monster_trackers:
				if String(tracker.id) in ["recharge:" + String(action.id).trim_prefix("monster:"), "fightclub:" + String(action.id).trim_prefix("monster:")]:
					cost = 1
		benefits.append("Capacità · " + String(action.name) + " · " + timing + (" · Costo %d" % cost if cost > 0 else ""))
		for option: Dictionary in action.get("options", []):
			benefits.append("    Opzione · " + String(option.name))
	for tracker: Dictionary in _monster_trackers:
		if tracker.get("origin_id", "") == "feature:" + String(feature.get("key", "")):
			benefits.append("Risorsa · " + String(tracker.name) + " · Max %d" % int(tracker.max))
	return benefits


func _request_section(section: int) -> void:
	section_requested.emit(section)


func _toggle(key: String) -> void:
	var previous_scroll: int = _scroll.scroll_vertical
	_expanded[key] = not bool(_expanded.get(key, false))
	_rebuild()
	_scroll.scroll_vertical = previous_scroll
	call_deferred("_restore_scroll", previous_scroll)


func _restore_scroll(position: int) -> void:
	if _scroll != null:
		_scroll.scroll_vertical = position


func _ensure_visible(key: String) -> void:
	if _scroll != null and _cards.has(key) and is_instance_valid(_cards[key]):
		_scroll.ensure_control_visible(_cards[key] as Control)


func focus_feature(name: String, source_label: String = "") -> void:
	var target: Dictionary = {}
	var wanted_class: String = source_label.get_slice(" · ", 0).strip_edges()
	var wanted_book: String = source_label.get_slice(" · ", 1).strip_edges()
	for feature: Dictionary in _features:
		if String(feature["name"]).nocasecmp_to(name) != 0:
			continue
		if not wanted_class.is_empty() and (
			String(feature.get("class_name", "")).nocasecmp_to(wanted_class) != 0
			or (not wanted_book.is_empty() and String(feature["class_source"]).nocasecmp_to(wanted_book) != 0)
		):
			continue
		target = feature
		break
	if target.is_empty():
		for feature: Dictionary in _features:
			if String(feature["name"]).nocasecmp_to(name) == 0:
				target = feature
				break
	if target.is_empty():
		# Group trackers (e.g. Legendary Actions) point to a bestiary
		# section rather than to a specific action inside that section.
		for feature: Dictionary in _features:
			if String(feature["origin"]).to_lower().ends_with(name.to_lower()):
				target = feature
				break
	if target.is_empty():
		return
	_active_origin = String(target["origin_key"])
	for i: int in range(_origin_choice.item_count):
		if String(_origin_choice.get_item_metadata(i)) == _active_origin:
			_origin_choice.select(i)
			break
	_search.clear()
	_expanded[String(target["key"])] = true
	_rebuild()
	call_deferred("_ensure_visible", String(target["key"]))


# Preserve the old API for desktop consumers; the computation is no longer
# implemented on the view itself.
static func collect_features(record: Dictionary) -> Array[Dictionary]:
	return CreatureFeatures.collect_features(record)


func focus_origin(sid: String, fallback_name: String = "") -> void:
	for feature: Dictionary in _features:
		if sid == "feature:" + String(feature.get("key", "")) or sid == String(feature.get("origin_key", "")):
			_active_origin = String(feature.get("origin_key", ""))
			for i: int in range(_origin_choice.item_count):
				if String(_origin_choice.get_item_metadata(i)) == _active_origin:
					_origin_choice.select(i)
			_search.clear()
			_expanded[String(feature["key"])] = true
			_rebuild()
			call_deferred("_ensure_visible", String(feature["key"]))
			return
	focus_feature(fallback_name)
