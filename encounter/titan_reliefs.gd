extends RefCounted

func build(parent: Node3D,units: float,stone: Material) -> void:
	var source: Node3D = load("res://encounter/assets/characters/titan_relief.glb").instantiate()
	var mesh_node: MeshInstance3D = source.find_children("*","MeshInstance3D",true,false)[0]
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh_node.mesh
	batch.instance_count = 16
	for i in range(16):
		var row := i/4
		var yaw := -.95+float(i%4)*.63+(row%2)*.12
		if row == 1 and i%4 in [1,2]:
			yaw = -.48 if i%4==1 else .48
		var pitch := -.80+row*.51
		var n := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
		var x := Vector3.UP.cross(n).normalized()
		var basis := Basis(x,n.cross(x).normalized(),n)
		basis = basis.rotated(n,(-.12 if i%2==0 else .14))
		batch.set_instance_transform(i,Transform3D(basis.scaled(Vector3.ONE*(3.8+i%3*.45)*units),n*205*units))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CarvedTitanFaces"
	instance.multimesh = batch
	instance.material_override = stone
	parent.add_child(instance)
	source.free()
