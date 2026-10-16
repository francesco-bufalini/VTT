extends SceneTree

const Catalog = preload("res://vtt/content_catalog.gd")
const Documents = preload("res://vtt/document_homebrew.gd")
const Instances = preload("res://vtt/item_instance.gd")
const Inventory = preload("res://vtt/creature_inventory_tab.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const QuickCustom = preload("res://vtt/quick_custom_catalog.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const ItemInbox = preload("res://vtt/item_inbox.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stamp: String = str(Time.get_ticks_usec())
	var row: Dictionary = Documents.create_document("Documento test " + stamp, "Primo testo")
	assert(not row.is_empty(), "A document must be writable as homebrew JSON")
	var identifier: String = String(row.get("id", ""))
	assert(identifier.begins_with("homebrew:vttdoc:documents:"))
	assert(String(row.get("category", "")) == "documents")
	assert(int(row.get("added_at", 0)) > 0)
	assert(Documents.definition_for(row).get("description", "") == "Primo testo")
	var document_path: String = Documents.ROOT_DIR.path_join(identifier.trim_prefix(Documents.OWN_PREFIX) + ".json")
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(document_path))
	assert(json is Dictionary and json.get("document") is Array)
	assert(json["document"][0].has("description") and not json["document"][0].has("added_at"))
	assert(not json["document"][0].has("display_style"), "Display style belongs only to owned instances")

	var saved: Dictionary = Instances.from_saved(row)
	saved["display_style"] = "lettera"
	var reread: Dictionary = Instances.from_saved(saved)
	assert(reread.get("added_at") == row.get("added_at"))
	assert(reread.get("display_style") == "lettera")
	assert(reread.get("instance_id") == row.get("instance_id"))
	assert(Documents.update_definition(row, "Titolo modificato", "Nuovo contenuto"))
	var edited: Dictionary = Documents.definition_for(row)
	assert(edited.get("id") == identifier, "Editing title must not break inventory references")
	assert(edited.get("description") == "Nuovo contenuto")

	# Old sheets migrate their old documents array into ordinary inventory
	# rows and preserve the chosen style.
	var legacy := {
		"id": "test_legacy_" + stamp,
		"title": "Lettera antica",
		"text": "Consegna originale",
		"style": "lettera"
	}
	var events: Array = []
	var deliveries: Array[Dictionary] = []
	var item_deliveries: Array[Dictionary] = []
	var tab := Inventory.new()
	root.add_child(tab)
	var record_delivery := func(recipient: String, document: Dictionary) -> String:
		deliveries.append({"recipient": recipient, "document": document.duplicate(true)})
		return "test_delivery_" + recipient
	var online_peers := func() -> Array[Dictionary]:
		return [{"id": "person_one", "label": "Giocatore uno"},
			{"id": "person_two", "label": "Giocatore due"}]
	var record_item_delivery := func(recipient: String, item: Dictionary, definitions: Array[Dictionary]) -> String:
		item_deliveries.append({"recipient": recipient, "item": item.duplicate(true),
			"definitions": definitions.duplicate(true)})
		return "item_delivery_" + recipient
	tab.setup(func(items: Array) -> void: events.append(items.duplicate(true)),
		Callable(), Callable(), record_delivery, online_peers, record_item_delivery)
	tab.load_record({"inventory": [row], "documents": [legacy]})
	await process_frame
	await process_frame
	assert(tab._inventory.size() == 2)
	assert(events.size() > 0, "Migrated inventory must be published after loading")
	var migrated: Dictionary = tab._inventory[1]
	assert(migrated.get("id") == Documents.legacy_id(legacy))
	assert(migrated.get("display_style") == "lettera")
	assert(Documents.definition_for(migrated).get("description") == "Consegna originale")
	# Both desktop right-click and mobile long-press open the same
	# opt-in recipient picker; opening it must never send to all peers.
	var docs_tab: Node = tab._documents_tab
	var owned_document_list: ItemList = docs_tab.get("_list")
	owned_document_list.select(0)
	assert(not (docs_tab.get("_share_button") as Button).disabled)
	(docs_tab.get("_share_button") as Button).pressed.emit()
	assert(deliveries.is_empty(), "Opening a document share must not broadcast")
	var document_dialog: ConfirmationDialog
	for child: Node in docs_tab.get_children():
		if child is ConfirmationDialog and child.title == "Invia documento: scegli destinatari":
			document_dialog = child
	assert(document_dialog != null and document_dialog.get_ok_button().disabled)
	var document_checks := document_dialog.find_children("*", "CheckBox", true, false)
	assert(document_checks.size() == 2)
	(document_checks[0] as CheckBox).button_pressed = true
	document_dialog.hide()
	document_dialog.confirmed.emit()
	await process_frame
	assert(deliveries.size() == 1 and deliveries[0].recipient == "person_one")
	assert(String(deliveries[0].document.title) == "Titolo modificato"
		and String(deliveries[0].document.text) == "Nuovo contenuto"
		and String(deliveries[0].document.id) == identifier,
		"Only the selected peer receives the current saved document definition")

	# Export only referenced homebrew, and preserve the document's body.
	var portable_record: Dictionary = {"kind": "character", "inventory": [row]}
	var local_background: Dictionary = QuickCustom.create("backgrounds", "Portable " + stamp,
		"Descrizione trasportabile", [{"kind": "skill", "key": "arcana"}])
	assert(not local_background.is_empty())
	var custom_feat: Dictionary = QuickCustom.create("feats", "Portable Feat " + stamp,
		"Talento trasportabile", [{"kind": "tool", "key": "thieves' tools"}])
	assert(not custom_feat.is_empty())
	var custom_item: Dictionary = QuickCustom.create("items", "Portable Item " + stamp,
		"Oggetto trasportabile", [], {
		"type": "OTH", "custom_item_type": "magic", "rarity": "rare", "value": 250})
	assert(not custom_item.is_empty())
	var prof_record: Dictionary = {"kind": "character",
		"background": local_background.name, "background_source": "Personalizzato",
		"feats_catalog": [{"id": custom_feat.id, "name": custom_feat.name,
			"source": "Personalizzato"}]}
	var selected: Array[Dictionary] = Proficiencies.choices(prof_record)
	assert(Proficiencies.has_choice(selected, "skill", "arcana"))
	assert(Proficiencies.has_choice(selected, "tool", "thieves' tools"))
	var item_definition: Dictionary = {}
	for entry: Dictionary in Catalog.home_entries("items"):
		if String(entry.get("id", "")) == String(custom_item.id):
			item_definition = entry
	assert(ItemRules.kind(item_definition) == "magic"
		and int(item_definition.get("value", 0)) == 250,
		"Custom item fields must load through the normal catalog")
	var item_instance: Dictionary = Instances.from_catalog(item_definition)
	assert(String(item_instance.get("rarity", "")) == "rare"
		and int(item_instance.get("value", 0)) == 250)
	# Explicitly send a single unequipped copy, including its homebrew
	# definitions, to just one of the two online recipients.
	item_instance["quantity"] = 6
	item_instance["equipped"] = true
	item_instance["equipped_slots"] = ["main"]
	tab._inventory.append(item_instance.duplicate(true))
	tab.call("_refresh_inventory", tab._inventory.size() - 1)
	assert(not (tab.get("_item_share_button") as Button).disabled)
	(tab.get("_item_share_button") as Button).pressed.emit()
	assert(item_deliveries.is_empty(), "Opening an item share must not broadcast")
	var item_dialog: ConfirmationDialog
	for child: Node in tab.get_children():
		if child is ConfirmationDialog and child.title == "Invia oggetto: scegli destinatari":
			item_dialog = child
	assert(item_dialog != null and item_dialog.get_ok_button().disabled)
	var item_checks := item_dialog.find_children("*", "CheckBox", true, false)
	assert(item_checks.size() == 2)
	(item_checks[0] as CheckBox).button_pressed = true
	item_dialog.hide()
	item_dialog.confirmed.emit()
	await process_frame
	assert(item_deliveries.size() == 1 and item_deliveries[0].recipient == "person_one")
	for sent: Dictionary in item_deliveries:
		assert(int(sent.item.quantity) == 1 and not bool(sent.item.equipped)
			and not (sent.definitions as Array).is_empty(),
			"Shared homebrew items must arrive as one unequipped copy with definitions")
	assert(int(tab._inventory[tab._inventory.size() - 1].quantity) == 6,
		"Sending a copy must not change the sender's stack")
	var arriving: Dictionary = item_deliveries[0]
	assert(ItemInbox.receive({
		"id": "inventory_transfer_" + stamp, "sender_id": "person_one",
		"item": arriving.item, "definitions": arriving.definitions
	}))
	# Mimic another device without the source definition.
	assert(QuickCustom.remove(custom_feat) and QuickCustom.remove(custom_item))
	tab.call("receive_item")
	assert(ItemInbox.pending().is_empty())
	assert(tab._inventory.size() == 4 and not bool(tab._inventory[-1].equipped)
		and String(tab._inventory[-1].id) == String(custom_item.id),
		"Incoming item must append to the inventory without equipping itself")
	assert(Catalog.home_entries("items").any(func(entry: Dictionary) -> bool:
		return String(entry.get("id", "")) == String(custom_item.id)),
		"Receiving homebrew item must install the missing definition")
	assert(QuickCustom.remove(custom_item), "Imported quick-created item must still be removable")
	portable_record["background_id"] = local_background.id
	portable_record["background"] = local_background.name
	assert(PortableContent.unresolved(portable_record).is_empty(),
		"Valid local homebrew references must all be exportable")
	portable_record["additional_item_id"] = "homebrew:quick_local:items:missing_definition"
	assert(PortableContent.unresolved(portable_record) == [
		"homebrew:quick_local:items:missing_definition"],
		"Export must detect missing local dependencies instead of silently omitting them")
	portable_record.erase("additional_item_id")
	var bundled: Array[Dictionary] = PortableContent.bundle(portable_record)
	var ids: Array[String] = []
	for entry: Dictionary in bundled:
		ids.append(String(entry.get("id", "")))
	assert(identifier in ids and String(local_background.id) in ids
		and bundled.size() == 2, "Only directly used homebrew records must travel")
	var conflicting_bundle: Array[Dictionary] = bundled.duplicate(true)
	var conflicting_data: Dictionary = conflicting_bundle[0]["data"]
	conflicting_data["description"] = "A DIFFERENT DEFINITION FOR THE SAME STABLE ID"
	assert(PortableContent.install(conflicting_bundle) == ERR_ALREADY_EXISTS,
		"Import must refuse an existing ID with conflicting homebrew content")
	assert(PortableContent.install(bundled) == OK,
		"Import must accept identical definitions without creating duplicates")
	assert(QuickCustom.remove(local_background))
	assert(PortableContent.install(bundled) == OK,
		"On a second device, import must restore missing homebrew by its stable ID")
	var restored := false
	for local: Dictionary in Catalog.home_entries("backgrounds"):
		if String(local.get("id", "")) == String(local_background.id):
			restored = String(local.get("description", "")) == "Descrizione trasportabile"
	assert(restored, "Restored background must have its description and original ID")
	var invalid: Array = [{"id": "homebrew:bad:backgrounds:../../unsafe",
		"name": "Unsafe", "data": {}}]
	assert(PortableContent.install(invalid) == ERR_INVALID_DATA,
		"Imported definition IDs must not create arbitrary filesystem paths")
	var local_parts: PackedStringArray = String(local_background.id).split(":")
	var imported_path := PortableContent.IMPORT_DIR.path_join(local_parts[1]).path_join(
		local_parts[2] + "_" + local_parts[3] + ".json")
	assert(FileAccess.file_exists(imported_path))
	assert(QuickCustom.remove(local_background),
		"Imported quick-created backgrounds must remain deletable by the user")
	assert(not FileAccess.file_exists(imported_path))
	Catalog.reload_homebrew()

	# Regression: ItemList's prior selection must not index the replacement
	# inventory while switching from a creature with documents to one without.
	var documents_tab: Node = tab._documents_tab
	var document_list: ItemList = documents_tab.get("_list")
	assert(document_list.item_count == 2)
	document_list.select(0)
	documents_tab.call("load_inventory", [])
	assert(document_list.item_count == 0
		and document_list.get_selected_items().is_empty()
		and (documents_tab.get("_indices") as Array).is_empty(),
		"Switching to an empty inventory clears stale document selection")
	documents_tab.call("_refresh_list")
	documents_tab.call("load_inventory", [row])
	assert(document_list.item_count == 1
		and int(documents_tab.call("_selected_inventory_index")) == 0,
		"Documents can be selected again after an empty inventory")
	documents_tab.call("load_inventory", [])

	# Catch the regressions that were invisible to the transport tests:
	# narrow inventory width, a readable document body editor and a
	# bounded modal with usable native action buttons.
	root.gui_embed_subwindows = true
	root.set_meta("vtt_touch_layout", true)
	root.size = Vector2i(360, 640)
	tab.configure_touch_layout()
	# Reconfiguring an already compact screen must not dereference old
	# HBox nodes or assume the first document child is still its toolbar.
	tab.configure_touch_layout()
	assert(documents_tab.get_node_or_null("DocumentsToolbar") is HFlowContainer,
		"Touch layout must reflow the real document toolbar exactly once")
	tab.size = Vector2(360, 600)
	await process_frame
	assert(tab.get_combined_minimum_size().x <= 360,
		"Inventory content must not widen its phone-sized sheet")
	documents_tab.call("load_inventory", [row])
	var open_document_button := documents_tab.get("_open_button") as Button
	assert(not open_document_button.disabled)
	open_document_button.pressed.emit()
	await process_frame
	documents_tab.call("_toggle_editor", true)
	await process_frame
	var editor: TextEdit = documents_tab.get("_body_edit") as TextEdit
	var preview: TextureRect = documents_tab.get("_full_image") as TextureRect
	var edit_dialog: AcceptDialog = documents_tab.get("_dialog") as AcceptDialog
	assert(editor.is_visible_in_tree() and editor.virtual_keyboard_enabled
		and not preview.visible,
		"On mobile the full-width multiline editor replaces the preview")
	assert(edit_dialog.position.x >= 0 and edit_dialog.position.y >= 0
		and edit_dialog.position.x + edit_dialog.size.x <= root.size.x
		and edit_dialog.position.y + edit_dialog.size.y <= root.size.y,
		"Document editing popup must remain inside the mobile screen")
	editor.text = "Corpo documento modificabile\nSeconda riga"
	editor.text_changed.emit()
	var save_timer: Timer = documents_tab.get("_autosave_timer") as Timer
	assert(save_timer != null and not save_timer.is_stopped(),
		"Document editor must use one reusable debounce timer while typing")
	documents_tab.call("_flush_edit")
	assert(save_timer.is_stopped(), "Manual save must cancel a pending autosave")
	assert(String(Documents.definition_for(row).get("description", "")) ==
		"Corpo documento modificabile\nSeconda riga",
		"Mobile multiline document edits must persist")
	edit_dialog.hide()
	documents_tab.call("load_inventory", [])
	tab.queue_free()
	await process_frame

	var legacy_path: String = Documents.ROOT_DIR.path_join(
		String(migrated.get("id", "")).trim_prefix(Documents.OWN_PREFIX) + ".json"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(document_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	Catalog.reload_homebrew()
	print("PASS: homebrew Documents definitions, live item date/style, rename and legacy migration")
	quit()
