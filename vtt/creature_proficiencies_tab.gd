extends VBoxContainer

# Expandable Statistics editor: structured origins on the left, individual
# proficiencies on the right. Nothing is inferred from natural-language text.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const OriginButton = preload("res://vtt/bounded_tooltip_button.gd")

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
var _feat_section: VBoxContainer
var _feat_toggle_button: Button
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
var _choice_dialog: ConfirmationDialog
var _choice_contents: VBoxContainer
var _choice_selector: OptionButton
var _choice_scroll: ScrollContainer
var _choice_source_id := ""
var _choice_groups: Array[Dictionary] = []
var _delete_dialog: ConfirmationDialog
var _delete_picker: OptionButton
var _delete_kind := ""
var _delete_key := ""
var _mandatory_grants: Dictionary = {}


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

	# Feats belong to Info. Construct the section here so the same
	# catalog and synchronization logic can be kept, then reparent it.
	_feat_section = VBoxContainer.new()
	left.add_child(_feat_section)
	_feat_toggle_button = Button.new()
	_feat_toggle_button.text = "TALENTI ▾"
	_feat_toggle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_feat_toggle_button.add_theme_font_size_override("font_size", 17)
	_feat_toggle_button.pressed.connect(func() -> void:
		_feat_editor.visible = not _feat_editor.visible
		_feat_toggle_button.text = "TALENTI ▾" if _feat_editor.visible else "TALENTI ▸"
	)
	_feat_section.add_child(_feat_toggle_button)
	_feat_editor = VBoxContainer.new()
	_feat_editor.visible = true
	_feat_section.add_child(_feat_editor)
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
	_choice_dialog = ConfirmationDialog.new()
	_choice_dialog.title = "Completa le competenze"
	_choice_dialog.ok_button_text = "Applica"
	_choice_dialog.cancel_button_text = "Annulla"
	_choice_dialog.confirmed.connect(_apply_choice_dialog)
	add_child(_choice_dialog)
	var choice_scroll := ScrollContainer.new()
	choice_scroll.custom_minimum_size = Vector2(460, 370)
	choice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_dialog.add_child(choice_scroll)
	_choice_contents = VBoxContainer.new()
	_choice_contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_contents.add_theme_constant_override("separation", 9)
	choice_scroll.add_child(_choice_contents)
	_choice_scroll = choice_scroll
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina competenza"
	_delete_dialog.ok_button_text = "Elimina"
	_delete_dialog.cancel_button_text = "Annulla"
	_delete_dialog.confirmed.connect(_confirm_delete_competence)
	add_child(_delete_dialog)
	var delete_content := VBoxContainer.new()
	_delete_dialog.add_child(delete_content)
	var delete_info := Label.new()
	delete_info.text = "Da quale origine vuoi eliminare la competenza?"
	delete_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delete_content.add_child(delete_info)
	_delete_picker = OptionButton.new()
	_delete_picker.custom_minimum_size.x = 345
	delete_content.add_child(_delete_picker)
	_refresh_proficiency_picker()
	load_record({})


func move_feats_to_info(destination: VBoxContainer) -> void:
	if destination == null or _feat_section == null:
		return
	_feat_section.reparent(destination)
	_feat_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL


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
	# A still-open choice dialog must not modify the next selected creature.
	if _choice_dialog != null:
		_choice_dialog.hide()
	if _delete_dialog != null:
		_delete_dialog.hide()
	_choice_source_id = ""
	_choice_groups.clear()
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
	_rebuild_mandatory_grants()
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
		var select := OriginButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var selected := _selected_id == sid
		select.toggle_mode = true
		select.button_pressed = selected
		select.clip_text = true
		select.text = String(item.get("name", "")) + " (%d)" % matching
		var description: String = _origin_description(item)
		select.tooltip_text = description + ("\n\n⚠ Da scegliere: " + ", ".join(missing) if not missing.is_empty() else "")
		select.pressed.connect(_select_origin.bind(sid))
		line.add_child(select)
		# The warning has its own button: long source names must not clip it.
		if not missing.is_empty() and not sid.is_empty():
			var warning := Button.new()
			warning.text = "⚠"
			warning.flat = true
			warning.custom_minimum_size.x = 32
			warning.add_theme_color_override("font_color", Color(1.0, 0.80, 0.33))
			warning.tooltip_text = "Completa le scelte: " + ", ".join(missing)
			warning.pressed.connect(_open_missing_choices.bind(sid))
			line.add_child(warning)
		if not sid.is_empty():
			var active := CheckButton.new()
			active.text = "⏻"
			active.tooltip_text = "Origine attiva / disattivata"
			active.button_pressed = not bool(item.get("disabled", false))
			active.toggled.connect(_toggle_origin.bind(sid))
			line.add_child(active)
		if selected:
			var highlight := StyleBoxFlat.new()
			highlight.draw_center = false
			highlight.border_color = Color(0.40, 0.72, 0.91)
			highlight.set_border_width_all(2)
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
					return Catalog.info_text(entry, _source_description_text(entry))
		return Catalog.info_text(data, _source_description_text(data)) + "\nCompetenze strutturate: " + JSON.stringify(data)
	if sid.begins_with("feature:"):
		for feature_entry: Dictionary in Traits.collect_features(source_record):
			if sid == "feature:" + String(feature_entry.get("key", "")):
				return Catalog.info_text(feature_entry, _source_description_text(feature_entry))
	if sid.begins_with("item:"):
		var raw: Variant = source_record.get("inventory", [])
		if raw is Array:
			for owned: Variant in raw:
				if owned is Dictionary and sid == "item:" + String(owned.get("id", "")):
					var definition: Dictionary = owned
					# Live inventory entries often omit the item's description.
					# Resolve the original catalogue or homebrew definition.
					for catalog_item: Dictionary in Catalog.entries("items"):
						if String(catalog_item.get("id", "")) == String(owned.get("id", "")):
							definition = catalog_item
							break
					return Catalog.info_text(definition, _source_description_text(definition))
	return String(origin.get("name", "Origine personalizzata"))


func _source_description_text(entry: Dictionary) -> String:
	var raw: Variant = entry.get("description", entry.get("entries", entry.get("text", "")))
	if raw is String:
		return String(raw)
	if raw is Array:
		var parts := PackedStringArray()
		for section: Variant in raw:
			if section is String:
				parts.append(String(section))
			elif section is Dictionary:
				var nested: Variant = (section as Dictionary).get("entry", (section as Dictionary).get("entries", ""))
				if nested is String:
					parts.append(String(nested))
				elif nested is Array:
					for sentence: Variant in nested:
						if sentence is String:
							parts.append(String(sentence))
		return "\n".join(parts)
	return ""


func _section_for_proficiency(kind: String, key: String) -> String:
	if kind == "weapon" and key in ["simple", "martial", "all"]:
		return "weapon_category"
	return kind


func _refresh_competences() -> void:
	for node: Node in _proficiency_cards.get_children():
		_proficiency_cards.remove_child(node)
		node.queue_free()
	var enabled: Dictionary = _enabled_map()
	var grouped: Dictionary = {}
	var by_section: Dictionary = {}
	for index: int in range(_rows.size()):
		var entry: Dictionary = _rows[index]
		var kind: String = String(entry.get("kind", ""))
		if kind == "expertise":
			continue
		var key: String = String(entry.get("key", ""))
		var identity: String = kind + "|" + key
		if not grouped.has(identity):
			grouped[identity] = []
			var section: String = _section_for_proficiency(kind, key)
			if not by_section.has(section):
				by_section[section] = []
			by_section[section].append(identity)
		grouped[identity].append(index)
	if grouped.is_empty():
		var empty := Label.new()
		empty.text = "Nessuna competenza disponibile."
		_proficiency_cards.add_child(empty)
		return
	var headings: Dictionary = {
		"skill": "Abilità",
		"save": "Tiri salvezza",
		"weapon_category": "Categorie di armi",
		"weapon": "Singole armi",
		"armor": "Armature e scudi",
		"tool": "Strumenti",
		"language": "Lingue"
	}
	var sections: Array[String] = ["skill", "save", "weapon_category", "weapon", "armor", "tool", "language"]
	for section: String in sections:
		if not by_section.has(section):
			continue
		var heading := Label.new()
		heading.text = String(headings.get(section, section.capitalize()))
		heading.add_theme_font_size_override("font_size", 15)
		_proficiency_cards.add_child(heading)
		var entries: Array = by_section[section]
		entries.sort_custom(func(a: Variant, b: Variant) -> bool:
			return String(a).naturalnocasecmp_to(String(b)) < 0
		)
		for identity: String in entries:
			var indices: Array = grouped[identity]
			var example: Dictionary = _rows[int(indices[0])]
			var kind: String = String(example.get("kind", ""))
			var key: String = String(example.get("key", ""))
			var active := false
			var selected := false
			var selected_active := false
			var linked: Array[String] = []
			for index: Variant in indices:
				var link: Dictionary = _rows[int(index)]
				var sid: String = String(link.get("origin_id", ""))
				var grant_active: bool = not bool(link.get("disabled", false)) and bool(enabled.get(sid, true))
				if sid == _selected_id:
					selected = true
					selected_active = selected_active or grant_active
				active = active or grant_active
				var origin_label: String = _origin_display(sid) if not sid.is_empty() else "Senza origine"
				var status_label: String = ("✓ " if grant_active else "○ ") + origin_label
				if status_label not in linked:
					linked.append(status_label)
			var cell := PanelContainer.new()
			_proficiency_cards.add_child(cell)
			if selected_active:
				var background := StyleBoxFlat.new()
				background.draw_center = false
				background.border_color = Color(0.44, 0.75, 0.95)
				background.set_border_width_all(2)
				background.set_corner_radius_all(5)
				cell.add_theme_stylebox_override("panel", background)
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 4)
			cell.add_child(box)
			var label := Label.new()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.clip_text = true
			var mastered: bool = kind == "skill" and _effective_expertise(key, enabled)
			label.text = ("✓ " if active else "○ ") + key + (" 🎓🎓" if mastered else "")
			label.tooltip_text = "Origini:\n" + "\n".join(linked)
			box.add_child(label)
			if kind == "skill":
				var expert := CheckButton.new()
				expert.text = "Mestria"
				expert.tooltip_text = "Maestria (doppia competenza)"
				expert.button_pressed = mastered
				expert.toggled.connect(_toggle_group_expertise.bind(key, indices.duplicate()))
				box.add_child(expert)
			var toggle := CheckButton.new()
			toggle.text = "⏻"
			toggle.tooltip_text = "Competenza effettiva da almeno un'origine attiva. Seleziona l'origine per modificare solo le sue concessioni."
			toggle.button_pressed = _group_enabled(indices)
			# An origin filter is for highlighting, not for turning unrelated
			# proficiencies off. Mandatory grants remain immutable individually.
			toggle.disabled = (_selected_id not in ["~none~", ""] and not selected) or _has_mandatory_in_scope(indices)
			toggle.toggled.connect(_toggle_group.bind(indices.duplicate()))
			box.add_child(toggle)
			if not _deletable_sources(kind, key).is_empty():
				var remove := Button.new()
				remove.text = "✕"
				remove.tooltip_text = "Elimina una competenza scelta. Se concessa da più origini, scegli quale."
				remove.flat = true
				remove.pressed.connect(_request_delete_competence.bind(kind, key))
				box.add_child(remove)



func _rebuild_mandatory_grants() -> void:
	_mandatory_grants.clear()
	var state: Dictionary = _record.duplicate(true)
	state["feats_catalog"] = _feats.duplicate(true)
	for source: Dictionary in Rules.candidate_sources(state):
		var sid: String = String(source.get("id", ""))
		for grant: Dictionary in Rules.fixed_grants(source):
			var identity: String = sid + "|" + String(grant.get("kind", "")) + "|" + String(grant.get("key", ""))
			_mandatory_grants[identity] = true


func _is_mandatory_choice(row: Dictionary) -> bool:
	var sid: String = String(row.get("origin_id", ""))
	if sid.is_empty():
		return false
	return _mandatory_grants.has(sid + "|" + String(row.get("kind", "")) + "|" + String(row.get("key", "")))


func _has_mandatory_in_scope(indices: Array) -> bool:
	for raw_index: Variant in indices:
		var row: Dictionary = _rows[int(raw_index)]
		var sid: String = String(row.get("origin_id", ""))
		if _selected_id not in ["~none~", ""] and sid != _selected_id:
			continue
		if _is_mandatory_choice(row):
			return true
	return false


func _deletable_sources(kind: String, key: String) -> Array[String]:
	var sources: Array[String] = []
	for row: Dictionary in _rows:
		if String(row.get("kind", "")) != kind or String(row.get("key", "")) != key:
			continue
		var sid: String = String(row.get("origin_id", ""))
		if _is_mandatory_choice(row) or (bool(row.get("automatic", false)) and not sid.is_empty()):
			continue
		if sid not in sources:
			sources.append(sid)
	return sources


func _request_delete_competence(kind: String, key: String) -> void:
	var eligible: Array[String] = _deletable_sources(kind, key)
	if eligible.is_empty():
		return
	var all_sources: Dictionary = {}
	for row: Dictionary in _rows:
		if String(row.get("kind", "")) == kind and String(row.get("key", "")) == key:
			all_sources[String(row.get("origin_id", ""))] = true
	if all_sources.size() <= 1:
		_delete_competence_from_source(kind, key, eligible[0])
		return
	_delete_kind = kind
	_delete_key = key
	_delete_dialog.title = "Elimina · " + key.capitalize()
	_delete_picker.clear()
	_delete_picker.add_item("Da tutte le origini (tranne concessioni obbligatorie)")
	_delete_picker.set_item_metadata(0, "~all~")
	var source_ids: Array = all_sources.keys()
	source_ids.sort()
	for raw_id: Variant in source_ids:
		var sid: String = String(raw_id)
		var label: String = "Senza origine" if sid.is_empty() else _origin_display(sid)
		if label.is_empty():
			label = sid
		_delete_picker.add_item(label)
		var index: int = _delete_picker.item_count - 1
		_delete_picker.set_item_metadata(index, sid)
		_delete_picker.set_item_disabled(index, sid not in eligible)
	_delete_picker.select(0)
	DialogLayout.popup(_delete_dialog, Vector2i(445, 185), 0.90)


func _confirm_delete_competence() -> void:
	if _delete_picker.selected < 0 or _delete_kind.is_empty():
		return
	var sid: String = String(_delete_picker.get_item_metadata(_delete_picker.selected))
	_delete_competence_from_source(_delete_kind, _delete_key, sid)
	_delete_kind = ""
	_delete_key = ""


func _delete_competence_from_source(kind: String, key: String, sid: String) -> void:
	var removed_skills: Array[String] = []
	for i: int in range(_rows.size() - 1, -1, -1):
		var row: Dictionary = _rows[i]
		if String(row.get("kind", "")) != kind or String(row.get("key", "")) != key:
			continue
		var row_sid: String = String(row.get("origin_id", ""))
		if sid != "~all~" and row_sid != sid:
			continue
		if _is_mandatory_choice(row) or (bool(row.get("automatic", false)) and not row_sid.is_empty()):
			continue
		if kind == "skill":
			removed_skills.append(row_sid + "|" + key)
		_rows.remove_at(i)
	_remove_orphaned_manual_expertise(removed_skills)
	_publish()


func _delete_manual_group(indices: Array) -> void:
	# Older callers can still delete their explicitly selected, nonmandatory
	# rows; mandatory catalog grants never disappear from one origin.
	var removed_skills: Array[String] = []
	for i: int in range(_rows.size() - 1, -1, -1):
		if i not in indices:
			continue
		var row: Dictionary = _rows[i]
		if _is_mandatory_choice(row):
			continue
		var sid: String = String(row.get("origin_id", ""))
		if bool(row.get("automatic", false)) and not sid.is_empty():
			continue
		if String(row.get("kind", "")) == "skill":
			removed_skills.append(sid + "|" + String(row.get("key", "")))
		_rows.remove_at(i)
	_remove_orphaned_manual_expertise(removed_skills)
	_publish()


func _remove_orphaned_manual_expertise(removed_skills: Array[String]) -> void:
	for pair: String in removed_skills:
		var still_granted := false
		for row: Dictionary in _rows:
			if String(row.get("kind", "")) == "skill" and String(row.get("origin_id", "")) + "|" + String(row.get("key", "")) == pair:
				still_granted = true
				break
		if still_granted:
			continue
		for i: int in range(_rows.size() - 1, -1, -1):
			var row: Dictionary = _rows[i]
			if String(row.get("kind", "")) == "expertise" and not bool(row.get("automatic", false)) and String(row.get("origin_id", "")) + "|" + String(row.get("key", "")) == pair:
				_rows.remove_at(i)


func _group_enabled(indices: Array) -> bool:
	var enabled: Dictionary = _enabled_map()
	for index: Variant in indices:
		var row: Dictionary = _rows[int(index)]
		if not bool(row.get("disabled", false)) and bool(enabled.get(String(row.get("origin_id", "")), true)):
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
		if _is_mandatory_choice(row):
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
	if _is_mandatory_choice(_rows[index]):
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


func _catalog_entries_for_kind(kind: String) -> Array[Dictionary]:
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
	return items


func _catalog_entries() -> Array[Dictionary]:
	var kind: String = String(GROUPS[_kind_picker.selected].get("kind", "skill"))
	var items: Array[Dictionary] = _catalog_entries_for_kind(kind)
	if kind == "skill":
		var allowed: Array[String] = Rules.restricted_choices(_selected_source_record(), kind)
		if not allowed.is_empty():
			var restricted: Array[Dictionary] = []
			for item: Dictionary in items:
				if String(item.get("key", "")) in allowed:
					restricted.append(item)
			return restricted
	return items



func _choice_options_for_requirement(requirement: Dictionary) -> Array[Dictionary]:
	var kind: String = String(requirement.get("kind", ""))
	var data: Dictionary = requirement.get("data", {})
	var result: Array[Dictionary] = []
	var used: Dictionary = {}
	for entry: Dictionary in _catalog_entries_for_kind(kind):
		var key: String = String(entry.get("key", ""))
		if key.is_empty() or used.has(key):
			continue
		# Use each requirement's structured pool, not the union from all
		# the source's choices. This also handles "any" and typed tools.
		if Rules.grant_matches([data], kind, key) != 1:
			continue
		used[key] = true
		result.append(entry)
	return result


func _has_active_source_grant(sid: String, kind: String, key: String) -> bool:
	for row: Dictionary in _rows:
		if String(row.get("origin_id", "")) == sid and String(row.get("kind", "")) == kind and String(row.get("key", "")) == key:
			if not bool(row.get("disabled", false)):
				return true
	return false


func _open_missing_choices(sid: String) -> void:
	_choice_source_id = sid
	_selected_id = sid
	_add_competence_button.disabled = false
	_refresh_origins()
	_refresh_competences()
	_refresh_proficiency_picker()
	for node: Node in _choice_contents.get_children():
		_choice_contents.remove_child(node)
		node.queue_free()
	_choice_groups.clear()
	var source: Dictionary = _selected_source_record()
	if source.is_empty():
		return
	_choice_dialog.title = "Completa · " + String(source.get("name", "Origine"))
	var intro := Label.new()
	intro.text = "Seleziona le competenze concesse dall'origine. Puoi completare le scelte anche in più volte."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_contents.add_child(intro)
	for requirement: Dictionary in source.get("requirements", []):
		var kind: String = String(requirement.get("kind", ""))
		var count: int = maxi(1, int(requirement.get("count", 1)))
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 16)
		_choice_contents.add_child(title)
		var group: Dictionary = {"kind": kind, "count": count, "title": title, "boxes": []}
		var options: Array[Dictionary] = _choice_options_for_requirement(requirement)
		if options.is_empty():
			title.text = "%s · scegli %d" % [kind.capitalize(), count]
			var note := Label.new()
			note.text = "Elenco non disponibile nei dati strutturati. Usa + Competenza per un'aggiunta manuale."
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_choice_contents.add_child(note)
			continue
		for option: Dictionary in options:
			var key: String = String(option.get("key", ""))
			var check := CheckBox.new()
			check.text = String(option.get("label", key))
			check.button_pressed = _has_active_source_grant(sid, kind, key)
			check.tooltip_text = "Competenza: " + key
			_choice_contents.add_child(check)
			(group["boxes"] as Array).append({"key": key, "check": check})
			check.toggled.connect(_on_choice_check_toggled.bind(group))
		_choice_groups.append(group)
		_refresh_choice_limit(group)
	DialogLayout.popup(_choice_dialog, Vector2i(540, 630), 0.90)


func _on_choice_check_toggled(_checked: bool, group: Dictionary) -> void:
	_refresh_choice_limit(group)


func _refresh_choice_limit(group: Dictionary) -> void:
	var chosen := 0
	for entry: Dictionary in group.get("boxes", []):
		if (entry.get("check") as CheckBox).button_pressed:
			chosen += 1
	var count: int = int(group.get("count", 1))
	(group.get("title") as Label).text = "%s · %d/%d scelte" % [String(group.get("kind", "")).capitalize(), chosen, count]
	for entry: Dictionary in group.get("boxes", []):
		var check: CheckBox = entry.get("check")
		check.disabled = chosen >= count and not check.button_pressed


func _apply_choice_dialog() -> void:
	if _choice_source_id.is_empty():
		return
	var offered: Dictionary = {}
	var chosen: Dictionary = {}
	for group: Dictionary in _choice_groups:
		var kind: String = String(group.get("kind", ""))
		for entry: Dictionary in group.get("boxes", []):
			var identity: String = kind + "|" + String(entry.get("key", ""))
			offered[identity] = true
			if (entry.get("check") as CheckBox).button_pressed:
				chosen[identity] = true
	var removed_skills: Array[String] = []
	for i: int in range(_rows.size() - 1, -1, -1):
		var row: Dictionary = _rows[i]
		if String(row.get("origin_id", "")) != _choice_source_id or bool(row.get("automatic", false)):
			continue
		var identity: String = String(row.get("kind", "")) + "|" + String(row.get("key", ""))
		if offered.has(identity) and not chosen.has(identity):
			if String(row.get("kind", "")) == "skill":
				removed_skills.append(_choice_source_id + "|" + String(row.get("key", "")))
			_rows.remove_at(i)
	for raw_identity: Variant in chosen.keys():
		var identity: String = String(raw_identity)
		var kind: String = identity.get_slice("|", 0)
		var key: String = identity.substr(kind.length() + 1)
		var existing := false
		for row: Dictionary in _rows:
			if String(row.get("origin_id", "")) == _choice_source_id and String(row.get("kind", "")) == kind and String(row.get("key", "")) == key:
				row["disabled"] = false
				existing = true
		if not existing:
			_rows.append({"kind": kind, "key": key, "origin_id": _choice_source_id,
				"origin_name": _origin_display(_choice_source_id), "disabled": false})
	_remove_orphaned_manual_expertise(removed_skills)
	_choice_source_id = ""
	_publish()


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
