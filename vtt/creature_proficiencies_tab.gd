extends VBoxContainer

# Expandable Statistics editor: structured origins on the left, individual
# proficiencies on the right. Nothing is inferred from natural-language text.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")

const GROUPS := [
	{"kind": "weapon", "label": "Armi"},
	{"kind": "armor", "label": "Armature / Scudi"},
	{"kind": "skill", "label": "Abilità"},
	{"kind": "save", "label": "Tiri salvezza"},
	{"kind": "tool", "label": "Strumenti"},
	{"kind": "language", "label": "Lingue"}
]

var _changed: Callable
var _record: Dictionary = {}
var _rows: Array[Dictionary] = []
var _origins: Array[Dictionary] = []
var _feats: Array[Dictionary] = []
var _loading := false
var _selected_id := "~none~"
var _origin_cards: VBoxContainer
var _proficiency_cards: VBoxContainer
var _status: Label
var _origin_editor: VBoxContainer
var _competence_editor: VBoxContainer
var _feat_editor: VBoxContainer
var _origin_picker: OptionButton
var _origin_name: LineEdit
var _kind_picker: OptionButton
var _proficiency_picker: OptionButton
var _proficiency_name: LineEdit
var _feat_filter: LineEdit
var _feat_list: ItemList
var _feat_owned: ItemList
var _feat_available: Array[Dictionary] = []
var _add_competence_button: Button


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
	var left := _create_column(columns, "Origini delle competenze", 190)
	var right := _create_column(columns, "Singole competenze", 225)

	var origin_scroller := ScrollContainer.new()
	origin_scroller.custom_minimum_size.y = 245
	origin_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	origin_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(origin_scroller)
	_origin_cards = VBoxContainer.new()
	_origin_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_cards.add_theme_constant_override("separation", 5)
	origin_scroller.add_child(_origin_cards)
	var add_origin := Button.new()
	add_origin.text = "+ Origine"
	add_origin.pressed.connect(func() -> void: _origin_editor.visible = not _origin_editor.visible)
	left.add_child(add_origin)
	_origin_editor = VBoxContainer.new()
	_origin_editor.visible = false
	left.add_child(_origin_editor)
	_origin_picker = OptionButton.new()
	_origin_picker.item_selected.connect(_on_origin_option)
	_origin_editor.add_child(_origin_picker)
	_origin_name = LineEdit.new()
	_origin_name.placeholder_text = "Nome origine personalizzata"
	_origin_editor.add_child(_origin_name)
	var origin_confirm := Button.new()
	origin_confirm.text = "Aggiungi origine"
	origin_confirm.pressed.connect(_add_origin)
	_origin_editor.add_child(origin_confirm)

	var manage_feats := Button.new()
	manage_feats.text = "Talenti posseduti ▸"
	manage_feats.pressed.connect(func() -> void:
		_feat_editor.visible = not _feat_editor.visible
		manage_feats.text = "Talenti posseduti ▾" if _feat_editor.visible else "Talenti posseduti ▸"
	)
	left.add_child(manage_feats)
	_feat_editor = VBoxContainer.new()
	_feat_editor.visible = false
	left.add_child(_feat_editor)
	_feat_filter = LineEdit.new()
	_feat_filter.placeholder_text = "Cerca talento…"
	_feat_filter.clear_button_enabled = true
	_feat_filter.text_changed.connect(func(_value: String) -> void: _refresh_feat_lists())
	_feat_editor.add_child(_feat_filter)
	_feat_list = ItemList.new()
	_feat_list.custom_minimum_size.y = 90
	_feat_list.item_activated.connect(func(_i: int) -> void: _add_feat())
	_feat_editor.add_child(_feat_list)
	var add_feat := Button.new()
	add_feat.text = "+ Talento dal catalogo"
	add_feat.pressed.connect(_add_feat)
	_feat_editor.add_child(add_feat)
	_feat_owned = ItemList.new()
	_feat_owned.custom_minimum_size.y = 65
	_feat_editor.add_child(_feat_owned)
	var remove_feat := Button.new()
	remove_feat.text = "Rimuovi talento selezionato"
	remove_feat.pressed.connect(_remove_feat)
	_feat_editor.add_child(remove_feat)

	var competence_scroller := ScrollContainer.new()
	competence_scroller.custom_minimum_size.y = 245
	competence_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	competence_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(competence_scroller)
	_proficiency_cards = VBoxContainer.new()
	_proficiency_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_proficiency_cards.add_theme_constant_override("separation", 4)
	competence_scroller.add_child(_proficiency_cards)
	_add_competence_button = Button.new()
	_add_competence_button.text = "+ Competenza all'origine selezionata"
	_add_competence_button.disabled = true
	_add_competence_button.pressed.connect(func() -> void:
		if _selected_id not in ["~none~", ""]:
			_competence_editor.visible = not _competence_editor.visible
	)
	right.add_child(_add_competence_button)
	_competence_editor = VBoxContainer.new()
	_competence_editor.visible = false
	right.add_child(_competence_editor)
	_kind_picker = OptionButton.new()
	for item: Dictionary in GROUPS:
		_kind_picker.add_item(String(item.get("label", "")))
	_kind_picker.item_selected.connect(func(_i: int) -> void: _refresh_proficiency_picker())
	_competence_editor.add_child(_kind_picker)
	_proficiency_picker = OptionButton.new()
	_competence_editor.add_child(_proficiency_picker)
	_proficiency_name = LineEdit.new()
	_proficiency_name.placeholder_text = "Oppure scrivi una competenza"
	_competence_editor.add_child(_proficiency_name)
	var competence_confirm := Button.new()
	competence_confirm.text = "Aggiungi competenza"
	competence_confirm.pressed.connect(_add_competence)
	_competence_editor.add_child(competence_confirm)
	_refresh_proficiency_picker()
	load_record({})


func _create_column(parent: HBoxContainer, heading: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 15)
	content.add_child(title)
	return content


func load_record(record: Dictionary) -> void:
	_loading = true
	_record = record.duplicate(true)
	_rows = Rules.choices(record)
	_origins = Rules.origins(record)
	_feats.clear()
	var raw: Variant = record.get("feats_catalog", [])
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				_feats.append((entry as Dictionary).duplicate(true))
	if _selected_id != "~none~" and not _origin_exists(_selected_id):
		_selected_id = "~none~"
	_refresh()
	_loading = false


func _origin_exists(sid: String) -> bool:
	if sid.is_empty():
		return true
	for entry: Dictionary in _origins:
		if String(entry.get("id", "")) == sid:
			return true
	return false


func _effective_record() -> Dictionary:
	var record: Dictionary = _record.duplicate(true)
	record["proficiency_origins"] = _origins.duplicate(true)
	record["feats_catalog"] = _feats.duplicate(true)
	Rules.sync_legacy_fields(record, _rows)
	return record


func _enabled_map() -> Dictionary:
	var enabled: Dictionary = {}
	for item: Dictionary in _origins:
		enabled[String(item.get("id", ""))] = not bool(item.get("disabled", false))
	return enabled


func _refresh() -> void:
	_add_competence_button.disabled = _selected_id in ["~none~", ""]
	_refresh_origins()
	_refresh_competences()
	_refresh_origin_picker()
	_refresh_feat_lists()
	_status.text = "Seleziona un'origine per evidenziare le competenze collegate; cliccala di nuovo per deselezionarla."
	_status.tooltip_text = "✓ competenza attiva · ◇ scelte da completare · ⏻ disattivazione senza eliminare i dati"


func _refresh_origins() -> void:
	for node: Node in _origin_cards.get_children():
		node.queue_free()
		_origin_cards.remove_child(node)
	var enabled: Dictionary = _enabled_map()
	var all: Array[Dictionary] = _origins.duplicate(true)
	var has_unassigned := false
	for entry: Dictionary in _rows:
		if String(entry.get("origin_id", "")).is_empty():
			has_unassigned = true
	if has_unassigned:
		all.append({"id": "", "name": "⚠ Senza origine", "disabled": false, "requirements": []})
	for item: Dictionary in all:
		var sid: String = String(item.get("id", ""))
		var matching := 0
		for proficiency: Dictionary in _rows:
			if String(proficiency.get("origin_id", "")) == sid:
				matching += 1
		var missing: Array[String] = Rules.requirement_missing(item, _rows, enabled)
		var card := PanelContainer.new()
		_origin_cards.add_child(card)
		var line := HBoxContainer.new()
		card.add_child(line)
		var select := Button.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var selected := _selected_id == sid
		select.toggle_mode = true
		select.button_pressed = selected
		select.clip_text = true
		select.text = ("%s%s" % ["◇ " if not missing.is_empty() else "• ", String(item.get("name", ""))]) + " (%d)" % matching
		var description: String = _origin_description(item)
		select.tooltip_text = description + ("\n\n◇ Da scegliere: " + ", ".join(missing) if not missing.is_empty() else "")
		select.pressed.connect(_select_origin.bind(sid))
		line.add_child(select)
		if not sid.is_empty():
			var active := CheckButton.new()
			active.text = "⏻"
			active.tooltip_text = "Origine attiva / disattivata"
			active.button_pressed = not bool(item.get("disabled", false))
			active.toggled.connect(_toggle_origin.bind(sid))
			line.add_child(active)
		if selected:
			var highlight := StyleBoxFlat.new()
			highlight.bg_color = Color(0.18, 0.39, 0.54, 0.28)
			highlight.set_corner_radius_all(5)
			card.add_theme_stylebox_override("panel", highlight)
		elif bool(item.get("disabled", false)):
			card.modulate.a = 0.58


func _origin_description(origin: Dictionary) -> String:
	var sid: String = String(origin.get("id", ""))
	var source_record: Dictionary = _effective_record()
	for candidate: Dictionary in Rules.candidate_sources(source_record):
		if String(candidate.get("id", "")) != sid:
			continue
		if String(candidate.get("group", "")) == "class":
			return Rules.starting_description(candidate)
		var data: Dictionary = candidate.get("data", {})
		var group: String = String(candidate.get("group", ""))
		var catalogue: String = {"race": "races", "subrace": "races",
			"background": "backgrounds", "feat": "feats"}.get(group, "")
		if not catalogue.is_empty():
			for entry: Dictionary in Catalog.entries(catalogue):
				if String(entry.get("name", "")).nocasecmp_to(String(data.get("name", ""))) == 0 and String(entry.get("source", "")) == String(data.get("source", "")):
					return Catalog.info_text(entry)
		return Catalog.info_text(data) + "\nCompetenze strutturate: " + JSON.stringify(data)
	if sid.begins_with("feature:"):
		for feature_entry: Dictionary in Traits.collect_features(source_record):
			if sid == "feature:" + String(feature_entry.get("key", "")):
				return Catalog.info_text(feature_entry)
	if sid.begins_with("item:"):
		var raw: Variant = source_record.get("inventory", [])
		if raw is Array:
			for owned: Variant in raw:
				if owned is Dictionary and sid == "item:" + String(owned.get("id", "")):
					return Catalog.info_text(owned)
	return String(origin.get("name", "Origine personalizzata"))


func _refresh_competences() -> void:
	for node: Node in _proficiency_cards.get_children():
		node.queue_free()
		_proficiency_cards.remove_child(node)
	var enabled: Dictionary = _enabled_map()
	var grouped: Dictionary = {}
	var ordered: Array[String] = []
	for index: int in range(_rows.size()):
		var entry: Dictionary = _rows[index]
		var kind: String = String(entry.get("kind", ""))
		if kind == "expertise":
			continue
		var identity: String = kind + "|" + String(entry.get("key", ""))
		if not grouped.has(identity):
			grouped[identity] = []
			ordered.append(identity)
		grouped[identity].append(index)
	if ordered.is_empty():
		var empty := Label.new()
		empty.text = "Nessuna competenza. Seleziona un'origine per aggiungerne."
		_proficiency_cards.add_child(empty)
		return
	var last_kind := ""
	for identity: String in ordered:
		var indices: Array = grouped[identity]
		var example: Dictionary = _rows[int(indices[0])]
		var kind: String = String(example.get("kind", ""))
		var key: String = String(example.get("key", ""))
		if kind != last_kind:
			last_kind = kind
			var heading := Label.new()
			heading.text = {"tool": "Strumenti", "save": "Tiri salvezza", "weapon": "Armi",
				"armor": "Armature e scudi", "skill": "Abilità", "language": "Lingue"}.get(kind, kind.capitalize())
			heading.add_theme_font_size_override("font_size", 14)
			_proficiency_cards.add_child(heading)
		var active := false
		var selected := false
		var linked: Array[String] = []
		for index: Variant in indices:
			var link: Dictionary = _rows[int(index)]
			var sid: String = String(link.get("origin_id", ""))
			if sid == _selected_id:
				selected = true
			if not bool(link.get("disabled", false)) and bool(enabled.get(sid, true)):
				active = true
			var label: String = _origin_display(sid) if not sid.is_empty() else "Senza origine"
			if label not in linked:
				linked.append(label)
		var cell := PanelContainer.new()
		_proficiency_cards.add_child(cell)
		if selected:
			var background := StyleBoxFlat.new()
			background.bg_color = Color(0.18, 0.43, 0.62, 0.32)
			background.set_corner_radius_all(5)
			cell.add_theme_stylebox_override("panel", background)
		if not active:
			cell.modulate.a = 0.58
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		cell.add_child(box)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		var mastered: bool = kind == "skill" and _effective_expertise(key, enabled)
		label.text = ("✓ " if active else "○ ") + key + (" 🎓🎓" if mastered else "")
		label.tooltip_text = "Origini: " + ", ".join(linked)
		box.add_child(label)
		if kind == "skill":
			var expert := CheckButton.new()
			expert.text = "✦✦"
			expert.tooltip_text = "Maestria (doppia competenza)"
			expert.button_pressed = mastered
			expert.toggled.connect(_toggle_group_expertise.bind(key, indices.duplicate()))
			box.add_child(expert)
		var toggle := CheckButton.new()
		toggle.text = "⏻"
		toggle.tooltip_text = "Disattiva " + ("il collegamento con l'origine selezionata" if selected else "tutte le concessioni di questa competenza")
		toggle.button_pressed = _group_enabled(indices)
		toggle.disabled = _selected_id not in ["~none~", ""] and not selected
		toggle.toggled.connect(_toggle_group.bind(indices.duplicate()))
		box.add_child(toggle)
		if _selected_id not in ["~none~", ""] and not selected:
			var attach := Button.new()
			attach.text = "↳"
			attach.tooltip_text = "Aggiungi anche l'origine selezionata, senza rimuovere le altre"
			attach.pressed.connect(_link_group.bind(kind, key))
			box.add_child(attach)


func _group_enabled(indices: Array) -> bool:
	for index: Variant in indices:
		var row: Dictionary = _rows[int(index)]
		if _selected_id not in ["~none~", ""] and String(row.get("origin_id", "")) != _selected_id:
			continue
		if not bool(row.get("disabled", false)):
			return true
	return false


func _effective_expertise(key: String, enabled: Dictionary) -> bool:
	for row: Dictionary in _rows:
		if String(row.get("kind", "")) == "expertise" and String(row.get("key", "")) == key:
			var sid: String = String(row.get("origin_id", ""))
			if not bool(row.get("disabled", false)) and bool(enabled.get(sid, true)):
				return true
	return false


func _toggle_group(on: bool, indices: Array) -> void:
	for index: Variant in indices:
		var row: Dictionary = _rows[int(index)]
		if _selected_id not in ["~none~", ""] and String(row.get("origin_id", "")) != _selected_id:
			continue
		row["disabled"] = not on
	_publish()


func _toggle_group_expertise(on: bool, key: String, indices: Array) -> void:
	var origin: Dictionary = {}
	for index: Variant in indices:
		var row: Dictionary = _rows[int(index)]
		if _selected_id not in ["~none~", ""] and String(row.get("origin_id", "")) != _selected_id:
			continue
		origin = row
		break
	if origin.is_empty():
		return
	var sid: String = String(origin.get("origin_id", ""))
	for entry: Dictionary in _rows:
		if String(entry.get("kind", "")) == "expertise" and String(entry.get("key", "")) == key and String(entry.get("origin_id", "")) == sid:
			entry["disabled"] = not on
			_publish()
			return
	if on:
		_rows.append({"kind": "expertise", "key": key, "origin_id": sid,
			"origin_name": _origin_display(sid), "disabled": false})
	_publish()


func _link_group(kind: String, key: String) -> void:
	if _selected_id in ["~none~", ""] or not _valid_structured_choice(kind, key):
		return
	for entry: Dictionary in _rows:
		if String(entry.get("kind", "")) == kind and String(entry.get("key", "")) == key and String(entry.get("origin_id", "")) == _selected_id:
			entry["disabled"] = false
			_publish()
			return
	_rows.append({"kind": kind, "key": key, "origin_id": _selected_id,
		"origin_name": _origin_display(_selected_id), "disabled": false})
	_publish()


func _has_expertise(sid: String, key: String) -> bool:
	for item: Dictionary in _rows:
		if String(item.get("kind", "")) == "expertise" and String(item.get("key", "")) == key and String(item.get("origin_id", "")) == sid:
			return not bool(item.get("disabled", false))
	return false


func _select_origin(sid: String) -> void:
	_selected_id = "~none~" if _selected_id == sid else sid
	_add_competence_button.disabled = _selected_id in ["~none~", ""]
	_competence_editor.visible = false
	_refresh_origins()
	_refresh_competences()
	_refresh_proficiency_picker()


func _toggle_origin(on: bool, sid: String) -> void:
	for item: Dictionary in _origins:
		if String(item.get("id", "")) == sid:
			item["disabled"] = not on
			break
	_publish()


func _toggle_competence(on: bool, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index]["disabled"] = not on
	_publish()


func _set_expertise(on: bool, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var source: Dictionary = _rows[index]
	var sid: String = String(source.get("origin_id", ""))
	var key: String = String(source.get("key", ""))
	for item: Dictionary in _rows:
		if String(item.get("kind", "")) == "expertise" and String(item.get("key", "")) == key and String(item.get("origin_id", "")) == sid:
			item["disabled"] = not on
			_publish()
			return
	if on:
		_rows.append({"kind": "expertise", "key": key, "origin_id": sid,
			"origin_name": source.get("origin_name", ""), "disabled": false})
	_publish()


func _reassign(index: int) -> void:
	if _selected_id == "~none~" or index < 0 or index >= _rows.size():
		return
	_rows[index]["origin_id"] = _selected_id
	_rows[index]["origin_name"] = _origin_display(_selected_id)
	_publish()


func _origin_display(sid: String) -> String:
	for item: Dictionary in _origins:
		if String(item.get("id", "")) == sid:
			return String(item.get("name", ""))
	return ""


func _refresh_origin_picker() -> void:
	_origin_picker.clear()
	_origin_picker.add_item("Origine personalizzata")
	_origin_picker.set_item_metadata(0, {"name": "", "id": ""})
	for feature_entry: Dictionary in Traits.collect_features(_effective_record()):
		_origin_picker.add_item("Tratto · " + String(feature_entry.get("name", "")))
		_origin_picker.set_item_metadata(_origin_picker.item_count - 1, {
			"id": "feature:" + String(feature_entry.get("key", "")),
			"name": "Tratto · " + String(feature_entry.get("name", ""))
		})
	var inv: Variant = _record.get("inventory", [])
	if inv is Array:
		for item: Variant in inv:
			if not item is Dictionary:
				continue
			_origin_picker.add_item("Oggetto · " + String(item.get("name", "")))
			_origin_picker.set_item_metadata(_origin_picker.item_count - 1, {
				"id": "item:" + String(item.get("id", "")),
				"name": "Oggetto · " + String(item.get("name", ""))
			})


func _on_origin_option(index: int) -> void:
	var meta: Dictionary = _origin_picker.get_item_metadata(index)
	_origin_name.text = String(meta.get("name", ""))


func _add_origin() -> void:
	var name: String = _origin_name.text.strip_edges()
	var metadata: Dictionary = _origin_picker.get_item_metadata(_origin_picker.selected)
	var sid: String = String(metadata.get("id", ""))
	if name.is_empty():
		name = String(metadata.get("name", "")).strip_edges()
	if name.is_empty():
		return
	if sid.is_empty():
		sid = "custom|" + name.to_lower().uri_encode()
	if not _origin_exists(sid):
		_origins.append({"id": sid, "name": name, "group": "custom",
			"disabled": false, "automatic": false, "requirements": []})
	_selected_id = sid
	_origin_editor.visible = false
	_origin_name.clear()
	_publish()


func _selected_source_record() -> Dictionary:
	for item: Dictionary in _origins:
		if String(item.get("id", "")) == _selected_id:
			return item
	return {}


func _catalog_entries() -> Array[Dictionary]:
	var kind: String = String(GROUPS[_kind_picker.selected].get("kind", "skill"))
	var items: Array[Dictionary] = []
	if kind == "skill":
		for key: String in Rules.SKILLS:
			items.append({"key": key, "label": key.capitalize()})
	elif kind == "save":
		for key: String in Rules.ABILITIES:
			items.append({"key": key, "label": key.to_upper()})
	elif kind == "armor":
		for key: String in Rules.ARMORS:
			items.append({"key": key, "label": key.capitalize()})
	elif kind == "weapon":
		for key: String in ["simple", "martial"]:
			items.append({"key": key, "label": key.capitalize()})
		for item: Dictionary in Catalog.entries("weapons"):
			if _valid_edition(item):
				items.append({"key": String(item.get("name", "")).to_lower(), "label": String(item.get("name", ""))})
	elif kind in ["tool", "language"]:
		for item: Dictionary in Catalog.entries("tools" if kind == "tool" else "languages"):
			if _valid_edition(item):
				items.append({"key": String(item.get("name", "")).to_lower(), "label": String(item.get("name", ""))})
	if kind == "skill":
		var allowed: Array[String] = Rules.restricted_choices(_selected_source_record(), kind)
		if not allowed.is_empty():
			var restricted: Array[Dictionary] = []
			for item: Dictionary in items:
				if String(item.get("key", "")) in allowed:
					restricted.append(item)
			return restricted
	return items


func _refresh_proficiency_picker() -> void:
	_proficiency_picker.clear()
	var used: Dictionary = {}
	for entry: Dictionary in _catalog_entries():
		var key: String = String(entry.get("key", ""))
		if not used.has(key):
			used[key] = true
			_proficiency_picker.add_item(String(entry.get("label", "")))
			_proficiency_picker.set_item_metadata(_proficiency_picker.item_count - 1, key)


# Free-form sources allow any manual link. Structured skill choice lists
# and counts, when provided, constrain both Add and Attach actions.
func _valid_structured_choice(kind: String, key: String) -> bool:
	if kind != "skill":
		return true
	var source: Dictionary = _selected_source_record()
	var allowed: Array[String] = Rules.restricted_choices(source, kind)
	if not allowed.is_empty() and key not in allowed:
		return false
	for entry: Dictionary in _rows:
		if String(entry.get("kind", "")) == kind and String(entry.get("key", "")) == key and String(entry.get("origin_id", "")) == _selected_id:
			return true
	var max_choices := 0
	for requirement: Dictionary in source.get("requirements", []):
		if String(requirement.get("kind", "")) == kind:
			max_choices += int(requirement.get("count", 0))
	if max_choices == 0:
		return true
	var assigned := 0
	for entry: Dictionary in _rows:
		if String(entry.get("origin_id", "")) != _selected_id or String(entry.get("kind", "")) != kind or bool(entry.get("disabled", false)):
			continue
		if allowed.is_empty() or String(entry.get("key", "")) in allowed:
			assigned += 1
	return assigned < max_choices


func _add_competence() -> void:
	if _selected_id in ["~none~", ""]:
		return
	var kind: String = String(GROUPS[_kind_picker.selected].get("kind", "skill"))
	var key: String = _proficiency_name.text.strip_edges().to_lower()
	if key.is_empty() and _proficiency_picker.selected >= 0:
		key = String(_proficiency_picker.get_item_metadata(_proficiency_picker.selected))
	if key.is_empty():
		return
	if not _valid_structured_choice(kind, key):
		_proficiency_name.tooltip_text = "Scelta non prevista dai dati strutturati o limite dell'origine raggiunto."
		return
	for row: Dictionary in _rows:
		if String(row.get("origin_id", "")) == _selected_id and String(row.get("kind", "")) == kind and String(row.get("key", "")) == key:
			row["disabled"] = false
			_publish()
			return
	_rows.append({"kind": kind, "key": key, "origin_id": _selected_id,
		"origin_name": _origin_display(_selected_id), "disabled": false})
	_proficiency_name.clear()
	_competence_editor.visible = false
	_publish()


func _valid_edition(item: Dictionary) -> bool:
	var source: String = String(item.get("source", ""))
	var edition: String = String(_record.get("rules_version", "2014"))
	if edition == "2014":
		return source not in ["XPHB", "XDMG", "EFA"] and String(item.get("edition", "")) != "one"
	return source not in ["XDMG", "EFA"]


func _refresh_feat_lists() -> void:
	if _feat_list == null:
		return
	_feat_available.clear()
	_feat_list.clear()
	var needle: String = _feat_filter.text.to_lower()
	for item: Dictionary in Catalog.entries("feats"):
		if not _valid_edition(item):
			continue
		if not needle.is_empty() and needle not in String(item.get("name", "")).to_lower():
			continue
		_feat_available.append(item)
		_feat_list.add_item("%s · %s" % [item.get("name", ""), item.get("source", "")])
		if _feat_available.size() >= 160:
			break
	_feat_owned.clear()
	for item: Dictionary in _feats:
		_feat_owned.add_item("%s · %s" % [item.get("name", ""), item.get("source", "")])


func _add_feat() -> void:
	var indexes: PackedInt32Array = _feat_list.get_selected_items()
	if indexes.is_empty() or indexes[0] >= _feat_available.size():
		return
	var feat: Dictionary = _feat_available[indexes[0]]
	for owned: Dictionary in _feats:
		if String(owned.get("id", "")) == String(feat.get("id", "")):
			return
	_feats.append({"id": feat.get("id", ""), "name": feat.get("name", ""), "source": feat.get("source", "")})
	_refresh_from_current_state()


func _remove_feat() -> void:
	var indexes: PackedInt32Array = _feat_owned.get_selected_items()
	if indexes.is_empty() or indexes[0] >= _feats.size():
		return
	_feats.remove_at(indexes[0])
	_refresh_from_current_state()


func _refresh_from_current_state() -> void:
	var current: Dictionary = _effective_record()
	_origins = Rules.origins(current)
	_rows = Rules.choices(current)
	_publish()


func _publish() -> void:
	_refresh()
	if not _loading and _changed.is_valid():
		# Requirements are recalculated from the bundled 5etools index on load,
		# and must not be duplicated into every character's saved file.
		var stored: Array[Dictionary] = []
		for item: Dictionary in _origins:
			stored.append({"id": item.get("id", ""), "name": item.get("name", ""),
				"group": item.get("group", ""), "automatic": bool(item.get("automatic", false)),
				"disabled": bool(item.get("disabled", false))})
		_changed.call(_rows.duplicate(true), _feats.duplicate(true), stored)
