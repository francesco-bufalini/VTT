extends RefCounted
## Four adjacent vertices: origin, length, width, and vertical height.
## The base is rectangular, freely positioned and rotated on a horizontal plane.

static func geometry(points: Array) -> Dictionary:
	if points.size() != 4:
		return {}
	var vertices: Array[Vector3] = []
	for value: Variant in points:
		if not value is Array or value.size() != 3:
			return {}
		for coordinate: Variant in value:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000.0:
				return {}
		vertices.append(Vector3(float(value[0]), float(value[1]), float(value[2])))
	var origin: Vector3 = vertices[0]
	var length: Vector3 = vertices[1] - origin
	var width: Vector3 = vertices[2] - origin
	var height: Vector3 = vertices[3] - origin
	if absf(length.y) > 0.0001 or absf(width.y) > 0.0001 or Vector2(height.x, height.z).length() > 0.0001:
		return {}
	if length.length() < 0.001 or width.length() < 0.001 or absf(height.y) < 0.001:
		return {}
	if absf(length.normalized().dot(width.normalized())) > 0.0001:
		return {}
	var x_axis: Vector3 = length.normalized()
	var z_axis: Vector3 = x_axis.cross(Vector3.UP)
	return {
		"shape": "parallelepiped",
		"position": origin + (length + width + height) * 0.5,
		"basis": Basis(x_axis, Vector3.UP, z_axis),
		"size": Vector3(length.length(), absf(height.y), width.length())
	}


static func intersects_cell(box: Dictionary, point: Vector3, tolerance: float) -> bool:
	if box.is_empty():
		return false
	var basis: Basis = box.basis
	var delta: Vector3 = point - Vector3(box.position)
	var half: Vector3 = Vector3(box.size) * 0.5
	if absf(delta.y) > half.y + tolerance:
		return false
	# Separating axes of the oriented base and the occupied world-grid cell.
	# Projecting the cell matters at diagonal edges: its corner can intersect
	# the box even when its centre is farther than half a cell from a face.
	for axis: Vector3 in [basis.x, basis.z, Vector3.RIGHT, Vector3.BACK]:
		var box_radius: float = half.x * absf(axis.dot(basis.x)) + half.z * absf(axis.dot(basis.z))
		var cell_radius: float = tolerance * (absf(axis.x) + absf(axis.z))
		if absf(delta.dot(axis)) > box_radius + cell_radius:
			return false
	return true


static func translated(points: Array, offset: Vector3) -> Array:
	var result: Array = []
	for value: Array in points:
		result.append([float(value[0]) + offset.x, float(value[1]) + offset.y, float(value[2]) + offset.z])
	return result


static func outline_mesh(size: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	var half: Vector3 = size * 0.5
	for axis: int in range(3):
		for first: float in [-1.0, 1.0]:
			for second: float in [-1.0, 1.0]:
				var point := Vector3.ZERO
				point[(axis + 1) % 3] = half[(axis + 1) % 3] * first
				point[(axis + 2) % 3] = half[(axis + 2) % 3] * second
				point[axis] = -half[axis]
				surface.add_vertex(point)
				point[axis] = half[axis]
				surface.add_vertex(point)
	return surface.commit()
