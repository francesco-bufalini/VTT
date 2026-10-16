extends RefCounted

# View-independent decisions shared by desktop 2D/3D and remote/mobile input.
# The caller chooses the candidate; this module never raycasts or draws.
# Distinct spells decide their own target exclusions and phase transitions.
const ReachGeometry = preload("res://vtt/flanking_system.gd")


static func token_in_range(
	source: Node3D,
	candidate: Node3D,
	range_feet: float,
	cell_size: float,
	exclude_source: bool = true
) -> Dictionary:
	if (
		source == null or not is_instance_valid(source)
		or candidate == null or not is_instance_valid(candidate)
		or (exclude_source and source == candidate)
	):
		return {"valid": false}
	var feet: float = ReachGeometry.token_tactical_distance_feet(
		source, candidate, cell_size
	)
	if feet > range_feet + 0.001:
		return {
			"valid": false, "out_of_range": true,
			"target": candidate, "distance_feet": int(round(feet))
		}
	return {"valid": true, "target": candidate}


static func point_in_range(
	origin: Vector3,
	point: Vector3,
	range_feet: float,
	cell_size: float
) -> Dictionary:
	var safe_cell: float = maxf(cell_size, 0.001)
	var distance: float = origin.distance_to(point)
	if distance > range_feet / 5.0 * safe_cell + safe_cell * 0.01:
		return {
			"valid": false, "out_of_range": true,
			"point": point, "distance_feet": int(round(distance / safe_cell * 5.0))
		}
	return {"valid": true, "point": point}


static func excludes_caster(spell_data: Dictionary) -> bool:
	var mode: String = String(spell_data.get("target_mode", ""))
	var description: String = String(spell_data.get("description", "")).to_lower()
	return (
		mode in ["self_token", "token_then_direction"]
		or "other than you" in description
		or "other than yourself" in description
		or "excluding you" in description
	)


static func filter_affected(
	candidates: Array,
	caster: Node3D,
	spell_data: Dictionary
) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var exclude: bool = excludes_caster(spell_data)
	for value: Variant in candidates:
		if not value is Node3D:
			continue
		var token: Node3D = value as Node3D
		if (
			token == null or not is_instance_valid(token)
			or (exclude and caster != null and token == caster)
		):
			continue
		result.append(token)
	return result
