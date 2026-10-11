extends VBoxContainer

# Independent, expandable Statistics editor for feat grants.
# The left column is an origin list; the right one is the feat list,
# matching the two-column proficiency/bonus editors.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const OriginButton = preload("res://vtt/bounded_tooltip_button.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

var _changed: Callable
var _record: Dictionary = {}
var _feats: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _selected_id := "~none~"
var _loading := false
var _status: Label
var _origin_cards: VBoxContainer
var _feat_cards: VBoxContainer
var _origin_editor: VBoxContainer
var _origin_picker: OptionButton
var _feat_editor: VBoxContainer
var _feat_filter: LineEdit
var _feat_picker: OptionButton
var _catalog_matches: Array[Dictionary] = []
var _remove_dialog: ConfirmationDialog
var _remove_picker: OptionButton
var _remove_sid := ""
var _descriptions: Dictionary = {}
var _source_candidates: Array[Dictionary] = []
var _feature_entries: Array[Dictionary] = []
var _catalog_cache: Dictionary = {}
var _proficiency_choices: Array[Dictionary] = []


func _refresh_description_sources() -> void:
	_descriptions.clear()
	_catalog_cache.clear()
	var record: Dictionary = _effective_record()
	_source_candidates = Rules.candidate_sources(record)
	_feature_entries = Traits.collect_features(record)
	_proficiency_choices = Rules.choices(record)


func _catalog_entries(category: String) -> Array[Dictionary]:
	if not _catalog_cache.has(category):
		_catalog_cache[category] = Catalog.entries(category)
	return _catalog_cache[category]



func setup(on_change: Callable) -> void:
	_changed = on_change
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 9)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := _make_column(columns, "Origini dei talenti", 190)
	var right := _make_column(columns, "Talenti posseduti", 225)

	var origin_scroll := ScrollContainer.new()
	origin_scroll.custom_minimum_size.y = 245
	origin_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	origin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(origin_scroll)
	_origin_cards = VBoxContainer.new()
	_origin_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_cards.add_theme_constant_override("separation", 5)
	origin_scroll.add_child(_origin_cards)

	var add_origin := Button.new()
	add_origin.text = "Seleziona origine"
	add_origin.pressed.connect(func() -> void:
		_origin_editor.visible = not _origin_editor.visible
	)
	left.add_child(add_origin)
	_origin_editor = VBoxContainer.new()
	_origin_editor.hide()
	left.add_child(_origin_editor)
	_origin_picker = OptionButton.new()
	_origin_editor.add_child(_origin_picker)
	var confirm_origin := Button.new()
	confirm_origin.text = "Seleziona origine esistente"
	confirm_origin.pressed.connect(_add_origin)
	_origin_editor.add_child(confirm_origin)

	var feat_scroll := ScrollContainer.new()
	feat_scroll.custom_minimum_size.y = 245
	feat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(feat_scroll)
	_feat_cards = VBoxContainer.new()
	_feat_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feat_cards.add_theme_constant_override("separation", 4)
	feat_scroll.add_child(_feat_cards)

	var add_feat := Button.new()
	add_feat.text = "+ Talento all'origine selezionata"
	add_feat.pressed.connect(func() -> void:
		_feat_editor.visible = not _feat_editor.visible
	)
	right.add_child(add_feat)
	_feat_editor = VBoxContainer.new()
	_feat_editor.hide()
	right.add_child(_feat_editor)
	_feat_filter = LineEdit.new()
	_feat_filter.placeholder_text = "Cerca talento nel compendio…"
	_feat_filter.clear_button_enabled = true
	_feat_filter.text_changed.connect(func(_value: String) -> void: _refresh_feat_picker())
	_feat_editor.add_child(_feat_filter)
	_feat_picker = OptionButton.new()
	_feat_picker.fit_to_longest_item = false
	_feat_editor.add_child(_feat_picker)
	var confirm_feat := Button.new()
	confirm_feat.text = "Aggiungi talento"
	confirm_feat.pressed.connect(_add_feat)
	_feat_editor.add_child(confirm_feat)

	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.title = "Rimuovi talento"
	_remove_dialog.ok_button_text = "Rimuovi"
	_remove_dialog.cancel_button_text = "Annulla"
	_remove_dialog.confirmed.connect(_remove_selected_origin_grant)
	add_child(_remove_dialog)
	var remove_box := VBoxContainer.new()
	_remove_dialog.add_child(remove_box)
	var help := Label.new()
	help.text = "Da quale origine rimuovere questo talento?"
	remove_box.add_child(help)
	_remove_picker = OptionButton.new()
	_remove_picker.custom_minimum_size.x = 350
	remove_box.add_child(_remove_picker)
	load_record({})


func _make_column(parent: HBoxContainer, heading: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 15)
	column.add_child(title)
	return column


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_feats_reset()
	var raw: Variant = record.get("feats_catalog", [])
	if raw is Array:
		for feat: Variant in raw:
			if feat is Dictionary:
				_feats.append((feat as Dictionary).duplicate(true))
	_origins = Rules.origins(record)
	_rebuild_sources()
	_refresh_description_sources()
	if _selected_id != "~none~" and not _has_origin(_selected_id):
		_selected_id = "~none~"
	if _remove_dialog != null:
		_remove_dialog.hide()
	_refresh()
	_loading = false


# Only origins with a structured 5etools feat grant or an already
# recorded feat relationship belong in the Talenti source list. All other
# traits remain available on the Tratti page, not as phantom feat granters.
func _rebuild_sources() -> void:
	var effective: Dictionary = _effective_record()
	var enabled: Dictionary = Rules.origin_enabled_map(effective)
	var discovered: Array[Dictionary] = Rules.trait_origins(effective, true)
	var by_id: Dictionary = {}
	for source: Dictionary in discovered:
		var sid: String = String(source.get("id", ""))
		by_id[sid] = source
	for source: Dictionary in Rules.origins(effective):
		var sid: String = String(source.get("id", ""))
		if sid.is_empty():
			continue
		var group: String = String(source.get("group", ""))
		var associated := false
		for feat: Dictionary in _feats:
			if String(feat.get("origin_id", "")) == sid:
				associated = true
				break
		if associated and not by_id.has(sid):
			by_id[sid] = source.duplicate(true)
	var existing_origins: Array[Dictionary] = Bonuses.available_origins(effective)
	for feat: Dictionary in _feats:
		var sid: String = String(feat.get("origin_id", ""))
		if sid.is_empty() or by_id.has(sid):
			continue
		for source: Dictionary in existing_origins:
			if String(source.get("id", "")) == sid:
				by_id[sid] = source.duplicate(true)
				break
	var result: Array[Dictionary] = []
	for sid: String in by_id.keys():
		var source: Dictionary = by_id[sid]
		source["inactive"] = not bool(enabled.get(sid, false))
		result.append(source)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	_origins = result


func _feats_reset() -> void:
	_feats.clear()


func _has_origin(sid: String) -> bool:
	for row: Dictionary in _origins:
		if String(row.get("id", "")) == sid:
			return true
	return false


func _effective_record() -> Dictionary:
	var record: Dictionary = _record.duplicate(true)
	record["feats_catalog"] = _feats.duplicate(true)
	# This editor displays only feat-granting sources. Preserve disabled
	# state for all the other origins while resolving cascading activation.
	var merged: Dictionary = {}
	for source: Variant in record.get("proficiency_origins", []):
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	for source: Dictionary in _origins:
		merged[String(source.get("id", ""))] = source.duplicate(true)
	record["proficiency_origins"] = merged.values()
	return record


func _enabled() -> Dictionary:
	return Rules.origin_enabled_map(_effective_record())


func _label(sid: String) -> String:
	if sid.is_empty():
		return "Senza origine"
	for origin: Dictionary in _origins:
		if String(origin.get("id", "")) == sid:
			return String(origin.get("name", sid))
	return sid


func _description(sid: String) -> String:
	if _descriptions.has(sid):
		return String(_descriptions[sid])
	if sid.is_empty():
		return "Talento aggiunto senza un'origine specificata."
	var description := _label(sid)
	for source: Dictionary in _source_candidates:
		if String(source.get("id", "")) != sid:
			continue
		if String(source.get("group", "")) == "class":
			description = Rules.starting_description(source)
		else:
			var category: String = {"background": "backgrounds", "race": "races",
				"subrace": "races", "feat": "feats"}.get(String(source.get("group", "")), "")
			description = Catalog.info_text(source.get("data", {}), Catalog.description_text(category, source.get("data", {})))
			if not category.is_empty():
				for entry: Dictionary in _catalog_entries(category):
					if String(entry.get("name", "")).nocasecmp_to(String(source.get("data", {}).get("name", ""))) == 0 and String(entry.get("source", "")) == String(source.get("data", {}).get("source", "")):
						description = Catalog.info_text(entry, Catalog.description_text(category, entry))
						break
		break
	if sid.begins_with("feature:"):
		for feature: Dictionary in _feature_entries:
			if sid == "feature:" + String(feature.get("key", "")):
				description = Catalog.info_text(feature, Catalog.description_text_from_raw_item(feature))
				break
	if sid.begins_with("item:"):
		for raw: Variant in _record.get("inventory", []):
			if raw is Dictionary and sid == "item:" + String(raw.get("id", "")):
				description = Catalog.info_text(raw, Catalog.description_text("items", raw))
				break
	_descriptions[sid] = description
	return description


func _origin_grants_tooltip(sid: String) -> String:
	var chosen: PackedStringArray = []
	var fixed: PackedStringArray = []
	for choice: Dictionary in _proficiency_choices:
		if String(choice.get("origin_id", "")) != sid:
			continue
		var line: String = ("○ " if bool(choice.get("disabled", false)) else "✓ ")
		line += String(choice.get("kind", "")).capitalize() + ": " + String(choice.get("key", "")).capitalize()
		if bool(choice.get("automatic", false)):
			fixed.append(line)
		else:
			chosen.append(line)
	for feat: Dictionary in _feats:
		if String(feat.get("origin_id", "")) == sid:
			chosen.append(("○ " if bool(feat.get("disabled", false)) else "✓ ") + "Talento: " + String(feat.get("name", "")))
	var sections: PackedStringArray = []
	if not chosen.is_empty():
		sections.append("Scelte già effettuate:\n" + "\n".join(chosen))
	if not fixed.is_empty():
		sections.append("Concessioni automatiche:\n" + "\n".join(fixed))
	return "\n\n" + "\n\n".join(sections) if not sections.is_empty() else ""


func _feat_description(feat: Dictionary) -> String:
	for entry: Dictionary in _catalog_entries("feats"):
		if String(entry.get("name", "")).nocasecmp_to(String(feat.get("name", ""))) == 0 and String(entry.get("source", "")) == String(feat.get("source", "")):
			return Catalog.info_text(entry, Catalog.description_text("feats", entry))
	return Catalog.info_text(feat, Catalog.description_text("feats", feat))


func _refresh() -> void:
	_status.text = "Seleziona un'origine a sinistra per evidenziare i talenti concessi. Ogni talento può diventare origine di altri effetti."
	_refresh_origins()
	_refresh_feats()
	_refresh_origin_picker()
	_refresh_feat_picker()


func _refresh_origins() -> void:
	for node: Node in _origin_cards.get_children():
		_origin_cards.remove_child(node)
		node.queue_free()
	var enabled: Dictionary = _enabled()
	var sources: Array[Dictionary] = [{"id": "", "name": "Senza origine", "disabled": false}]
	sources.append_array(_origins)
	var seen: Dictionary = {}
	for origin: Dictionary in sources:
		var sid: String = String(origin.get("id", ""))
		if seen.has(sid):
			continue
		seen[sid] = true
		var count := 0
		for feat: Dictionary in _feats:
			if String(feat.get("origin_id", "")) == sid:
				count += 1
		var panel := PanelContainer.new()
		_origin_cards.add_child(panel)
		var line := HBoxContainer.new()
		panel.add_child(line)
		var select := OriginButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.toggle_mode = true
		select.button_pressed = _selected_id == sid
		select.clip_text = true
		select.text = _label(sid) + " (%d)" % count
		select.tooltip_text = _description(sid) + _origin_grants_tooltip(sid)
		select.pressed.connect(_select_origin.bind(sid))
		line.add_child(select)
		if not sid.is_empty():
			var on := CheckButton.new()
			on.text = "⏻"
			on.button_pressed = bool(enabled.get(sid, false))
			on.disabled = not on.button_pressed and not bool(origin.get("disabled", false))
			on.tooltip_text = "Disattiva l'origine e tutti i talenti e benefici che dipendono da essa."
			on.toggled.connect(_toggle_origin.bind(sid))
			line.add_child(on)
		if _selected_id == sid:
			var border := StyleBoxFlat.new()
			border.draw_center = false
			border.border_color = Color(0.40, 0.72, 0.91)
			border.set_border_width_all(2)
			border.set_corner_radius_all(5)
			panel.add_theme_stylebox_override("panel", border)
		elif not bool(enabled.get(sid, true)):
			panel.modulate.a = 0.58


func _refresh_feats() -> void:
	for node: Node in _feat_cards.get_children():
		_feat_cards.remove_child(node)
		node.queue_free()
	if _feats.is_empty():
		var empty := Label.new()
		empty.text = "Nessun talento disponibile."
		_feat_cards.add_child(empty)
		return
	var enabled: Dictionary = _enabled()
	var groups: Dictionary = {}
	for index: int in range(_feats.size()):
		var sid: String = Rules.feat_source_id(_feats[index])
		if not groups.has(sid):
			groups[sid] = []
		groups[sid].append(index)
	var keys: Array[String] = []
	for sid: String in groups.keys():
		keys.append(sid)
	keys.sort()
	for sid: String in keys:
		var indices: Array = groups[sid]
		var feat: Dictionary = _feats[int(indices[0])]
		var active: bool = bool(enabled.get(sid, false))
		var own_active := false
		var selected_active := false
		var source_lines: Array[String] = []
		for index: Variant in indices:
			var granted: Dictionary = _feats[int(index)]
			var origin_id: String = String(granted.get("origin_id", ""))
			var local_active: bool = not bool(granted.get("disabled", false))
			own_active = own_active or local_active
			var grant_active: bool = local_active and (origin_id.is_empty() or bool(enabled.get(origin_id, false)))
			selected_active = selected_active or (grant_active and origin_id == _selected_id)
			source_lines.append(("✓ " if grant_active else "○ ") + _label(origin_id))
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = 52
		_feat_cards.add_child(panel)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.12, 0.12, 0.88)
		style.border_color = Color(0.79, 0.66, 0.43, 0.78) if selected_active else Color(0.36, 0.31, 0.27, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.set_content_margin_all(7)
		panel.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(line)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = ("✓ " if active else "○ ") + String(feat.get("name", "")) + " · " + String(feat.get("source", ""))
		label.tooltip_text = _feat_description(feat) + "\n\nOrigini:\n" + "\n".join(source_lines)
		if selected_active:
			label.add_theme_color_override("font_color", Color(0.96, 0.87, 0.66))
		line.add_child(label)
		var toggle := CheckButton.new()
		toggle.text = "⏻"
		toggle.custom_minimum_size.y = 34
		toggle.button_pressed = active
		# A feat inherited from an inactive source must not appear enabled or
		# be manually re-enabled until its granting origin is restored.
		toggle.disabled = not active and own_active
		toggle.tooltip_text = "Attiva o disattiva il talento e le origini che dipendono da esso."
		toggle.toggled.connect(_toggle_grants.bind(indices.duplicate()))
		line.add_child(toggle)
		var remove := Button.new()
		remove.text = "✕"
		remove.flat = true
		remove.custom_minimum_size = Vector2(34, 34)
		remove.tooltip_text = "Elimina la concessione da una specifica origine."
		remove.pressed.connect(_request_remove.bind(sid))
		line.add_child(remove)


func _refresh_origin_picker() -> void:
	_origin_picker.clear()
	for source: Dictionary in _origins:
		var sid: String = String(source.get("id", ""))
		if sid.is_empty():
			continue
		_origin_picker.add_item(String(source.get("name", sid)))
		_origin_picker.set_item_metadata(_origin_picker.item_count - 1, sid)
	if _origin_picker.item_count > 0:
		_origin_picker.select(0)


func _refresh_feat_picker() -> void:
	_catalog_matches.clear()
	_feat_picker.clear()
	var needle: String = _feat_filter.text.strip_edges().to_lower()
	var edition: String = String(_record.get("rules_version", "2014"))
	for feat: Dictionary in _catalog_entries("feats"):
		var source: String = String(feat.get("source", ""))
		if edition == "2014" and (source in ["XPHB", "XDMG", "EFA"] or String(feat.get("edition", "")) == "one"):
			continue
		if edition != "2014" and source in ["XDMG", "EFA"]:
			continue
		if not needle.is_empty() and needle not in (String(feat.get("name", "")) + " " + source).to_lower():
			continue
		_catalog_matches.append(feat)
		_feat_picker.add_item("%s · %s" % [feat.get("name", ""), source])
		if _catalog_matches.size() >= 160:
			break
	if _feat_picker.item_count > 0:
		_feat_picker.select(0)


func _select_origin(sid: String) -> void:
	_selected_id = "~none~" if sid == _selected_id else sid
	_feat_editor.hide()
	_refresh_origins()
	_refresh_feats()


func _toggle_origin(on: bool, sid: String) -> void:
	for source: Dictionary in _origins:
		if String(source.get("id", "")) == sid:
			source["disabled"] = not on
			break
	_publish()


func _add_origin() -> void:
	if _origin_picker.selected < 0:
		return
	var sid: String = String(_origin_picker.get_item_metadata(_origin_picker.selected))
	# A new origin must be justified by an actual trait. This picker is
	# restricted to existing structured feat granters and linked sources.
	if sid.is_empty() or not _has_origin(sid):
		return
	_selected_id = sid
	_origin_editor.hide()
	_refresh_origins()
	_refresh_feats()


func _add_feat() -> void:
	var index: int = _feat_picker.selected
	if index < 0 or index >= _catalog_matches.size():
		return
	var feat: Dictionary = _catalog_matches[index]
	var sid: String = Rules.feat_source_id(feat)
	var origin_id: String = "" if _selected_id == "~none~" else _selected_id
	# Re-adding a previously muted grant reactivates it; different source
	# grants of the same feat stay independent.
	if sid == origin_id:
		_status.text = "Un talento non può essere origine di se stesso."
		return
	for granted: Dictionary in _feats:
		if Rules.feat_source_id(granted) == sid and String(granted.get("origin_id", "")) == origin_id:
			granted["disabled"] = false
			_feat_editor.hide()
			_publish()
			return
	_feats.append({"id": feat.get("id", ""), "name": feat.get("name", ""),
		"source": feat.get("source", ""), "origin_id": origin_id,
		"origin_name": _label(origin_id), "disabled": false})
	_feat_editor.hide()
	_publish()


func _toggle_grants(on: bool, indices: Array) -> void:
	for raw_index: Variant in indices:
		_feats[int(raw_index)]["disabled"] = not on
	_publish()


func _request_remove(sid: String) -> void:
	_remove_sid = sid
	_remove_picker.clear()
	_remove_picker.add_item("Tutte le origini")
	_remove_picker.set_item_metadata(0, "~all~")
	for feat: Dictionary in _feats:
		if Rules.feat_source_id(feat) != sid:
			continue
		var parent: String = String(feat.get("origin_id", ""))
		_remove_picker.add_item(_label(parent))
		_remove_picker.set_item_metadata(_remove_picker.item_count - 1, parent)
	if _remove_picker.item_count == 2:
		_remove_picker.select(1)
		_remove_selected_origin_grant()
		return
	for i: int in range(1, _remove_picker.item_count):
		if String(_remove_picker.get_item_metadata(i)) == _selected_id:
			_remove_picker.select(i)
			break
	DialogLayout.popup(_remove_dialog, Vector2i(420, 190), 0.85)


func _remove_selected_origin_grant() -> void:
	var parent: String = String(_remove_picker.get_item_metadata(_remove_picker.selected))
	for i: int in range(_feats.size() - 1, -1, -1):
		var feat: Dictionary = _feats[i]
		if Rules.feat_source_id(feat) == _remove_sid and (parent == "~all~" or String(feat.get("origin_id", "")) == parent):
			_feats.remove_at(i)
	_publish()


func _publish() -> void:
	# Recover catalog-backed origins after inserting/removing a feat and
	# preserve any temporarily disabled origin switches.
	var state: Dictionary = _effective_record()
	_rebuild_sources()
	_refresh_description_sources()
	_refresh()
	if _loading or not _changed.is_valid():
		return
	var stored: Array[Dictionary] = []
	for source: Dictionary in _origins:
		stored.append({"id": source.get("id", ""), "name": source.get("name", ""),
			"group": source.get("group", ""), "automatic": bool(source.get("automatic", false)),
			"disabled": bool(source.get("disabled", false))})
	_changed.call(_feats.duplicate(true), stored)
