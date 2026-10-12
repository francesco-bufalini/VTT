extends RefCounted

# A 2D contour of the Minkowski sum of a token's occupied footprint
# and its attack reach. Both the 2D HUD and the 3D ring use these points;
# this matches distance_from_footprint_to_point_world on a horizontal plane.
static func rounded_footprint_perimeter(
	half_footprint: float,
	radius: float,
	segments_per_corner: int = 20
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var half: float = maxf(0.0, half_footprint)
	var reach: float = maxf(0.001, radius)
	var segments: int = maxi(4, segments_per_corner)
	var corners: Array[Vector2] = [
		Vector2(half, half),
		Vector2(-half, half),
		Vector2(-half, -half),
		Vector2(half, -half)
	]
	for quadrant: int in range(4):
		var first_angle: float = float(quadrant) * PI * 0.5
		for step: int in range(segments + 1):
			var angle: float = first_angle + PI * 0.5 * float(step) / float(segments)
			result.append(corners[quadrant] + Vector2(cos(angle), sin(angle)) * reach)
	return result
