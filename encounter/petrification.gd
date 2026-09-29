extends Node

var avatar: CharacterBody3D
var _originals: Array = []
var _debris: MultiMeshInstance3D
var _effect: Tween

func clear() -> void:
	if _effect != null:
		_effect.kill()
	if is_instance_valid(_debris):
		_debris.free()
	if is_instance_valid(avatar):
		avatar.free()
	for record in _originals:
		if is_instance_valid(record[0]):
			record[0].material_override = record[1]
			record[0].visible = record[2]
	_originals.clear()
	get_parent().get_node("ShoulderPlatform").open_head_space(false)

func apply(animate: bool = true) -> void:
	if is_instance_valid(avatar):
		return
	var actor := get_parent() as Node3D
	var scene := actor.get_parent()
	var units: float = scene.measurement_tool.meters_to_world(1)
	var visual: Node3D = actor.get_node("ClimbingVisual") if actor.has_node("ClimbingVisual") and actor.get_node("ClimbingVisual").visible else actor.get_node("KaosVisual")
	var stone := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://encounter/sphere_surface.gdshader").replace("void fragment() {", "uniform vec3 giant_origin;\nuniform float unit_scale;\nvarying vec3 world_point;\nvoid vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }\nvoid fragment() {\n vec3 local=(world_point-giant_origin)/unit_scale;\n if(local.y>122.0 && abs(local.x)<11.5) { discard; }")
	stone.shader = shader
	shader.code = shader.code.replace("local.y>122.0", "local.y>119.8")
	preload("res://encounter/pbr_assets.gd").apply(stone,"dark_rock")
	stone.set_shader_parameter("giant_origin",actor.global_position)
	stone.set_shader_parameter("unit_scale",units)
	for child in visual.get_children():
		if child is MeshInstance3D:
			_originals.append([child,child.material_override,child.visible])
			child.material_override = stone
			var label := String(child.get_meta("visual_role",child.name))
			if "Hair" in label or "Lock" in label or "Crown" in label or "Sclera" in label or "Iris" in label or "Pupil" in label or "Lightning" in label:
				child.hide()
	var platform: Node3D = actor.get_node("ShoulderPlatform")
	platform.open_head_space(true)
	avatar = scene.token_scene.instantiate()
	avatar.name = "KaosPhaseTwo"
	scene.tokens_root.add_child(avatar)
	avatar.configure(Color(.06,.06,.09),scene.cell_size,"Large",2.0)
	for child in avatar.visuals.get_children():
		child.hide()
	# Reuse the actual Kaos visual, including costume, at token scale.
	var miniature: Node3D = actor.get_node("KaosVisual").duplicate()
	miniature.name = "KaosSkin"
	miniature.show()
	avatar.visuals.add_child(miniature)
	miniature.scale = Vector3.ONE/(75*units)
	miniature.position = Vector3(0,-1,0)
	for child in miniature.get_children():
		if child is MeshInstance3D:
			for record in _originals:
				if record[0].name == child.name:
					child.material_override = record[1]
					child.visible = record[2]
	avatar.global_position = platform.to_global(Vector3(0,scene.cell_size+.015,0))
	avatar.grid_support = platform
	avatar._support_transform = platform.global_transform
	avatar.set_meta("kaos_phase_two",true)
	if animate:
		_burst(visual.get_node("FaceAnchor").global_position,units)

func _burst(origin: Vector3,units: float) -> void:
	_debris = MultiMeshInstance3D.new()
	_debris.multimesh = MultiMesh.new()
	_debris.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = units*.7
	mesh.height = units*1.4
	mesh.radial_segments = 6
	mesh.rings = 3
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(.14,.15,.16)
	mesh.material = rock
	_debris.multimesh.mesh = mesh
	_debris.multimesh.instance_count = 36
	get_parent().add_child(_debris)
	_debris.global_position = origin
	_effect = create_tween()
	_effect.tween_method(func(t: float):
		for i in range(36):
			var direction := Vector3(cos(i*2.4),sin(i*1.7)*.7,sin(i*2.4)).normalized()
			var p := direction*(3+t*18)*units-Vector3.UP*t*t*8*units
			_debris.multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.UP,t+i).scaled(Vector3.ONE*(1-t*.9)),p))
	,0.0,1.0,1.3)
	_effect.tween_callback(func(): _debris.hide())
