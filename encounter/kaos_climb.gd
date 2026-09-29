extends Node

signal climb_completed
signal stage_changed(stage: String)
@export var charge_duration: float = 1.0
@export var duration: float = 1.25
@export var grip_duration: float = .35
@export var settle_duration: float = .65
var sequence_stage: String = "idle"
var _pose_meshes: Array[MeshInstance3D] = []
const BODY_CLEARANCE_METERS := 50.0
var _visual: Node3D
var _destination: Vector3
var _origin: Vector3
var _units: float
var _sphere: Vector3
var _radius: float
var _face_y: float
var _tween: Tween
var _platform_home: Vector3
var _platform_target: Vector3
var _sequence_id: int = 0

func prepare() -> void:
	if is_instance_valid(_visual):
		return
	var actor := get_parent() as Node3D
	var scene := actor.get_parent()
	_units = scene.measurement_tool.meters_to_world(1)
	var sphere: Node3D = scene.get_node("KlothisRoot/SphereVisual")
	_sphere = sphere.global_position
	_radius = 220*_units
	var face: Node3D = scene.get_node("KlothisRoot/KlothisVisual/FaceAnchor")
	_face_y = face.global_position.y
	_destination = Vector3(face.global_position.x,_face_y-136*_units,0)
	_destination.z = _surface_z(_destination.x,_face_y)+BODY_CLEARANCE_METERS*_units
	_visual = Node3D.new()
	_visual.name = "ClimbingVisual"
	actor.add_child(_visual)
	var builder = preload("res://encounter/sculpted_giant_visual.gd").new()
	builder.anatomy_override = "res://encounter/assets/characters/kaos_climbing.glb"
	builder.climbing = true
	var skin: Material
	for child in actor.get_node("KaosVisual").get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Anatomy"):
			skin = child.material_override
			break
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(.62,.52,.35)
	builder.build(_visual,_units,skin,null,gold,false)
	# Bend the braced pose around the same sphere without flattening the torso.
	for child in _visual.get_children():
		if child is MeshInstance3D:
			var mesh := ArrayMesh.new()
			mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
			mesh.add_blend_shape("Airborne")
			mesh.add_blend_shape("OneHandGrip")
			for surface in range(child.mesh.get_surface_count()):
				var source: Array = child.mesh.surface_get_arrays(surface)
				var role := String(child.get_meta("visual_role",child.name))
				var base: Array = _pose_arrays(source,child.transform,0,role)
				var shapes: Array[Array] = []
				for pose in [1,2]:
					var posed: Array
					var authored: Array = child.mesh.surface_get_blend_shape_arrays(surface)
					if authored.size() >= pose:
						var flight: Array = source.duplicate()
						flight[Mesh.ARRAY_VERTEX] = authored[pose-1][Mesh.ARRAY_VERTEX]
						posed = _pose_arrays(flight,child.transform,3 if pose==1 else 4,role)
					else:
						posed = _pose_arrays(source,child.transform,pose,role)
					var blend: Array = []
					blend.resize(Mesh.ARRAY_MAX)
					for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
						blend[slot] = posed[slot]
					shapes.append(blend)
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base,shapes)
				mesh.surface_set_material(surface,child.mesh.surface_get_material(surface))
			child.mesh = mesh
			child.transform = Transform3D.IDENTITY
			_pose_meshes.append(child)
		elif child is Marker3D:
			child.position = _wrap(child.position)
	_platform_home = actor.get_node("ShoulderPlatform").position
	_platform_target = _platform_home
	_visual.hide()

func _surface_z(x: float,y: float) -> float:
	return _sphere.z+sqrt(maxf(0.0,_radius*_radius-pow(x-_sphere.x,2)-pow(y-_sphere.y,2)))

func _wrap(p: Vector3) -> Vector3:
	var surface := _surface_z(_destination.x+p.x,_destination.y+p.y)
	# The torso stays upright: only the bracing limbs conform to the sphere.
	var q := p/_units
	var knee := smoothstep(4,12,q.x)*(1.0-smoothstep(63,78,q.y))
	var grip_depth := 42.0
	var contact := surface-_destination.z+maxf(.45*_units,grip_depth*_units+p.z)
	p.z = lerpf(p.z,contact,knee)
	return p

func _pose_arrays(source: Array, transform: Transform3D, pose: int, role: String = "") -> Array:
	var arrays := source.duplicate()
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX].duplicate()
	for i in range(vertices.size()):
		var p: Vector3 = transform*vertices[i]/_units
		if pose == 1:
			var side := signf(p.x)
			# Only cuffs occupy this compact volume; flowing hair must not follow the arms.
			var cuff := Vector3(side*28,138,-43)
			if role.begins_with("EngravedGold") and p.distance_to(cuff)<6:
				var old_axis := Vector3(side*2,15,-23).normalized()
				var new_axis := Vector3(side,-20,-2).normalized()
				p = Vector3(side*17,77,-2)+Basis(Quaternion(old_axis,new_axis))*(p-cuff)
			var head := smoothstep(124,131,p.y)*(1.0-smoothstep(10,15,absf(p.x)))
			var neck := Vector3(0,125,0)
			p = p.lerp(neck+Basis(Vector3.RIGHT,deg_to_rad(24))*(p-neck),head)
		elif pose == 2 and role.begins_with("EngravedGold"):
			var cuff := Vector3(28,138,-43)
			if p.distance_to(cuff)<6:
				p = Vector3(37,111.5,-38)+Basis(Quaternion(Vector3(2,15,-23).normalized(),Vector3(8,4,-22).normalized()))*(p-cuff)
		vertices[i] = _wrap(p*_units) if role.begins_with("Anatomy") and pose not in [1,3] else p*_units
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var st := SurfaceTool.new()
	st.create_from(raw,0)
	st.generate_normals()
	st.generate_tangents()
	return st.commit().surface_get_arrays(0)

func _air_pose(weight: float) -> void:
	for mesh in _pose_meshes:
		mesh.set_blend_shape_value(0,weight)

func _one_hand_pose(weight: float) -> void:
	for mesh in _pose_meshes:
		mesh.set_blend_shape_value(1,weight)

func _stage(value: String) -> void:
	sequence_stage = value
	stage_changed.emit(value)

func reset_pose() -> void:
	_sequence_id += 1
	if _tween != null:
		_tween.kill()
	get_parent().get_node("KaosVisual").show()
	if is_instance_valid(_visual):
		_visual.hide()
		_air_pose(0)
		_one_hand_pose(0)
		get_parent().get_node("ShoulderPlatform").position = _platform_home
	_stage("idle")

func restore_phase_two() -> void:
	prepare()
	get_parent().get_node("KaosVisual").hide()
	_visual.show()
	_air_pose(0)
	_one_hand_pose(1)
	get_parent().global_position = _destination
	get_parent().get_node("ShoulderPlatform").position = _platform_target
	_stage("one_hand")

func start() -> void:
	prepare()
	_sequence_id += 1
	var sequence := _sequence_id
	# Do not let the first-use mesh preparation consume the charge's first physics tick.
	await get_tree().process_frame
	await get_tree().process_frame
	_origin = get_parent().global_position
	var motion: Node = get_parent().motion
	_air_pose(1)
	_one_hand_pose(0)
	_stage("charge")
	var charge_start := Time.get_ticks_usec()
	while true:
		if sequence != _sequence_id:
			return
		var fraction := clampf((Time.get_ticks_usec()-charge_start)/1000000.0/maxf(.01,charge_duration),0,1)
		motion.crouch(.5-.5*cos(fraction*PI))
		if fraction >= 1:
			break
		await get_tree().process_frame
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_callback(func(): _stage("launch"))
	_tween.tween_method(motion.crouch,1.0,0.0,.18)
	_tween.parallel().tween_method(_move,0.0,.12,.18)
	_tween.tween_callback(func():
		get_parent().get_node("KaosVisual").hide()
		_visual.show()
		_stage("airborne"))
	_tween.tween_method(_move,.12,.90,maxf(.01,duration)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _stage("two_hands"))
	_tween.tween_method(_air_pose,1.0,0.0,grip_duration)
	_tween.parallel().tween_method(_move,.90,1.0,grip_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _stage("settling"))
	_tween.tween_method(_one_hand_pose,0.0,1.0,settle_duration).set_trans(Tween.TRANS_SINE)
	await _tween.finished
	restore_phase_two()
	climb_completed.emit()

func _move(t: float) -> void:
	var point := _origin.lerp(_destination,t)
	# Clearance on the outward arc prevents crossing the sphere during ascent.
	point.z += sin(t*PI)*110*_units
	get_parent().global_position = point
	get_parent().get_node("ShoulderPlatform").position = _platform_home.lerp(_platform_target,t)
