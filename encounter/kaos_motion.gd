extends Node

var _meshes: Array[MeshInstance3D] = []
var _units: float
var _platform: Node3D
var _platform_y: float
var _visual: Node3D
var _rest_phase: float = 0

func setup(visual: Node3D,units: float,platform: Node3D) -> void:
	_visual = visual
	_units = units
	_platform = platform
	_platform_y = platform.position.y
	for node in visual.get_children():
		if not node is MeshInstance3D:
			continue
		var role := String(node.get_meta("visual_role",node.name))
		if not (role.begins_with("Anatomy") or role in ["TailoredSkirtPanel","CentralEmbroideredDrape","ShoulderAnchoredMantle"]):
			continue
		var source: Mesh = node.mesh
		var result := ArrayMesh.new()
		result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		for label in ["LeftStride","RightStride","Crouch"]:
			result.add_blend_shape(label)
		for surface in range(source.get_surface_count()):
			var base: Array = source.surface_get_arrays(surface)
			var targets: Array[Array] = []
			for pose in range(3):
				var shape: Array = []
				shape.resize(Mesh.ARRAY_MAX)
				var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX].duplicate()
				for i in range(vertices.size()):
					var p: Vector3 = node.transform*vertices[i]/units
					var weight := 1.0-smoothstep(60,78,p.y)
					if pose < 2:
						var side := 1.0 if p.x>0 else -1.0
						var angle := side*(.26 if pose==0 else -.26)*weight
						var hip := Vector3(side*8,74,0)
						p = hip+Basis(Vector3.RIGHT,angle)*(p-hip)
						p.y += maxf(0,side*(1 if pose==0 else -1))*5*weight
					else:
						# Feet stay planted; knees travel forward while pelvis descends.
						p.y -= 11*smoothstep(3,74,p.y)
						p.z -= sin(clampf(p.y/74,0,1)*PI)*10
					vertices[i] = node.transform.affine_inverse()*(p*units)
				shape[Mesh.ARRAY_VERTEX] = vertices
				shape[Mesh.ARRAY_NORMAL] = base[Mesh.ARRAY_NORMAL]
				shape[Mesh.ARRAY_TANGENT] = base[Mesh.ARRAY_TANGENT]
				targets.append(shape)
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base,targets)
			result.surface_set_material(surface,source.surface_get_material(surface))
		node.mesh = result
		_meshes.append(node)

func set_stride(phase: float) -> void:
	_rest_phase = phase
	var swing := sin(phase*PI)
	for mesh in _meshes:
		mesh.set_blend_shape_value(0,maxf(0,swing))
		mesh.set_blend_shape_value(1,maxf(0,-swing))
		mesh.set_blend_shape_value(2,0)

func crouch(amount: float) -> void:
	for mesh in _meshes:
		mesh.set_blend_shape_value(0,0)
		mesh.set_blend_shape_value(1,0)
		mesh.set_blend_shape_value(2,amount)
	# Accessories above the hips follow the lowered torso too.
	for child in _visual.get_children():
		if child is Node3D and not (child is MeshInstance3D and child in _meshes):
			if not child.has_meta("motion_home"):
				child.set_meta("motion_home",child.position)
			child.position = child.get_meta("motion_home")-Vector3.UP*11*_units*amount
	_platform.position.y = _platform_y-11*_units*amount

func reset() -> void:
	crouch(0)
	set_stride(0)
