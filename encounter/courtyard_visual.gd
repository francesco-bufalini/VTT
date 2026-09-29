extends RefCounted

# Decorative continuation only: tactical bounds and collision remain unchanged.
func build(root: Node3D, units: float, marble: Material) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(4):
		var inner := 60.0 + ring * 67.0
		var outer := inner + 67.0
		for segment in range(180):
			var a := TAU * segment / 180.0
			var b := TAU * (segment + 1) / 180.0
			var points: Array[Vector3] = [Vector3(cos(a)*inner, -0.4, sin(a)*inner-60), Vector3(cos(b)*inner, -0.4, sin(b)*inner-60), Vector3(cos(b)*outer, -0.4, sin(b)*outer-60), Vector3(cos(a)*outer, -0.4, sin(a)*outer-60)]
			for index in [0, 2, 1, 0, 3, 2]:
				mesh.set_uv(Vector2(points[index].x, points[index].z) * 0.1)
				mesh.add_vertex(points[index] * units)
	mesh.generate_normals()
	mesh.generate_tangents()
	var floor := MeshInstance3D.new()
	floor.name = "ContinuousMarbleTerraces"
	floor.mesh = mesh.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://encounter/marble.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(material,"marble_01")
	floor.material_override = material
	root.add_child(floor)
	var play_surface := MeshInstance3D.new()
	play_surface.name = "TacticalMarbleSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(120,180)*units
	play_surface.mesh = plane
	play_surface.material_override = material
	play_surface.position = Vector3(0,-0.01,85*units)
	root.add_child(play_surface)
	# Low banks locate the playable area without filling it with decorative objects.
	for side in [-1.0, 1.0]:
		var bank := MeshInstance3D.new()
		bank.name = "BattlemapBank"
		var box := BoxMesh.new()
		box.size = Vector3(2, 0.35, 184) * units
		bank.mesh = box
		bank.material_override = marble
		bank.position = Vector3(side * 62, -0.1, 85) * units
		root.add_child(bank)
