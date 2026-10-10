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
var _pending: Array[String] = []
var _completed: Array[String] = []
var _active_side: String = ""
var _burst_sent: bool = false
var _impact_sent: bool = false
var _model_fitted: bool = false
var _sealed_hand_offsets: Dictionary = {}
var _hand_target_positions: Dictionary = {}
var _hand_target_radii: Dictionary = {}
var _final_eye_midpoint_position: Vector3 = Vector3.ZERO

const PRISON_RADIUS_METERS := 220.0
const SEALED_HAND_CLEARANCE_METERS := 0.35
const SEALED_HAND_MAX_PUSH_METERS := 30.0

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
	_refine_animation_timing()
	reset_seals()
	_fit_model()
	_bring_head_details_forward()
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
		# Only the active limb may move; queued breaks retain their sealed pose.
		for inactive in ["left", "right"]:
			if inactive != side:
				var suffix: String = ".l" if inactive == "left" else ".r"
				if bone.ends_with(suffix) or bone.ends_with(suffix.replace(".", "_")):
					enable = false
		if side != "forehead" and bone == "head":
			enable = false
		animation.track_set_enabled(index, enable)
	player.play(_clips[side], 0.0)
	player.advance(0.0)

func _process(_delta: float) -> void:
	# Legacy hierarchies are retired in _ready() and on encounter state
	# changes. Hiding the huge Kaos/Klothys visual trees every render frame
	# needlessly repeats visibility work even while the encounter is idle.
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
	_apply_sealed_hand_clearance()
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
		if old == null or old.has_meta("import_replaced"):
			continue
		old.hide()
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
	# Fit the rock to the same corrected, persistent poses used during play.
	# The lowest finger touches the platform; no part of either hand is buried.
	_model_fitted = true
	reset_seals()
	var palm_bottom := INF
	_hand_target_positions.clear()
	_hand_target_radii.clear()
	for side: String in ["left", "right"]:
		_start_attack(side)
		player.advance(1.5)
		skeleton.force_update_all_bone_transforms()
		var palm_center: Vector3 = _palm_center(side)
		_hand_target_positions[side] = palm_center
		_hand_target_radii[side] = _palm_footprint_radius(side, palm_center)
		palm_bottom = minf(palm_bottom, float(_sealed_hand_metrics(side).min_y))

	reset_seals()

	# First put the petrified creature in its definitive position.  The cone
	# target must be the actual flat neck stump after this correction.
	statue.global_position.y += palm_bottom - neck_y
	statue_box = statue.global_transform * statue.get_aabb()
	statue_top = _neck_top(statue)

	# Only now sample Klothys at the END of Break_Forehead_Seal and derive the
	# point between her eyes from the skinned head geometry.  seal_broken fires
	# near the start of the animation, so the live pose is intentionally not
	# used for this telegraph.
	_start_attack("forehead")
	var forehead_animation: Animation = player.get_animation(_clips["forehead"])
	player.seek(forehead_animation.length, true)
	skeleton.force_update_all_bone_transforms()
	_final_eye_midpoint_position = _current_eye_midpoint_world_position(
		statue_top
	)
	reset_seals()
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
		surfaces.append({"vertices":vertices,"bones":bones,"weights":weights,"indices":arrays[Mesh.ARRAY_INDEX],"influences":int(bones.size()/float(vertices.size()))})
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


func get_hand_target_position(side: String) -> Vector3:
	side = side.to_lower()
	return _hand_target_positions.get(side, Vector3.ZERO)


func get_hand_target_radius(side: String) -> float:
	side = side.to_lower()
	return float(_hand_target_radii.get(side, 0.0))


func get_forehead_world_position() -> Vector3:
	return _current_forehead_world_position()


func get_forehead_final_world_position() -> Vector3:
	# Backward-compatible alias: this is now the true point between the eyes,
	# not the forehead seal center.
	return get_final_eye_midpoint_world_position()


func get_final_eye_midpoint_world_position() -> Vector3:
	if _final_eye_midpoint_position != Vector3.ZERO:
		return _final_eye_midpoint_position
	return _current_eye_midpoint_world_position(
		get_petrified_neck_world_position()
	)


func _current_forehead_world_position() -> Vector3:
	# The forehead seal node pivot is near the imported model origin, not on
	# Klothys' face. Use the actual skinned seal geometry so this is the visible
	# forehead position for whichever pose is currently sampled.
	var seal := _seals.get("forehead") as MeshInstance3D
	if seal != null and is_instance_valid(seal) and seal.mesh != null:
		if seal.skin != null:
			var posed_points: PackedVector3Array = _posed_vertices(seal)
			if not posed_points.is_empty():
				return _bounds(posed_points).get_center()
		return seal.global_transform * seal.get_aabb().get_center()

	# Fallback to the head bone rather than the model/root pivot.
	if skeleton != null and is_instance_valid(skeleton):
		var head_index: int = skeleton.find_bone("head")
		if head_index >= 0:
			return (
				skeleton.global_transform
				* skeleton.get_bone_global_pose(head_index)
			).origin

	return model.global_position if model != null else global_position


func _current_eye_midpoint_world_position(
	neck_target: Vector3
) -> Vector3:
	var forehead: Vector3 = _current_forehead_world_position()
	if skeleton == null or not is_instance_valid(skeleton):
		return forehead

	var head_bone: int = skeleton.find_bone("head")
	if head_bone < 0:
		return forehead

	var body := model.find_child(
		"Klotis_Body_V5",
		true,
		false
	) as MeshInstance3D
	if body == null or body.skin == null or body.mesh == null:
		return forehead

	var data: Dictionary = _skin_data(body)
	var posed: PackedVector3Array = _posed_vertices(body)
	var head_world: Transform3D = (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(head_bone)
	)
	var inverse_head: Transform3D = head_world.affine_inverse()
	var head_points := PackedVector3Array()
	var offset := 0

	for surface: Dictionary in data.surfaces:
		for vertex_index in surface.vertices.size():
			var head_weight := 0.0
			for influence in surface.influences:
				var slot: int = (
					vertex_index * surface.influences + influence
				)
				var influenced_bone: int = data.binds[
					surface.bones[slot]
				]
				while (
					influenced_bone >= 0
					and influenced_bone != head_bone
				):
					influenced_bone = skeleton.get_bone_parent(
						influenced_bone
					)
				if influenced_bone == head_bone:
					head_weight += surface.weights[slot]
			if head_weight > 0.45:
				head_points.append(
					inverse_head * posed[offset + vertex_index]
				)
		offset += surface.vertices.size()

	if head_points.is_empty():
		return forehead

	var minimum := head_points[0]
	var maximum := head_points[0]
	for point: Vector3 in head_points:
		minimum = Vector3(
			minf(minimum.x, point.x),
			minf(minimum.y, point.y),
			minf(minimum.z, point.z)
		)
		maximum = Vector3(
			maxf(maximum.x, point.x),
			maxf(maximum.y, point.y),
			maxf(maximum.z, point.z)
		)

	var size: Vector3 = maximum - minimum
	if size.length_squared() <= 0.000001:
		return forehead

	var forehead_local: Vector3 = inverse_head * forehead
	# The visible forehead sigil is a reliable center-line landmark.  Moving
	# down about 15% of the skinned head height reaches the bridge between the
	# eyes while staying in the final animated head basis.
	var eye_level: float = forehead_local.y - size.y * 0.15
	var head_center: Vector3 = (minimum + maximum) * 0.5
	var neck_local: Vector3 = inverse_head * neck_target
	var face_direction: Vector3 = neck_local - head_center
	if face_direction.length_squared() <= 0.000001:
		face_direction = Vector3.FORWARD
	else:
		face_direction = face_direction.normalized()

	# Pick actual face vertices around the center-line/eye-height band, then
	# average the most forward ones.  This prevents the origin from ending up
	# at the head bone, inside the skull, or on the forehead sigil itself.
	var candidates: Array[Dictionary] = []
	var x_band: float = maxf(size.x * 0.10, 0.001)
	var y_band: float = maxf(size.y * 0.10, 0.001)
	for point: Vector3 in head_points:
		if absf(point.x - forehead_local.x) > x_band:
			continue
		if absf(point.y - eye_level) > y_band:
			continue
		candidates.append({
			"point": point,
			"score": (point - head_center).dot(face_direction),
		})

	if candidates.is_empty():
		# Wider fallback for unusual imports/weights.
		x_band = maxf(size.x * 0.20, 0.001)
		y_band = maxf(size.y * 0.18, 0.001)
		for point: Vector3 in head_points:
			if absf(point.x - forehead_local.x) > x_band:
				continue
			if absf(point.y - eye_level) > y_band:
				continue
			candidates.append({
				"point": point,
				"score": (point - head_center).dot(face_direction),
			})

	if candidates.is_empty():
		var fallback_local := forehead_local
		fallback_local.y = eye_level
		return head_world * fallback_local

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.score) > float(b.score)
	)
	var sample_count: int = mini(12, candidates.size())
	var midpoint := Vector3.ZERO
	for index in range(sample_count):
		midpoint += candidates[index].point
	midpoint /= float(sample_count)
	return head_world * midpoint


func get_petrified_neck_world_position() -> Vector3:
	var statue := model.find_child(
		"Empyrean_Headless_Petrified",
		true,
		false
	) as MeshInstance3D
	if statue != null and is_instance_valid(statue):
		return _neck_top(statue)
	return statue_top


func _palm_footprint_radius(side: String, center: Vector3) -> float:
	var body := model.find_child("Klotis_Body_V5", true, false) as MeshInstance3D
	if body == null:
		return 0.0
	var data := _skin_data(body)
	var points := _posed_vertices(body)
	var bone := skeleton.find_bone("hand.l" if side == "left" else "hand.r")
	if bone < 0:
		bone = skeleton.find_bone("hand_l" if side == "left" else "hand_r")
	if bone < 0:
		return 0.0
	var radius := 0.0
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
				radius = maxf(
					radius,
					Vector2(point.x - center.x, point.z - center.z).length()
				)
		offset += surface.vertices.size()
	return radius


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
	var minimum_y := INF
	var count := 0
	var offset := 0
	for surface: Dictionary in data.surfaces:
		for i in surface.vertices.size():
			var hand_weight := 0.0
			for k in surface.influences:
				var slot: int = i * surface.influences + k
				var influenced_bone: int = data.binds[surface.bones[slot]]
				while influenced_bone >= 0 and influenced_bone != bone:
					influenced_bone = skeleton.get_bone_parent(influenced_bone)
				if influenced_bone == bone:
					hand_weight += surface.weights[slot]
			if hand_weight > 0.55:
				var point: Vector3 = points[offset + i]
				center += point
				minimum_y = minf(minimum_y, point.y)
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
		"min_y": minimum_y,
	}


func _apply_sealed_hand_clearance() -> void:
	if not _model_fitted:
		return
	var units: float = scene.measurement_tool.meters_to_world(1.0)
	var target_radius := (PRISON_RADIUS_METERS + SEALED_HAND_CLEARANCE_METERS) * units
	for side: String in ["left", "right"]:
		var hand_bone := skeleton.find_bone("hand.l" if side == "left" else "hand.r")
		if hand_bone < 0:
			hand_bone = skeleton.find_bone("hand_l" if side == "left" else "hand_r")
		if hand_bone < 0:
			continue
		var offset := Vector3.ZERO
		# Re-evaluate after each push because finger skin weights blend at the wrist.
		for iteration in range(4):
			var metrics := _sealed_hand_metrics(side)
			if metrics.is_empty():
				break
			var required_push := target_radius - float(metrics.min_radius)
			if required_push <= 0.001:
				break
			var outward: Vector3 = (metrics.center - model.global_position).normalized()
			var parent_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand_bone))
			var local_push := parent_world.basis.inverse() * (outward * minf(required_push, SEALED_HAND_MAX_PUSH_METERS * units))
			skeleton.set_bone_pose_position(hand_bone, skeleton.get_bone_pose_position(hand_bone) + local_push)
			skeleton.force_update_all_bone_transforms()
			offset += local_push
		if not _sealed_hand_offsets.has(side):
			_sealed_hand_offsets[side] = offset
			_bake_hand_clearance(side, offset)


func _bake_hand_clearance(side: String, offset: Vector3) -> void:
	var animation: Animation = player.get_animation(_clips[side])
	var suffix: String = ".l" if side == "left" else ".r"
	for track in animation.get_track_count():
		var bone := String(animation.track_get_path(track)).get_slice(":", 1)
		if bone not in ["hand" + suffix, "hand" + suffix.replace(".", "_")]:
			continue
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		var resting: Vector3 = animation.track_get_key_value(track, 0)
		animation.track_remove_key(track, 0)
		for frame in range(43):
			var time := frame / 30.0
			var remaining := 1.0 - smoothstep(0.4, 1.1, time)
			animation.position_track_insert_key(track, time, resting + offset * remaining)


func _refine_animation_timing() -> void:
	# Ease each phase and lead with the shoulder, then elbow, then wrist.
	# The contact event at frame 38 and the final platform pose stay fixed.
	for side: String in ["left", "right", "forehead"]:
		var animation: Animation = player.get_animation(_clips[side])
		var source := animation.duplicate(true) as Animation
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or animation.track_get_key_count(track) <= 1:
				continue
			var bone := String(animation.track_get_path(track)).get_slice(":", 1)
			var lag := 0.035 if bone.begins_with("forearm") else (0.065 if bone.begins_with("hand") else 0.0)
			for key in range(animation.track_get_key_count(track) - 1, -1, -1):
				animation.track_remove_key(track, key)
			for frame in range(43):
				var time := frame / 30.0
				var sample := time
				# Release, anticipation, strike, and settle each have zero end velocity.
				var phases := [0.0, 0.4, 0.7, 38.0 / 30.0, 1.4]
				var authored := [0.0, 0.8, 1.0, 38.0 / 30.0, 1.4]
				for phase in range(phases.size() - 1):
					var start: float = phases[phase]
					var end: float = phases[phase + 1]
					if time >= start and time <= end:
						var delayed := lag * sin(PI * clampf((time - start) / (end - start), 0.0, 1.0))
						sample = lerpf(authored[phase], authored[phase + 1], smoothstep(start, end, time - delayed))
						break
				animation.rotation_track_insert_key(track, time, source.rotation_track_interpolate(track, sample))


func _bring_head_details_forward() -> void:
	# Shift the existing details in head bind space so they follow its bow.
	# The flowing hair blends this offset into its head weights only.
	var head := skeleton.find_bone("head")
	var cap := model.find_child("Klotis_Golden_Hair_Cap_V5", true, false) as MeshInstance3D
	var scalp_center := cap.mesh.get_aabb().get_center()
	for label: String in ["Klotis_Golden_Hair_Cap_V5", "Klotis_Full_Forehead_Hair", "Klotis_Fine_Scalp_Strands_V5", "Klotis_Flowing_Gold_Hair_V5", "Klotis_Curved_Horns_Six_V5"]:
		var node := model.find_child(label, true, false) as MeshInstance3D
		if node == null or node.skin == null:
			continue
		var source := node.mesh
		var mesh := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := int(bones.size() / float(vertices.size()))
			for vertex in vertices.size():
				for influence in influences:
					var slot := vertex * influences + influence
					var bind := bones[slot]
					var bone := node.skin.get_bind_bone(bind)
					if bone < 0:
						bone = skeleton.find_bone(node.skin.get_bind_name(bind))
					if bone == head and weights[slot] > 0.0:
						var bind_pose := node.skin.get_bind_pose(bind)
						var adjustment := Vector3(0, 0, 0.20)
						if label not in ["Klotis_Curved_Horns_Six_V5", "Klotis_Flowing_Gold_Hair_V5"]:
							var relative: Vector3 = bind_pose * vertices[vertex] - bind_pose * scalp_center
							adjustment = Vector3(0, 0, 0.16) + relative * Vector3(0.08, 0.12, 0.28)
						vertices[vertex] += bind_pose.basis.inverse() * adjustment * weights[slot]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			mesh.surface_set_material(surface, source.surface_get_material(surface))
		node.mesh = mesh
		_skin_cache.erase(node)


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
	# Find the centre of the actual upward-facing flat cut at the top of the
	# headless neck.  Using only the single highest vertex was unstable and
	# could aim at one edge of the stump.
	var all_points := PackedVector3Array()
	var surface_data: Array[Dictionary] = []
	var min_y := INF
	var max_y := -INF

	for surface_index in statue.mesh.get_surface_count():
		var arrays: Array = statue.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		surface_data.append({
			"vertices": vertices,
			"indices": indices,
		})
		for vertex: Vector3 in vertices:
			var world_point: Vector3 = statue.global_transform * vertex
			all_points.append(world_point)
			min_y = minf(min_y, world_point.y)
			max_y = maxf(max_y, world_point.y)

	if all_points.is_empty():
		return statue.global_position

	var height: float = maxf(max_y - min_y, 0.001)
	var top_band_min: float = max_y - height * 0.14
	var weighted_center := Vector3.ZERO
	var total_area := 0.0

	for surface: Dictionary in surface_data:
		var vertices: PackedVector3Array = surface.vertices
		var indices: PackedInt32Array = surface.indices
		var triangle_count: int = (
			indices.size() / 3
			if not indices.is_empty()
			else vertices.size() / 3
		)
		for triangle_index in range(triangle_count):
			var base: int = triangle_index * 3
			var ia: int = (
				indices[base]
				if not indices.is_empty()
				else base
			)
			var ib: int = (
				indices[base + 1]
				if not indices.is_empty()
				else base + 1
			)
			var ic: int = (
				indices[base + 2]
				if not indices.is_empty()
				else base + 2
			)
			var a: Vector3 = statue.global_transform * vertices[ia]
			var b: Vector3 = statue.global_transform * vertices[ib]
			var c: Vector3 = statue.global_transform * vertices[ic]
			var centroid: Vector3 = (a + b + c) / 3.0
			if centroid.y < top_band_min:
				continue
			var cross: Vector3 = (b - a).cross(c - a)
			var twice_area: float = cross.length()
			if twice_area <= 0.000001:
				continue
			var flatness: float = absf(
				cross.normalized().dot(Vector3.UP)
			)
			if flatness < 0.72:
				continue
			var area: float = twice_area * 0.5
			weighted_center += centroid * area
			total_area += area

	if total_area > 0.000001:
		return weighted_center / total_area

	# Fallback: average a small top-height band.  This is still much more
	# stable than choosing only vertices exactly at max_y.
	var fallback_center := Vector3.ZERO
	var fallback_count := 0
	var tolerance: float = maxf(height * 0.035, 0.01)
	for point: Vector3 in all_points:
		if max_y - point.y <= tolerance:
			fallback_center += point
			fallback_count += 1
	if fallback_count > 0:
		return fallback_center / float(fallback_count)
	return statue.global_position
