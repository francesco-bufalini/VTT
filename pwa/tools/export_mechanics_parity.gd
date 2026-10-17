extends SceneTree

const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://pwa/.test-artifacts/mechanics-cases.json"))
	if not cases is Array:
		quit(1)
		return
	var results: Array = []
	for entry: Dictionary in cases:
		var record: Dictionary = entry["record"]
		var values: Dictionary = {}
		for target: String in entry.get("targets", []):
			values[target] = Bonuses.value(record, target)
		results.append({"trackers": Trackers.for_creature(record), "values": values})
	var file := FileAccess.open("res://pwa/.test-artifacts/native-mechanics-parity.json", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(results))
	file.close()
	print("PASS: native resource and numeric formula fixtures exported")
	quit()
