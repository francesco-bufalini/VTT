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


# Sparse latitude/meridian lines describe the *surface* of a true 3D sphere.
# No triangles, solid fill or interior tint: tokens and terrain stay readable.
# The equator is a separate mesh to give each range a clearer silhouette.
static func sphere_wire_mesh(radius: float, segments: int = 64) -> ArrayMesh:
	var steps: int = maxi(24, segments)
	var distance: float = maxf(radius, 0.001)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for degrees: float in [-42.0, 0.0, 42.0]:
		var elevation: float = deg_to_rad(degrees)
		var plane_radius: float = cos(elevation) * distance
		var height: float = sin(elevation) * distance
		for index: int in range(steps):
			var a0: float = TAU * float(index) / float(steps)
			var a1: float = TAU * float(index + 1) / float(steps)
			surface.add_vertex(Vector3(cos(a0) * plane_radius, height, sin(a0) * plane_radius))
			surface.add_vertex(Vector3(cos(a1) * plane_radius, height, sin(a1) * plane_radius))
	# Full vertical great circles make the upper/lower hemispheres visible
	# from the side, rather than reducing the preview to a flat ground ring.
	for meridian: int in range(4):
		var azimuth: float = PI * float(meridian) / 4.0
		var direction := Vector2(cos(azimuth), sin(azimuth))
		for index: int in range(steps):
			var a0: float = TAU * float(index) / float(steps)
			var a1: float = TAU * float(index + 1) / float(steps)
			surface.add_vertex(Vector3(
				cos(a0) * direction.x * distance,
				sin(a0) * distance,
				cos(a0) * direction.y * distance
			))
			surface.add_vertex(Vector3(
				cos(a1) * direction.x * distance,
				sin(a1) * distance,
				cos(a1) * direction.y * distance
			))
	# Three true radii remain visible along the world axes, with the
	# same line primitive and material as the sphere surface.
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(axis * distance)
	return surface.commit()


# Luminous silhouettes for volume AoEs. These are purely decorative lines;
# the gameplay mesh and its existing collision/hit detection remain untouched.
static func _outline_segment(surface: SurfaceTool, start: Vector3, end: Vector3) -> void:
	surface.add_vertex(start)
	surface.add_vertex(end)


static func _outline_circle(
	surface: SurfaceTool, radius: float, center: Vector3,
	plane: int = 0, segments: int = 64
) -> void:
	for index: int in range(segments):
		var a0 := TAU * float(index) / float(segments)
		var a1 := TAU * float(index + 1) / float(segments)
		var v0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var v1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		if plane == 1:
			v0 = Vector3(v0.x, v0.z, 0.0)
			v1 = Vector3(v1.x, v1.z, 0.0)
		elif plane == 2:
			v0 = Vector3(0.0, v0.x, v0.z)
			v1 = Vector3(0.0, v1.x, v1.z)
		_outline_segment(surface, center + v0, center + v1)


static func area_outline_mesh(geometry: Dictionary) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	var shape := String(geometry.get("shape", "sphere"))
	var radius := maxf(float(geometry.get("radius", 0.5)), 0.001)
	var height := maxf(float(geometry.get("height", 1.0)), 0.001)
	match shape:
		"cube", "flat_square":
			var half: Vector3 = geometry.get("size", Vector3.ONE) * 0.5
			for iy: float in [-1.0, 1.0]:
				var y := iy * half.y
				var corners := [
					Vector3(-half.x, y, -half.z), Vector3(half.x, y, -half.z),
					Vector3(half.x, y, half.z), Vector3(-half.x, y, half.z)
				]
				for index: int in range(4):
					_outline_segment(surface, corners[index], corners[(index + 1) % 4])
			for ix: float in [-1.0, 1.0]:
				for iz: float in [-1.0, 1.0]:
					_outline_segment(surface,
						Vector3(ix * half.x, -half.y, iz * half.z),
						Vector3(ix * half.x, half.y, iz * half.z))
		"cone":
			_outline_circle(surface, radius, Vector3(0.0, height * 0.5, 0.0))
			for index: int in range(8):
				var angle := TAU * float(index) / 8.0
				_outline_segment(surface, Vector3(0.0, -height * 0.5, 0.0),
					Vector3(cos(angle) * radius, height * 0.5, sin(angle) * radius))
		"line", "cylinder":
			for iy: float in [-1.0, 1.0]:
				_outline_circle(surface, radius, Vector3(0.0, iy * height * 0.5, 0.0))
			for index: int in range(8):
				var angle := TAU * float(index) / 8.0
				var x := cos(angle) * radius
				var z := sin(angle) * radius
				_outline_segment(surface, Vector3(x, -height * 0.5, z),
					Vector3(x, height * 0.5, z))
		_:
			for plane: int in range(3):
				_outline_circle(surface, radius, Vector3.ZERO, plane)
	return surface.commit()


static func dimension_radii_mesh(geometry: Dictionary) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for point: Vector3 in dimension_radii_points(geometry):
		surface.add_vertex(point)
	return surface.commit()


static func dimension_radii_points(geometry: Dictionary) -> PackedVector3Array:
	var shape: String = String(geometry.get("shape", "sphere"))
	var extents := Vector3.ONE * float(geometry.get("radius", 0.5))
	if shape in ["cube", "flat_square"]:
		extents = (geometry.get("size", Vector3.ONE) as Vector3) * 0.5
	elif shape in ["cone", "cylinder", "line"]:
		extents.y = float(geometry.get("height", 1.0)) * 0.5
		if shape == "cone":
			extents.x *= 0.5
			extents.z *= 0.5
	var result := PackedVector3Array()
	for index: int in range(3):
		if shape == "flat_square" and index == 1:
			continue
		var endpoint := Vector3.ZERO
		endpoint[index] = extents[index]
		result.append(Vector3.ZERO)
		result.append(endpoint)
	return result


static func sphere_equator_mesh(radius: float, segments: int = 96) -> ArrayMesh:
	var steps: int = maxi(24, segments)
	var distance: float = maxf(radius, 0.001)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for index: int in range(steps):
		var a0: float = TAU * float(index) / float(steps)
		var a1: float = TAU * float(index + 1) / float(steps)
		surface.add_vertex(Vector3(cos(a0) * distance, 0.0, sin(a0) * distance))
		surface.add_vertex(Vector3(cos(a1) * distance, 0.0, sin(a1) * distance))
	return surface.commit()
