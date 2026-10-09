extends RefCounted

# Geometry-only fallback for spell targeting; no scene state or casting side effects.
# The caller supplies its current cell size and slot-adjusted sphere radius.

static func contains_point(
	point: Vector3,
	start: Vector3,
	end: Vector3,
	shape: String,
	spell_data: Dictionary,
	cell_size: float,
	effective_radius_feet: float
) -> bool:
	var tolerance: float = cell_size * 0.45

	match shape:
		"sphere":
			var radius: float = (
				effective_radius_feet
				/ 5.0
				* cell_size
			)
			return point.distance_to(start) <= radius + tolerance

		"cube":
			var half_side: float = (
				float(spell_data.get("aoe_side_feet", 10.0))
				* 0.5
				/ 5.0
				* cell_size
			)
			var delta: Vector3 = point - start
			return (
				absf(delta.x) <= half_side + tolerance
				and absf(delta.y) <= half_side + tolerance
				and absf(delta.z) <= half_side + tolerance
			)

		"flat_square":
			var half_square: float = (
				float(spell_data.get("aoe_side_feet", 10.0))
				* 0.5
				/ 5.0
				* cell_size
			)
			var flat_delta: Vector3 = point - start
			return (
				absf(flat_delta.x) <= half_square + tolerance
				and absf(flat_delta.z) <= half_square + tolerance
				and absf(flat_delta.y) <= cell_size * 1.5
			)

		"cylinder":
			var radius_world: float = (
				float(spell_data.get("aoe_radius_feet", 5.0))
				/ 5.0
				* cell_size
			)
			var height_world: float = (
				float(spell_data.get("aoe_height_feet", 5.0))
				/ 5.0
				* cell_size
			)
			var cylinder_delta: Vector3 = point - start
			var horizontal: Vector2 = Vector2(
				cylinder_delta.x,
				cylinder_delta.z
			)
			return (
				horizontal.length() <= radius_world + tolerance
				and cylinder_delta.y >= -tolerance
				and cylinder_delta.y <= height_world + tolerance
			)

		"line":
			var line_axis: Vector3 = end - start
			var line_length: float = line_axis.length()
			if line_length < 0.0001:
				return false
			var line_direction: Vector3 = line_axis / line_length
			var from_start: Vector3 = point - start
			var along: float = from_start.dot(line_direction)
			if along < -tolerance or along > line_length + tolerance:
				return false
			var closest: Vector3 = start + line_direction * clampf(
				along,
				0.0,
				line_length
			)
			var half_width: float = (
				maxf(
					float(spell_data.get("line_width_feet", 5.0)),
					5.0
				)
				* 0.5
				/ 5.0
				* cell_size
			)
			return point.distance_to(closest) <= half_width + tolerance

		"cone":
			var cone_axis: Vector3 = end - start
			var cone_length: float = cone_axis.length()
			if cone_length < 0.0001:
				return false
			var cone_direction: Vector3 = cone_axis / cone_length
			var cone_delta: Vector3 = point - start
			var cone_along: float = cone_delta.dot(cone_direction)
			if cone_along < -tolerance or cone_along > cone_length + tolerance:
				return false
			var radial_vector: Vector3 = (
				cone_delta - cone_direction * cone_along
			)
			# D&D cones are as wide at a given distance as that distance.
			return radial_vector.length() <= maxf(cone_along, 0.0) + tolerance

	return false


