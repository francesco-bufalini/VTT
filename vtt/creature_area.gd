extends Node

# Reusable creature sheet for players and GMs. No role-specific permissions.
const Archive = preload("res://vtt/creature_archive.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const Bestiary = preload("res://vtt/bestiary_5etools_client.gd")
const PlayerReference = preload("res://vtt/player_reference_catalog.gd")
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")

var board_root: Node3D
var _archive
var _client: Node
var _records: Array[Dictionary] = []
var _selected_id := ""
var _selected_kind := ""
var _catalog: Array[Dictionary] = []
var _filtered_catalog: Array[Dictionary] = []
var _loading := false

var _panel: PanelContainer
var _status: Label
var _creature_list: ItemList
var _catalog_list: ItemList
var _catalog_filter: LineEdit
var _name: LineEdit
var _hp: SpinBox
var _max_hp: SpinBox
var _ac: SpinBox
var _ability_spins: Dictionary = {}
var _species: OptionButton
var _class_name: OptionButton
var _multiclass_rows: VBoxContainer
var _multiclass_controls: Array[Dictionary] = []
var _level: HSlider
var _level_label: Label
var _feats: TextEdit
var _default_miniature: LineEdit
var _current_miniature: Label
var _reference: RichTextLabel
var _trackers: VBoxContainer
var _owner_target: LineEdit
var _import_dialog: AcceptDialog
var _import_text: TextEdit


func setup(root: Node3D) -> void:
	board_root = root
	_archive = Archive.new()
	_archive.setup(get_node_or_null("/root/CampaignManager"))
	_client = Bestiary.new()
	_client.name = "CreatureBestiary"
	add_child(_client)
	_client.setup()
	_client.catalog_ready.connect(_on_catalog_ready)
	_client.creature_ready.connect(_on_monster_received)
	_client.catalog_failed.connect(func(message: String) -> void: _set_status(message))
	_client.creature_failed.connect(
		func(_key: String, message: String) -> void: _set_status(message)
	)
	_build_ui()
	_build_transfer_dialog()
	_reload()
	if DisplayServer.get_name() != "headless":
		_client.load_catalog()


func toggle_panel() -> void:
	if _panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	_reload()
	_panel.show()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")


func hide_panel() -> void:
	_save()
	_panel.hide()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not _import_dialog.visible:
			hide_panel()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CreatureSheet"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 26
	_panel.offset_top = 52
	_panel.offset_right = -26
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	(board_root.get_node("UI") as CanvasLayer).add_child(_panel)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_add_label(header, "Creature · archivio personale 5e.tools")
	var owned_id := Button.new()
	owned_id.text = "Copia il mio ID"
	owned_id.pressed.connect(
		func() -> void:
			DisplayServer.clipboard_set(Owner.local_id())
			_set_status("ID copiato: condividilo solo con chi deve cederti una creatura.")
	)
	header.add_child(owned_id)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(hide_panel)
	header.add_child(close)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 300
	outer.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	columns.add_child(left)
	_add_label(left, "Le mie creature (indipendenti dalla scena)")
	_creature_list = ItemList.new()
	_creature_list.custom_minimum_size.y = 210
	_creature_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creature_list.item_selected.connect(_on_selected)
	left.add_child(_creature_list)

	var add_character := Button.new()
	add_character.text = "+ Personaggio / creatura con classi"
	add_character.pressed.connect(_create_character)
	left.add_child(add_character)

	_add_label(left, "Aggiungi dal bestiario")
	_catalog_filter = LineEdit.new()
	_catalog_filter.placeholder_text = "Cerca nome o fonte (5e.tools)"
	_catalog_filter.text_changed.connect(_filter_catalog)
	left.add_child(_catalog_filter)
	_catalog_list = ItemList.new()
	_catalog_list.custom_minimum_size.y = 170
	_catalog_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_list.item_activated.connect(_request_monster)
	left.add_child(_catalog_list)
	var add_monster := Button.new()
	add_monster.text = "+ Creatura del bestiario"
	add_monster.pressed.connect(_request_selected_monster)
	left.add_child(add_monster)

	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.split_offset = 330
	columns.add_child(right)

	var edit_scroll := ScrollContainer.new()
	edit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(edit_scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.add_child(form)

	var fields := GridContainer.new()
	fields.columns = 4
	form.add_child(fields)
	_add_label(fields, "Nome")
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_v: String) -> void: _save())
	fields.add_child(_name)
	_add_label(fields, "CA")
	_ac = _spin(fields, 0, 99)
	_add_label(fields, "PF attuali")
	_hp = _spin(fields, -999, 99999)
	_add_label(fields, "PF massimi")
	_max_hp = _spin(fields, 0, 99999)

	var abilities_row := GridContainer.new()
	abilities_row.columns = 6
	form.add_child(abilities_row)
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var cell := VBoxContainer.new()
		abilities_row.add_child(cell)
		_add_label(cell, ability.to_upper())
		var spin := _spin(cell, 1, 30)
		_ability_spins[ability] = spin

	var classes_row := GridContainer.new()
	classes_row.columns = 4
	form.add_child(classes_row)
	_add_label(classes_row, "Razza / Specie")
	_species = _reference_option(classes_row, PlayerReference.SPECIES)
	_add_label(classes_row, "Classe")
	_class_name = _reference_option(classes_row, PlayerReference.CLASSES)
	var multiclass_header := HBoxContainer.new()
	form.add_child(multiclass_header)
	_add_label(multiclass_header, "Classi aggiuntive (multiclasse)")
	var add_class := Button.new()
	add_class.text = "+ Classe"
	add_class.pressed.connect(_add_multiclass_row)
	multiclass_header.add_child(add_class)
	_multiclass_rows = VBoxContainer.new()
	form.add_child(_multiclass_rows)

	var level_row := HBoxContainer.new()
	form.add_child(level_row)
	_add_label(level_row, "Livello")
	_level = HSlider.new()
	_level.min_value = 1
	_level.max_value = 20
	_level.step = 1
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level.value_changed.connect(_on_level_changed)
	level_row.add_child(_level)
	_level_label = Label.new()
	level_row.add_child(_level_label)

	_add_label(form, "Talenti e scelte manuali (personalizzabili)")
	_feats = TextEdit.new()
	_feats.custom_minimum_size = Vector2(0, 56)
	_feats.text_changed.connect(_save)
	form.add_child(_feats)

	var miniature_row := HBoxContainer.new()
	form.add_child(miniature_row)
	_add_label(miniature_row, "Miniatura base")
	_default_miniature = LineEdit.new()
	_default_miniature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_default_miniature.placeholder_text = "ID miniatura catalogo"
	_default_miniature.text_changed.connect(func(_v: String) -> void: _save())
	miniature_row.add_child(_default_miniature)
	_current_miniature = Label.new()
	_current_miniature.text = "Aspetto attuale: nessun token"
	form.add_child(_current_miniature)

	var tracker_heading := HBoxContainer.new()
	form.add_child(tracker_heading)
	_add_label(tracker_heading, "Tracker e risorse")
	for kind: String in ["turn", "short_rest", "long_rest"]:
		var button := Button.new()
		button.text = {
			"turn": "Nuovo turno", "short_rest": "Riposo breve",
			"long_rest": "Riposo lungo"
		}[kind]
		button.pressed.connect(_reset_resources.bind(kind))
		tracker_heading.add_child(button)
	var new_tracker := Button.new()
	new_tracker.text = "+ Risorsa"
	new_tracker.pressed.connect(_add_tracker)
	tracker_heading.add_child(new_tracker)
	_trackers = VBoxContainer.new()
	form.add_child(_trackers)

	var actions := HBoxContainer.new()
	form.add_child(actions)
	var link_token := Button.new()
	link_token.text = "Associa a token selezionato"
	link_token.pressed.connect(_link_selected_token)
	actions.add_child(link_token)
	_owner_target = LineEdit.new()
	_owner_target.placeholder_text = "ID controllore destinatario"
	_owner_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_owner_target)
	var transfer := Button.new()
	transfer.text = "Cedi controllo"
	transfer.pressed.connect(_transfer)
	actions.add_child(transfer)
	var import_button := Button.new()
	import_button.text = "Ricevi creatura…"
	import_button.pressed.connect(_show_import)
	actions.add_child(import_button)

	_reference = RichTextLabel.new()
	_reference.bbcode_enabled = false
	_reference.selection_enabled = true
	_reference.scroll_active = true
	_reference.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_reference)


func _build_transfer_dialog() -> void:
	_import_dialog = AcceptDialog.new()
	_import_dialog.title = "Ricevi il controllo di una creatura"
	_import_dialog.ok_button_text = "Importa"
	_import_dialog.confirmed.connect(_import)
	add_child(_import_dialog)
	_import_text = TextEdit.new()
	_import_text.custom_minimum_size = Vector2(620, 220)
	_import_text.placeholder_text = "Incolla qui il codice JSON ricevuto dal precedente controllore."
	_import_dialog.add_child(_import_text)


func _add_label(parent: Node, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


func _spin(parent: Node, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.custom_minimum_size = Vector2(84, 30)
	spin.value_changed.connect(func(_v: float) -> void: _save())
	parent.add_child(spin)
	return spin


func _reference_option(parent: Node, choices: Array[Dictionary]) -> OptionButton:
	var select := OptionButton.new()
	select.add_item("—")
	select.set_item_metadata(0, {})
	for item: Dictionary in choices:
		select.add_item(PlayerReference.display_name(item))
		select.set_item_metadata(select.item_count - 1, item.duplicate(true))
	select.item_selected.connect(func(_i: int) -> void: _save())
	parent.add_child(select)
	return select


func _add_multiclass_row(
	class_name: String = "", class_level: int = 1
) -> void:
	var row := HBoxContainer.new()
	_multiclass_rows.add_child(row)
	var selector := _reference_option(row, PlayerReference.CLASSES)
	_select_reference(selector, class_name)
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = 20
	level.step = 1
	level.value = clampi(class_level, 1, 20)
	level.custom_minimum_size = Vector2(82, 30)
	level.value_changed.connect(func(_v: float) -> void: _save())
	row.add_child(level)
	var remove := Button.new()
	remove.text = "×"
	row.add_child(remove)
	var definition := {"row": row, "selector": selector, "level": level}
	_multiclass_controls.append(definition)
	remove.pressed.connect(
		func() -> void:
			_multiclass_controls.erase(definition)
			_multiclass_rows.remove_child(row)
			row.queue_free()
			_save()
	)
	_save()


func _clear_multiclass() -> void:
	for definition: Dictionary in _multiclass_controls:
		var row: HBoxContainer = definition["row"]
		_multiclass_rows.remove_child(row)
		row.queue_free()
	_multiclass_controls.clear()


func _select_reference(option: OptionButton, name: String) -> void:
	option.select(0)
	for i: int in range(1, option.item_count):
		var row: Dictionary = option.get_item_metadata(i)
		if String(row.get("name", "")).nocasecmp_to(name) == 0:
			option.select(i)
			return


func _reference_entry(option: OptionButton) -> Dictionary:
	var value: Variant = option.get_item_metadata(option.selected)
	return value as Dictionary if value is Dictionary else {}


func _reload() -> void:
	_records = _archive.list_owned()
	_creature_list.clear()
	var selected_index := -1
	for i: int in range(_records.size()):
		var item := _records[i]
		var kind := String(item.get("kind", ""))
		var icon := "◇" if kind == "monster" else "♙"
		_creature_list.add_item("%s %s" % [icon, String(item.get("name", ""))])
		_creature_list.set_item_metadata(i, String(item.get("id", "")))
		if (
			String(item.get("id", "")) == _selected_id
			and kind == _selected_kind
		):
			selected_index = i
	if selected_index < 0 and not _records.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_creature_list.select(selected_index)
		_on_selected(selected_index)
	else:
		_selected_id = ""
		_selected_kind = ""
		_loading = true
		_reference.text = "Crea una creatura o selezionala dall'archivio."
		_loading = false


func _current() -> Dictionary:
	for item: Dictionary in _records:
		if (
			String(item.get("id", "")) == _selected_id
			and String(item.get("kind", "")) == _selected_kind
		):
			return item.duplicate(true)
	return {}


func _on_selected(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	var record := _records[index]
	_selected_id = String(record.get("id", ""))
	_selected_kind = String(record.get("kind", ""))
	_load_form(record)


func _load_form(record: Dictionary) -> void:
	_loading = true
	_name.text = String(record.get("name", ""))
	_hp.value = int(record.get("current_hp", 1))
	_max_hp.value = int(record.get("max_hp", 1))
	_ac.value = int(record.get("armor_class", 10))
	var abilities_value: Variant = record.get("abilities", {})
	var abilities: Dictionary = (
		abilities_value as Dictionary if abilities_value is Dictionary else {}
	)
	for ability: String in _ability_spins.keys():
		(_ability_spins[ability] as SpinBox).value = int(abilities.get(ability, 10))
	_select_reference(_species, String(record.get("species", "")))
	_select_reference(_class_name, String(record.get("class", "")))
	_clear_multiclass()
	var classes_value: Variant = record.get("classes", [])
	if classes_value is Array:
		for i: int in range(1, (classes_value as Array).size()):
			var class_value: Variant = (classes_value as Array)[i]
			if class_value is Dictionary:
				_add_multiclass_row(
					String(class_value.get("name", "")),
					int(class_value.get("level", 1))
				)
	_level.value = clampi(int(record.get("level", 1)), 1, 20)
	_level_label.text = str(int(_level.value))
	_feats.text = String(record.get("feats", ""))
	_default_miniature.text = String(record.get("default_miniature_id", ""))
	var is_character := String(record.get("kind", "")) == "character"
	_species.disabled = not is_character
	_class_name.disabled = not is_character
	_level.editable = is_character
	var derived: Array[Dictionary] = (
		Rules.character_trackers(record) if is_character else
		Rules.monster_trackers(record.get("stat_block", {}))
	)
	record["trackers"] = Rules.reconcile_trackers(record.get("trackers", []), derived)
	_replace_current_record(record)
	_refresh_trackers(record)
	_refresh_reference(record)
	_refresh_current_miniature(record)
	_loading = false


func _on_level_changed(value: float) -> void:
	_level_label.text = str(int(value))
	_save()


func _replace_current_record(record: Dictionary) -> void:
	for i: int in range(_records.size()):
		if (
			String(_records[i].get("id", "")) == _selected_id
			and String(_records[i].get("kind", "")) == _selected_kind
		):
			_records[i] = record
			break


func _save() -> void:
	if _loading:
		return
	var record := _current()
	if record.is_empty():
		return
	record["name"] = _name.text.strip_edges()
	record["current_hp"] = int(_hp.value)
	record["max_hp"] = int(_max_hp.value)
	record["armor_class"] = int(_ac.value)
	var abilities: Dictionary = {}
	for ability: String in _ability_spins.keys():
		abilities[ability] = int((_ability_spins[ability] as SpinBox).value)
	record["abilities"] = abilities
	record["default_miniature_id"] = _default_miniature.text.strip_edges()
	if String(record.get("kind", "")) == "character":
		var species := _reference_entry(_species)
		var class_ref := _reference_entry(_class_name)
		record["species"] = String(species.get("name", ""))
		record["species_source"] = String(species.get("source", ""))
		record["class"] = String(class_ref.get("name", ""))
		record["class_source"] = String(class_ref.get("source", ""))
		record["level"] = int(_level.value)
		var classes: Array[Dictionary] = []
		var extras_level := 0
		for definition: Dictionary in _multiclass_controls:
			var secondary_option: OptionButton = definition["selector"]
			var extra_ref := _reference_entry(secondary_option)
			var extra_name := String(extra_ref.get("name", ""))
			if extra_name.is_empty():
				continue
			var extra_level := int((definition["level"] as SpinBox).value)
			extras_level += extra_level
			classes.append({
				"name": extra_name,
				"source": String(extra_ref.get("source", "")),
				"level": extra_level
			})
		var primary_level := maxi(1, int(_level.value) - extras_level)
		if not String(record["class"]).is_empty():
			classes.push_front({
				"name": record["class"],
				"source": record["class_source"],
				"level": primary_level
			})
		record["classes"] = classes
		record["feats"] = _feats.text
	var derived: Array[Dictionary] = (
		Rules.character_trackers(record)
		if String(record.get("kind", "")) == "character"
		else Rules.monster_trackers(record.get("stat_block", {}))
	)
	record["trackers"] = Rules.reconcile_trackers(record.get("trackers", []), derived)
	var error: Error = _archive.save(record)
	if error != OK:
		_set_status("Salvataggio non riuscito: %s" % error_string(error))
		return
	_replace_current_record(record)
	_sync_token_health(record)
	# A visible sheet follows current level and race/class immediately.
	_refresh_reference(record)
	_refresh_trackers(record)


func _refresh_trackers(record: Dictionary) -> void:
	for child: Node in _trackers.get_children():
		_trackers.remove_child(child)
		child.queue_free()
	var rows: Variant = record.get("trackers", [])
	if not rows is Array:
		return
	for raw: Variant in rows as Array:
		if not raw is Dictionary:
			continue
		var resource: Dictionary = raw as Dictionary
		var resource_id := String(resource.get("id", ""))
		var row := HBoxContainer.new()
		_trackers.add_child(row)
		var name := LineEdit.new()
		name.text = String(resource.get("label", "Risorsa"))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_submitted.connect(
			func(new_name: String) -> void:
				_update_tracker(resource_id, "label", new_name)
		)
		name.focus_exited.connect(
			func() -> void:
				_update_tracker(resource_id, "label", name.text)
		)
		row.add_child(name)
		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = 9999
		count.value = int(resource.get("current", 0))
		count.value_changed.connect(
			func(new_value: float) -> void:
				_update_tracker(resource_id, "current", int(new_value))
		)
		row.add_child(count)
		_add_label(row, "/")
		var maximum := SpinBox.new()
		maximum.min_value = 0
		maximum.max_value = 9999
		maximum.value = int(resource.get("maximum", 0))
		maximum.value_changed.connect(
			func(new_value: float) -> void:
				_update_tracker(resource_id, "maximum", int(new_value))
		)
		row.add_child(maximum)
		if String(resource.get("kind", "")) == "recharge":
			_add_label(row, "R%d+" % int(resource.get("recharge_min", 0)))
		elif String(resource.get("id", "")).begins_with("custom_"):
			var remove := Button.new()
			remove.text = "×"
			remove.pressed.connect(_remove_tracker.bind(resource_id))
			row.add_child(remove)


func _update_tracker(id: String, field: String, value: Variant) -> void:
	var record := _current()
	if record.is_empty():
		return
	var rows: Array = record.get("trackers", [])
	for i: int in range(rows.size()):
		if not rows[i] is Dictionary:
			continue
		var item: Dictionary = rows[i]
		if String(item.get("id", "")) != id:
			continue
		item[field] = value
		rows[i] = Rules.normalize_tracker(item)
		break
	record["trackers"] = rows
	if _archive.save(record) == OK:
		_replace_current_record(record)
		if field == "maximum":
			_refresh_trackers(record)


func _add_tracker() -> void:
	var record := _current()
	if record.is_empty():
		return
	var rows: Array = record.get("trackers", [])
	rows.append(Rules.default_tracker(
		"custom_%d" % Time.get_ticks_usec(), "Risorsa personalizzata",
		1, "long_rest"
	))
	record["trackers"] = rows
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_refresh_trackers(record)


func _remove_tracker(id: String) -> void:
	var record := _current()
	if record.is_empty() or not id.begins_with("custom_"):
		return
	var rows: Array = []
	for raw: Variant in record.get("trackers", []):
		if raw is Dictionary and String(raw.get("id", "")) != id:
			rows.append(raw)
	record["trackers"] = rows
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_refresh_trackers(record)


func _reset_resources(kind: String) -> void:
	var record := _current()
	if record.is_empty():
		return
	record["trackers"] = Rules.apply_reset(record.get("trackers", []), kind)
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_refresh_trackers(record)


func _refresh_reference(record: Dictionary) -> void:
	if String(record.get("kind", "")) == "monster":
		var stat: Dictionary = record.get("stat_block", {})
		var lines: PackedStringArray = [
			String(stat.get("name", record.get("name", ""))),
			"Fonte: %s" % String(stat.get("source", "5e.tools")),
			"GS: %s" % str(stat.get("cr", "—"))
		]
		for section: String in [
			"trait", "spellcasting", "action", "bonus", "reaction",
			"legendary", "mythic", "lairActions"
		]:
			var entries: Variant = stat.get(section, [])
			if not entries is Array:
				continue
			lines.append("")
			lines.append(section.to_upper())
			for raw: Variant in entries as Array:
				if raw is Dictionary:
					var item: Dictionary = raw as Dictionary
					lines.append("• " + String(item.get("name", section)))
					lines.append(_text_entries(item.get("entries", [])))
				elif raw is String:
					lines.append(String(raw))
		_reference.text = "\n".join(lines)
		return

	var class_name := String(record.get("class", ""))
	var species := String(record.get("species", ""))
	var max_level := clampi(int(_level.value), 1, 20)
	var parts: PackedStringArray = [
		"%s · %s · Livello %d" % [
			String(record.get("name", "")), species, max_level
		], "", "PRIVILEGI DI CLASSE (5e.tools)"
	]

	var class_rows: Array = record.get("classes", [])
	if class_rows.is_empty() and not class_name.is_empty():
		class_rows = [{"name": class_name, "level": max_level}]
	for class_value: Variant in class_rows:
		if not class_value is Dictionary:
			continue
		var class_data: Dictionary = class_value as Dictionary
		var this_name := String(class_data.get("name", ""))
		var this_level := mini(
			max_level, int(class_data.get("level", max_level))
		)
		parts.append("")
		parts.append("%s (livello %d)" % [this_name, this_level])
		for feature: Dictionary in Player5eTools.entries("class_features"):
			if String(feature.get("class_name", "")).nocasecmp_to(this_name) != 0:
				continue
			var level := int(feature.get("level", 0))
			if level > this_level:
				continue
			parts.append("Lv %d · %s" % [level, Player5eTools.display_label(feature)])
			var description := Player5eTools.description_text_from_raw_item(feature)
			if not description.is_empty():
				parts.append(description)
	parts.append("")
	parts.append("TRATTI DELLA SPECIE (5e.tools)")
	for feature: Dictionary in Player5eTools.entries("species_traits"):
		if String(feature.get("species", "")).nocasecmp_to(species) == 0:
			parts.append(Player5eTools.display_label(feature))
	_reference.text = "\n".join(parts)


func _text_entries(value: Variant) -> String:
	var parts: PackedStringArray = []
	if value is String:
		return String(value)
	if value is Array:
		for raw: Variant in value as Array:
			if raw is String:
				parts.append(String(raw))
			elif raw is Dictionary:
				var entry: Dictionary = raw as Dictionary
				if entry.has("name"):
					parts.append(String(entry.get("name", "")))
				parts.append(_text_entries(entry.get("entries", [])))
	return "\n".join(parts)


func _filter_catalog(query: String) -> void:
	_catalog_list.clear()
	_filtered_catalog.clear()
	var text_query := query.strip_edges().to_lower()
	if text_query.length() < 2:
		return
	for entry: Dictionary in _catalog:
		var label := "%s %s" % [
			String(entry.get("name", "")), String(entry.get("source", ""))
		]
		if text_query not in label.to_lower():
			continue
		_filtered_catalog.append(entry)
		_catalog_list.add_item(label)
		if _filtered_catalog.size() >= 80:
			break


func _on_catalog_ready(entries: Array[Dictionary]) -> void:
	_catalog = entries
	_filter_catalog(_catalog_filter.text)
	_set_status("%d voci del bestiario disponibili" % entries.size())


func _request_selected_monster() -> void:
	var chosen := _catalog_list.get_selected_items()
	if not chosen.is_empty():
		_request_monster(chosen[0])


func _request_monster(index: int) -> void:
	if index < 0 or index >= _filtered_catalog.size():
		return
	var entry := _filtered_catalog[index]
	_client.request_creature(
		String(entry.get("name", "")), String(entry.get("source", "")),
		"new_creature_%d" % Time.get_ticks_usec()
	)
	_set_status("Caricamento creatura da 5e.tools…")


func _on_monster_received(_key: String, stat: Dictionary) -> void:
	var record: Dictionary = _archive.create_monster(stat)
	record["kind"] = "monster"
	if _archive.save(record) != OK:
		_set_status("Impossibile salvare la creatura.")
		return
	_selected_id = String(record.get("id", ""))
	_selected_kind = "monster"
	_reload()
	_set_status("Creatura importata; ora ne controlli la scheda.")


func _create_character() -> void:
	var record: Dictionary = _archive.create_character()
	record["kind"] = "character"
	if _archive.save(record) != OK:
		_set_status("Impossibile creare il personaggio.")
		return
	_selected_id = String(record.get("id", ""))
	_selected_kind = "character"
	_reload()


func _link_selected_token() -> void:
	var selected_value: Variant = board_root.call(
		"get_selected_tokens_for_player_area"
	)
	if not selected_value is Array or (selected_value as Array).size() != 1:
		_set_status("Seleziona un solo token nella scena.")
		return
	var record := _current()
	if record.is_empty():
		return
	var token: Node3D = (selected_value as Array)[0] as Node3D
	if token == null:
		return
	var creature_id := String(record.get("id", ""))
	token.set_meta("creature_id", creature_id)
	token.set_meta("creature_owner_id", Owner.local_id())
	token.set_meta("default_miniature_id", String(record.get("default_miniature_id", "")))
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null:
		record["linked_token_sync_id"] = String(
			sync.call("get_sync_id_for_node", token)
		)
	record["linked_token_name"] = String(token.call("get_display_name"))
	if String(record.get("kind", "")) == "character":
		token.set_meta("player_character_id", creature_id)
		token.set_meta("player_character_name", String(record.get("name", "")))
	else:
		token.set_meta("master_creature_id", creature_id)
		token.set_meta("master_creature_name", String(record.get("name", "")))
		token.set_meta("master_creature_side", String(record.get("side", "ally")))
	if _archive.save(record) == OK:
		_replace_current_record(record)
		_sync_token_health(record)
		_refresh_current_miniature(record)
		_set_status("Creatura associata alla miniatura senza modificarne l'aspetto.")


func _refresh_current_miniature(record: Dictionary) -> void:
	var token := _find_linked_token(record)
	if token == null:
		_current_miniature.text = "Aspetto attuale: nessun token associato"
	elif token.has_method("get_visual_asset_path"):
		_current_miniature.text = "Aspetto attuale: " + String(
			token.call("get_visual_asset_path")
		)


func _find_linked_token(record: Dictionary) -> Node3D:
	var token_id := String(record.get("linked_token_sync_id", ""))
	if token_id.is_empty():
		return null
	var sync: Node = board_root.get("board_sync") as Node
	if sync == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is Node3D or not board_root.is_ancestor_of(node):
			continue
		if String(sync.call("get_sync_id_for_node", node)) == token_id:
			return node as Node3D
	return null


func _sync_token_health(record: Dictionary) -> void:
	var token := _find_linked_token(record)
	if token == null:
		return
	var method := (
		"set_player_hit_points"
		if String(record.get("kind", "")) == "character"
		else "set_master_hit_points"
	)
	if token.has_method(method):
		token.call(
			method, int(record.get("current_hp", 1)),
			int(record.get("max_hp", 1))
		)


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in _records:
		var id := String(record.get("linked_token_sync_id", ""))
		var maximum := int(record.get("max_hp", 0))
		if id.is_empty() or maximum <= 0:
			continue
		rows.append({
			"token_id": id,
			"percent": clampf(
				float(record.get("current_hp", 0)) / float(maximum) * 100.0,
				0.0, 100.0
			)
		})
	return rows


func _transfer() -> void:
	var record := _current()
	if record.is_empty():
		return
	var package: Dictionary = _archive.relinquish(
		record, _owner_target.text
	)
	if package.is_empty():
		_set_status("ID non valido o cessione non salvata.")
		return
	DisplayServer.clipboard_set(JSON.stringify(package))
	_selected_id = ""
	_selected_kind = ""
	_reload()
	_set_status(
		"Codice di cessione copiato. Invia il testo al nuovo controllore; "
		+ "la creatura non appare più nel tuo archivio."
	)


func _show_import() -> void:
	_import_text.clear()
	_import_dialog.popup_centered_clamped(Vector2i(720, 340), 0.9)


func _import() -> void:
	var parsed: Variant = JSON.parse_string(_import_text.text)
	if not parsed is Dictionary:
		_set_status("Codice di trasferimento non valido.")
		return
	var error: Error = _archive.import_transfer(parsed as Dictionary)
	if error != OK:
		_set_status(
			"Importazione non riuscita: ID di destinazione errato o codice non valido."
		)
		return
	var creature: Dictionary = (parsed as Dictionary).get("creature", {})
	_selected_id = String(creature.get("id", ""))
	_selected_kind = String(creature.get("kind", ""))
	_reload()
	_set_status("Ora sei il controllore di questa creatura.")


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
