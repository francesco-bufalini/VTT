extends RefCounted

var root: Node3D
var units: float
var skin: Material
var cloth: Material
var gold: Material
var front: float

func build(parent: Node3D, scale_units: float, body: Material, marble: Material, trim: Material, luminous: bool) -> void:
	root = parent
	units = scale_units
	skin = body
	cloth = marble
	gold = trim
	front = 1.0 if luminous else -1.0
	_ellipsoid(Vector3(0, 94, 0), Vector3(12.5, 25, 7), skin)
	_ellipsoid(Vector3(0, 69, 0), Vector3(10, 12, 6.5), skin)
	_limb(Vector3(0, 112, 0), Vector3(0, 132, 0), 4, skin)
	_ellipsoid(Vector3(0, 140, 0), Vector3(7, 10, 6), skin)
	_ellipsoid(Vector3(0, 136, front * 4), Vector3(4, 4, 3), skin)
	for side in [-1.0, 1.0]:
		var shoulder := Vector3(side * 11, 113, 0)
		_ellipsoid(shoulder, Vector3(4, 5, 6), skin)
		var elbow := Vector3(side * 21, 103 if luminous else 90, front * 2)
		var hand := Vector3(side * 32, 118 if luminous else 68, front * 4)
		if not luminous and side > 0:
			elbow = Vector3(22, 106, -4)
			hand = Vector3(27, 128, -8)
		_limb(shoulder, elbow, 3.8, skin)
		_ellipsoid(elbow, Vector3.ONE * 3.5, skin)
		_limb(elbow, hand, 2.7, skin)
		_ellipsoid(hand, Vector3(2.8, 4.2, 1.5), skin)
		for finger in range(5):
			var start := hand + Vector3((finger - 2) * 1.05, 2.5, 0)
			_limb(start, start + Vector3((finger - 2) * 0.5, 5.0 - absf(finger - 2) * 0.6, front), 0.48, skin)
		_limb(Vector3(side * 6, 69, 0), Vector3(side * 7, 38, front), 5.5, skin)
		_limb(Vector3(side * 7, 38, front), Vector3(side * 8, 7, 0), 3.8, skin)
		_ellipsoid(Vector3(side * 8, 4, front * 5), Vector3(4, 4, 7), skin)
		_ellipsoid(Vector3(side * 2.5, 141, front * 5.5), Vector3(0.85, 0.4, 0.45), gold)
		_ring(hand, 3.3, 0.65, Vector3.ZERO, gold)
	_ring(Vector3(0, 74, 0), 10, 0.7, Vector3.ZERO, gold)
	_ring(Vector3(0, 125, 0), 5.4, 0.6, Vector3.ZERO, gold)
	_ring(Vector3(0, 139, -front * 3), 12, 0.45, Vector3(PI / 2, 0, 0), gold)
	for ray in range(16):
		var angle := TAU * ray / 16.0
		var radial := Vector3(cos(angle), sin(angle), 0)
		_limb(Vector3(0, 139, -front * 3) + radial * 11, Vector3(0, 139, -front * 3) + radial * (15 + ray % 3), 0.17, gold)
	_drapery()
	_hair()
	if luminous:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 105, 18) * units
		light.omni_range = 280 * units
		light.light_color = Color(1, 0.91, 0.73)
		light.light_energy = 2.0
		root.add_child(light)

func _instance(mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = point * units
	node.material_override = material
	root.add_child(node)
	return node

func _ellipsoid(point: Vector3, size: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 24
	mesh.rings = 12
	_instance(mesh, point, material).scale = size * units

func _limb(a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.72 * units
	mesh.bottom_radius = radius * units
	mesh.height = a.distance_to(b) * units
	mesh.radial_segments = 16
	_instance(mesh, (a + b) * 0.5, material).basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))

func _ring(point: Vector3, radius: float, thickness: float, rotation: Vector3, material: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = (radius - thickness) * units
	mesh.outer_radius = (radius + thickness) * units
	_instance(mesh, point, material).rotation = rotation

func _drapery() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Open pleated robe, leaving the cosmic legs visible through the front.
	for row in range(20):
		for column in range(48):
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(row + offset.y) / 20
				var angle := 0.55 + float(column + offset.x) / 48 * (TAU - 1.1)
				var radius := 10.0 + t * 9.0 + sin(angle * 18) * (0.3 + t * 0.8)
				var point := Vector3(sin(angle) * radius, 75 - t * 72 + sin(angle * 7) * t * 2, cos(angle) * radius * front)
				surface.add_vertex(point * units)
	surface.generate_normals()
	var node := _instance(surface.commit(), Vector3.ZERO, cloth)
	var material: StandardMaterial3D = cloth.duplicate()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	for side in [-1.0, 1.0]:
		_limb(Vector3(side * 9, 118, front * 4), Vector3(side * 7, 75, front * 9), 1.5, cloth)
		_ellipsoid(Vector3(side * 9, 117, front * 5), Vector3(2.5, 2.5, 1), gold)

func _hair() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strand in range(48):
		var angle := TAU * strand / 48.0
		for segment in range(20):
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(segment + offset.y) / 20
				var spread := sin(angle) * (7 + t * 20)
				var point := Vector3(spread + sin(t * 8 + strand) * t * 3 + (offset.x - 0.5) * (0.65 - t * 0.45), 147 - t * (44 + strand % 5 * 7), -front * (3 + t * 20) + cos(angle) * 3)
				surface.add_vertex(point * units)
	surface.generate_normals()
	var material: StandardMaterial3D = cloth.duplicate()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.75, 0.76, 0.70)
	_instance(surface.commit(), Vector3.ZERO, material)
