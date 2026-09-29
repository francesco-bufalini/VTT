extends RefCounted

func build(root: Node3D, units: float, material: Material) -> void:
	var worn_stone := ShaderMaterial.new()
	worn_stone.shader = preload("res://encounter/worn_stone.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(worn_stone,"dark_rock")
	material = worn_stone
	var column := CylinderMesh.new()
	column.top_radius = 2.5
	column.bottom_radius = 3.0
	column.height = 29
	column.radial_segments = 16
	var capital := BoxMesh.new()
	capital.size = Vector3(8, 3, 9)
	var ledge := BoxMesh.new()
	ledge.size = Vector3(35, 5, 16)
	var arch := _arch_mesh()
	var transforms: Array[Transform3D] = []
	for row in range(10):
		for index in range(38):
			if row > 2 and (index * 17 + row * 7) % 19 < 3:
				continue
			var angle := PI * 0.88 + float(index) / 37 * PI * 1.16
			var radius := 310 + row * 8
			var basis := Basis(Vector3.UP, -angle - PI / 2).scaled(Vector3.ONE * units)
			var center := Vector3(cos(angle) * radius, row * 43, sin(angle) * radius - 60) * units
			transforms.append(Transform3D(basis, center))
	_batch(root, "FlutedColumns", column, transforms, Vector3(0, 14.5, 0), material)
	_batch(root, "Capitals", capital, transforms, Vector3(0, 30, 0), material)
	_batch(root, "RomanArches", arch, transforms, Vector3(11, 30, 0), material)
	_batch(root, "Cornices", ledge, transforms, Vector3(10, 42, 0), material)
	var plinth := BoxMesh.new()
	plinth.size = Vector3(8,4,10)
	_batch(root,"ColumnPlinths",plinth,transforms,Vector3(0,2,0),material)
	_back_wall(root, units)

func _back_wall(root: Node3D, units: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(128):
		var a := PI*0.88 + float(index)/128*PI*1.16
		var b := PI*0.88 + float(index+1)/128*PI*1.16
		var points: Array[Vector3] = [Vector3(cos(a)*395,0,sin(a)*395-60),Vector3(cos(b)*395,0,sin(b)*395-60),Vector3(cos(b)*395,440,sin(b)*395-60),Vector3(cos(a)*395,440,sin(a)*395-60)]
		for corner in [0,1,2,0,2,3]:
			surface.add_vertex(points[corner]*units)
	surface.generate_normals()
	var wall := MeshInstance3D.new()
	wall.name = "ContinuousApseWall"
	wall.mesh = surface.commit()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.13,0.145,0.15)
	stone.roughness = 1.0
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall.material_override = stone
	root.add_child(wall)

func _batch(root: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], offset: Vector3, material: Material) -> void:
	var batch := MultiMeshInstance3D.new()
	batch.material_override = material
	batch.name = label
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		var transform := transforms[index]
		transform.origin += transform.basis * offset
		batch.multimesh.set_instance_transform(index, transform)
	root.add_child(batch)

func _arch_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(20):
		var a := PI * segment / 20
		var b := PI * (segment + 1) / 20
		var corners: Array[Vector3] = []
		for z in [-2.0, 2.0]:
			for radius in [9.0, 11.0]:
				for angle in [a, b]:
					corners.append(Vector3(cos(angle) * radius, sin(angle) * radius, z))
		for face: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			for vertex in [0, 1, 2, 0, 2, 3]:
				surface.add_vertex(corners[face[vertex]])
	surface.generate_normals()
	return surface.commit()
