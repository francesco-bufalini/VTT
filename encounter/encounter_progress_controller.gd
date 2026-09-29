extends Node

signal state_changed
signal kaos_reached_klothis
signal phase_two_started
signal encounter_ended(reason: String)

@export var config: Resource = preload("res://encounter/encounter_config.gd").new()

var round_number: int = 0
var kaos_step: int = 10
var damage_since_last_advance: float = 0.0
var kaos_slowed: bool = false
var encounter_seed: int = 0
var encounter_finished: bool = false
var encounter_phase: int = 1
var giant_hp: float = 202.0
var avatar_hp: float = 200.0
var giant_petrified: bool = false
var end_reason: String = ""
var petrification: Node
var is_advancing: bool = false
var obstacle_coverage: float = 0.0
var obstacle_slowed: bool = false
const Coverage = preload("res://encounter/obstacle_coverage.gd")
var hazards: Node
var kaos: Node3D
var collapse: Node3D
var _area: Node3D
var _cell_size: float
var seals: Node

func register_seal_damage(index: int, amount: float) -> void:
	if not is_advancing and not encounter_finished and is_instance_valid(seals):
		seals.register_damage(index, amount)

func setup(hazard_controller: Node, kaos_controller: Node3D, effects: Node3D, area: Node3D, size: float) -> void:
	hazards = hazard_controller
	kaos = kaos_controller
	collapse = effects
	_area = area
	_cell_size = size
	petrification = preload("res://encounter/petrification.gd").new()
	kaos.add_child(petrification)
	seals.all_seals_broken.connect(func(): finish_encounter("Tutti i sigilli sono infranti"))
	reset_encounter()

func reset_encounter(seed_override: int = 0) -> bool:
	if is_advancing:
		return false
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.randomize()
	encounter_seed = seed_override if seed_override != 0 else int(config.encounter_seed)
	if encounter_seed == 0:
		encounter_seed = seed_rng.randi()
	round_number = 0
	kaos_step = 10
	damage_since_last_advance = 0
	kaos_slowed = false
	encounter_finished = false
	encounter_phase = 1
	giant_hp = config.giant_max_hp
	avatar_hp = config.avatar_max_hp
	giant_petrified = false
	end_reason = ""
	petrification.clear()
	if is_instance_valid(seals):
		seals.restore([0, 0, 0])
	hazards.initialize(config, _area, _cell_size, encounter_seed)
	hazards.generate_threats()
	kaos.snap_to_step(kaos_step)
	collapse.stop_effects()
	collapse.rebuild(hazards)
	refresh_obstacle_slowing()
	state_changed.emit()
	return true

func register_kaos_damage(amount: float) -> void:
	if encounter_finished or is_advancing or not is_finite(amount) or amount <= 0:
		return
	if giant_petrified:
		avatar_hp = maxf(0,avatar_hp-amount)
		if avatar_hp == 0:
			finish_encounter("Kaos sconfitto")
	else:
		var applied := minf(giant_hp,amount)
		giant_hp -= applied
		damage_since_last_advance += applied
		if giant_hp == 0:
			giant_petrified = true
			avatar_hp = config.avatar_max_hp
			encounter_phase = 2
			damage_since_last_advance = 0
			hazards.threatened_cells.clear()
			collapse.rebuild(hazards)
			petrification.apply()
			phase_two_started.emit()
			get_node("/root/EncounterEvents").phase_two_started.emit()
	refresh_obstacle_slowing()
	state_changed.emit()

func finish_encounter(reason: String) -> void:
	if encounter_finished:
		return
	encounter_finished = true
	end_reason = reason
	if get_parent().token_drag.active:
		get_parent().token_drag.finish(false)
	encounter_ended.emit(reason)
	get_node("/root/EncounterEvents").encounter_ended.emit(reason)
	state_changed.emit()

func pending_regeneration() -> float:
	return 0.0 if giant_petrified or giant_hp <= 0 else minf(config.regeneration_per_round,config.giant_max_hp-giant_hp)

func get_remaining_meters() -> int:
	return kaos_step * 15

func get_next_movement_meters() -> int:
	if giant_petrified or encounter_finished:
		return 0
	return mini(kaos_step, 1 if kaos_slowed else 2) * 15

func advance_encounter() -> void:
	if encounter_finished or is_advancing:
		return
	if get_parent().token_drag.active:
		return
	is_advancing = true
	var healed := pending_regeneration()
	giant_hp += healed
	damage_since_last_advance = maxf(0,damage_since_last_advance-healed)
	if kaos_step == 0 or giant_petrified:
		round_number += 1
		damage_since_last_advance = 0
		is_advancing = false
		refresh_obstacle_slowing()
		state_changed.emit()
		return
	var resolved: Array[Vector2i] = hazards.resolve_threats()
	collapse.rebuild(hazards, true)
	collapse.animate_collapse(resolved)
	refresh_obstacle_slowing()
	var movement_steps: int = 1 if damage_since_last_advance >= config.slow_damage_threshold or obstacle_slowed else 2
	kaos_step = maxi(0, kaos_step - movement_steps)
	round_number += 1
	state_changed.emit()
	await kaos.animate_to_step(kaos_step, config.advance_duration,round_number)
	damage_since_last_advance = 0
	kaos_slowed = false
	if kaos_step == 0:
		kaos_reached_klothis.emit()
		get_node("/root/EncounterEvents").kaos_reached_klothis.emit()
		state_changed.emit()
		await kaos.climb.start()
		encounter_phase = 2
	else:
		hazards.generate_threats()
	collapse.rebuild(hazards)
	is_advancing = false
	refresh_obstacle_slowing()
	state_changed.emit()

func refresh_obstacle_slowing() -> void:
	obstacle_coverage = Coverage.fraction(kaos.get_swept_bounds(kaos_step, maxi(0, kaos_step - 2)), collapse.get_obstacle_boxes(), config.obstacle_min_height_cells * _cell_size) if kaos_step > 0 else 0.0
	obstacle_slowed = obstacle_coverage >= config.obstacle_coverage_threshold
	kaos_slowed = not giant_petrified and kaos_step > 0 and (maxf(0,damage_since_last_advance-pending_regeneration()) >= config.slow_damage_threshold or obstacle_slowed)

# Saving during a transition is refused: no half-round snapshots.
func get_save_state() -> Dictionary:
	if is_advancing:
		return {}
	return {
		"version": 2, "round_number": round_number, "kaos_step": kaos_step,
		"giant_hp": giant_hp, "avatar_hp": avatar_hp, "giant_petrified": giant_petrified, "end_reason": end_reason,
		"avatar_position": [petrification.avatar.position.x,petrification.avatar.position.y,petrification.avatar.position.z] if giant_petrified else [],
		"avatar_rotation": petrification.avatar.rotation.y if giant_petrified else 0.0,
		"avatar_flying": petrification.avatar.flying if giant_petrified else false,
		"damage_since_last_advance": damage_since_last_advance, "kaos_slowed": kaos_slowed,
		"encounter_seed": str(encounter_seed), "rng_state": str(hazards.rng.state),
		"threatened_cells": hazards.serialize_cells(hazards.threatened_cells),
		"collapsed_cells": hazards.serialize_cells(hazards.collapsed_cells),
		"encounter_finished": encounter_finished,
		"encounter_phase": encounter_phase,
		"seal_damage": seals.damage.duplicate() if is_instance_valid(seals) else [0, 0, 0],
	}

func load_state(data: Dictionary) -> bool:
	if is_advancing or not _valid_state(data):
		return false
	petrification.clear()
	round_number = int(data.round_number)
	kaos_step = int(data.kaos_step)
	damage_since_last_advance = float(data.damage_since_last_advance)
	kaos_slowed = damage_since_last_advance >= config.slow_damage_threshold
	encounter_seed = int(data.encounter_seed)
	giant_hp = float(data.get("giant_hp",config.giant_max_hp))
	avatar_hp = float(data.get("avatar_hp",config.avatar_max_hp))
	giant_petrified = bool(data.get("giant_petrified",false))
	encounter_finished = bool(data.encounter_finished) if int(data.version) == 2 else false
	end_reason = str(data.get("end_reason",""))
	if is_instance_valid(seals):
		seals.restore(data.get("seal_damage", [0, 0, 0]))
	hazards.initialize(config, _area, _cell_size, encounter_seed)
	hazards.restore(data.threatened_cells, data.collapsed_cells, int(data.rng_state))
	kaos.snap_to_step(kaos_step)
	encounter_phase = 2 if kaos_step == 0 or giant_petrified else 1
	if kaos_step == 0:
		kaos.climb.restore_phase_two()
	if giant_petrified:
		petrification.apply(false)
		var pos: Array = data.get("avatar_position",[])
		if pos.size() == 3:
			petrification.avatar.position = Vector3(pos[0],pos[1],pos[2])
		petrification.avatar.rotation.y = float(data.get("avatar_rotation",0))
		petrification.avatar.set_flying(bool(data.get("avatar_flying",false)))
	collapse.stop_effects()
	collapse.rebuild(hazards)
	refresh_obstacle_slowing()
	state_changed.emit()
	return true

func _valid_state(data: Dictionary) -> bool:
	for key in ["version", "round_number", "kaos_step", "damage_since_last_advance", "encounter_seed", "rng_state", "threatened_cells", "collapsed_cells", "encounter_finished", "kaos_slowed"]:
		if not data.has(key):
			return false
	for key in ["version", "round_number", "kaos_step", "damage_since_last_advance"]:
		if not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
			return false
	for key in ["version", "round_number", "kaos_step"]:
		if float(data[key]) != floor(float(data[key])):
			return false
	for key in ["encounter_seed", "rng_state"]:
		if not (data[key] is String and data[key].is_valid_int()):
			return false
	if not data.encounter_finished is bool or not data.kaos_slowed is bool:
		return false
	if int(data.version) not in [1,2] or int(data.kaos_step) < 0 or int(data.kaos_step) > 10 or int(data.round_number) < 0:
		return false
	if not is_finite(float(data.damage_since_last_advance)) or float(data.damage_since_last_advance) < 0:
		return false
	if int(data.version) == 2:
		for key in ["giant_hp","avatar_hp","giant_petrified","end_reason","avatar_position","avatar_rotation","avatar_flying"]:
			if not data.has(key):
				return false
		for key in ["giant_hp","avatar_hp","avatar_rotation"]:
			if not (data[key] is int or data[key] is float) or not is_finite(float(data[key])):
				return false
		if not data.giant_petrified is bool or not data.avatar_flying is bool or not data.end_reason is String:
			return false
		if data.giant_hp < 0 or data.giant_hp > config.giant_max_hp or data.avatar_hp < 0 or data.avatar_hp > config.avatar_max_hp or data.giant_petrified != (data.giant_hp == 0):
			return false
		if not data.avatar_position is Array or data.avatar_position.size() != (3 if data.giant_petrified else 0):
			return false
		for coordinate in data.avatar_position:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return false
	if not data.threatened_cells is Array or not data.collapsed_cells is Array:
		return false
	var seal_values: Variant = data.get("seal_damage", [0, 0, 0])
	if not seal_values is Array or seal_values.size() != 3:
		return false
	for value in seal_values:
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0 or float(value) > 100:
			return false
	if int(data.version) == 2:
		var ended: bool = (data.giant_petrified and data.avatar_hp == 0) or seal_values.all(func(value): return float(value)>=seals.break_damage)
		if data.encounter_finished != ended:
			return false
		if data.giant_petrified and not data.threatened_cells.is_empty():
			return false
	if int(data.kaos_step) == 0 and not data.threatened_cells.is_empty():
		return false
	var seen: Dictionary = {}
	for list in [data.threatened_cells, data.collapsed_cells]:
		if not list is Array:
			return false
		for pair in list:
			if not pair is Array or pair.size() != 2:
				return false
			for coordinate in pair:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or float(coordinate) != floor(float(coordinate)):
					return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if not _area.contains_cell(cell) or seen.has(cell):
				return false
			seen[cell] = true
	return true

func save_to_file(path: String = "user://kaos_encounter.json") -> Error:
	var data := get_save_state()
	if data.is_empty():
		return ERR_BUSY
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	return OK

func load_from_file(path: String = "user://kaos_encounter.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_state(parsed) if parsed is Dictionary else false
