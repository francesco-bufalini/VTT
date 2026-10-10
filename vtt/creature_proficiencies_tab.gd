extends VBoxContainer

# Creature proficiency editor: explicit user choices and traceable sources.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")

const GROUPS := [
	{"kind": "weapon", "label": "Armi"},
	{"kind": "armor", "label": "Armature / Scudi"},
	{"kind": "skill", "label": "Abilità"},
	{"kind": "expertise", "label": "Maestria"},
	{"kind": "save", "label": "Tiri salvezza"},
	{"kind": "tool", "label": "Strumenti"},
	{"kind": "language", "label": "Lingue"}
]

var _changed: Callable
var _record: Dictionary = {}
var _rows: Array[Dictionary] = []
var _feats: Array[Dictionary] = []
var _available: Array[Dictionary] = []
var _feat_available: Array[Dictionary] = []
var _loading := false
var _group: OptionButton
var _search: LineEdit
var _options: ItemList
var _owned: ItemList
var _origin: OptionButton
var _status: Label
var _feat_search: LineEdit
var _feat_options: ItemList
var _feat_owned: ItemList
var _entry_text: LineEdit


func setup(on_change: Callable) -> void:
	_changed = on_change
	add_theme_constant_override("separation", 7)
	var heading := Label.new()
	heading.text = "Competenze e origini"
	heading.add_theme_font_size_override("font_size", 17)
	add_child(heading)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var pick_row := HFlowContainer.new()
	add_child(pick_row)
	_group = OptionButton.new()
	for group: Dictionary in GROUPS:
		_group.add_item(String(group["label"]))
	_group.item_selected.connect(func(_index: int) -> void: _refresh_available())
	pick_row.add_child(_group)
	_search = LineEdit.new()
	_search.placeholder_text = "Cerca una competenza…"
	_search.custom_minimum_size.x = 210
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh_available())
	pick_row.add_child(_search)
	_entry_text = LineEdit.new()
	_entry_text.placeholder_text = "Oppure scrivi il nome"
	_entry_text.custom_minimum_size.x = 170
	pick_row.add_child(_entry_text)
	var add := Button.new()
	add.text = "+ Aggiungi"
	add.pressed.connect(_add_choice)
	pick_row.add_child(add)

	var content := HFlowContainer.new()
	content.add_theme_constant_override("h_separation", 12)
	content.add_theme_constant_override("v_separation", 8)
	add_child(content)
	var source_col := VBoxContainer.new()
	source_col.custom_minimum_size.x = 235
	source_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(source_col)
	var heading1 := Label.new()
	heading1.text = "Competenze disponibili"
	source_col.add_child(heading1)
	_options = ItemList.new()
	_options.custom_minimum_size.y = 130
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.item_activated.connect(func(_i: int) -> void: _add_choice())
	source_col.add_child(_options)
	var chosen_col := VBoxContainer.new()
	chosen_col.custom_minimum_size.x = 270
	chosen_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(chosen_col)
	var heading2 := Label.new()
	heading2.text = "Competenze selezionate"
	chosen_col.add_child(heading2)
	_owned = ItemList.new()
	_owned.custom_minimum_size.y = 130
	_owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned.item_selected.connect(_selected_choice)
	chosen_col.add_child(_owned)
	var remove := Button.new()
	remove.text = "Rimuovi competenza"
	remove.pressed.connect(_remove_choice)
	chosen_col.add_child(remove)
	var origin_col := VBoxContainer.new()
	origin_col.custom_minimum_size.x = 260
	origin_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(origin_col)
	var heading3 := Label.new()
	heading3.text = "Tratto / fonte di origine"
	origin_col.add_child(heading3)
	_origin = OptionButton.new()
	_origin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin.item_selected.connect(_on_origin_selected)
	origin_col.add_child(_origin)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = "Prima le fonti suggerite dai campi strutturati; puoi associare anche un altro tratto, senza attribuirgli automaticamente competenze."
	origin_col.add_child(description)

	var rule := HSeparator.new()
	add_child(rule)
	var feats_header := Label.new()
	feats_header.text = "Talenti posseduti (fonti di competenze)"
	feats_header.add_theme_font_size_override("font_size", 15)
	add_child(feats_header)
	var feat_row := HFlowContainer.new()
	add_child(feat_row)
	_feat_search = LineEdit.new()
	_feat_search.placeholder_text = "Cerca talento nel catalogo 5etools…"
	_feat_search.clear_button_enabled = true
	_feat_search.custom_minimum_size.x = 245
	_feat_search.text_changed.connect(func(_value: String) -> void: _refresh_feats())
	feat_row.add_child(_feat_search)
	var add_feat := Button.new()
	add_feat.text = "+ Talento"
	add_feat.pressed.connect(_add_feat)
	feat_row.add_child(add_feat)
	var remove_feat := Button.new()
	remove_feat.text = "Rimuovi talento"
	remove_feat.pressed.connect(_remove_feat)
	feat_row.add_child(remove_feat)
	var feats_columns := HFlowContainer.new()
	feats_columns.add_theme_constant_override("h_separation", 12)
	add_child(feats_columns)
	_feat_options = ItemList.new()
	_feat_options.custom_minimum_size = Vector2(320, 110)
	_feat_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feat_options.item_activated.connect(func(_i: int) -> void: _add_feat())
	feats_columns.add_child(_feat_options)
	_feat_owned = ItemList.new()
	_feat_owned.custom_minimum_size = Vector2(260, 110)
	_feat_owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feats_columns.add_child(_feat_owned)
	load_record({})


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_rows = Rules.choices(record)
	_feats.clear()
	var source: Variant = record.get("feats_catalog", [])
	if source is Array:
		for raw: Variant in source:
			if raw is Dictionary:
				_feats.append((raw as Dictionary).duplicate(true))
	_refresh_available()
	_refresh_selected()
	_refresh_feats()
	_update_status()
	_loading = false


func _current_kind() -> String:
	return String(GROUPS[clampi(_group.selected, 0, GROUPS.size() - 1)]["kind"])


func _catalog_entries() -> Array[Dictionary]:
	var kind := _current_kind()
	var result: Array[Dictionary] = []
	if kind in ["skill", "expertise"]:
		for key: String in Rules.SKILLS:
			result.append({"key": key, "label": key.capitalize()})
	elif kind == "save":
		for key: String in Rules.ABILITIES:
			result.append({"key": key, "label": key.to_upper()})
	elif kind == "armor":
		for key: String in Rules.ARMORS:
			result.append({"key": key, "label": key.capitalize()})
	elif kind == "weapon":
		for group: String in ["simple", "martial", "all"]:
			result.append({"key": group, "label": group.capitalize()})
		for row: Dictionary in Catalog.entries("items"):
			if String(row.get("type", "")).split("|")[0] not in ["M", "R"]:
				continue
			if not _valid_edition(row):
				continue
			result.append({"key": String(row.get("name", "")).to_lower(), "label": String(row.get("name", ""))})
	elif kind in ["tool", "language"]:
		for row: Dictionary in Catalog.entries("tools" if kind == "tool" else "languages"):
			if _valid_edition(row):
				result.append({"key": String(row.get("name", "")).to_lower(), "label": String(row.get("name", ""))})
	var seen: Dictionary = {}
	var deduplicated: Array[Dictionary] = []
	for entry: Dictionary in result:
		if not seen.has(String(entry["key"])):
			seen[String(entry["key"])] = true
			deduplicated.append(entry)
	return deduplicated


func _valid_edition(row: Dictionary) -> bool:
	if String(_record.get("rules_version", "2014")) != "2014":
		return true
	return String(row.get("source", "")) not in ["XPHB", "XDMG", "EFA"]


func _refresh_available() -> void:
	if _options == null:
		return
	_available.clear()
	_options.clear()
	var query := _search.text.strip_edges().to_lower()
	for entry: Dictionary in _catalog_entries():
		if not query.is_empty() and query not in String(entry["label"]).to_lower():
			continue
		_available.append(entry)
		_options.add_item(String(entry["label"]))
		if _available.size() >= 250:
			break


func _refresh_selected(selected_index: int = -1) -> void:
	if _owned == null:
		return
	_owned.clear()
	for row: Dictionary in _rows:
		var kind := String(row.get("kind", ""))
		var tag := " · " + String(row.get("origin_name", ""))
		if String(row.get("origin_id", "")).is_empty():
			tag = " · origine da associare"
		_owned.add_item("%s · %s%s" % [kind.capitalize(), String(row.get("key", "")), tag])
	if selected_index >= 0 and selected_index < _rows.size():
		_owned.select(selected_index)
	_refresh_origins()


func _selected_choice(index: int) -> void:
	_refresh_origins(index)


func _refresh_origins(index: int = -1) -> void:
	_origin.clear()
	_origin.add_item("— Origine non associata")
	_origin.set_item_metadata(0, "")
	if index < 0:
		var selected: PackedInt32Array = _owned.get_selected_items()
		index = selected[0] if not selected.is_empty() else -1
	if index < 0 or index >= _rows.size():
		_origin.disabled = true
		return
	_origin.disabled = false
	var selected_row: Dictionary = _rows[index]
	var seen: Dictionary = {}
	var selected_id := String(selected_row.get("origin_id", ""))
	var selected_index := 0
	for suggestion: Dictionary in Rules.suggest_origins(_effective_record(), String(selected_row["kind"]), String(selected_row["key"])):
		var origin_id := String(suggestion["id"])
		if seen.has(origin_id):
			continue
		seen[origin_id] = true
		var label := "✓ " if int(suggestion.get("certainty", 0)) == 2 else "◇ "
		_origin.add_item(label + String(suggestion["name"]))
		var idx := _origin.item_count - 1
		_origin.set_item_metadata(idx, origin_id)
		if selected_id == origin_id:
			selected_index = idx
	for feature: Dictionary in Traits.collect_features(_effective_record()):
		var origin_id := "feature:" + String(feature.get("key", ""))
		if seen.has(origin_id):
			continue
		seen[origin_id] = true
		_origin.add_item("Tratto · " + String(feature.get("name", "")) + " (" + String(feature.get("origin", "")) + ")")
		var idx := _origin.item_count - 1
		_origin.set_item_metadata(idx, origin_id)
		if selected_id == origin_id:
			selected_index = idx
	# Keep obsolete/homebrew references visible and editable.
	if selected_index == 0 and not selected_id.is_empty():
		_origin.add_item("Altro · " + String(selected_row.get("origin_name", "")))
		selected_index = _origin.item_count - 1
		_origin.set_item_metadata(selected_index, selected_id)
	_origin.select(selected_index)


func _effective_record() -> Dictionary:
	var current := _record.duplicate(true)
	current["feats_catalog"] = _feats.duplicate(true)
	current["proficiency_choices"] = _rows.duplicate(true)
	return current


func _on_origin_selected(option: int) -> void:
	if _loading:
		return
	var selected: PackedInt32Array = _owned.get_selected_items()
	if selected.is_empty():
		return
	var i: int = selected[0]
	if i >= _rows.size():
		return
	var source_id := String(_origin.get_item_metadata(option))
	var name := ""
	if not source_id.is_empty():
		name = _origin.get_item_text(option).trim_prefix("✓ ").trim_prefix("◇ ")
	_rows[i]["origin_id"] = source_id
	_rows[i]["origin_name"] = name
	_publish(i)


func _add_choice() -> void:
	var kind := _current_kind()
	var key := _entry_text.text.strip_edges().to_lower()
	if key.is_empty():
		var selected: PackedInt32Array = _options.get_selected_items()
		if selected.is_empty() or selected[0] >= _available.size():
			return
		key = String(_available[selected[0]]["key"])
	if key.is_empty() or Rules.has_choice(_rows, kind, key):
		return
	if kind == "expertise" and not Rules.has_choice(_rows, "skill", key):
		_rows.append({"kind": "skill", "key": key, "origin_id": "", "origin_name": ""})
	_rows.append({"kind": kind, "key": key, "origin_id": "", "origin_name": ""})
	_entry_text.clear()
	_publish(_rows.size() - 1)


func _remove_choice() -> void:
	var selected: PackedInt32Array = _owned.get_selected_items()
	if selected.is_empty():
		return
	var idx: int = selected[0]
	if idx >= _rows.size():
		return
	var removed: Dictionary = _rows[idx]
	_rows.remove_at(idx)
	if String(removed.get("kind", "")) == "skill":
		var retained: Array[Dictionary] = []
		for row: Dictionary in _rows:
			if not (String(row.get("kind", "")) == "expertise" and String(row.get("key", "")) == String(removed.get("key", ""))):
				retained.append(row)
		_rows = retained
	_publish()


func _refresh_feats() -> void:
	if _feat_options == null:
		return
	_feat_available.clear()
	_feat_options.clear()
	var query := _feat_search.text.strip_edges().to_lower()
	for entry: Dictionary in Catalog.entries("feats"):
		if not _valid_edition(entry):
			continue
		if not query.is_empty() and query not in String(entry.get("name", "")).to_lower():
			continue
		_feat_available.append(entry)
		_feat_options.add_item(String(entry.get("name", "")) + " · " + String(entry.get("source", "")))
		if _feat_available.size() >= 180:
			break
	_feat_owned.clear()
	for item: Dictionary in _feats:
		_feat_owned.add_item(String(item.get("name", "")) + " · " + String(item.get("source", "")))


func _add_feat() -> void:
	var indexes: PackedInt32Array = _feat_options.get_selected_items()
	if indexes.is_empty() or indexes[0] >= _feat_available.size():
		return
	var feat: Dictionary = _feat_available[indexes[0]]
	for owned: Dictionary in _feats:
		if String(owned.get("id", "")) == String(feat.get("id", "")):
			return
	_feats.append({"id": feat.get("id", ""), "name": feat.get("name", ""), "source": feat.get("source", "")})
	_publish()


func _remove_feat() -> void:
	var indexes: PackedInt32Array = _feat_owned.get_selected_items()
	if indexes.is_empty() or indexes[0] >= _feats.size():
		return
	_feats.remove_at(indexes[0])
	# Orphaned origins stay visible until the user reassigns them.
	_publish()


func _update_status() -> void:
	var record := _effective_record()
	var unattached := Rules.unassigned_count(record)
	var missing: Array[Dictionary] = Rules.missing_structured(record)
	_status.text = ("• %d competenze senza origine" % unattached if unattached > 0 else "Origini associate")
	if not missing.is_empty():
		_status.text += "   ·   %d competenze iniziali da verificare" % missing.size()
	_status.tooltip_text = "Le competenze iniziali mancanti sono suggerimenti, non vengono assegnate automaticamente."


func _publish(selected_index: int = -1) -> void:
	_refresh_selected(selected_index)
	_refresh_feats()
	_update_status()
	if not _loading and _changed.is_valid():
		_changed.call(_rows.duplicate(true), _feats.duplicate(true))
