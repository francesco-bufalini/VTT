extends SceneTree

const Catalog = preload("res://vtt/content_catalog.gd")
const Documents = preload("res://vtt/document_homebrew.gd")
const Instances = preload("res://vtt/item_instance.gd")
const Inventory = preload("res://vtt/creature_inventory_tab.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const QuickCustom = preload("res://vtt/quick_custom_catalog.gd")


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
	var tab := Inventory.new()
	root.add_child(tab)
	var record_delivery := func(recipient: String, document: Dictionary) -> String:
		deliveries.append({"recipient": recipient, "document": document.duplicate(true)})
		return "test_delivery_" + recipient
	var online_peers := func() -> Array[Dictionary]:
		return [{"id": "person_one", "label": "Giocatore uno"},
			{"id": "person_two", "label": "Giocatore due"}]
	tab.setup(func(items: Array) -> void: events.append(items.duplicate(true)),
		Callable(), Callable(), record_delivery, online_peers)
	tab.load_record({"inventory": [row], "documents": [legacy]})
	await process_frame
	await process_frame
	assert(tab._inventory.size() == 2)
	assert(events.size() > 0, "Migrated inventory must be published after loading")
	var migrated: Dictionary = tab._inventory[1]
	assert(migrated.get("id") == Documents.legacy_id(legacy))
	assert(migrated.get("display_style") == "lettera")
	assert(Documents.definition_for(migrated).get("description") == "Consegna originale")
	# Desktop right-click/mobile long-press use this same context action.
	# A single share should queue one sanitized copy for each online peer.
	var docs_tab: Node = tab._documents_tab
	var owned_document_list: ItemList = docs_tab.get("_list")
	owned_document_list.select(0)
	docs_tab.set("_share_index", 0)
	docs_tab.call("_share_selected_document")
	assert(deliveries.size() == 2)
	for delivery: Dictionary in deliveries:
		assert(String(delivery.document.title) == "Titolo modificato"
			and String(delivery.document.text) == "Nuovo contenuto"
			and String(delivery.document.id) == identifier,
			"Send current saved document definition, not an empty inventory snapshot")

	# Export only referenced homebrew, and preserve the document's body.
	var portable_record: Dictionary = {"kind": "character", "inventory": [row]}
	var local_background: Dictionary = QuickCustom.create("backgrounds", "Portable " + stamp,
		"Descrizione trasportabile", [{"kind": "skill", "key": "arcana"}])
	assert(not local_background.is_empty())
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
	assert(PortableContent.install(bundled) == OK,
		"Import must skip existing definitions without creating duplicates")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(imported_path))
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
