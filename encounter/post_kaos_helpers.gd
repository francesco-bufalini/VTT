extends RefCounted

# Physical encounter geometry lives on layer 1 so normal CharacterBody3D tokens
# can actually collide with it.  The post-Kaos volumetric grid uses a separate
# proxy layer and therefore does not voxelize the whole pair of giants.
const SOLID_LAYER := 1
const RIGHT_ARM_GRID_LAYER := 8
const BODY_COLLISION_NAME := "WalkableBodyCollision"
const COLLISION_VERSION := 3

const KAOS_HEAD_CUT_Y_METERS := 116.5
const KAOS_HEAD_CUT_HALF_WIDTH_METERS := 13.0
const KAOS_SHOULDER_CAP_NAME := "KaosShoulderCap"
const KAOS_RIGHT_ARM_GRID_NAME := "KaosRightArmGridProxy"
const SPHERE_SOLID_BODY_NAME := "SphereSolidBody"

static func remove_legacy_platforms(scene: Node) -> void:
	for path in [
		"KaosRoot/ShoulderPlatform",
		"HandPlatforms",
	]:
		var node := scene.get_node_or_null(path)
		if node != null:
			node.free()

static func remove_kaos_phase_two_token(scene: Node) -> void:
	var tokens := scene.get_node_or_null("Tokens")
	if tokens == null:
		return
	for child in tokens.get_children():
		if (
			child.name == "KaosPhaseTwo"
			or bool(child.get_meta("kaos_phase_two", false))
		):
			child.free()

static func clear_baked_tokens(scene: Node) -> void:
	var tokens := scene.get_node_or_null("Tokens")
	if tokens == null:
		return
	for child in tokens.get_children():
		child.free()

# Keep the petrified body/arms, but remove Kaos' head and neck.  The clip is
# deliberately limited to the centre of the upper body so raised arms survive.
# A real stone cap closes the cut: from above the shoulders are a continuous,
# opaque walkable surface rather than an opening into the anatomy mesh.
static func prepare_headless_kaos(scene: Node) -> void:
	var kaos := scene.get_node_or_null("KaosRoot") as Node3D
	if kaos == null:
		return
	var visual := kaos.get_node_or_null("ClimbingVisual") as Node3D
	if visual == null or not visual.visible:
		visual = kaos.get_node_or_null("KaosVisual") as Node3D
	if visual == null:
		return

	var units: float = _meters_to_world(scene)
	var stone := _stone_material()
	var clipped_stone := _kaos_clipped_stone_material(
		kaos.global_position,
		units
	)

	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var label := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if (
			"Hair" in label
			or "Lock" in label
			or "Crown" in label
			or "Sclera" in label
			or "Iris" in label
			or "Pupil" in label
			or "Lightning" in label
		):
			mesh_instance.hide()
			continue
		if mesh_instance.name == KAOS_SHOULDER_CAP_NAME:
			continue
		mesh_instance.material_override = clipped_stone
		mesh_instance.set_meta("post_kaos_head_clipped", true)

	_ensure_kaos_shoulder_cap(visual, units, stone)
	visual.set_meta("post_kaos_headless", true)

# Backward-compatible alias for older baked scenes/scripts.
static func close_kaos_petrification_hole(scene: Node) -> void:
	prepare_headless_kaos(scene)

static func ensure_surface_collisions(scene: Node) -> void:
	var units: float = _meters_to_world(scene)

	var kaos_visual := scene.get_node_or_null(
		"KaosRoot/ClimbingVisual"
	) as Node3D
	if kaos_visual == null or not kaos_visual.visible:
		kaos_visual = scene.get_node_or_null(
			"KaosRoot/KaosVisual"
		) as Node3D
	if kaos_visual != null:
		_ensure_anatomy_collisions(
			kaos_visual,
			units,
			true
		)
		_ensure_cap_collision(kaos_visual, units)
		_ensure_right_arm_grid_proxy(kaos_visual, units)

	var klothis_visual := scene.get_node_or_null(
		"KlothisRoot/KlothisVisual"
	) as Node3D
	if klothis_visual != null:
		_ensure_anatomy_collisions(
			klothis_visual,
			units,
			false
		)

	_ensure_sphere_collision(scene, units)

# Compatibility with the previous helper API.
static func ensure_body_collisions(scene: Node) -> void:
	ensure_surface_collisions(scene)

static func _ensure_anatomy_collisions(
	visual: Node3D,
	units: float,
	clip_kaos_head: bool
) -> void:
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.visible:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if not role.begins_with("Anatomy"):
			continue

		var existing := mesh_instance.get_node_or_null(
			BODY_COLLISION_NAME
		) as StaticBody3D
		if (
			existing != null
			and int(existing.get_meta("post_kaos_collision_version", 0))
				== COLLISION_VERSION
		):
			continue
		if existing != null:
			existing.free()

		var shape: Shape3D = null
		if clip_kaos_head:
			shape = _kaos_body_shape_without_head(
				mesh_instance,
				visual,
				units
			)
		else:
			shape = mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue

		var body := StaticBody3D.new()
		body.name = BODY_COLLISION_NAME
		body.collision_layer = SOLID_LAYER
		body.collision_mask = 0
		body.add_to_group("tactical_platform")
		body.set_meta("post_kaos_body_collision", true)
		body.set_meta(
			"post_kaos_collision_version",
			COLLISION_VERSION
		)
		mesh_instance.add_child(body)

		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		collider.shape = shape
		body.add_child(collider)

static func _kaos_body_shape_without_head(
	mesh_instance: MeshInstance3D,
	visual: Node3D,
	units: float
) -> Shape3D:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return null

	var to_visual: Transform3D = (
		visual.global_transform.affine_inverse()
		* mesh_instance.global_transform
	)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kept_triangles := 0

	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in range(vertices.size()):
				indices[index] = index

		for index in range(0, indices.size() - 2, 3):
			var raw_a: Vector3 = vertices[indices[index]]
			var raw_b: Vector3 = vertices[indices[index + 1]]
			var raw_c: Vector3 = vertices[indices[index + 2]]
			var a: Vector3 = (to_visual * raw_a) / units
			var b: Vector3 = (to_visual * raw_b) / units
			var c: Vector3 = (to_visual * raw_c) / units
			var centroid := (a + b + c) / 3.0
			var upper_vertices := 0
			for point in [a, b, c]:
				if _point_is_kaos_head_or_neck(point):
					upper_vertices += 1

			# Removing a triangle as soon as two vertices belong to the central
			# head/neck volume prevents invisible pieces from remaining solid.
			if (
				upper_vertices >= 2
				or _point_is_kaos_head_or_neck(centroid)
			):
				continue

			surface.add_vertex(raw_a)
			surface.add_vertex(raw_b)
			surface.add_vertex(raw_c)
			kept_triangles += 1

	if kept_triangles == 0:
		return null
	var clipped_mesh := surface.commit()
	if clipped_mesh == null:
		return null
	return clipped_mesh.create_trimesh_shape()

static func _point_is_kaos_head_or_neck(point: Vector3) -> bool:
	return (
		point.y > KAOS_HEAD_CUT_Y_METERS
		and absf(point.x) < KAOS_HEAD_CUT_HALF_WIDTH_METERS
	)

static func _ensure_kaos_shoulder_cap(
	visual: Node3D,
	units: float,
	stone: Material
) -> void:
	var cap := visual.get_node_or_null(
		KAOS_SHOULDER_CAP_NAME
	) as MeshInstance3D
	if cap == null:
		var mesh := CylinderMesh.new()
		mesh.top_radius = units
		mesh.bottom_radius = units
		mesh.height = 0.8 * units
		mesh.radial_segments = 64
		mesh.rings = 1
		cap = MeshInstance3D.new()
		cap.name = KAOS_SHOULDER_CAP_NAME
		cap.mesh = mesh
		cap.position = Vector3(
			0.0,
			KAOS_HEAD_CUT_Y_METERS - 0.15,
			0.0
		) * units
		# Broad across both shoulders, but only as deep as the upper torso.
		cap.scale = Vector3(13.0, 1.0, 9.5)
		cap.set_meta("visual_role", KAOS_SHOULDER_CAP_NAME)
		cap.set_meta("post_kaos_shoulder_cap", true)
		visual.add_child(cap)
	cap.material_override = stone
	cap.show()

static func _ensure_cap_collision(
	visual: Node3D,
	units: float
) -> void:
	var cap := visual.get_node_or_null(
		KAOS_SHOULDER_CAP_NAME
	) as MeshInstance3D
	if cap == null:
		return
	var body := cap.get_node_or_null(
		BODY_COLLISION_NAME
	) as StaticBody3D
	if (
		body != null
		and int(body.get_meta("post_kaos_collision_version", 0))
			== COLLISION_VERSION
	):
		return
	if body != null:
		body.free()

	body = StaticBody3D.new()
	body.name = BODY_COLLISION_NAME
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.add_to_group("tactical_platform")
	body.set_meta("post_kaos_shoulder_collision", true)
	body.set_meta("post_kaos_collision_version", COLLISION_VERSION)
	cap.add_child(body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	# The shape is local to the already scaled visual cap.
	shape.size = Vector3(
		2.0 * units,
		0.8 * units,
		2.0 * units
	)
	collision.shape = shape
	body.add_child(collision)

static func _ensure_sphere_collision(
	scene: Node,
	units: float
) -> void:
	var sphere_root := scene.get_node_or_null(
		"KlothisRoot/SphereVisual"
	) as Node3D
	if sphere_root == null:
		return
	var body := sphere_root.get_node_or_null(
		SPHERE_SOLID_BODY_NAME
	) as StaticBody3D
	if (
		body != null
		and int(body.get_meta("post_kaos_collision_version", 0))
			== COLLISION_VERSION
	):
		return
	if body != null:
		body.free()

	body = StaticBody3D.new()
	body.name = SPHERE_SOLID_BODY_NAME
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.add_to_group("tactical_platform")
	body.set_meta("post_kaos_sphere_collision", true)
	body.set_meta("post_kaos_collision_version", COLLISION_VERSION)
	sphere_root.add_child(body)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = 220.0 * units
	collision.shape = shape
	body.add_child(collision)

static func _ensure_right_arm_grid_proxy(
	visual: Node3D,
	units: float
) -> void:
	var existing := visual.get_node_or_null(
		KAOS_RIGHT_ARM_GRID_NAME
	) as StaticBody3D
	if (
		existing != null
		and int(existing.get_meta("post_kaos_collision_version", 0))
			== COLLISION_VERSION
	):
		return
	if existing != null:
		existing.free()

	var proxy := StaticBody3D.new()
	proxy.name = KAOS_RIGHT_ARM_GRID_NAME
	proxy.collision_layer = RIGHT_ARM_GRID_LAYER
	proxy.collision_mask = 0
	proxy.set_meta("post_kaos_right_arm_grid", true)
	proxy.set_meta("post_kaos_collision_version", COLLISION_VERSION)
	visual.add_child(proxy)

	# Same climbing-pose landmarks used by hero_costume.gd for Kaos' right
	# bracer.  The proxy is grid-only: the exact anatomy collider below it
	# remains responsible for token placement and physical support.
	var points: Array[Vector3] = [
		Vector3(12.0, 117.0, -8.0),
		Vector3(26.0, 125.0, -23.0),
		Vector3(28.0, 140.0, -46.0),
		Vector3(29.0, 143.0, -51.0),
	]
	var radii: Array[float] = [5.2, 4.7, 3.8]
	for index in range(points.size() - 1):
		_add_grid_capsule(
			proxy,
			points[index] * units,
			points[index + 1] * units,
			radii[index] * units,
			index
		)

static func _add_grid_capsule(
	parent: StaticBody3D,
	from: Vector3,
	to: Vector3,
	radius: float,
	index: int
) -> void:
	var axis := to - from
	var length := axis.length()
	if length <= 0.001:
		return
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(length + radius * 2.0, radius * 2.0)

	var collision := CollisionShape3D.new()
	collision.name = "RightArmGridSegment%d" % index
	collision.shape = shape
	collision.position = (from + to) * 0.5
	collision.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	parent.add_child(collision)

static func _stone_material() -> ShaderMaterial:
	var stone := ShaderMaterial.new()
	stone.shader = load("res://encounter/sphere_surface.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	return stone

static func _kaos_clipped_stone_material(
	giant_origin: Vector3,
	units: float
) -> ShaderMaterial:
	var stone := ShaderMaterial.new()
	var shader := Shader.new()
	var code := FileAccess.get_file_as_string(
		"res://encounter/sphere_surface.gdshader"
	)
	code = code.replace(
		"void fragment() {",
		(
			"uniform vec3 giant_origin;\n"
			+ "uniform float unit_scale;\n"
			+ "varying vec3 world_point;\n"
			+ "void vertex() { "
			+ "world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }\n"
			+ "void fragment() {\n"
			+ " vec3 local=(world_point-giant_origin)/unit_scale;\n"
			+ " if(local.y>%f && abs(local.x)<%f) { discard; }\n"
		)
		% [
			KAOS_HEAD_CUT_Y_METERS,
			KAOS_HEAD_CUT_HALF_WIDTH_METERS,
		]
	)
	shader.code = code
	stone.shader = shader
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	stone.set_shader_parameter("giant_origin", giant_origin)
	stone.set_shader_parameter("unit_scale", units)
	return stone

static func _meters_to_world(scene: Node) -> float:
	var tool := scene.get_node_or_null("MeasurementTool")
	if tool != null and tool.has_method("meters_to_world"):
		return float(tool.call("meters_to_world", 1.0))
	return 1.0

static func has_post_roster(scene: Node) -> bool:
	var tokens := scene.get_node_or_null("Tokens")
	if tokens == null:
		return false
	for child in tokens.get_children():
		if bool(child.get_meta("post_kaos_roster", false)):
			return true
	return false
