extends SceneTree

const Inbox = preload("res://vtt/document_inbox.gd")
const Documents = preload("res://vtt/document_homebrew.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Isolate this test from existing user data. If interrupted, the original
	# inbox remains recoverable at the uniquely named backup path.
	var path: String = ProjectSettings.globalize_path(Inbox.PATH)
	var backup: String = path + ".test_backup_" + str(Time.get_ticks_usec())
	var had_inbox := FileAccess.file_exists(path)
	if had_inbox:
		assert(DirAccess.rename_absolute(path, backup) == OK)
	var failures: Array[String] = []
	var broken := FileAccess.open(path, FileAccess.WRITE)
	if broken == null:
		failures.append("Could not prepare malformed inbox fixture")
	else:
		broken.store_string("{invalid JSON")
		broken.close()
		if Inbox.receive({"id": "should-not-overwrite", "title": "New"}):
			failures.append("Malformed inbox must reject new packets")
		if FileAccess.get_file_as_string(path) != "{invalid JSON":
			failures.append("Rejecting a packet must preserve the malformed inbox")
	var rows: Array[Dictionary] = []
	for index: int in range(Inbox.MAX_DOCUMENTS):
		rows.append({"id": "capacity_%d" % index, "title": "Retained"})
	if not Inbox._write(rows):
		failures.append("Could not prepare full inbox fixture")
	else:
		if Inbox.receive({"id": "overflow", "title": "Do not evict"}):
			failures.append("Full inbox must reject new deliveries")
		var actual: Array[Dictionary] = Inbox.pending()
		if actual.size() != Inbox.MAX_DOCUMENTS or String(actual[0].get("id", "")) != "capacity_0":
			failures.append("Full inbox must preserve the first acknowledged delivery")
	if not Inbox._write([]):
		failures.append("Could not prepare acknowledgment fixture")
	var note := {"id": "safe-delivery", "title": "Keep until saved", "text": "Content"}
	if not Inbox.receive(note):
		failures.append("Could not queue document")
	if not Inbox.acknowledge_inventory([]) or Inbox.pending().size() != 1:
		failures.append("Unpersisted documents must remain in inbox")
	var legacy_id: String = Documents.legacy_id(note)
	if not Inbox.acknowledge_inventory([{"id": "some-other-item"}]) or Inbox.pending().size() != 1:
		failures.append("Unrelated inventory items must not acknowledge documents")
	if not Inbox.acknowledge_inventory([{"id": legacy_id}]) or not Inbox.pending().is_empty():
		failures.append("A confirmed saved inventory must acknowledge only owned documents")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if had_inbox and DirAccess.rename_absolute(backup, path) != OK:
		failures.append("Failed to restore original user inbox backup: " + backup)
	for failure: String in failures:
		push_error(failure)
	assert(failures.is_empty(), "Document safety regressions: " + "; ".join(failures))
	print("PASS: document inbox corruption, capacity and deferred acknowledgment")
	quit()
