extends SceneTree

const Archive = preload("res://vtt/creature_archive.gd")
const Owner = preload("res://vtt/creature_owner.gd")

class TestCampaign extends Node:
	var selected_campaign_group_id := "test_archive_revision_audit"
	var active_campaign_id := ""

var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func run() -> void:
	var campaign := TestCampaign.new()
	campaign.selected_campaign_group_id += "_%d" % Time.get_ticks_usec()
	root.add_child(campaign)
	var archive := Archive.new()
	archive.setup(campaign)
	# Never touch a real user's unified archive during the regression.
	var isolated_path := "user://tests/archive_revision_%d/creatures.json" % Time.get_ticks_usec()
	archive._storage.path = isolated_path
	archive._characters.archive_path = isolated_path
	archive._monsters.archive_path = isolated_path
	for kind: String in ["character", "monster"]:
		var original: Dictionary = archive.create_character() if kind == "character" else archive.create_monster({"name": "Audit monster"})
		check(archive.save(original) == OK, "Initial sheet save failed")
		var outgoing: Dictionary = archive.relinquish(original, "remote-owner-0123456789")
		check(not outgoing.is_empty(), "Transfer failed")
		var returned: Dictionary = outgoing.duplicate(true)
		returned["recipient"] = Owner.local_id()
		returned.creature["owner_id"] = Owner.local_id()
		returned.creature["transfer_revision"] = 2
		returned.creature["name"] = "Returned sheet"
		check(archive.import_transfer(returned) == OK, "Return transfer failed")
		var records: Array[Dictionary] = [original]
		var storage_error: Error = archive._characters.save_characters(records) if kind == "character" else archive._monsters.save_creatures(records)
		check(storage_error == ERR_UNAUTHORIZED, "Legacy storage adapter accepted a stale sheet: " + kind)
		check(archive.save(original) == ERR_UNAUTHORIZED, "Stale sheet save rolled back transfer revision: " + kind)
		check(archive.relinquish(original, "another-owner-0123456789").is_empty(), "Stale sheet was transferred again: " + kind)
		check(archive.delete(original) == ERR_UNAUTHORIZED, "Stale sheet deleted a returned creature: " + kind)
		var stored: Dictionary = archive._stored(kind, String(original.id))
		check(stored.get("transfer_revision", -1) == 2, "Current revision was lost: " + kind)
		check(stored.get("name", "") == "Returned sheet", "Current data was overwritten: " + kind)
		check(archive.import_transfer(returned) == ERR_ALREADY_EXISTS, "Replayed transfer overwrote current sheet: " + kind)
		stored["kind"] = kind
		stored["name"] = "Current owner edit"
		check(archive.save(stored) == OK, "Current owner cannot edit the returned sheet: " + kind)
		check(archive.delete(stored) == OK, "Current owner cannot delete the returned sheet: " + kind)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path))
	campaign.free()
	if not failed:
		print("PASS: returned creature sheets reject stale saves, transfers, deletions and replay")
	quit(1 if failed else 0)