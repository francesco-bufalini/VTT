extends VBoxContainer

# Private creature inventory. These are catalog references, not scene items:
# placing or deleting physical objects on the board never changes a sheet.
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")

var _on_change: Callable
var _on_status: Callable
var _catalog: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _inventory: Array[Dictionary] = []
var _loading: bool = false

var _search: LineEdit
var _catalog_list: ItemList
var _inventory_list: ItemList
var _quantity: SpinBox
var _details: RichTextLabel
var _add_button: Button
var _remove_button: Button


func setup(on_change: Callable, on_status: Callable) -> void:
	_on_change = on_change
	_on_status = on_status
	add_theme_constant_override("separation", 7)
	var heading := Label.new()
	heading.text = "Inventario · oggetti 5etools e homebrew"
	heading.add_theme_font_size_override("font_size", 17)
	add_child(heading)

	_search = LineEdit.new()
	_search.placeholder_text = "Cerca oggetto per nome, fonte o rarità…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _filter_catalog())
	add_child(_search)

	_catalog_list = ItemList.new()
	_catalog_list.custom_minimum_size.y = 145
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.item_selected.connect(_on_catalog_selected)
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
	add_child(_inventory_list)

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
	reload_catalog()
	_refresh_inventory()


func reload_catalog() -> void:
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
				"quantity": clampi(int(item.get("quantity", 1)), 1, 99999)
			})
	_refresh_inventory()
	_loading = false


func _filter_catalog() -> void:
	if _catalog_list == null:
		return
	var query: String = _search.text.strip_edges().to_lower()
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
		_filtered.append(item)
		_catalog_list.add_item(Player5eTools.display_label(item))
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
	_loading = true
	_quantity.value = int(_inventory[index].get("quantity", 1))
	_loading = false
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
		"quantity": 1
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
	_refresh_inventory(index)
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
		_inventory_list.add_item("%d × %s · %s" % [
			int(item.get("quantity", 1)),
			String(item.get("name", "")),
			String(item.get("source", ""))
		])
	if selected_index >= 0 and selected_index < _inventory.size():
		_inventory_list.select(selected_index)
		_quantity.value = int(_inventory[selected_index].get("quantity", 1))
	_remove_button.disabled = selected_index < 0
	_quantity.editable = selected_index >= 0
	_loading = old_loading


func _show_details(item: Dictionary) -> void:
	var description: String = Player5eTools.description_text_from_raw_item(item)
	_details.text = Player5eTools.info_text(item, description)


func _publish() -> void:
	if not _loading and _on_change.is_valid():
		_on_change.call(_inventory.duplicate(true))
