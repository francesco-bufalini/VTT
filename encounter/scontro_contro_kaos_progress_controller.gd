extends "res://encounter/encounter_progress_controller.gd"

const LOCAL_SAVE_PATH := "user://scontro_contro_kaos.json"


func _should_end_on_all_seals_broken() -> bool:
	return false


func reset_encounter(seed_override: int = 0) -> bool:
	var reset_ok := super.reset_encounter(seed_override)
	if not reset_ok:
		return false
	_force_phase_two_start()
	return true


func _force_phase_two_start() -> void:
	round_number = 1
	kaos_step = 0
	damage_since_last_advance = 0.0
	kaos_slowed = false
	obstacle_slowed = false
	obstacle_coverage = 0.0
	encounter_finished = false
	encounter_phase = 2
	giant_hp = config.giant_max_hp
	avatar_hp = config.avatar_max_hp
	giant_petrified = false
	end_reason = ""

	hazards.threatened_cells.clear()
	collapse.stop_effects()
	collapse.rebuild(hazards)

	# Skip the whole approach/climb sequence and restore exactly the pose
	# reached by Encounter when Kaos has completed the climb onto the sphere.
	kaos.climb.restore_phase_two()
	refresh_obstacle_slowing()
	state_changed.emit()


func _valid_state(data: Dictionary) -> bool:
	if not super._valid_state(data):
		return false
	# This campaign has no phase 1. Refuse snapshots from the original
	# Encounter that would put Kaos back on the approach path.
	return int(data.get("kaos_step", -1)) == 0


func save_to_file(path: String = LOCAL_SAVE_PATH) -> Error:
	return super.save_to_file(path)


func load_from_file(path: String = LOCAL_SAVE_PATH) -> bool:
	return super.load_from_file(path)
