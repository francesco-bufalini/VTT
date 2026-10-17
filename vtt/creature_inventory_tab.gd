extends VBoxContainer
const DialogLayout = preload("res://vtt/dialog_layout.gd")

# Private creature inventory. These are catalog references, not scene items:
# placing or deleting physical objects on the board never changes a sheet.
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const Infusions = preload("res://vtt/creature_infusions.gd")
const ItemInstance = preload("res://vtt/item_instance.gd")
const DocumentsTab = preload("res://vtt/creature_documents_tab.gd")
const DocumentStore = preload("res://vtt/document_homebrew.gd")
const DocumentInbox = preload("res://vtt/document_inbox.gd")
const ItemInbox = preload("res://vtt/item_inbox.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const ItemImagePreview = preload("res://vtt/item_image_preview.gd")
const CreatureLocale = preload("res://vtt/creature_gui_locale.gd")
const QuickCustom = preload("res://vtt/quick_custom_catalog.gd")
const QuickCustomDialog = preload("res://vtt/quick_custom_catalog_dialog.gd")
const ShareRecipients = preload("res://vtt/share_recipients_dialog.gd")

var _on_change: Callable
var _on_status: Callable
var _catalog: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _inventory: Array[Dictionary] = []
var _loading: bool = false
var _rules_version := "2014"
var _gui_language := "it"
var _loaded_creature_id := ""

var _category_filter: OptionButton
var _rarity_filter: OptionButton
var _source_filter: OptionButton
var _property_filter: OptionButton
var _search_toggle: Button
var _search_panel: VBoxContainer
var _catalog_count: Label
var _details_from_catalog := false
var _equip_main: Button
var _equip_off: Button
var _equip_armor: Button
var _generic_equip: CheckButton
var _attuned: CheckButton
var _active_item: CheckButton
var _unequip: Button
var _search: LineEdit
var _catalog_list: ItemList
var _inventory_list: ItemList
var _quantity: SpinBox
var _weapon_size_choice: OptionButton
var _creature_size_name := "Medium"
var _details: RichTextLabel
var _add_button: Button
var _delete_custom_item: Button
var _remove_button: Button
var _documents_tab: Node
var _image_preview: AcceptDialog
var _document_change: Callable
var _send_document: Callable
var _peer_provider: Callable
var _send_item: Callable
var _item_share_menu: PopupMenu
var _item_share_button: Button
var _item_share_index := -1
var _item_touch_start := Vector2.ZERO
var _item_touch_active := false
var _item_touch_generation := 0
var _optional_features: Array[Dictionary] = []
var _infusion_record: Dictionary = {}
var _infusion_panel: VBoxContainer
var _infusion_status: Label
var _infusion_catalog_picker: OptionButton
var _infusion_known_picker: OptionButton
var _infusion_candidates: Array[Dictionary] = []
var _infusion_known: Array[Dictionary] = []
var _infusion_learn_button: Button
var _infusion_forget_button: Button
var _infusion_apply_button: Button
var _infusion_clear_button: Button


func setup(on_change: Callable, on_status: Callable, on_document_change: Callable = Callable(),
		send_document: Callable = Callable(), peer_provider: Callable = Callable(),
		send_item: Callable = Callable()) -> void:
	_on_change = on_change
	_on_status = on_status
	_document_change = on_document_change
	_send_document = send_document
	_peer_provider = peer_provider
	_send_item = send_item
	add_theme_constant_override("separation", 7)
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 7)
	add_child(heading_row)
	var heading := Label.new()
	heading.text = "Inventario · Catalogo e oggetti personalizzati"
	heading.add_theme_font_size_override("font_size", 17)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	_search_toggle = Button.new()
	_search_toggle.text = "🔍 Cerca oggetti"
	_search_toggle.toggle_mode = true
	_search_toggle.tooltip_text = "Mostra ricerca oggetti"
	_search_toggle.toggled.connect(_set_search_visible)
	heading_row.add_child(_search_toggle)

	# The search results expand immediately below the heading; the inventory
	# and its shared item description remain in their original positions.
	_search_panel = VBoxContainer.new()
	_search_panel.add_theme_constant_override("separation", 6)
	add_child(_search_panel)
	var search_row := HBoxContainer.new()
	_search_panel.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Nome, fonte, rarità, danno o proprietà…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_value: String) -> void: _filter_catalog())
	search_row.add_child(_search)
	var reset_button := Button.new()
	reset_button.text = "Azzera filtri"
	reset_button.pressed.connect(_reset_catalog_filters)
	search_row.add_child(reset_button)

	var filter_row := HFlowContainer.new()
	filter_row.add_theme_constant_override("h_separation", 9)
	filter_row.add_theme_constant_override("v_separation", 5)
	_search_panel.add_child(filter_row)
	_category_filter = OptionButton.new()
	# Identifiers are independent of the translated visible labels.
	var categories: Array = [
		["Tutti", "all"], ["Armi", "weapon"], ["Scudi", "shield"],
		["Armature", "armor"], ["Strumenti", "tool"],
		["Oggetti magici", "magic"], ["Documenti", "document"],
		["Altri oggetti", "other"]
	]
	for pair: Array in categories:
		_add_option(_category_filter, String(pair[0]), String(pair[1]))
	_category_filter.item_selected.connect(func(_index: int) -> void: _filter_catalog())
	_add_catalog_filter(filter_row, "Categoria", _category_filter, 145)
	_rarity_filter = OptionButton.new()
	_rarity_filter.item_selected.connect(func(_index: int) -> void: _filter_catalog())
	_add_catalog_filter(filter_row, "Rarità", _rarity_filter, 140)
	_source_filter = OptionButton.new()
	_source_filter.item_selected.connect(func(_index: int) -> void: _filter_catalog())
	_add_catalog_filter(filter_row, "Fonte", _source_filter, 110)
	_property_filter = OptionButton.new()
	for choice: Array in [
		["Tutte", ""], ["Accurata (Finesse)", "F"], ["Portata", "R"],
		["Da lancio", "T"], ["A due mani", "2H"], ["Leggera", "L"],
		["Pesante", "H"], ["Versatile", "V"]
	]:
		_property_filter.add_item(String(choice[0]))
		_property_filter.set_item_metadata(_property_filter.item_count - 1, String(choice[1]))
	_property_filter.item_selected.connect(func(_index: int) -> void: _filter_catalog())
	_add_catalog_filter(filter_row, "Proprietà arma", _property_filter, 160)

	var results_row := HBoxContainer.new()
	_search_panel.add_child(results_row)
	_catalog_count = Label.new()
	_catalog_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_row.add_child(_catalog_count)
	_add_button = Button.new()
	_add_button.text = "+ Aggiungi all'inventario"
	_add_button.tooltip_text = "Aggiungi l'oggetto selezionato; doppio clic sulla lista per aggiungere"
	_add_button.pressed.connect(_add_selected)
	results_row.add_child(_add_button)
	_delete_custom_item = Button.new()
	_delete_custom_item.text = "Elimina dal catalogo"
	_delete_custom_item.disabled = true
	_delete_custom_item.pressed.connect(_delete_selected_custom_item)
	results_row.add_child(_delete_custom_item)
	_catalog_list = ItemList.new()
	_catalog_list.mouse_force_pass_scroll_events = false
	_catalog_list.custom_minimum_size.y = 190
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.item_selected.connect(_on_catalog_selected)
	_catalog_list.gui_input.connect(_on_image_click.bind(true))
	_catalog_list.item_activated.connect(func(_index: int) -> void: _add_selected())
	_search_panel.add_child(_catalog_list)
	var inventory_title := Label.new()
	inventory_title.text = "Oggetti posseduti"
	inventory_title.add_theme_font_size_override("font_size", 15)
	add_child(inventory_title)
	_inventory_list = ItemList.new()
	_inventory_list.mouse_force_pass_scroll_events = false
	_inventory_list.custom_minimum_size.y = 145
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_list.item_selected.connect(_on_inventory_selected)
	_inventory_list.gui_input.connect(_on_image_click.bind(false))
	_inventory_list.gui_input.connect(_on_inventory_checkbox_input)
	_inventory_list.gui_input.connect(_on_inventory_item_input)
	add_child(_inventory_list)
	_item_share_menu = PopupMenu.new()
	_item_share_menu.add_item("Invia copia a utenti selezionati", 1)
	_item_share_menu.id_pressed.connect(func(_id: int) -> void: _share_selected_item())
	_inventory_list.add_child(_item_share_menu)
	# A visible action is essential on Android: a regular tap on ItemList
	# does not open the desktop right-click menu.
	_item_share_button = Button.new()
	_item_share_button.text = "Invia una copia…"
	_item_share_button.disabled = true
	_item_share_button.pressed.connect(_share_current_item)
	add_child(_item_share_button)
	# Infusions are optional class features applied to existing owned items.
	# They live inside the existing inventory tab, not in a parallel editor.
	_infusion_panel = VBoxContainer.new()
	_infusion_panel.add_theme_constant_override("separation", 5)
	_infusion_panel.visible = false
	add_child(_infusion_panel)
	var infusion_heading := Label.new()
	infusion_heading.text = "Infusioni · Artefice (TCE)"
	infusion_heading.add_theme_font_size_override("font_size", 15)
	_infusion_panel.add_child(infusion_heading)
	_infusion_status = Label.new()
	_infusion_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_infusion_panel.add_child(_infusion_status)
	var learn_row := HFlowContainer.new()
	_infusion_panel.add_child(learn_row)
	_infusion_catalog_picker = OptionButton.new()
	_infusion_catalog_picker.fit_to_longest_item = false
	_infusion_catalog_picker.custom_minimum_size.x = 180
	_infusion_catalog_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	learn_row.add_child(_infusion_catalog_picker)
	_infusion_learn_button = Button.new()
	_infusion_learn_button.text = "Impara"
	_infusion_learn_button.pressed.connect(_learn_infusion)
	learn_row.add_child(_infusion_learn_button)
	var use_row := HFlowContainer.new()
	_infusion_panel.add_child(use_row)
	_infusion_known_picker = OptionButton.new()
	_infusion_known_picker.fit_to_longest_item = false
	_infusion_known_picker.custom_minimum_size.x = 180
	_infusion_known_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_infusion_known_picker.item_selected.connect(func(_index: int) -> void: _refresh_infusion_ui())
	use_row.add_child(_infusion_known_picker)
	_infusion_apply_button = Button.new()
	_infusion_apply_button.text = "Infondi oggetto"
	_infusion_apply_button.pressed.connect(_apply_infusion)
	use_row.add_child(_infusion_apply_button)
	_infusion_forget_button = Button.new()
	_infusion_forget_button.text = "Dimentica"
	_infusion_forget_button.pressed.connect(_forget_infusion)
	use_row.add_child(_infusion_forget_button)
	_infusion_clear_button = Button.new()
	_infusion_clear_button.text = "Termina infusione"
	_infusion_clear_button.pressed.connect(_clear_infusion)
	_infusion_panel.add_child(_infusion_clear_button)
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
	_equip_armor = Button.new()
	_equip_armor.text = "Indossa armatura"
	_equip_armor.tooltip_text = "Seleziona questa armatura per calcolare automaticamente la CA"
	_equip_armor.pressed.connect(_equip_selected.bind("body"))
	equipment_row.add_child(_equip_armor)
	_unequip = Button.new()
	_unequip.text = "Rimuovi equipaggiamento"
	_unequip.pressed.connect(_unequip_selected)
	equipment_row.add_child(_unequip)
	# Hand and armor slots are now selected only on the Statistics sheet.
	# Keep these internal controls for legacy save tests, not in the inventory UI.
	equipment_row.visible = false
	var item_switches := HFlowContainer.new()
	item_switches.add_theme_constant_override("h_separation", 8)
	add_child(item_switches)
	var equip_hint := Label.new()
	equip_hint.text = "Seleziona un oggetto e usa Equipaggiato o Sintonia. Armi, scudi e armature si equipaggiano in Statistiche."
	equip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(equip_hint)
	move_child(equip_hint, item_switches.get_index())
	_generic_equip = CheckButton.new()
	_generic_equip.text = "Equipaggiato"
	_generic_equip.tooltip_text = "Equipaggia o riponi l'oggetto selezionato senza occupare slot. Per armi, scudi e armature usa Statistiche."
	_generic_equip.toggled.connect(_set_generic_equipment)
	item_switches.add_child(_generic_equip)
	_attuned = CheckButton.new()
	_attuned.text = "Sintonia"
	_attuned.tooltip_text = "Gli oggetti che richiedono sintonia conferiscono bonus solo quando sintonizzati."
	_attuned.toggled.connect(_set_attunement)
	item_switches.add_child(_attuned)
	_active_item = CheckButton.new()
	_active_item.text = "Attivo"
	_active_item.tooltip_text = "Disattiva gli effetti di un oggetto senza rimuoverlo dall'inventario."
	_active_item.toggled.connect(_set_active_item)
	item_switches.add_child(_active_item)

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

	# Weapon sizes are instance overrides. Without one, the weapon always
	# follows the current creature's size, even after a transformation.
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	add_child(size_row)
	var size_caption := Label.new()
	size_caption.text = "Taglia arma"
	size_row.add_child(size_caption)
	_weapon_size_choice = OptionButton.new()
	_weapon_size_choice.add_item("Come creatura (Medium)")
	for size_name: String in ItemRules.WEAPON_SIZES:
		_weapon_size_choice.add_item(size_name)
	_weapon_size_choice.disabled = true
	_weapon_size_choice.tooltip_text = "Default: taglia della creatura. Le armi Grandi/Enormi/Mastodontiche usano dadi aggiuntivi."
	_weapon_size_choice.item_selected.connect(_on_weapon_size_changed)
	size_row.add_child(_weapon_size_choice)
	_remove_button = Button.new()
	_remove_button.text = "Rimuovi"
	_remove_button.pressed.connect(_remove_selected)
	actions.add_child(_remove_button)

	_details = RichTextLabel.new()
	_details.mouse_force_pass_scroll_events = false
	_details.custom_minimum_size.y = 160
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.scroll_active = true
	_details.selection_enabled = true
	_details.hide()
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
	_documents_tab.call("setup", Callable(self, "_documents_changed"), _on_status,
		_send_document, _peer_provider)
	_image_preview = ItemImagePreview.new()
	add_child(_image_preview)
	_image_preview.call("setup")
	reload_catalog()
	_refresh_inventory()
	_set_search_visible(false)


func configure_touch_layout() -> void:
	# Reflow only once: this is also called when restoring/switching mobile
	# sheets, after the document tab has created non-toolbar child nodes.
	var touch = preload("res://vtt/mobile/touch_layout.gd")
	var objects_page := _inventory_list.get_parent() as VBoxContainer
	var header: Node = objects_page.get_child(0)
	if header is HBoxContainer:
		var title := header.get_child(0) as Label
		# An HBox may already be the compacted toolbar on a second call.
		if title != null:
			title.text = "Inventario"
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		touch.replace_box(header, VBoxContainer.new())
	for field: Control in [_search, _add_button]:
		var parent: Node = field.get_parent()
		if parent is HBoxContainer:
			touch.replace_box(parent, VBoxContainer.new())
	for field: Control in [_quantity, _weapon_size_choice]:
		var parent: Node = field.get_parent()
		if parent is HBoxContainer:
			touch.replace_box(parent, HFlowContainer.new())
	_search_panel.custom_minimum_size.x = 0
	_inventory_list.custom_minimum_size.x = 0
	_catalog_list.custom_minimum_size.x = 0
	_documents_tab.custom_minimum_size.x = 0
	var document_toolbar: Node = _documents_tab.get_node_or_null("DocumentsToolbar")
	if document_toolbar is HBoxContainer:
		touch.replace_box(document_toolbar, HFlowContainer.new())
	var tabs := objects_page.get_parent() as TabContainer
	tabs.custom_minimum_size.x = 0
	for page: Control in [objects_page, _documents_tab]:
		page.custom_minimum_size.x = 0
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_catalog_filter(parent: HFlowContainer, caption: String, option: OptionButton, width_px: float) -> void:
	var group := VBoxContainer.new()
	group.custom_minimum_size.x = width_px
	parent.add_child(group)
	var label := Label.new()
	label.text = caption
	group.add_child(label)
	option.fit_to_longest_item = false
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(option)


func _set_search_visible(show: bool) -> void:
	_search_panel.visible = show
	_search_toggle.set_pressed_no_signal(show)
	_search_toggle.tooltip_text = "Nascondi ricerca oggetti" if show else "Mostra ricerca oggetti"
	if not show:
		_catalog_list.deselect_all()
		_add_button.disabled = true
		if _details_from_catalog:
			_details_from_catalog = false
			var owned_index: int = _selected_inventory_index()
			if owned_index >= 0:
				_on_inventory_selected(owned_index)
			else:
				_details.hide()
	elif is_inside_tree():
		_search.grab_focus()


func _reset_catalog_filters() -> void:
	_search.clear()
	_category_filter.select(0)
	_rarity_filter.select(0)
	_source_filter.select(0)
	_property_filter.select(0)
	_filter_catalog()


func _documents_changed(inventory: Array) -> void:
	# Documents share the exact same live inventory array and persistence path.
	if _loading:
		return
	_loading = true
	_inventory.clear()
	for raw: Variant in inventory:
		if raw is Dictionary:
			_inventory.append(ItemInstance.from_saved(raw as Dictionary))
	_sanitize_equipment()
	reload_catalog()
	_refresh_inventory()
	_loading = false
	_publish()


func receive_document() -> void:
	# The inbox remains authoritative until the archive explicitly confirms
	# the inventory save. Never take_all()/clear it before persisting the sheet.
	var incoming: Array[Dictionary] = DocumentInbox.pending()
	var changed := false
	for note: Dictionary in incoming:
		var received_id: String = DocumentStore.legacy_id(note)
		var already_owned := false
		for saved: Dictionary in _inventory:
			if String(saved.get("id", "")) == received_id:
				already_owned = true
				break
		if already_owned:
			continue
		var item: Dictionary = DocumentStore.from_legacy(note)
		if item.is_empty():
			continue # Retry next time rather than acknowledging an invalid import.
		_inventory.append(item)
		changed = true
	if changed:
		reload_catalog()
		_refresh_inventory()
		_documents_tab.call("load_inventory", _inventory)
	# Also re-save when a prior attempt already placed the document in memory:
	# only CreatureArea may acknowledge the inbox after successful persistence.
	if not incoming.is_empty():
		_publish()


# Document sharing has its own tab. All other owned inventory entries use
# the same online peers, but send a single unequipped copy instead of
# mutating the sender's equipped/attuned stack.
func _on_inventory_item_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			var index: int = _inventory_list.get_item_at_position(mouse.position, true)
			if index >= 0:
				_open_item_share_menu(index, mouse.position)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		_item_touch_generation += 1
		_item_touch_active = touch.pressed
		if touch.pressed:
			_item_touch_start = touch.position
			var generation := _item_touch_generation
			var index: int = _inventory_list.get_item_at_position(touch.position, true)
			if index >= 0:
				get_tree().create_timer(0.55).timeout.connect(func() -> void:
					if is_inside_tree() and _item_touch_active and generation == _item_touch_generation:
						_item_touch_active = false
						_open_item_share_menu(index, _item_touch_start)
				)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.position.distance_to(_item_touch_start) > 18.0:
			_item_touch_active = false


func _open_item_share_menu(index: int, local_position: Vector2) -> void:
	if index < 0 or index >= _inventory.size() or DocumentStore.is_document(_inventory[index]):
		return
	_item_share_index = index
	_inventory_list.select(index)
	_on_inventory_selected(index)
	var peers: Array = _peer_provider.call() if _peer_provider.is_valid() else []
	_item_share_menu.set_item_disabled(0, peers.is_empty() or not _send_item.is_valid())
	DialogLayout.popup_menu(
		_item_share_menu, Vector2i(_inventory_list.get_global_rect().position + local_position)
	)


func _share_current_item() -> void:
	_item_share_index = _selected_inventory_index()
	_share_selected_item()


func _share_selected_item() -> void:
	if _item_share_index < 0 or _item_share_index >= _inventory.size():
		return
	if not _peer_provider.is_valid() or not _send_item.is_valid():
		_report_item_share("Sincronizzazione oggetti non disponibile.")
		return
	if ShareRecipients.choose(self, _peer_provider.call(), "oggetto",
			Callable(self, "_send_selected_item_to")) == null:
		_report_item_share("Nessun utente online disponibile per l'invio.")


func _send_selected_item_to(recipients: Array[String]) -> void:
	if _item_share_index < 0 or _item_share_index >= _inventory.size():
		return
	var selected: Dictionary = _inventory[_item_share_index]
	if DocumentStore.is_document(selected):
		return
	var definition: Dictionary = _catalog_entry(selected)
	var instance: Dictionary = ItemInstance.from_saved(selected)
	for field: String in ItemInstance.SNAPSHOT_FIELDS:
		if not instance.has(field) and definition.has(field):
			var value: Variant = definition[field]
			instance[field] = value.duplicate(true) if value is Array or value is Dictionary else value
	instance["quantity"] = 1
	instance["equipped"] = false
	instance["equipped_slots"] = []
	instance["attuned"] = false
	instance["active"] = true
	instance.erase("instance_id")
	var reference: Dictionary = {"inventory": [instance]}
	var missing: Array[String] = PortableContent.unresolved(reference)
	if not missing.is_empty():
		_report_item_share("Impossibile inviare: definizioni homebrew mancanti (%s)." % ", ".join(missing))
		return
	var definitions: Array[Dictionary] = PortableContent.bundle(reference)
	var sent := 0
	for recipient: String in recipients:
		var delivery_id: String = String(_send_item.call(recipient, instance, definitions))
		if not delivery_id.is_empty():
			sent += 1
	if sent == 0:
		_report_item_share("Oggetto non inviato: nessun utente raggiungibile o dati troppo grandi.")
	else:
		_report_item_share("Una copia di '%s' in consegna a %d utenti." % [
			String(instance.get("name", "Oggetto")), sent])


func _report_item_share(message: String) -> void:
	if _on_status.is_valid():
		_on_status.call(message)


func receive_item() -> void:
	# The durable inbox is shared by desktop and mobile, even if no
	# character was selected when the network packet was acknowledged.
	var incoming: Array[Dictionary] = ItemInbox.take_all()
	var changed := false
	for delivery: Dictionary in incoming:
		var raw: Variant = delivery.get("item", {})
		var definitions: Variant = delivery.get("definitions", [])
		if not raw is Dictionary or not definitions is Array:
			ItemInbox.requeue(delivery)
			continue
		if PortableContent.install(definitions) != OK:
			ItemInbox.requeue(delivery)
			continue
		var owned: Dictionary = ItemInstance.from_saved(raw as Dictionary)
		if String(owned.get("id", "")).is_empty() or String(owned.get("name", "")).is_empty():
			ItemInbox.requeue(delivery)
			continue
		owned["quantity"] = 1
		owned["equipped"] = false
		owned["equipped_slots"] = []
		owned["attuned"] = false
		owned["active"] = true
		owned["instance_id"] = "received_item_%d" % Time.get_ticks_usec()
		_inventory.append(owned)
		changed = true
	if changed:
		_sanitize_equipment()
		reload_catalog()
		_refresh_inventory(_inventory.size() - 1)
		_documents_tab.call("load_inventory", _inventory)
		_publish()


# 5etools indexes weapons and armor as both specialized and mundane items.
# Keep the richer specialized record in search without changing saved IDs.
static func _catalog_identity(item: Dictionary) -> String:
	var name: String = String(item.get("name", "")).strip_edges().to_lower()
	var source: String = String(item.get("source", "")).strip_edges().to_upper()
	var type_code: String = String(item.get("type", "")).strip_edges().to_upper()
	return name + "|" + source + "|" + type_code if not name.is_empty() and not source.is_empty() and not type_code.is_empty() else ""


static func _unique_catalog_items(items: Array[Dictionary]) -> Array[Dictionary]:
	var specialized: Dictionary = {}
	for item: Dictionary in items:
		if not String(item.get("id", "")).begins_with("mundane_item:"):
			var key: String = _catalog_identity(item)
			if not key.is_empty():
				specialized[key] = true
	var result: Array[Dictionary] = []
	for item: Dictionary in items:
		if (String(item.get("id", "")).begins_with("mundane_item:")
			and specialized.has(_catalog_identity(item))):
			continue
		result.append(item)
	return result


func reload_catalog() -> void:
	ItemRules.reset_catalog()
	_catalog = _unique_catalog_items(Player5eTools.entries("items"))
	_populate_catalog_options()
	if _catalog_list != null:
		_filter_catalog()


func load_record(record: Dictionary) -> void:
	_infusion_record = record.duplicate(true)
	_optional_features.clear()
	for raw_feature: Variant in record.get("optional_features_catalog", []):
		if raw_feature is Dictionary:
			_optional_features.append((raw_feature as Dictionary).duplicate(true))
	_loaded_creature_id = String(record.get("id", ""))
	_creature_size_name = String(record.get("size_name", "Medium"))
	if _creature_size_name not in ItemRules.WEAPON_SIZES:
		_creature_size_name = "Medium"
	_weapon_size_choice.set_item_text(0, "Come creatura (%s)" % _creature_size_name)
	var edition := String(record.get("rules_version", "2014"))
	if edition != _rules_version:
		_rules_version = edition
		_populate_catalog_options()
		_filter_catalog()
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
			_inventory.append(ItemInstance.from_saved(item))
	# One-time migration from record.documents to ordinary owned items.
	# Keep the old save property until every document is safely materialized.
	var migrated := false
	var legacy: Variant = record.get("documents", [])
	if legacy is Array:
		for raw: Variant in legacy:
			if not raw is Dictionary:
				continue
			var note: Dictionary = raw
			var existing_id: String = DocumentStore.legacy_id(note)
			var found := false
			for owned: Dictionary in _inventory:
				if String(owned.get("id", "")) == existing_id:
					found = true
					break
			if found:
				continue
			var item: Dictionary = DocumentStore.from_legacy(note)
			if item.is_empty():
				continue
			_inventory.append(item)
			migrated = true
	# Retain the previous inbox import behavior for deliveries received when
	# no creature was selected. There is no document-only sending UI.
	for note: Dictionary in DocumentInbox.pending():
		var received_id: String = DocumentStore.legacy_id(note)
		var already_owned := false
		for owned: Dictionary in _inventory:
			if String(owned.get("id", "")) == received_id:
				already_owned = true
				break
		if already_owned:
			migrated = true # Acknowledge only when a subsequent archive save succeeds.
			continue
		var received: Dictionary = DocumentStore.from_legacy(note)
		if received.is_empty():
			continue # Keep original inbox record for retry.
		_inventory.append(received)
		migrated = true
	_sanitize_equipment()
	_refresh_inventory()
	_loading = false
	_refresh_infusion_ui()
	if _documents_tab != null:
		_documents_tab.call("load_inventory", _inventory)
	if migrated:
		reload_catalog()
		# CreatureArea is still loading the sheet here; publishing synchronously
		# would be ignored by its _loading guard.
		call_deferred("_publish_migration", _loaded_creature_id)
	if not ItemInbox.pending().is_empty():
		call_deferred("receive_item")


func _catalog_entry(item: Dictionary) -> Dictionary:
	for row: Dictionary in _catalog:
		if String(row.get("id", "")) == String(item.get("id", "")):
			return ItemInstance.resolve(row, item)
	# Previously owned duplicate mundane rows still resolve to the same
	# specialized item's mechanics after cleaning up the search results.
	if String(item.get("id", "")).begins_with("mundane_item:"):
		var identity: String = _catalog_identity(item)
		if not identity.is_empty():
			for row: Dictionary in _catalog:
				if _catalog_identity(row) == identity:
					return ItemInstance.resolve(row, item)
	return ItemInstance.resolve(item, item)


func _image_label(item: Dictionary, caption: String) -> String:
	if DocumentStore.is_document(item) or ItemImagePreview.image_source(item).is_empty():
		return caption
	# Image marker follows the manual/source abbreviation, not the item name.
	var source: String = String(item.get("source", "")).strip_edges()
	if source.is_empty():
		return caption + "  🖼"
	var index: int = caption.rfind(source)
	if index < 0:
		return caption + "  🖼"
	var end: int = index + source.length()
	return caption.substr(0, end) + "  🖼" + caption.substr(end)


func _on_image_click(event: InputEvent, from_catalog: bool) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var list: ItemList = _catalog_list if from_catalog else _inventory_list
	var index: int = list.get_item_at_position(click.position, true)
	if index < 0:
		return
	var label: String = list.get_item_text(index)
	var image_offset: int = label.find("🖼")
	if image_offset < 0:
		return
	var rect: Rect2 = list.get_item_rect(index)
	var font: Font = list.get_theme_font("font")
	if font == null:
		return
	var size: int = list.get_theme_font_size("font_size")
	var before: String = label.substr(0, image_offset)
	var glyph_x: float = rect.position.x + font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if absf(click.position.x - glyph_x) > 24.0:
		return
	var item: Dictionary = {}
	if from_catalog and index < _filtered.size():
		item = _filtered[index]
	elif not from_catalog and index < _inventory.size():
		item = _catalog_entry(_inventory[index])
	if DocumentStore.is_document(item) or ItemImagePreview.image_source(item).is_empty():
		return
	_image_preview.call("preview", item)
	get_viewport().set_input_as_handled()


func _edition_allows_item(item: Dictionary) -> bool:
	return _rules_version != "2014" or not (
		String(item.get("type", "")).to_upper().contains("|XPHB")
		or String(item.get("id", "")).to_lower().ends_with("|xphb")
	)


func _option_value(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _add_option(option: OptionButton, label: String, value: String) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)


func _restore_option(option: OptionButton, old_value: String) -> void:
	for index: int in range(option.item_count):
		if String(option.get_item_metadata(index)) == old_value:
			option.select(index)
			return
	option.select(0)


func _rarity_label(rarity: String) -> String:
	match rarity:
		"common": return "Comune"
		"uncommon": return "Non comune"
		"rare": return "Raro"
		"very rare": return "Molto raro"
		"legendary": return "Leggendario"
		"artifact": return "Artefatto"
		"varies": return "Variabile"
		_: return rarity.capitalize()


func _item_rarity(item: Dictionary) -> String:
	var rarity := String(item.get("rarity", "")).strip_edges().to_lower()
	return "__none__" if rarity.is_empty() or rarity == "none" else rarity


func _populate_catalog_options() -> void:
	if _rarity_filter == null or _source_filter == null:
		return
	var old_rarity := _option_value(_rarity_filter)
	var old_source := _option_value(_source_filter)
	_rarity_filter.clear()
	_source_filter.clear()
	_add_option(_rarity_filter, "Tutte", "")
	_add_option(_source_filter, "Tutte", "")
	var rarities: Array[String] = []
	var sources: Array[String] = []
	for item: Dictionary in _catalog:
		if not _edition_allows_item(item):
			continue
		var rarity := _item_rarity(item)
		if rarity not in rarities:
			rarities.append(rarity)
		var source := String(item.get("source", "")).strip_edges()
		if not source.is_empty() and source not in sources:
			sources.append(source)
	rarities.sort()
	sources.sort()
	for rarity: String in rarities:
		_add_option(_rarity_filter, "Senza rarità" if rarity == "__none__" else _rarity_label(rarity), rarity)
	for source: String in sources:
		_add_option(_source_filter, source, source)
	_restore_option(_rarity_filter, old_rarity)
	_restore_option(_source_filter, old_source)


func _catalog_matches(item: Dictionary, words: PackedStringArray) -> bool:
	if not _edition_allows_item(item):
		return false
	var category: String = _option_value(_category_filter)
	if category == "magic":
		if not String(item.get("id", "")).begins_with("magic_item:") and not bool(item.get("magic", false)):
			return false
	elif category != "all" and category != "" and ItemRules.kind(item) != category:
		return false
	var rarity := _option_value(_rarity_filter)
	if not rarity.is_empty() and _item_rarity(item) != rarity:
		return false
	var source := _option_value(_source_filter)
	if not source.is_empty() and String(item.get("source", "")) != source:
		return false
	var property_code := _option_value(_property_filter)
	if not property_code.is_empty() and (
		ItemRules.kind(item) != "weapon" or not ItemRules.has_property(item, property_code)
	):
		return false
	var searchable := ("%s %s %s %s %s %s %s %s %s" % [
		item.get("name", ""), item.get("source", ""), item.get("rarity", ""),
		item.get("weapon_category", ""), ItemRules.category_name(item),
		item.get("damage", ""), item.get("range", ""), item.get("type", ""),
		JSON.stringify(item.get("properties", []))
	]).to_lower()
	for word: String in words:
		if word not in searchable:
			return false
	return true


func _catalog_row_label(item: Dictionary) -> String:
	var marker := "📦"
	match ItemRules.kind(item):
		"weapon": marker = "⚔"
		"shield", "armor": marker = "🛡"
		"tool": marker = "🛠"
		"magic": marker = "✨"
		"document": marker = "📄"
	var tags: PackedStringArray = []
	var damage := String(item.get("damage", "")).strip_edges()
	if not damage.is_empty():
		tags.append(damage)
	var rarity := _item_rarity(item)
	if rarity != "__none__":
		tags.append(_rarity_label(rarity))
	var source := String(item.get("source", "")).strip_edges()
	if not source.is_empty():
		tags.append(source)
	if String(item.get("origin", "")) == "homebrew":
		tags.append("Homebrew")
	var owned := false
	for saved: Dictionary in _inventory:
		if String(saved.get("id", "")) == String(item.get("id", "")):
			owned = true
			break
	return marker + "  " + ("✓ " if owned else "") + String(item.get("name", "")) + (
		"    ·    " + " · ".join(tags) if not tags.is_empty() else ""
	)


func _filter_catalog() -> void:
	if _catalog_list == null:
		return
	var selected_id := ""
	var selected: PackedInt32Array = _catalog_list.get_selected_items()
	if not selected.is_empty() and selected[0] < _filtered.size():
		selected_id = String(_filtered[selected[0]].get("id", ""))
	if selected_id == "__create_custom_item__":
		selected_id = ""
	var words: PackedStringArray = _search.text.strip_edges().to_lower().split(" ", false)
	_filtered.clear()
	_catalog_list.clear()
	_filtered.append({"id": "__create_custom_item__", "name": "＋ Crea oggetto personalizzato"})
	_catalog_list.add_item("＋ Crea oggetto personalizzato")
	var matches := 0
	var selected_index := -1
	var prioritized: Array[Dictionary] = []
	for item: Dictionary in _catalog:
		if QuickCustom.is_custom(item):
			prioritized.append(item)
	for item: Dictionary in _catalog:
		if not QuickCustom.is_custom(item):
			prioritized.append(item)
	for item: Dictionary in prioritized:
		if String(item.get("name", "")).strip_edges().is_empty() or not _catalog_matches(item, words):
			continue
		matches += 1
		if _filtered.size() >= 250:
			continue
		if String(item.get("id", "")) == selected_id:
			selected_index = _filtered.size()
		_filtered.append(item)
		_catalog_list.add_item(_image_label(item, _catalog_row_label(item)))
		# Search can render hundreds of results in one keystroke. Never
		# expand rich item descriptions or heterogeneous 5etools properties
		# into tooltips for every result; read them only on explicit selection.
		_catalog_list.set_item_tooltip(_catalog_list.item_count - 1,
			str(item.get("name", "")) + " · " + str(item.get("source", "")))
	_catalog_count.text = (
		"Risultati: %d" % matches if matches <= 250
		else "Risultati: 250 di %d · Affina i filtri per vedere gli altri" % matches
	)
	_add_button.disabled = true
	_delete_custom_item.disabled = true
	if _details_from_catalog:
		_details.hide()
		_details_from_catalog = false
	if selected_index >= 0:
		_catalog_list.select(selected_index)
		_on_catalog_selected(selected_index)


func _on_catalog_selected(index: int) -> void:
	if index >= 0 and index < _filtered.size() and String(_filtered[index].get("id", "")) == "__create_custom_item__":
		_add_button.disabled = true
		_delete_custom_item.disabled = true
		_open_custom_item_editor()
		return
	_add_button.disabled = index < 0 or index >= _filtered.size()
	_delete_custom_item.disabled = index < 0 or index >= _filtered.size() or not QuickCustom.is_custom(_filtered[index])
	if index >= 0 and index < _filtered.size():
		var item: Dictionary = _filtered[index]
		_details_from_catalog = true
		_show_details(item)
	else:
		if _details_from_catalog:
			_details.hide()
			_details_from_catalog = false


func _open_custom_item_editor() -> void:
	QuickCustomDialog.create_popup(self, "items", func(_created: Dictionary) -> void:
		reload_catalog()
		_set_search_visible(true)
	)


func _delete_selected_custom_item() -> void:
	var selected: PackedInt32Array = _catalog_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _filtered.size():
		return
	var item: Dictionary = _filtered[selected[0]]
	if not QuickCustom.is_custom(item):
		return
	QuickCustomDialog.delete_popup(self, item, func() -> void:
		reload_catalog()
	)


func _selected_inventory_index() -> int:
	if _inventory_list == null:
		return -1
	var selected: PackedInt32Array = _inventory_list.get_selected_items()
	return selected[0] if not selected.is_empty() else -1


func _on_inventory_selected(index: int) -> void:
	if index < 0 or index >= _inventory.size():
		return
	_details_from_catalog = false
	_quantity.set_value_no_signal(int(_inventory[index].get("quantity", 1)))
	_set_weapon_size_choice(_inventory[index])
	_quantity.editable = not DocumentStore.is_document(_inventory[index])
	_remove_button.disabled = false
	_item_share_button.disabled = DocumentStore.is_document(_inventory[index]) or not _send_item.is_valid()
	_update_equip_buttons()
	_refresh_infusion_ui()
	var item_id: String = String(_inventory[index].get("id", ""))
	for catalog_item: Dictionary in _catalog:
		if String(catalog_item.get("id", "")) == item_id:
			_show_details(_catalog_entry(_inventory[index]))
			return
	_details.text = "%s\n%s%s\n%s" % [
		String(_inventory[index].get("name", "")),
		CreatureLocale.text_for("Fonte: ", _gui_language),
		String(_inventory[index].get("source", "")),
		CreatureLocale.text_for("Voce non installata nel catalogo locale.", _gui_language)
	]
	_details.show()


func _add_selected() -> void:
	var selected: PackedInt32Array = _catalog_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _filtered.size():
		return
	var source_item: Dictionary = _filtered[selected[0]]
	var item_id: String = String(source_item.get("id", "")).strip_edges()
	if item_id.is_empty() or item_id == "__create_custom_item__":
		return
	for i: int in range(_inventory.size()):
		if not DocumentStore.is_document(source_item) and String(_inventory[i].get("id", "")) == item_id and not ItemInstance.has_customizations(_inventory[i]):
			_inventory[i]["quantity"] = mini(99999, int(_inventory[i]["quantity"]) + 1)
			_refresh_inventory(i)
			_publish()
			_filter_catalog()
			return
	var new_item: Dictionary = ItemInstance.from_catalog(source_item)
	_inventory.append(new_item)
	_refresh_inventory(_inventory.size() - 1)
	_publish()
	_filter_catalog()


func update_creature_size(size_name: String) -> void:
	if size_name not in ItemRules.WEAPON_SIZES or _creature_size_name == size_name:
		return
	_creature_size_name = size_name
	_weapon_size_choice.set_item_text(0,
		CreatureLocale.text_for("Come creatura (%s)", _gui_language) % CreatureLocale.text_for(size_name, _gui_language))


func _set_weapon_size_choice(item: Dictionary) -> void:
	var is_weapon: bool = not item.is_empty() and ItemRules.kind(_catalog_entry(item)) == "weapon"
	_weapon_size_choice.disabled = not is_weapon
	var overrides: Variant = item.get("instance_overrides", {})
	var explicit: String = String((overrides as Dictionary).get("weapon_size", "")) if overrides is Dictionary else ""
	var choice := 0
	if is_weapon and explicit in ItemRules.WEAPON_SIZES:
		choice = ItemRules.WEAPON_SIZES.find(explicit) + 1
	_weapon_size_choice.select(choice)


func _on_weapon_size_changed(choice: int) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	var row: Dictionary = _inventory[index].duplicate(true)
	if ItemRules.kind(_catalog_entry(row)) != "weapon":
		return
	var override_size: String = (
		String(ItemRules.WEAPON_SIZES[choice - 1])
		if choice > 0 and choice <= ItemRules.WEAPON_SIZES.size() else ""
	)
	var overrides: Dictionary = row.get("instance_overrides", {}).duplicate(true)
	if String(overrides.get("weapon_size", "")) == override_size:
		return
	# Changing one weapon in a stack must leave the other copies untouched.
	if int(row.get("quantity", 1)) > 1:
		_inventory[index]["quantity"] = int(row["quantity"]) - 1
		row["quantity"] = 1
		row["equipped_slots"] = []
		index += 1
		_inventory.insert(index, row)
	if override_size.is_empty():
		overrides.erase("weapon_size")
	else:
		overrides["weapon_size"] = override_size
	row["instance_overrides"] = overrides
	_inventory[index] = row
	_sanitize_equipment()
	_refresh_inventory(index)
	_publish()


func _on_quantity_changed(value: float) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	if DocumentStore.is_document(_inventory[index]):
		_quantity.set_value_no_signal(1)
		return
	if _inventory[index].get("infusion", {}) is Dictionary and not (_inventory[index].get("infusion", {}) as Dictionary).is_empty() and int(value) != 1:
		_quantity.set_value_no_signal(1)
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
	if _search_panel.visible:
		_filter_catalog()


func _refresh_inventory(selected_index: int = -1) -> void:
	if _inventory_list == null:
		return
	var old_loading: bool = _loading
	_loading = true
	_inventory_list.clear()
	for item: Dictionary in _inventory:
		_inventory_list.add_item(_image_label(_catalog_entry(item), _inventory_label(item)))
		var item_index: int = _inventory_list.item_count - 1
		var category: String = ItemRules.kind(_catalog_entry(item))
		if category not in ["weapon", "armor", "shield"]:
			_inventory_list.set_item_icon(item_index, get_theme_icon("checked" if bool(item.get("equipped", false)) else "unchecked", "CheckBox"))
			_inventory_list.set_item_icon_modulate(item_index, Color(0.79, 0.92, 0.97))
			_inventory_list.set_item_tooltip(item_index, "Clicca sulla casella a sinistra per equipaggiare o riporre l’oggetto.")
	if selected_index >= 0 and selected_index < _inventory.size():
		_details_from_catalog = false
		_inventory_list.select(selected_index)
		_quantity.value = int(_inventory[selected_index].get("quantity", 1))
		_show_details(_catalog_entry(_inventory[selected_index]))
	else:
		_details_from_catalog = false
		_details.hide()
	_set_weapon_size_choice(_inventory[selected_index] if selected_index >= 0 and selected_index < _inventory.size() else {})
	_remove_button.disabled = selected_index < 0
	_item_share_button.disabled = selected_index < 0 or not _send_item.is_valid() or (
		selected_index >= 0 and DocumentStore.is_document(_inventory[selected_index]))
	_quantity.editable = selected_index >= 0 and not DocumentStore.is_document(_inventory[selected_index])
	_update_equip_buttons()
	_loading = old_loading
	_refresh_infusion_ui()


# ItemList has no cell checkbox mode. Its checkbox theme icons form clickable
# controls at the start of each generic-item row; the selection remains intact.
func _on_inventory_checkbox_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.position.x > 43.0:
		return
	var index: int = _inventory_list.get_item_at_position(click.position, true)
	if index < 0 or index >= _inventory.size():
		return
	var kind: String = ItemRules.kind(_catalog_entry(_inventory[index]))
	if kind in ["weapon", "armor", "shield"]:
		return
	_inventory_list.select(index)
	_on_inventory_selected(index)
	_set_generic_equipment(not bool(_inventory[index].get("equipped", false)))
	get_viewport().set_input_as_handled()


func set_gui_language(language: String) -> void:
	if language not in ["it", "en"] or _gui_language == language:
		return
	_gui_language = language
	var selected_index: int = _selected_inventory_index()
	_refresh_inventory(selected_index)


func _inventory_label(item: Dictionary) -> String:
	var tags: PackedStringArray = []
	var slots: Array = ItemRules.slots(item)
	if bool(item.get("equipped", false)) and ItemRules.kind(_catalog_entry(item)) not in ["weapon", "armor", "shield"]:
		tags.append(CreatureLocale.text_for("Equipaggiato", _gui_language))
	if "main" in slots:
		tags.append("⚔ " + CreatureLocale.text_for("Principale", _gui_language))
	if "body" in slots:
		tags.append(CreatureLocale.text_for("Indossata", _gui_language))
	if "off" in slots:
		tags.append("🛡 " + CreatureLocale.text_for("Secondaria", _gui_language))
	var equipment := (" [" + ", ".join(tags) + "]") if not tags.is_empty() else ""
	var extra: Variant = item.get("instance_overrides", {})
	var size_name: String = String((extra as Dictionary).get("weapon_size", "")) if extra is Dictionary else ""
	var size_label := " · " + CreatureLocale.text_for("taglia", _gui_language) + " " + CreatureLocale.text_for(size_name, _gui_language) if size_name in ItemRules.WEAPON_SIZES else ""
	var item_name: String = String(item.get("name", ""))
	var infusion: Variant = item.get("infusion", {})
	if infusion is Dictionary and not (infusion as Dictionary).is_empty():
		item_name += " ✦ " + String((infusion as Dictionary).get("name", ""))
	if DocumentStore.is_document(item):
		item_name = String(_catalog_entry(item).get("name", item_name))
	return "%d × %s%s%s · %s" % [item.get("quantity", 1), item_name, equipment, size_label, item.get("source", "")]


func _show_details(item: Dictionary) -> void:
	var description: String = Player5eTools.description_text_from_raw_item(item)
	_details.text = CreatureLocale.text_for(ItemRules.category_name(item), _gui_language) + "\n" + Player5eTools.info_text(item, description)
	var attached: Variant = item.get("infusion", {})
	if attached is Dictionary and not (attached as Dictionary).is_empty():
		var option: Dictionary = Infusions.definition(attached as Dictionary)
		_details.text += "\n\nInfusione: " + String((attached as Dictionary).get("name", ""))
		_details.text += "\n" + Player5eTools.description_text("optional_features", option)
	_details.show()



func _sanitize_equipment() -> void:
	var used: Dictionary = {}
	for i: int in range(_inventory.size()):
		var row: Dictionary = _inventory[i]
		var entry: Dictionary = _catalog_entry(row) if not _catalog.is_empty() else ItemRules.entry_for(row)
		var valid: Array = []
		for raw_slot: Variant in ItemRules.slots(row):
			var slot := String(raw_slot)
			if slot not in ["main", "off", "body"] or used.has(slot):
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
	_equip_armor.disabled = not present or not ItemRules.valid_slot(entry, "body")
	var kind: String = ItemRules.kind(entry) if present else ""
	_generic_equip.disabled = not present or kind in ["weapon", "armor", "shield", "document"]
	_generic_equip.set_pressed_no_signal(present and bool(_inventory[index].get("equipped", false)))
	_generic_equip.tooltip_text = (
		"Armi, scudi e armature si equipaggiano in Statistiche."
		if present and kind in ["weapon", "armor", "shield"] else
		"Equipaggia o riponi l'oggetto selezionato senza occupare slot."
	)
	var needs_attunement: bool = present and ItemRules.requires_attunement(entry)
	_attuned.disabled = not needs_attunement
	_attuned.set_pressed_no_signal(present and bool(_inventory[index].get("attuned", false)))
	_attuned.tooltip_text = (
		"Attiva la sintonia con l'oggetto selezionato; è necessaria per i suoi benefici magici."
		if needs_attunement else "L'oggetto selezionato non richiede sintonia."
	)
	_active_item.disabled = not present or kind == "document"
	_active_item.set_pressed_no_signal(present and bool(_inventory[index].get("active", true)))
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


func _set_generic_equipment(value: bool) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	var kind: String = ItemRules.kind(_catalog_entry(_inventory[index]))
	if kind in ["weapon", "armor", "shield", "document"]:
		_generic_equip.set_pressed_no_signal(bool(_inventory[index].get("equipped", false)))
		return
	if bool(_inventory[index].get("equipped", false)) == value:
		return
	_inventory[index]["equipped"] = value
	_refresh_inventory(index)
	_publish()


func _set_attunement(value: bool) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	if not ItemRules.requires_attunement(_catalog_entry(_inventory[index])):
		_attuned.set_pressed_no_signal(false)
		return
	_inventory[index]["attuned"] = value
	_refresh_inventory(index)
	_publish()


func _set_active_item(value: bool) -> void:
	if _loading:
		return
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory[index]["active"] = value
	_publish()


func _unequip_selected() -> void:
	var index := _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory[index]["equipped_slots"] = []
	_refresh_inventory(index)
	_publish()


func _publish_migration(expected_creature_id: String) -> void:
	if _loaded_creature_id == expected_creature_id:
		_publish()


func _publish() -> void:
	if not _loading and _on_change.is_valid():
		if _documents_tab != null:
			_documents_tab.call("load_inventory", _inventory)
		_on_change.call(_inventory.duplicate(true))


# Preserve other optional class features when adding/removing an Artificer
# infusion. The creature sheet already persists this field on save/export.
func optional_features() -> Array[Dictionary]:
	return _optional_features.duplicate(true)


func _effective_infusion_record() -> Dictionary:
	var record: Dictionary = _infusion_record.duplicate(true)
	record["optional_features_catalog"] = _optional_features.duplicate(true)
	record["inventory"] = _inventory.duplicate(true)
	return record


func _refresh_infusion_ui() -> void:
	if _infusion_panel == null:
		return
	var record: Dictionary = _effective_infusion_record()
	var level: int = Infusions.artificer_level(record)
	_infusion_panel.visible = level > 0
	if level <= 0:
		return
	var limit: int = Infusions.known_limit(record)
	var active_limit: int = Infusions.active_limit(record)
	_infusion_status.text = "Conosciute: %d/%d · Oggetti infusi: %d/%d" % [
		Infusions.known(record).size(), limit, Infusions.active_count(_inventory, _loaded_creature_id), active_limit]
	if level < 2:
		_infusion_status.text += " · Disponibili dal livello 2"
	var previous: int = _infusion_known_picker.selected
	_infusion_known = Infusions.known(record)
	_infusion_known_picker.clear()
	for option: Dictionary in _infusion_known:
		var caption: String = String(option.get("name", ""))
		if not String(option.get("plan_item_name", "")).is_empty():
			caption += " → " + String(option.get("plan_item_name", ""))
		_infusion_known_picker.add_item(caption)
	if not _infusion_known.is_empty():
		_infusion_known_picker.select(clampi(previous, 0, _infusion_known.size() - 1))
	_infusion_candidates.clear()
	_infusion_catalog_picker.clear()
	for option: Dictionary in Infusions.catalog():
		if int(option.get("min_level", 2)) > level:
			continue
		if String(option.get("application_kind", "")) != "replicate" and Infusions.is_learned(record, option):
			continue
		_infusion_candidates.append(option)
		_infusion_catalog_picker.add_item(String(option.get("name", "")))
		_infusion_catalog_picker.set_item_tooltip(_infusion_catalog_picker.item_count - 1,
			String(option.get("item_prerequisite", "")))
	if not _infusion_candidates.is_empty():
		_infusion_catalog_picker.select(0)
	_infusion_learn_button.disabled = level < 2 or _infusion_candidates.is_empty() or _infusion_known.size() >= limit
	_infusion_forget_button.disabled = _infusion_known.is_empty()
	var selected_index: int = _selected_inventory_index()
	var owns: bool = selected_index >= 0 and selected_index < _inventory.size()
	_infusion_apply_button.disabled = not owns or _infusion_known.is_empty() or level < 2
	_infusion_clear_button.disabled = not owns or not _inventory[selected_index].get("infusion", {}) is Dictionary or (
		(_inventory[selected_index].get("infusion", {}) as Dictionary).is_empty())


func _infusion_message(message: String) -> void:
	if _on_status.is_valid():
		_on_status.call(message)
	_infusion_status.text = message


func _learn_infusion() -> void:
	var index: int = _infusion_catalog_picker.selected
	if index < 0 or index >= _infusion_candidates.size():
		return
	var record: Dictionary = _effective_infusion_record()
	var level: int = Infusions.artificer_level(record)
	if level < 2 or Infusions.known(record).size() >= Infusions.known_limit(record):
		_infusion_message("Limite delle infusioni conosciute raggiunto.")
		return
	var option: Dictionary = _infusion_candidates[index]
	var learned: Dictionary = {"id": option.get("id", ""), "name": option.get("name", ""), "source": "TCE"}
	if String(option.get("application_kind", "")) == "replicate":
		var selected: int = _selected_inventory_index()
		if selected < 0 or selected >= _inventory.size():
			_infusion_message("Seleziona prima dall'inventario l'oggetto magico da replicare.")
			return
		var entry: Dictionary = _catalog_entry(_inventory[selected])
		if not Infusions.replicable(option, entry, level):
			_infusion_message("Questo oggetto non è nei piani replicabili disponibili a questo livello.")
			return
		learned["plan_item_id"] = String(_inventory[selected].get("id", ""))
		learned["plan_item_name"] = String(entry.get("name", ""))
	if Infusions.is_learned(record, learned):
		_infusion_message("Infusione o piano già conosciuto.")
		return
	_optional_features.append(learned)
	_refresh_infusion_ui()
	_publish()


func _selected_known_infusion() -> Dictionary:
	var index: int = _infusion_known_picker.selected
	if index >= 0 and index < _infusion_known.size():
		return _infusion_known[index]
	return {}


func _forget_infusion() -> void:
	var selected: Dictionary = _selected_known_infusion()
	if selected.is_empty():
		return
	var sid: String = String(selected.get("id", ""))
	var plan: String = String(selected.get("plan_item_id", ""))
	for i: int in range(_optional_features.size() - 1, -1, -1):
		var feature: Dictionary = _optional_features[i]
		if String(feature.get("id", "")) == sid and String(feature.get("plan_item_id", "")) == plan:
			_optional_features.remove_at(i)
			break
	for owned: Dictionary in _inventory:
		var active: Variant = owned.get("infusion", {})
		if active is Dictionary and String(active.get("creator_id", "")) == _loaded_creature_id and String(active.get("id", "")) == sid and String(active.get("plan_item_id", "")) == plan:
			owned.erase("infusion")
			owned["attuned"] = false
	_refresh_inventory(_selected_inventory_index())
	_publish()


func _apply_infusion() -> void:
	var selected: Dictionary = _selected_known_infusion()
	var index: int = _selected_inventory_index()
	if selected.is_empty() or index < 0 or index >= _inventory.size():
		return
	var record: Dictionary = _effective_infusion_record()
	var level: int = Infusions.artificer_level(record)
	if level < int(selected.get("min_level", 2)):
		_infusion_message("Livello dell'Artefice insufficiente per questa infusione.")
		return
	var owned: Dictionary = _inventory[index]
	if int(owned.get("quantity", 0)) <= 0:
		return
	if not Infusions.item_eligible(selected, owned):
		_infusion_message("Oggetto incompatibile con i prerequisiti di questa infusione.")
		return
	for i: int in range(_inventory.size()):
		if i == index:
			continue
		var other: Variant = _inventory[i].get("infusion", {})
		if other is Dictionary and String(other.get("creator_id", "")) == _loaded_creature_id and String(other.get("id", "")) == String(selected.get("id", "")) and String(other.get("plan_item_id", "")) == String(selected.get("plan_item_id", "")):
			_infusion_message("Questa infusione è già applicata a un altro oggetto.")
			return
	var old: Variant = owned.get("infusion", {})
	if old is Dictionary and not (old as Dictionary).is_empty() and String(old.get("creator_id", "")) != _loaded_creature_id:
		_infusion_message("L'oggetto è già infuso da un altro Artefice.")
		return
	if (not old is Dictionary or (old as Dictionary).is_empty()) and Infusions.active_count(_inventory, _loaded_creature_id) >= Infusions.active_limit(record):
		_infusion_message("Limite di oggetti infusi raggiunto: termina prima un'altra infusione.")
		return
	# A single physical item receives the infusion. Splitting a stack preserves
	# its remaining ordinary copies without inventing a second item system.
	if int(owned.get("quantity", 1)) > 1:
		var remainder: Dictionary = owned.duplicate(true)
		remainder["quantity"] = int(owned["quantity"]) - 1
		remainder.erase("infusion")
		remainder["equipped_slots"] = []
		remainder["equipped"] = false
		remainder["attuned"] = false
		_inventory.append(remainder)
		owned["quantity"] = 1
	owned["infusion"] = {
		"id": selected.get("id", ""), "name": selected.get("name", ""),
		"source": "TCE", "level": level, "creator_id": _loaded_creature_id,
		"plan_item_id": selected.get("plan_item_id", ""),
		"requires_attunement": bool(selected.get("requires_attunement", false))
	}
	_inventory[index] = owned
	_refresh_inventory(index)
	_publish()


func _clear_infusion() -> void:
	var index: int = _selected_inventory_index()
	if index < 0 or index >= _inventory.size():
		return
	_inventory[index].erase("infusion")
	_inventory[index]["attuned"] = false
	_refresh_inventory(index)
	_publish()
