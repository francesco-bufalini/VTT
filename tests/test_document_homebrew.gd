extends SceneTree

const Catalog = preload("res://vtt/content_catalog.gd")
const Documents = preload("res://vtt/document_homebrew.gd")
const Instances = preload("res://vtt/item_instance.gd")
const Inventory = preload("res://vtt/creature_inventory_tab.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const QuickCustom = preload("res://vtt/quick_custom_catalog.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const Inbox = preload("res://vtt/document_inbox.gd")
const Archive = preload("res://vtt/creature_archive.gd")
class TestCampaign extends Node:
	var selected_campaign_group_id := ""
	var active_campaign_id := ""


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
	(docs_tab.get_parent() as TabContainer).current_tab = 1
	await process_frame
	await process_frame
	owned_document_list.select(0)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = owned_document_list.get_item_rect(0).get_center()
	docs_tab.call("_on_document_input", right_click)
	assert(int(docs_tab.get("_share_index")) == 0,
		"Desktop right-click must select the clicked document for sharing")
	(docs_tab.get("_share_menu") as PopupMenu).hide()
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
	portable_record["inventory"] = [row, item_instance]
	portable_record["feats_catalog"] = prof_record["feats_catalog"].duplicate(true)
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
		and String(custom_feat.id) in ids and String(custom_item.id) in ids
		and bundled.size() == 4, "Every referenced background, feat, item and document must travel")
	assert(PortableContent.install(bundled) == OK,
		"Import must skip existing definitions without creating duplicates")
	var conflict: Array[Dictionary] = bundled.duplicate(true)
	conflict[0]["data"]["description"] = "Conflicting remote edit"
	assert(PortableContent.install(conflict) == ERR_ALREADY_EXISTS,
		"Conflicting stable IDs must reject import before replacing local content")
	assert(Documents.definition_for(row).get("description") == "Nuovo contenuto")
	assert(QuickCustom.remove(local_background))
	assert(QuickCustom.remove(custom_feat) and QuickCustom.remove(custom_item))
	assert(PortableContent.install(bundled) == OK,
		"On a second device, import must restore missing homebrew by its stable ID")
	var restored := false
	for local: Dictionary in Catalog.home_entries("backgrounds"):
		if String(local.get("id", "")) == String(local_background.id):
			restored = String(local.get("description", "")) == "Descrizione trasportabile"
	assert(restored, "Restored background must have its description and original ID")
	var restored_choices: Array[Dictionary] = Proficiencies.choices(prof_record)
	assert(Proficiencies.has_choice(restored_choices, "skill", "arcana")
		and Proficiencies.has_choice(restored_choices, "tool", "thieves' tools"),
		"Imported background and feat must retain their proficiency grants")
	var restored_item := false
	for entry: Dictionary in Catalog.home_entries("items"):
		if String(entry.get("id", "")) == String(custom_item.id):
			restored_item = ItemRules.kind(entry) == "magic" and int(entry.get("value", 0)) == 250
	assert(restored_item, "Imported item must retain type, value and stable identity")
	assert(QuickCustom.remove(custom_feat) and QuickCustom.remove(custom_item))
	# Exercise the same public import API as a selected desktop/Android JSON.
	var campaign := TestCampaign.new()
	campaign.selected_campaign_group_id = "test_portable_" + stamp
	root.add_child(campaign)
	var archive := Archive.new()
	archive.setup(campaign)
	portable_record["name"] = "Portable character"
	portable_record["id"] = "original_identity"
	var exported: Dictionary = {"format": "vtt_creature_export_v1", "version": 1,
		"creature": portable_record, "homebrew_content": bundled}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(exported))
	assert(archive.import_export_copy(decoded) == OK)
	var imported: Array[Dictionary] = archive.list_owned()
	assert(imported.size() == 1 and imported[0].id != "original_identity")
	assert(imported[0].inventory.size() == 2
		and imported[0].feats_catalog[0].id == custom_feat.id,
		"JSON import must persist owned items and homebrew feat references")
	var reopened := Archive.new()
	reopened.setup(campaign)
	assert(reopened.list_owned()[0].id == imported[0].id,
		"Imported creature must survive reopening its archive")
	assert(archive.delete(imported[0]) == OK)
	for store in [archive._characters, archive._monsters]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store._file_path()))
	campaign.queue_free()
	assert(QuickCustom.remove(custom_feat) and QuickCustom.remove(custom_item))
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
	var delivery: Dictionary = {"id": "durable_" + stamp, "title": "Durable", "text": "Keep until saved"}
	assert(Inbox.receive(delivery))
	tab.load_record({"id": "durable-character", "inventory": []})
	await process_frame
	await process_frame
	assert(Inbox.pending().size() == 1,
		"Publishing a UI change without a successful archive save must retain the inbox delivery")
	assert(tab._inventory.size() == 1)
	tab.load_record({"id": "durable-character", "inventory": tab._inventory.duplicate(true)})
	await process_frame
	assert(tab._inventory.size() == 1 and Inbox.pending().size() == 1,
		"Reloading a pending delivery must not duplicate its inventory document")
	assert(Inbox.acknowledge_inventory(tab._inventory))
	assert(Inbox.pending().is_empty())
	var delivery_path: String = Documents.ROOT_DIR.path_join(
		Documents.legacy_id(delivery).trim_prefix(Documents.OWN_PREFIX) + ".json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(delivery_path))
	tab.queue_free()
	await process_frame

	var legacy_path: String = Documents.ROOT_DIR.path_join(
		String(migrated.get("id", "")).trim_prefix(Documents.OWN_PREFIX) + ".json"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(document_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	Catalog.reload_homebrew()
	print("PASS: documents, custom background/feat/item JSON round-trip, persistence, conflicts, context menu and durable inbox")
	quit()
