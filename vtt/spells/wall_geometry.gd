extends RefCounted


static func path_length(points: Array[Vector3]) -> float:
	var total: float = 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


static func clamp_endpoint(
	start: Vector3,
	target: Vector3,
	max_distance: float
) -> Vector3:
	if max_distance <= 0.0:
		return start
	var delta: Vector3 = target - start
	var distance: float = delta.length()
	if distance <= max_distance or distance <= 0.0001:
		return target
	return start + delta / distance * max_distance


static func angle_on_circle(center: Vector3, point: Vector3) -> float:
	var delta: Vector3 = point - center
	return atan2(delta.z, delta.x)


static func point_on_circle(
	center: Vector3,
	radius: float,
	angle: float
) -> Vector3:
	return center + Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)


static func project_to_circle(
	center: Vector3,
	point: Vector3,
	radius: float
) -> Vector3:
	var delta: Vector3 = point - center
	delta.y = 0.0
	if delta.length_squared() < 0.0001:
		delta = Vector3.RIGHT
	return center + delta.normalized() * radius


static func unwrap_delta(previous_angle: float, current_angle: float) -> float:
	return wrapf(
		current_angle - previous_angle,
		-PI,
		PI
	)


static func sample_arc(
	center: Vector3,
	radius: float,
	start_angle: float,
	sweep: float,
	min_segments: int = 4
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var fraction: float = clampf(absf(sweep) / TAU, 0.0, 1.0)
	var segment_count: int = maxi(
		min_segments,
		int(ceil(48.0 * fraction))
	)
	if absf(sweep) < 0.0001:
		segment_count = 1

	for index: int in range(segment_count + 1):
		var t: float = float(index) / float(maxi(segment_count, 1))
		points.append(
			point_on_circle(
				center,
				radius,
				start_angle + sweep * t
			)
		)
	return points


static func sample_full_circle(
	center: Vector3,
	radius: float
) -> Array[Vector3]:
	return sample_arc(center, radius, 0.0, TAU, 48)


static func serialize_points(points: Array[Vector3]) -> Array:
	var result: Array = []
	for point: Vector3 in points:
		result.append([point.x, point.y, point.z])
	return result


static func deserialize_points(value: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if not entry is Array:
			continue
		var data: Array = entry
		if data.size() != 3:
			continue
		result.append(
			Vector3(
				float(data[0]),
				float(data[1]),
				float(data[2])
			)
		)
	return result
