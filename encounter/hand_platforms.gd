extends Node3D

func setup(scene: Node3D) -> void:
	var units: float = scene.measurement_tool.meters_to_world(1)
	var visual: Node3D = scene.get_node("KlothisRoot/KlothisVisual")
	for label in ["LeftWristSealAnchor","RightWristSealAnchor"]:
		var anchor: Node3D = visual.get_node(label)
		var body := StaticBody3D.new()
		body.name = label+"Platform"
		body.collision_layer = 4
		body.collision_mask = 0
		body.add_to_group("tactical_platform")
		add_child(body)
		body.global_position = anchor.global_position+Vector3(0,-3,3)*units
		var size: Vector2 = Vector2(8,6)*scene.cell_size
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x,.3,size.y)
		collision.shape = shape
		collision.position.y = -.15
		body.add_child(collision)
		# SurfaceGrid adds the grid from this solid collision automatically.
