extends SceneTree

const EncounterProgressController = preload(
	"res://encounter/encounter_progress_controller.gd"
)
const SealController = preload("res://encounter/seal_controller.gd")
const EnvironmentCollapseController = preload(
	"res://encounter/environment_collapse_controller.gd"
)
const CollapseObject = preload("res://encounter/collapse_object.gd")
const Petrification = preload("res://encounter/petrification.gd")


func _initialize() -> void:
	for script: Script in [
		EncounterProgressController,
		SealController,
		EnvironmentCollapseController,
		CollapseObject,
		Petrification
	]:
		if script == null:
			push_error("Encounter sync: animation script failed to preload")
			quit(1)
			return
	print("PASS: encounter sync animation scripts parse")
	quit()
