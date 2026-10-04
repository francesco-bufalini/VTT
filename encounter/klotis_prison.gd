extends Node3D
## Imported prison for Scontro contro Kaos; gameplay seal state remains in SealController.
signal seal_broken(side: String)
signal palm_strike(side: String, world_position: Vector3)
@export var seal_hit_points: int = 20
signal arm_walkable(side: String)
signal head_bowed
var scene: Node3D
var _skin_cache: Dictionary = {}
var _skin_shape: ConcavePolygonShape3D
var _skin_shapes: Dictionary = {}
var _skin_elapsed: float = 0.0
var statue_top: Vector3
var baseline_dimensions: Dictionary = {}
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var broken: Dictionary = {"left": false, "right": false, "forehead": false}
var health: Dictionary = {}
var _clips: Dictionary = {}
var _seals: Dictionary = {}
var _lights: Dictionary = {}
var _areas: Dictionary = {}
var _pending: Array[String] = []
var _completed: Array[String] = []
var _active_side: String = ""
var _burst_sent: bool = false
var _impact_sent: bool = false

const PRISON_RADIUS_METERS := 220.0
const SEALED_RIGHT_HAND_CLEARANCE_METERS := 0.35
const SEALED_RIGHT_HAND_MAX_PUSH_METERS := 30.0

func _ready() -> void:
	model = get_node("Visual") as Node3D
	for node in model.find_children("*", "", true, false):
		if node is AnimationPlayer:
			player = node as AnimationPlayer
		if node is Skeleton3D:
			skeleton = node as Skeleton3D
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			for index in range(mesh_node.mesh.get_surface_count()):
				var original := mesh_node.mesh.surface_get_material(index) as StandardMaterial3D
				if original != null:
					var material := original.duplicate() as StandardMaterial3D
					if String(node.name).begins_with("Earth_") or String(node.name).begins_with("Titan_"):
						material.vertex_color_use_as_albedo = true
					if original.resource_name.begins_with("V4_Sigil"):
						material.emission_energy_multiplier = 1.1
					mesh_node.set_surface_override_material(index, material)
	for side in ["left", "right", "forehead"]:
		var suffix: String = side.capitalize()
		_seals[side] = model.find_child("Seal_" + suffix + "_V5", true, false)
		_lights[side] = model.find_child("SealLight_" + suffix + "_V5", true, false)
		health[side] = seal_hit_points
	for node in model.find_children("SealLight_*", "Light3D", true, false):
		node.light_energy = 0.04 if String(node.name).contains("Forehead") else 0.065
		if node is OmniLight3D:
			node.omni_range = 1.4 * model.scale.x
	if player == null or skeleton == null:
		push_error("Rig o AnimationPlayer mancante")
		return
	# Private animation copies let a freed arm retain its pose while the other attacks.
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, library)
	for clip in player.get_animation_list():
		if String(clip).ends_with("Break_Left_Seal"):
			_clips["left"] = clip
		elif String(clip).ends_with("Break_Right_Seal"):
			_clips["right"] = clip
		elif String(clip).ends_with("Break_Forehead_Seal"):
			_clips["forehead"] = clip
	player.animation_finished.connect(_on_animation_finished)
	for clip in _clips.values():
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	reset_seals()
	_fit_model()
	_build_walkable_surfaces()
	_retire_legacy()
	scene.encounter.seals.changed.connect(_sync_seal_state)
	scene.encounter.state_changed.connect(_retire_legacy)
	_sync_seal_state()

func damage_seal(side: String, damage: int) -> bool:
	side = side.to_lower()
	if not health.has(side) or broken[side] or damage <= 0:
		return false
	health[side] = maxi(0, int(health[side]) - damage)
	return break_seal(side) if health[side] == 0 else false

func break_seal(side: String) -> bool:
	side = side.to_lower()
	if not broken.has(side) or broken[side] or not _clips.has(side):
		return false
	broken[side] = true
	health[side] = 0
	if _active_side.is_empty():
		_start_attack(side)
	else:
		_pending.append(side)
	return true

func _start_attack(side: String) -> void:
	_active_side = side
	_burst_sent = false
	_impact_sent = false
	var animation: Animation = player.get_animation(_clips[side])
	for index in range(animation.get_track_count()):
		var path: String = String(animation.track_get_path(index))
		var bone: String = path.get_slice(":", 1)
		var enable: bool = true
		for previous in _completed:
			var ending: String = ".l" if previous == "left" else (".r" if previous == "right" else ".f")
			var safe_ending: String = "_l" if previous == "left" else ("_r" if previous == "right" else "_f")
			if bone.ends_with(ending) or bone.ends_with(safe_ending) or (previous == "forehead" and bone == "head"):
				enable = false
		# While the right seal is intact, keep that side in its corrected
		# resting pose even if another full-rig animation contains right-side
		# tracks. The right-side tracks are re-enabled when its own seal breaks.
		if side != "right" and not bool(broken.get("right", false)):
			if bone.ends_with(".r") or bone.ends_with("_r"):
				enable = false
		animation.track_set_enabled(index, enable)
	player.play(_clips[side], 0.0)
	player.advance(0.0)

func _process(_delta: float) -> void:
	_retire_legacy()
	if player == null or _active_side.is_empty():
		return
	var time: float = player.current_animation_position
	if time >= 12.0 / 30.0 and not _burst_sent:
		_burst_sent = true
		(_seals[_active_side] as Node3D).visible = false
		if _lights[_active_side] != null:
			(_lights[_active_side] as Light3D).visible = false
		seal_broken.emit(_active_side)
	if time >= 38.0 / 30.0 and not _impact_sent and _active_side != "forehead":
		_impact_sent = true
		var bone_name: String = "hand.l" if _active_side == "left" else "hand.r"
		var index: int = skeleton.find_bone(bone_name)
		if index < 0:
			index = skeleton.find_bone(bone_name.replace(".", "_"))
		var point: Vector3 = global_position
		if index >= 0:
			point = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		palm_strike.emit(_active_side, point)

func _on_animation_finished(_name: StringName) -> void:
	if _active_side.is_empty():
		return
	_update_skin_collision()
	var side := _active_side
	var fragments := model.find_child("Seal_Fragments_" + side.capitalize() + "_V5", true, false) as Node3D
	if fragments != null:
		fragments.visible = false
	_completed.append(side)
	_active_side = ""
	scene.volumetric_grid.call_deferred("refresh")
	if side == "forehead":
		head_bowed.emit()
	else:
		arm_walkable.emit(side)
	if not _pending.is_empty():
		_start_attack(_pending.pop_front())

func reset_seals() -> void:
	if player == null or not _clips.has("left"):
		return
	_pending.clear()
	_completed.clear()
	_active_side = ""
	player.stop()
	skeleton.reset_bone_poses()
	for clip in _clips.values():
		var animation: Animation = player.get_animation(clip)
		for index in range(animation.get_track_count()):
			animation.track_set_enabled(index, true)
	player.play(_clips["left"], 0.0)
	player.advance(0.0)
	player.pause()
	_apply_sealed_right_hand_clearance()
	for side in ["left", "right", "forehead"]:
		var fragments := model.find_child("Seal_Fragments_" + side.capitalize() + "_V5", true, false) as Node3D
		if fragments != null:
			fragments.visible = true
		broken[side] = false
		health[side] = seal_hit_points
		(_seals[side] as Node3D).visible = true
		if _lights[side] != null:
			(_lights[side] as Light3D).visible = true

func _physics_process(delta: float) -> void:
	if _active_side.is_empty():
		return
	_skin_elapsed += delta
	if _skin_elapsed >= 0.15:
		_skin_elapsed = 0.0
		_update_skin_collision()

func _sync_seal_state() -> void:
	var values: Array = scene.encounter.seals.damage
	var must_reset := false
	for index in range(3):
		var side: String = ["forehead", "left", "right"][index]
		if broken[side] and values[index] < scene.encounter.seals.break_damage:
			must_reset = true
	if must_reset:
		reset_seals()
		_update_skin_collision()
		scene.volumetric_grid.call_deferred("refresh")
	for index in range(3):
		var side: String = ["forehead", "left", "right"][index]
		if values[index] >= scene.encounter.seals.break_damage and not broken[side]:
			break_seal(side)

func _retire_legacy() -> void:
	for root_path: String in ["KaosRoot", "KlothisRoot"]:
		var legacy: Node3D = scene.get_node(root_path)
		if legacy.has_meta("import_collisions_retired"):
			continue
		legacy.set_meta("import_collisions_retired", true)
		legacy.add_to_group("grid_3d_excluded")
		for collider in legacy.find_children("*", "CollisionObject3D", true, false):
			collider.collision_layer = 0
			collider.collision_mask = 0
	for path: String in ["KlothisRoot/KlothisVisual", "KlothisRoot/SphereVisual", "KaosRoot/KaosVisual", "KaosRoot/ClimbingVisual"]:
		var old := scene.get_node_or_null(path) as Node3D
		if old == null:
			continue
		old.hide()
		if old.has_meta("import_replaced"):
			continue
		old.set_meta("import_replaced", true)
		old.add_to_group("grid_3d_excluded")
		for collider in old.find_children("*", "CollisionObject3D", true, false):
			collider.collision_layer = 0
			collider.collision_mask = 0

func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box

func _legacy_body_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("Anatomy*", "MeshInstance3D", true, false):
		if not n.is_visible_in_tree():
			continue
		var b: AABB = n.global_transform * n.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _fit_model() -> void:
	var sphere := scene.get_node("KlothisRoot/SphereVisual") as Node3D
	var plates := model.find_child("Earth_Hexagonal_Stone_Plates", true, false) as MeshInstance3D
	var units: float = scene.measurement_tool.meters_to_world(1)
	var sphere_scale: float = 440.0 * units / plates.get_aabb().size.y
	model.scale = Vector3.ONE * sphere_scale
	model.global_position = sphere.global_position
	var old_goddess := _legacy_body_bounds(scene.get_node("KlothisRoot/KlothisVisual"))
	var old_statue := _legacy_body_bounds(scene.get_node("KaosRoot/ClimbingVisual"))
	var body := model.find_child("Klotis_Body_V5", true, false) as MeshInstance3D
	var points := _posed_vertices(body)
	var box := _bounds(points)
	var rig := skeleton.get_parent() as Node3D
	rig.scale *= old_goddess.size.y / box.size.y
	_skin_cache.clear()
	box = _bounds(_posed_vertices(body))
	rig.global_position.y += old_goddess.get_center().y - box.get_center().y
	rig.global_position.x += old_goddess.get_center().x - box.get_center().x
	var statue := model.find_child("Empyrean_Headless_Petrified", true, false) as MeshInstance3D
	var statue_box: AABB = statue.global_transform * statue.get_aabb()
	var neck_y := statue_box.end.y
	statue.scale *= old_statue.size.y / statue_box.size.y
	statue_box = statue.global_transform * statue.get_aabb()
	statue.global_position.y += neck_y - statue_box.end.y
	# Keep the authored palm contact after fitting the two characters' heights.
	var palm_height := 0.0
	for side: String in ["left", "right"]:
		player.play(_clips[side], 0.0)
		player.advance(42.0 / 30.0)
		skeleton.force_update_all_bone_transforms()
		palm_height += _palm_center(side).y * 0.5
	player.stop()
	reset_seals()
	statue.global_position.y += palm_height - 0.02 * sphere_scale - neck_y
	statue_box = statue.global_transform * statue.get_aabb()
	statue_top = _neck_top(statue)
	baseline_dimensions = {"sphere_diameter":440.0*units,"goddess_height":old_goddess.size.y,"statue_height":old_statue.size.y}
	for light in model.find_children("SealLight_*", "OmniLight3D", true, false):
		light.omni_range = 1.4 * sphere_scale

func _skin_data(mesh_node: MeshInstance3D) -> Dictionary:
	if _skin_cache.has(mesh_node):
		return _skin_cache[mesh_node]
	var surfaces: Array[Dictionary] = []
	for surface in range(mesh_node.mesh.get_surface_count()):
		var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		surfaces.append({"vertices":vertices,"bones":bones,"weights":weights,"indices":arrays[Mesh.ARRAY_INDEX],"influences":bones.size()/vertices.size()})
	var binds: Array[int] = []
	for i in mesh_node.skin.get_bind_count():
		var bone := mesh_node.skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(mesh_node.skin.get_bind_name(i))
		binds.append(bone)
	var data := {"surfaces":surfaces,"binds":binds}
	_skin_cache[mesh_node] = data
	return data

func _skin_matrices(mesh_node: MeshInstance3D, data: Dictionary) -> Array[Transform3D]:
	skeleton.force_update_all_bone_transforms()
	var matrices: Array[Transform3D] = []
	for i in mesh_node.skin.get_bind_count():
		matrices.append(skeleton.global_transform * skeleton.get_bone_global_pose(data.binds[i]) * mesh_node.skin.get_bind_pose(i))
	return matrices

func _posed_vertices(mesh_node: MeshInstance3D) -> PackedVector3Array:
	var data := _skin_data(mesh_node)
	var matrices := _skin_matrices(mesh_node, data)
	var output := PackedVector3Array()
	for surface: Dictionary in data.surfaces:
		for i in surface.vertices.size():
			var point := Vector3.ZERO
			for k in surface.influences:
				var slot: int = i*surface.influences+k
				var weight: float = surface.weights[slot]
				if weight > 0.0:
					point += (matrices[surface.bones[slot]] * surface.vertices[i]) * weight
			output.append(point)
	return output

func _palm_center(side: String) -> Vector3:
	var body := model.find_child("Klotis_Body_V5", true, false) as MeshInstance3D
	var data := _skin_data(body)
	var points := _posed_vertices(body)
	var bone := skeleton.find_bone("hand.l" if side == "left" else "hand.r")
	if bone < 0:
		bone = skeleton.find_bone("hand_l" if side == "left" else "hand_r")
	var center := Vector3.ZERO
	var count := 0
	var offset := 0
	for surface: Dictionary in data.surfaces:
		for i in surface.vertices.size():
			var hand_weight := 0.0
			for k in surface.influences:
				var slot: int = i*surface.influences+k
				if data.binds[surface.bones[slot]] == bone:
					hand_weight += surface.weights[slot]
			if hand_weight > 0.75:
				center += points[offset+i]
				count += 1
		offset += surface.vertices.size()
	return center / maxf(1, count)


func _sealed_hand_metrics(side: String) -> Dictionary:
	var body := model.find_child("Klotis_Body_V5", true, false) as MeshInstance3D
	if body == null or skeleton == null:
		return {}
	var data := _skin_data(body)
	var points := _posed_vertices(body)
	var bone := skeleton.find_bone("hand.l" if side == "left" else "hand.r")
	if bone < 0:
		bone = skeleton.find_bone("hand_l" if side == "left" else "hand_r")
	if bone < 0:
		return {}

	var center := Vector3.ZERO
	var minimum_radius := INF
	var count := 0
	var offset := 0
	for surface: Dictionary in data.surfaces:
		for i in surface.vertices.size():
			var hand_weight := 0.0
			for k in surface.influences:
				var slot: int = i * surface.influences + k
				if data.binds[surface.bones[slot]] == bone:
					hand_weight += surface.weights[slot]
			if hand_weight > 0.55:
				var point: Vector3 = points[offset + i]
				center += point
				minimum_radius = minf(
					minimum_radius,
					point.distance_to(model.global_position)
				)
				count += 1
		offset += surface.vertices.size()

	if count == 0:
		return {}
	return {
		"center": center / float(count),
		"min_radius": minimum_radius,
	}


func _apply_sealed_right_hand_clearance() -> void:
	if scene == null or model == null or skeleton == null:
		return
	var measurement := scene.get_node_or_null("MeasurementTool")
	if measurement == null or not measurement.has_method("meters_to_world"):
		return

	skeleton.force_update_all_bone_transforms()
	var metrics := _sealed_hand_metrics("right")
	if metrics.is_empty():
		return

	var units := float(measurement.call("meters_to_world", 1.0))
	if units <= 0.0:
		return
	var target_radius := (
		(PRISON_RADIUS_METERS + SEALED_RIGHT_HAND_CLEARANCE_METERS) * units
	)
	var minimum_radius := float(metrics.get("min_radius", target_radius))
	var required_push := target_radius - minimum_radius
	if required_push <= 0.0:
		return
	required_push = minf(
		required_push,
		SEALED_RIGHT_HAND_MAX_PUSH_METERS * units
	)

	var center: Vector3 = metrics.get("center", Vector3.ZERO)
	var outward := center - model.global_position
	if outward.length_squared() <= 0.000001:
		return
	outward = outward.normalized()

	var hand_bone := skeleton.find_bone("hand.r")
	if hand_bone < 0:
		hand_bone = skeleton.find_bone("hand_r")
	if hand_bone < 0:
		return

	var parent_bone := skeleton.get_bone_parent(hand_bone)
	var parent_world := skeleton.global_transform
	if parent_bone >= 0:
		parent_world = (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(parent_bone)
		)
	var local_push := (
		parent_world.basis.inverse()
		* (outward * required_push)
	)
	skeleton.set_bone_pose_position(
		hand_bone,
		skeleton.get_bone_pose_position(hand_bone) + local_push
	)
	skeleton.force_update_all_bone_transforms()


func _build_walkable_surfaces() -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var label := String(n.name)
		if n.skin != null and label in ["Klotis_Body_V5", "Klotis_Draped_Bodice_V5", "Klotis_Pleated_Gown_V5", "Klotis_Curved_Horns_Six_V5", "Klotis_Blindfold_V5", "Klotis_Golden_Hair_Cap_V5"]:
			var body := _collision_body(label + "SolidSurface")
			var collision_mesh := ConcavePolygonShape3D.new()
			collision_mesh.backface_collision = true
			collision_mesh.set_faces(_skin_faces(n))
			var shape := CollisionShape3D.new()
			shape.shape = collision_mesh
			body.add_child(shape)
			if label == "Klotis_Body_V5":
				_skin_shape = collision_mesh
			if label in ["Klotis_Body_V5", "Klotis_Curved_Horns_Six_V5", "Klotis_Blindfold_V5", "Klotis_Golden_Hair_Cap_V5"]:
				_skin_shapes[n] = collision_mesh
		elif n.skin == null and (label.begins_with("Earth_") or label.begins_with("Titan_") or label.begins_with("Empyrean_") or label == "Klotis_Pleated_Gown_V5"):
			var body := _collision_body(label + "SolidSurface")
			body.global_transform = n.global_transform
			var shape := CollisionShape3D.new()
			shape.shape = n.mesh.create_trimesh_shape()
			body.add_child(shape)
	_update_skin_collision()

func _collision_body(label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1 | 8
	body.collision_mask = 0
	body.add_to_group("tactical_platform")
	body.set_meta("klotis_imported_surface", true)
	body.set_meta("volumetric_grid_surface_proxy", true)
	add_child(body)
	return body

func _update_skin_collision() -> void:
	for mesh_node: MeshInstance3D in _skin_shapes:
		var shape: ConcavePolygonShape3D = _skin_shapes[mesh_node]
		shape.set_faces(_skin_faces(mesh_node))

func _skin_faces(mesh_node: MeshInstance3D) -> PackedVector3Array:
	var data := _skin_data(mesh_node)
	var points := _posed_vertices(mesh_node)
	var faces := PackedVector3Array()
	var offset := 0
	var inverse := global_transform.affine_inverse()
	for surface: Dictionary in data.surfaces:
		for index: int in surface.indices:
			faces.append(inverse * points[offset + index])
		offset += surface.vertices.size()
	return faces

func _neck_top(statue: MeshInstance3D) -> Vector3:
	var points := PackedVector3Array()
	var height := -INF
	for surface in statue.mesh.get_surface_count():
		var arrays: Array = statue.mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = statue.global_transform * vertex
			points.append(point)
			height = maxf(height, point.y)
	var center := Vector3.ZERO
	var count := 0
	for point in points:
		if height - point.y < 0.01:
			center += point
			count += 1
	return center / maxf(1,count)
