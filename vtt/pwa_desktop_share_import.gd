extends RefCounted
# Native receiver for the PWA's existing bounded, explicitly accepted transfers.
# Creature copies use the desktop archive; item stacks enter its durable inbox.
const Archive = preload("res://vtt/creature_archive.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")
const ItemInbox = preload("res://vtt/item_inbox.gd")

static func import_received(kind: String, payload: Variant, transfer_id: String) -> Error:
	if not payload is Dictionary or transfer_id.length() != 32 or not transfer_id.is_valid_hex_number():
		return ERR_INVALID_DATA
	var package: Dictionary = payload
	if kind == "creature":
		var archive = Archive.new()
		archive.setup()
		if package.get("format") == "vtt_creature_batch_export_v1":
			return archive.import_export_batch(package)
		return archive.import_export_copy(package)
	if kind == "homebrew":
		if package.get("format") != "vtt_homebrew_share_v1" or package.get("version") != 1:
			return ERR_INVALID_DATA
		return PortableContent.install(package.get("definitions"))
	if kind != "inventory" or package.get("format") != "vtt_inventory_export_v1" or package.get("version") != 1:
		return ERR_INVALID_DATA
	var rows: Variant = package.get("items", null)
	var definitions: Variant = package.get("definitions", null)
	if not rows is Array or rows.is_empty() or rows.size() > 200 or not definitions is Array:
		return ERR_INVALID_DATA
	if ItemInbox.pending().size() + rows.size() > 200:
		return ERR_OUT_OF_MEMORY
	for value: Variant in rows:
		if not value is Dictionary:
			return ERR_INVALID_DATA
		var item: Dictionary = value
		if String(item.get("name", "")).strip_edges().is_empty() and String(item.get("id", "")).strip_edges().is_empty():
			return ERR_INVALID_DATA
		var quantity: Variant = item.get("quantity", 1)
		if not quantity is int and not quantity is float:
			return ERR_INVALID_DATA
		if int(quantity) < 1 or int(quantity) > 99999 or float(quantity) != float(int(quantity)):
			return ERR_INVALID_DATA
	var installed: Error = PortableContent.install(definitions)
	if installed != OK:
		return installed
	# This inbox is not tied to whichever creature happens to be open on the
	# host. It is imported only when the native inventory next consumes it.
	for i: int in range(rows.size()):
		var item: Dictionary = (rows[i] as Dictionary).duplicate(true)
		if String(item.get("id", "")).strip_edges().is_empty():
			item["id"] = "pwa_received_" + transfer_id + "_" + str(i)
		if String(item.get("name", "")).strip_edges().is_empty():
			item["name"] = String(item["id"])
		item["container_id"] = "backpack"
		item["equipped"] = false
		item["equipped_slots"] = []
		item["attuned"] = false
		item["attuned_count"] = 0
		var delivery := {"id": "pwa_" + transfer_id + "_" + str(i),
			"item": item, "definitions": []}
		if not ItemInbox.receive(delivery):
			return ERR_CANT_CREATE
	return OK
