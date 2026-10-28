extends SceneTree
const Archive = preload("res://vtt/creature_archive.gd")
class RecordingArchive extends Archive:
	var imported: Array[Dictionary] = []
	func import_export_copy(payload: Dictionary) -> Error:
		imported.append(payload.duplicate(true))
		return OK
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var archive := RecordingArchive.new()
	var entries: Array = []
	for index: int in range(201):
		entries.append({"format":"vtt_creature_export_v1","version":1,
			"creature":{"id":"batch_%d" % index,"kind":"character","name":"Creatura %d" % index}})
	var payload := {"format":"vtt_creature_batch_export_v1","version":1,"entries":entries}
	assert(archive.import_export_batch(payload) == OK)
	assert(archive.imported.size() == 201, "All roots from a full archive must reach the existing importer")
	archive.imported.clear()
	entries[200].creature.name = ""
	assert(archive.import_export_batch(payload) == ERR_INVALID_DATA)
	assert(archive.imported.is_empty(), "Validate the last root before importing any entry")
	entries[200].creature.name = "Creatura 200"
	entries[0].creature.notes = "x".repeat(16 * 1024 * 1024)
	assert(archive.import_export_batch(payload) == ERR_INVALID_DATA)
	assert(archive.imported.is_empty(), "The portable byte bound still applies to large archives")
	print("PASS: full portable archives over 200 roots import with preflight validation and a 16 MiB bound")
	quit()
