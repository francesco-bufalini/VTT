extends SceneTree
const Inbox = preload("res://vtt/document_inbox.gd")
const Documents = preload("res://vtt/document_homebrew.gd")
func _initialize() -> void:
	var rows: Array[Dictionary] = []
	for index: int in range(Inbox.MAX_DOCUMENTS):
		rows.append({"id": "safety_%d" % index, "title": "Saved", "text": "Preserve me"})
	assert(Inbox._write(rows))
	assert(not Inbox.receive({"id": "overflow", "title": "New"}))
	assert(Inbox.pending() == rows, "A full inbox must preserve all acknowledged deliveries")
	assert(Inbox.receive(rows[0]), "Retries must succeed even when full")
	assert(Inbox.acknowledge_inventory([{"id": Documents.legacy_id(rows[0])}]))
	assert(Inbox.pending().size() == Inbox.MAX_DOCUMENTS - 1)
	assert(Inbox.receive({"id": "overflow", "title": "New"}))
	var file := FileAccess.open(Inbox.PATH, FileAccess.WRITE)
	file.store_string("broken original inbox")
	file.close()
	assert(not Inbox.receive({"id": "new", "title": "New"}))
	assert(FileAccess.get_file_as_string(Inbox.PATH) == "broken original inbox")
	assert(Inbox._write([]))
	print("PASS: inbox capacity, retries, durable inventory acknowledgement and corrupt-file preservation")
	quit()
