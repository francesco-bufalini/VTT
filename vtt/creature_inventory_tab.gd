extends VBoxContainer

# Private creature inventory. These are catalog references, not scene items:
# placing or deleting physical objects on the board never changes a sheet.
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const DocumentsTab = preload("res://vtt/creature_documents_tab.gd")
const ItemImagePreview = preload("res://vtt/item_image_preview.gd")

var _on_change: Callable
var _on_status: Callable
var _catalog: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _inventory: Array[Dictionary] = []
var _loading: bool = false

var _category_filter: OptionButton
var _equip_main: Button
var _equip_off: Button
var _unequip: Button
var _search: LineEdit
var _catalog_list: ItemList
var _inventory_list: ItemList
var _quantity: SpinBox
var _details: RichTextLabel
var _add_button: Button
var _remove_button: Button
var _documents_tab: Node
var _image_preview: AcceptDialog
var _document_change: Callable
var _send_document: Callable
var _peer_provider: Callable


func setup(on_change: Callable, on_status: Callable, on_document_change: Callable = Callable(), send_document: Callable = Callable(), peer_provider: Callable = Callable()) -> void:
	_on_change = on_change
	_on_status = on_status
	_document_change = on_document_change
	_send_document = send_document
	_peer_provider = peer_provider
	add_theme_constant_override("separation", 7)
	var heading := Label.new()
	heading.text = "Inventario · Catalogo e oggetti personalizzati"
	heading.add_theme_font_size_override("font_size", 17)
	add_child(heading)

	var categories_row := HBoxContainer.new()
	add_child(categories_row)
	var category_caption := Label.new()
	category_caption.text = "Categoria"
	categories_row.add_child(category_caption)
	_category_filter = OptionButton.new()
	for category_name: String in ["Tutti", "Armi", "Scudi", "Armature", "Strumenti", "Oggetti magici", "Altri oggetti"]:
		_category_filter.add_item(category_name)
	_category_filter.item_selected.connect(func(_index: int) -> void: _filter_catalog())
	_category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories_row.add_child(_category_filter)

	_search = LineEdit.new()
	_search.placeholder_text = "Cerca oggetto per nome, fonte o rarità…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _filter_catalog())
	add_child(_search)

	_catalog_list = ItemList.new()
	_catalog_list.custom_minimum_size.y = 145
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.item_selected.connect(_on_catalog_selected)
	_catalog_list.gui_input.connect(_on_image_click.bind(true))
	_catalog_list.item_activated.connect(func(_index: int) -> void: _add_selected())
	add_child(_catalog_list)
	_add_button = Button.new()
	_add_button.text = "+ Aggiungi all'inventario"
	_add_button.pressed.connect(_add_selected)
	add_child(_add_button)

	var inventory_title := Label.new()
	inventory_title.text = "Oggetti posseduti"
	inventory_title.add_theme_font_size_override("font_size", 15)
	add_child(inventory_title)
	_inventory_list = ItemList.new()
	_inventory_list.custom_minimum_size.y = 145
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_list.item_selected.connect(_on_inventory_selected)
	_inventory_list.gui_input.connect(_on_image_click.bind(false))
	add_child(_inventory_list)
	var equipment_row := HFlowContainer.new()
	equipment_row.add_theme_constant_override("h_separation", 6)
	equipment_row.add_theme_constant_override("v_separation", 3)
	add_child(equipment_row)
	_equip_main = Button.new()
	_equip_main.text = "⚔ Mano principale"
	_equip_main.pressed.connect(_equip_selected.bind("main"))
	equipment_row.add_child(_equip_main)
	_equip_off = Button.new()
	_equip_off.text = "🛡 Secondaria / Scudo"
	_equip_off.pressed.connect(_equip_selected.bind("off"))
	equipment_row.add_child(_equip_off)
	_unequip = Button.new()
	_unequip.text = "Rinfodera"
	_unequip.pressed.connect(_unequip_selected)
	equipment_row.add_child(_unequip)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	var qty_label := Label.new()
	qty_label.text = "Quantità"
	actions.add_child(qty_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 99999
	_quantity.step = 1
	_quantity.rounded = true
	_quantity.update_on_text_changed = true
	_quantity.custom_minimum_size.x = 95
	_quantity.value_changed.connect(_on_quantity_changed)
	actions.add_child(_quantity)
	_remove_button = Button.new()
	_remove_button.text = "Rimuovi"
	_remove_button.pressed.connect(_remove_selected)
	actions.add_child(_remove_button)

	_details = RichTextLabel.new()
	_details.custom_minimum_size.y = 160
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.scroll_active = true
	_details.selection_enabled = true
	add_child(_details)
	var inner_tabs := TabContainer.new()
	inner_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(inner_tabs)
	var objects_page := VBoxContainer.new()
	objects_page.name = "Oggetti"
	inner_tabs.add_child(objects_page)
	for child: Node in get_children():
		if child != inner_tabs:
			remove_child(child)
			objects_page.add_child(child)
	_documents_tab = DocumentsTab.new()
	_documents_tab.name = "Documenti"
	inner_tabs.add_child(_documents_tab)
	_documents_tab.call("setup", Callable(self, "_documents_changed"), _on_status, _send_document, _peer_provider)
	_image_preview = ItemImagePreview.new()
	add_child(_image_preview)
	_image_preview.call("setup")
	reload_catalog()
	_refresh_inventory()


func _documents_changed(documents: Array) -> void:
	if _document_change.is_valid():
		_document_change.call(documents)


func receive_document() -> void:
	if _documents_tab != null:
		_documents_tab.call("receive_document")


func reload_catalog() -> void:
	ItemRules.reset_catalog()
	_catalog = Player5eTools.entries("items")
	if _catalog_list != null:
		_filter_catalog()


func load_record(record: Dictionary) -> void:
	_loading = true
	_inventory.clear()
	var saved: Variant = record.get("inventory", [])
	if saved is Array:
		for raw: Variant in saved:
			if not raw is Dictionary:
				continue
			var item: Dictionary = raw as Dictionary
			var item_id: String = String(item.get("id", "")).strip_edges()
			var name: String = String(item.get("name", "")).strip_edges()
			if item_id.is_empty() or name.is_empty():
				continue
			_inventory.append({
				"id": item_id,
				"name": name,
				"source": String(item.get("source", "")),
				"quantity": clampi(int(item.get("quantity", 1)), 1, 99999),
				"equipped_slots": ItemRules.slots(item)
			})
	_sanitize_equipment()
	_refresh_inventory()
	_loading = false
	if _documents_tab != null:
		_documents_tab.call("load_record", record)


func _catalog_entry(item: Dictionary) -> Dictionary:
	for row: Dictionary in _catalog:
		if String(row.get("id", "")) == String(item.get("id", "")):
			return row
	return item


func _image_label(item: Dictionary, caption: String) -> String:
	return ("🖼  " if not ItemImagePreview.image_source(item).is_empty() else "") + caption


func _on_image_click(event: InputEvent, from_catalog: bool) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var list: ItemList = _catalog_list if from_catalog else _inventory_list
	var index: int = list.get_item_at_position(click.position, true)
	if index < 0:
		return
	var rect: Rect2 = list.get_item_rect(index)
	if click.position.x - rect.position.x > 38:
		return
	var item: Dictionary = {}
	if from_catalog and index < _filtered.size():
		item = _filtered[index]
	elif not from_catalog and index < _inventory.size():
		item = _catalog_entry(_inventory[index])
	if ItemImagePreview.image_source(item).is_empty():
		return
	_image_preview.call("preview", item)
	get_viewport().set_input_as_handled()


func _filter_catalog() -> void:
	if _catalog_list == null:
		return
	var query: String = _search.text.strip_edges().to_lower()
	var selected_category := _category_filter.get_item_text(_category_filter.selected)
	_filtered.clear()
	_catalog_list.clear()
	for item: Dictionary in _catalog:
		var name: String = String(item.get("name", ""))
		if name.is_empty():
			continue
		var haystack: String = ("%s %s %s" % [
			name, String(item.get("source", "")), String(item.get("rarity", ""))
		]).to_lower()
		if not query.is_empty() and query not in haystack:
			continue
		if selected_category != "Tutti" and ItemRules.category_name(item) != selected_category:
			continue
		_filtered.append(item)
		_catalog_list.add_item(_image_label(item, ItemRules.category_name(item) + " · " + Player5eTools.display_label(item)))
		if _filtered.size() >= 250:
			break
	_add_button.disabled = true


func _on_catalog_selected(index: int) -> void:
	_add_button.disabled = index < 0 or index >= _filtered.size()
	if index >= 0 and index < _filtered.size():
		_show_details(_filtered[index])


func _selected_inventory_index() -> int:
	if _inventory_list == null:
		return -1
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	return selected[0] if not selected.is_empty() else -1


func _on_inventory_selected(index: int) -> void:
	if index < 0 or index >= _inventory.size():
		return
	_quantity.set_value_no_signal(int(_inventory[index].get("quantity", 1)))
	_quantity.editable = true
	_remove_button.disabled = false
	_update_equip_buttons()
	var item_id: String = String(_inventory[index].get("id", ""))
	for catalog_item: Dictionary in _catalog:
		if String(catalog_item.get("id", "")) == item_id:
			_show_details(catalog_item)
			return
	_details.text = "%s\nFonte: %s\nVoce non installata nel catalogo locale." % [
		String(_inventory[index].get("name", "")),
		String(_inventory[index].get("source", ""))
	]


func _add_selected() -> void:
	var selected: PackedInt32Array = _catalog_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _filtered.size():
		return
	var source_item: Dictionary = _filtered[selected[0]]
	var item_id: String = String(source_item.get("id", "")).strip_edges()
	if item_id.is_empty():
		return
	for i: int in range(_inventory.size()):
		if String(_inventory[i].get("id", "")) == item_id:
			_inventory[i]["quantity"] = mini(99999, int(_inventory[i]["quantity"]) + 1)
			_refresh_inventory(i)
			_publish()
			return
	_inventory.append({
		"id": item_id,
		"name": String(source_item.get("name", "")),
		"source": String(source_item.get("source", "")),
		"quantity": 1,
		"equipped_slots": []
	})
	_refresh_inventory(_inventory.size() - 1)
	_publish()


func _on_quantity_changed(value: float) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory[index]["quantity"] = clampi(int(value), 1, 99999)
	_sanitize_equipment()
	_update_equip_buttons()
	# Keep the active editor and selection intact while typing multiple digits.
	_inventory_list.set_item_text(index, _image_label(_catalog_entry(_inventory[index]), _inventory_label(_inventory[index])))
	_publish()


func _remove_selected() -> void:
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory.remove_at(index)
	_refresh_inventory()
	_publish()


func _refresh_inventory(selected_index: int = -1) -> void:
	if _inventory_list == null:
		return
	var old_loading: bool = _loading
	_loading = true
	_inventory_list.clear()
	for item: Dictionary in _inventory:
		_inventory_list.add_item(_image_label(_catalog_entry(item), _inventory_label(item)))
	if selected_index >= 0 and selected_index < _inventory.size():
		_inventory_list.select(selected_index)
		_quantity.value = int(_inventory[selected_index].get("quantity", 1))
	_remove_button.disabled = selected_index < 0
	_quantity.editable = selected_index >= 0
	_update_equip_buttons()
	_loading = old_loading


func _inventory_label(item: Dictionary) -> String:
	var tags: PackedStringArray = []
	var slots: Array = ItemRules.slots(item)
	if "main" in slots:
		tags.append("⚔ Principale")
	if "off" in slots:
		tags.append("🛡 Secondaria")
	var equipment := (" [" + ", ".join(tags) + "]") if not tags.is_empty() else ""
	return "%d × %s%s · %s" % [item.get("quantity", 1), item.get("name", ""), equipment, item.get("source", "")]


func _show_details(item: Dictionary) -> void:
	var description: String = Player5eTools.description_text_from_raw_item(item)
	_details.text = ItemRules.category_name(item) + "\n" + Player5eTools.info_text(item, description)



func _sanitize_equipment() -> void:
	var used: Dictionary = {}
	for i: int in range(_inventory.size()):
		var row: Dictionary = _inventory[i]
		var entry: Dictionary = _catalog_entry(row) if not _catalog.is_empty() else ItemRules.entry_for(row)
		var valid: Array = []
		for raw_slot: Variant in ItemRules.slots(row):
			var slot := String(raw_slot)
			if slot not in ["main", "off"] or used.has(slot):
				continue
			if not ItemRules.valid_slot(entry, slot):
				continue
			if valid.size() >= int(row.get("quantity", 1)):
				continue
			valid.append(slot)
			used[slot] = true
		row["equipped_slots"] = valid
		_inventory[i] = row
	var main: Dictionary = ItemRules.occupying(_inventory, "main")
	if not main.is_empty() and ItemRules.is_two_handed(_catalog_entry(main)) and used.has("off"):
		for i: int in range(_inventory.size()):
			var row: Dictionary = _inventory[i]
			var slots: Array = ItemRules.slots(row)
			slots.erase("off")
			row["equipped_slots"] = slots
			_inventory[i] = row


func _update_equip_buttons() -> void:
	if _equip_main == null:
		return
	var index := _selected_inventory_index()
	var present := index >= 0 and index < _inventory.size()
	var entry: Dictionary = _catalog_entry(_inventory[index]) if present else {}
	_equip_main.disabled = not present or not ItemRules.valid_slot(entry, "main")
	_equip_off.disabled = not present or not ItemRules.valid_slot(entry, "off")
	_unequip.disabled = not present or ItemRules.slots(_inventory[index]).is_empty()


func _equip_selected(slot: String) -> void:
	var index := _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	var entry: Dictionary = _catalog_entry(_inventory[index])
	if not ItemRules.valid_slot(entry, slot):
		return
	for i: int in range(_inventory.size()):
		var item: Dictionary = _inventory[i]
		var item_slots: Array = ItemRules.slots(item)
		item_slots.erase(slot)
		if slot == "main" and ItemRules.is_two_handed(entry):
			item_slots.erase("off")
		if slot == "off" and ItemRules.is_two_handed(_catalog_entry(item)):
			item_slots.erase("main")
		item["equipped_slots"] = item_slots
		_inventory[i] = item
	var updated: Dictionary = _inventory[index]
	var updated_slots: Array = ItemRules.slots(updated)
	if int(updated.get("quantity", 1)) < 2 and not updated_slots.is_empty() and slot not in updated_slots:
		updated_slots.clear()
	if slot not in updated_slots:
		updated_slots.append(slot)
	updated["equipped_slots"] = updated_slots
	_inventory[index] = updated
	_sanitize_equipment()
	_refresh_inventory(index)
	_publish()


func _unequip_selected() -> void:
	var index := _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory[index]["equipped_slots"] = []
	_refresh_inventory(index)
	_publish()


func _publish() -> void:
	if not _loading and _on_change.is_valid():
		_on_change.call(_inventory.duplicate(true))
