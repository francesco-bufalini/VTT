extends SceneTree

const EncounterProgressController = preload(
	"res://encounter/encounter_progress_controller.gd"
)
const SealController = preload("res://encounter/seal_controller.gd")


func _initialize() -> void:
	if EncounterProgressController == null:
		push_error("Encounter sync: progress controller failed to preload")
		quit(1)
		return
	if SealController == null:
		push_error("Encounter sync: seal controller failed to preload")
		quit(1)
		return
	print("PASS: encounter sync animation scripts parse")
	quit()
