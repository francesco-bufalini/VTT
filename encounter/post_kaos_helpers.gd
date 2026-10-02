extends RefCounted

const WALKABLE_LAYER := 1
const RIGHT_ARM_GRID_LAYER := 8
const BODY_COLLISION_NAME := "WalkableBodyCollision"
const GRID_EXCLUDED_GROUP := "grid_3d_excluded"
const COLLISION_VERSION := 6
const GEOMETRY_VERSION := 4
const SCONTRO_GEOMETRY_VERSION := 1
const DECOR_VERSION := 5

# Kaos' final one-hand pose keeps the head around y=136 m.  Remove the
# complete skull plus the central neck column, while preserving the shoulders
# and both arms.  The visible shoulder cap then closes the cut as solid stone.
const KAOS_HEAD_CENTER_METERS := Vector3(0.0, 136.0, 0.0)
const KAOS_HEAD_RADIUS_METERS := 17.5
const KAOS_NECK_BOTTOM_METERS := 108.0
const KAOS_NECK_TOP_METERS := 130.0
const KAOS_NECK_RADIUS_X_METERS := 12.5
const KAOS_NECK_RADIUS_Z_METERS := 11.0

# Scontro contro Kaos keeps a visible, solid stump at the base of the neck.
# Only the head and upper neck are removed.
const SCONTRO_NECK_CUT_BOTTOM_METERS := 121.5
const SCONTRO_NECK_CUT_TOP_METERS := 130.0
const SCONTRO_NECK_RADIUS_X_METERS := 12.5
const SCONTRO_NECK_RADIUS_Z_METERS := 11.0

# The grid proxy is deliberately narrower than the physical Kaos collider.
# Only the positive-X bracing arm should produce blue volumetric cells.
const KAOS_RIGHT_ARM_MIN_X_METERS := 17.0
const KAOS_RIGHT_ARM_MIN_Y_METERS := 101.0
const KAOS_RIGHT_ARM_MAX_Y_METERS := 149.0
const KAOS_RIGHT_ARM_MAX_Z_METERS := 1.0
const KAOS_RIGHT_ARM_MIN_Z_METERS := -58.0

const RUIN_NODE_NAMES: Array[String] = [
	"FlutedColumns",
	"Capitals",
	"RomanArches",
	"Cornices",
	"ColumnPlinths",
	"ContinuousApseWall",
]

const KAOS_HEAD_VISUAL_TERMS: Array[String] = [
	"Hair",
	"Lock",
	"Crown",
	"Sclera",
	"Iris",
	"Pupil",
	"Brow",
	"Mouth",
	"Blindfold",
	"FittedGoldCollar",
	"GoldCollarRim",
	"Lightning",
]

const KLOTHYS_HAIR_TERMS: Array[String] = [
	"AnatomicalHairline",
	"RootedSilverLock",
	"PartedTempleLock",
	"HangingSilverTress",
	"PartedHairCap",
	"SculptedHairLock",
]


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


static func active_kaos_visual(scene: Node) -> Node3D:
	var kaos := scene.get_node_or_null("KaosRoot") as Node3D
	if kaos == null:
		return null
	var climbing := kaos.get_node_or_null("ClimbingVisual") as Node3D
	if climbing != null and climbing.visible:
		return climbing
	return kaos.get_node_or_null("KaosVisual") as Node3D


static func prepare_kaos_petrified_geometry(scene: Node) -> void:
	var visual := active_kaos_visual(scene)
	if visual == null:
		return
	var units := _scene_units(scene)
	if units <= 0.0:
		return

	if int(visual.get_meta("post_kaos_geometry_version", 0)) < GEOMETRY_VERSION:
		_freeze_active_blend_shapes(visual)
		_clip_kaos_head_and_neck(visual, units)
		_remove_kaos_head_accessories(visual)
		visual.set_meta("post_kaos_geometry_version", GEOMETRY_VERSION)

	var stone := _stone_material()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not mesh_instance.visible:
			continue
		mesh_instance.material_override = stone

	_ensure_kaos_shoulder_cap(visual, units, stone)


static func prepare_scontro_kaos_terrain(scene: Node) -> void:
	var visual := active_kaos_visual(scene)
	if visual == null:
		return
	var units := _scene_units(scene)
	if units <= 0.0:
		return

	if (
		int(visual.get_meta("scontro_kaos_geometry_version", 0))
		< SCONTRO_GEOMETRY_VERSION
	):
		_freeze_active_blend_shapes(visual)
		_clip_scontro_kaos_head_and_upper_neck(visual, units)
		_remove_kaos_head_accessories(visual)
		visual.set_meta(
			"scontro_kaos_geometry_version",
			SCONTRO_GEOMETRY_VERSION
		)

	var stone := _stone_material()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not mesh_instance.visible:
			continue
		mesh_instance.material_override = stone

	_ensure_scontro_shoulder_fill(visual, units, stone)
	_ensure_scontro_neck_base(visual, units, stone)


static func disable_scontro_legacy_platforms(scene: Node) -> void:
	# Keep the ShoulderPlatform node alive because the encounter controller
	# still references it, but make it physically inert. The visible Kaos body,
	# shoulder fill and neck stump are now the actual terrain.
	var shoulder := scene.get_node_or_null(
		"KaosRoot/ShoulderPlatform"
	) as CollisionObject3D
	if shoulder != null:
		shoulder.collision_layer = 0
		shoulder.collision_mask = 0
		if shoulder.is_in_group("tactical_platform"):
			shoulder.remove_from_group("tactical_platform")
		for node in shoulder.find_children(
			"*",
			"CollisionShape3D",
			true,
			false
		):
			var shape := node as CollisionShape3D
			if shape != null:
				shape.set_deferred("disabled", true)

	var hand_platforms := scene.get_node_or_null("HandPlatforms")
	if hand_platforms != null:
		hand_platforms.free()


# Compatibility alias used by older baked post-Kaos scenes.
static func close_kaos_petrification_hole(scene: Node) -> void:
	prepare_kaos_petrified_geometry(scene)


static func restore_encounter_decor(
	scene: Node,
	force_rebuild: bool = false
) -> void:
	var current := int(scene.get_meta("post_kaos_decor_version", 0))
	if (
		not force_rebuild
		and current >= DECOR_VERSION
		and _decor_is_complete(scene)
	):
		_ensure_decor_visible(scene)
		return

	# Fallback used at runtime when the baked scene is incomplete. The bake/
	# upgrader uses copy_decor_from_scontro() below so the committed .scn
	# contains the literal visual result of Scontro contro Kaos.
	var units := _scene_units(scene)
	if units <= 0.0:
		return
	preload("res://encounter/encounter_scenery.gd").new().call(
		"replace_klothis_sphere_and_ruins_from_encounter",
		scene
	)
	_ensure_decor_visible(scene)
	scene.set_meta("post_kaos_decor_version", DECOR_VERSION)


static func copy_decor_from_scontro(
	destination: Node,
	source: Node
) -> bool:
	if destination == null or source == null:
		return false

	var src_klothys_root := source.get_node_or_null("KlothisRoot") as Node3D
	var dst_klothys_root := destination.get_node_or_null("KlothisRoot") as Node3D
	if src_klothys_root == null or dst_klothys_root == null:
		return false

	var src_visual := src_klothys_root.get_node_or_null("KlothisVisual") as Node3D
	var src_sphere := src_klothys_root.get_node_or_null("SphereVisual") as Node3D
	var dst_visual := dst_klothys_root.get_node_or_null("KlothisVisual") as Node3D
	var dst_sphere := dst_klothys_root.get_node_or_null("SphereVisual") as Node3D
	if (
		src_visual == null
		or src_sphere == null
		or dst_visual == null
		or dst_sphere == null
	):
		return false

	# Preserve only the destination containers. Replace their complete visual
	# contents with duplicates of the *actual runtime Scontro scene*.
	for child in dst_visual.get_children().duplicate():
		child.free()
	for child in dst_sphere.get_children().duplicate():
		child.free()

	dst_klothys_root.transform = src_klothys_root.transform
	dst_visual.transform = src_visual.transform
	dst_sphere.transform = src_sphere.transform

	for child in src_visual.get_children():
		var copy := child.duplicate(
			Node.DUPLICATE_SIGNALS
			| Node.DUPLICATE_GROUPS
			| Node.DUPLICATE_SCRIPTS
			| Node.DUPLICATE_USE_INSTANTIATION
		)
		if copy != null:
			dst_visual.add_child(copy)

	for child in src_sphere.get_children():
		var copy := child.duplicate(
			Node.DUPLICATE_SIGNALS
			| Node.DUPLICATE_GROUPS
			| Node.DUPLICATE_SCRIPTS
			| Node.DUPLICATE_USE_INSTANTIATION
		)
		if copy != null:
			dst_sphere.add_child(copy)

	var src_ruins := source.get_node_or_null("Board/MapGeometry") as Node3D
	var dst_ruins := destination.get_node_or_null("Board/MapGeometry") as Node3D
	if src_ruins == null or dst_ruins == null:
		return false

	for node_name in RUIN_NODE_NAMES:
		var old := dst_ruins.get_node_or_null(node_name)
		if old != null:
			old.free()
		var original := src_ruins.get_node_or_null(node_name)
		if original == null:
			continue
		var copy := original.duplicate(
			Node.DUPLICATE_SIGNALS
			| Node.DUPLICATE_GROUPS
			| Node.DUPLICATE_SCRIPTS
			| Node.DUPLICATE_USE_INSTANTIATION
		)
		if copy != null:
			dst_ruins.add_child(copy)

	_ensure_decor_visible(destination)
	destination.set_meta("post_kaos_decor_version", DECOR_VERSION)
	destination.set_meta("post_kaos_decor_source", "scontro_contro_kaos_runtime")
	return true


static func ensure_solid_surfaces(
	scene: Node,
	full_grid_surfaces: bool = false
) -> void:
	var grid_mode := "full" if full_grid_surfaces else "right_arm"
	var current := int(scene.get_meta("post_kaos_collision_version", 0))
	if (
		current >= COLLISION_VERSION
		and String(scene.get_meta("post_kaos_grid_mode", "")) == grid_mode
		and _solid_surface_set_is_complete(scene, full_grid_surfaces)
	):
		return

	_remove_generated_collisions(scene)

	var kaos_visual := active_kaos_visual(scene)
	if kaos_visual != null:
		# Exact trimesh bodies remain the physical support for tokens. They are
		# intentionally excluded from direct grid probing; dedicated layer-8
		# surface proxies below feed the blue grid without changing physics.
		_add_anatomy_collisions(kaos_visual, true, "kaos")
		var cap := kaos_visual.get_node_or_null(
			"PetrifiedShoulderCap"
		) as MeshInstance3D
		if cap != null:
			_add_mesh_collision(cap, true, "kaos_shoulders")
		var neck_base := kaos_visual.get_node_or_null(
			"PetrifiedNeckBase"
		) as MeshInstance3D
		if neck_base != null:
			_add_mesh_collision(neck_base, true, "kaos_neck_base")

		if full_grid_surfaces:
			_add_anatomy_grid_proxies(
				kaos_visual,
				"kaos_grid"
			)
			if cap != null:
				_add_mesh_grid_proxy(cap, "kaos_shoulders_grid")
			if neck_base != null:
				_add_mesh_grid_proxy(
					neck_base,
					"kaos_neck_base_grid"
				)
		else:
			_add_kaos_right_arm_grid_proxy(scene, kaos_visual)

	var klothys := scene.get_node_or_null(
		"KlothisRoot/KlothisVisual"
	) as Node3D
	if klothys != null and klothys.visible:
		_add_anatomy_collisions(klothys, true, "klothys")
		if full_grid_surfaces:
			_add_anatomy_grid_proxies(
				klothys,
				"klothys_grid"
			)

	_add_sphere_collision(scene)
	if full_grid_surfaces:
		_add_sphere_grid_proxy(scene)

	scene.set_meta("post_kaos_collision_version", COLLISION_VERSION)
	scene.set_meta("post_kaos_grid_mode", grid_mode)


# Compatibility alias kept for the previous post-Kaos runtime script.
static func ensure_body_collisions(scene: Node) -> void:
	ensure_solid_surfaces(scene)


static func has_post_roster(scene: Node) -> bool:
	var tokens := scene.get_node_or_null("Tokens")
	if tokens == null:
		return false
	for child in tokens.get_children():
		if bool(child.get_meta("post_kaos_roster", false)):
			return true
	return false


static func _scene_units(scene: Node) -> float:
	var measurement := scene.get_node_or_null("MeasurementTool")
	if measurement == null or not measurement.has_method("meters_to_world"):
		return 0.0
	return float(measurement.call("meters_to_world", 1.0))


static func _stone_material() -> ShaderMaterial:
	var stone := ShaderMaterial.new()
	stone.shader = load("res://encounter/sphere_surface.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	return stone


static func _freeze_active_blend_shapes(visual: Node3D) -> void:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		# Collision and head clipping only depend on the authored anatomy.
		# Leaving cloth, hair and ornaments as blend-shaped render meshes avoids
		# rebuilding hundreds of heavy procedural meshes during the bake.
		if not role.begins_with("Anatomy"):
			continue
		var source: Mesh = mesh_instance.mesh
		var blend_count: int = source.get_blend_shape_count()
		if blend_count <= 0:
			continue

		var active_index := -1
		var active_weight := 0.0
		for index in range(blend_count):
			var weight := absf(mesh_instance.get_blend_shape_value(index))
			if weight > active_weight:
				active_weight = weight
				active_index = index
		if active_index < 0 or active_weight < 0.001:
			continue

		var frozen := ArrayMesh.new()
		for surface_index in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface_index).duplicate(true)
			var blend_arrays: Array = source.surface_get_blend_shape_arrays(
				surface_index
			)
			if active_index < blend_arrays.size():
				var target: Array = blend_arrays[active_index]
				for slot in [
					Mesh.ARRAY_VERTEX,
					Mesh.ARRAY_NORMAL,
					Mesh.ARRAY_TANGENT,
				]:
					if slot >= target.size():
						continue
					var target_value: Variant = target[slot]
					if target_value != null:
						arrays[slot] = target_value
			frozen.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := source.surface_get_material(surface_index)
			if material != null:
				frozen.surface_set_material(surface_index, material)
		mesh_instance.mesh = frozen


static func _clip_kaos_head_and_neck(visual: Node3D, units: float) -> void:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if not role.begins_with("Anatomy"):
			continue

		var source: Mesh = mesh_instance.mesh
		var clipped := ArrayMesh.new()
		for surface_index in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface_index).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in range(vertices.size()):
					indices[index] = index

			var kept := PackedInt32Array()
			for index in range(0, indices.size() - 2, 3):
				var a := indices[index]
				var b := indices[index + 1]
				var c := indices[index + 2]
				if (
					_keep_kaos_anatomy_vertex(
						mesh_instance.transform * vertices[a],
						units
					)
					and _keep_kaos_anatomy_vertex(
						mesh_instance.transform * vertices[b],
						units
					)
					and _keep_kaos_anatomy_vertex(
						mesh_instance.transform * vertices[c],
						units
					)
				):
					kept.append(a)
					kept.append(b)
					kept.append(c)
			arrays[Mesh.ARRAY_INDEX] = kept
			if kept.size() < 3:
				continue
			clipped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := source.surface_get_material(surface_index)
			if material != null:
				clipped.surface_set_material(
					clipped.get_surface_count() - 1,
					material
				)
		# Assign the clipped mesh even when every triangle was removed.
		# Head-only AnatomicalDetail meshes otherwise kept their untouched
		# original geometry and could leave floating ears/face pieces behind.
		mesh_instance.mesh = clipped
		if clipped.get_surface_count() == 0:
			mesh_instance.hide()


static func _clip_scontro_kaos_head_and_upper_neck(
	visual: Node3D,
	units: float
) -> void:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if not role.begins_with("Anatomy"):
			continue

		var source: Mesh = mesh_instance.mesh
		var clipped := ArrayMesh.new()
		for surface_index in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(
				surface_index
			).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in range(vertices.size()):
					indices[index] = index

			var kept := PackedInt32Array()
			for index in range(0, indices.size() - 2, 3):
				var a := indices[index]
				var b := indices[index + 1]
				var d := indices[index + 2]
				if (
					_keep_scontro_kaos_vertex(
						mesh_instance.transform * vertices[a],
						units
					)
					and _keep_scontro_kaos_vertex(
						mesh_instance.transform * vertices[b],
						units
					)
					and _keep_scontro_kaos_vertex(
						mesh_instance.transform * vertices[d],
						units
					)
				):
					kept.append(a)
					kept.append(b)
					kept.append(d)
			arrays[Mesh.ARRAY_INDEX] = kept
			if kept.size() < 3:
				continue
			clipped.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				arrays
			)
			var material := source.surface_get_material(surface_index)
			if material != null:
				clipped.surface_set_material(
					clipped.get_surface_count() - 1,
					material
				)

		mesh_instance.mesh = clipped
		if clipped.get_surface_count() == 0:
			mesh_instance.hide()


static func _keep_scontro_kaos_vertex(
	point_world_units: Vector3,
	units: float
) -> bool:
	var point := point_world_units / units
	return not _is_scontro_head_or_upper_neck(point)


static func _is_scontro_head_or_upper_neck(point: Vector3) -> bool:
	if point.distance_to(KAOS_HEAD_CENTER_METERS) <= KAOS_HEAD_RADIUS_METERS:
		return true
	if (
		point.y >= SCONTRO_NECK_CUT_BOTTOM_METERS
		and point.y <= SCONTRO_NECK_CUT_TOP_METERS
	):
		var nx := point.x / SCONTRO_NECK_RADIUS_X_METERS
		var nz := point.z / SCONTRO_NECK_RADIUS_Z_METERS
		if nx * nx + nz * nz <= 1.0:
			return true
	return false


static func _keep_kaos_anatomy_vertex(
	point_world_units: Vector3,
	units: float
) -> bool:
	var point := point_world_units / units
	return not _is_kaos_head_or_neck(point)


static func _is_kaos_head_or_neck(point: Vector3) -> bool:
	# Full skull: use a sphere instead of the former narrow X-only strip.
	# The old test left the sides/back of the head visible.
	if point.distance_to(KAOS_HEAD_CENTER_METERS) <= KAOS_HEAD_RADIUS_METERS:
		return true

	# Neck: remove the central elliptical column down to shoulder level.
	# Arms are far enough on X that they are unaffected.
	if (
		point.y >= KAOS_NECK_BOTTOM_METERS
		and point.y <= KAOS_NECK_TOP_METERS
	):
		var nx := point.x / KAOS_NECK_RADIUS_X_METERS
		var nz := point.z / KAOS_NECK_RADIUS_Z_METERS
		if nx * nx + nz * nz <= 1.0:
			return true

	return false


static func _remove_kaos_head_accessories(visual: Node3D) -> void:
	var to_remove: Array[Node] = []
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		if _matches_any_term(label, KAOS_HEAD_VISUAL_TERMS):
			to_remove.append(child)
	for child in to_remove:
		child.free()


static func _ensure_kaos_shoulder_cap(
	visual: Node3D,
	units: float,
	material: Material
) -> void:
	var old := visual.get_node_or_null("PetrifiedShoulderCap")
	if old != null:
		old.free()

	var mesh := SphereMesh.new()
	# Opaque ellipsoidal fill spanning the shoulder cavity. Using a rounded
	# volume instead of a thin disk prevents seeing through Kaos from oblique
	# camera angles while blending into the surviving shoulder anatomy.
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 64
	mesh.rings = 32

	var cap := MeshInstance3D.new()
	cap.name = "PetrifiedShoulderCap"
	cap.set_meta("visual_role", "PetrifiedShoulderCap")
	cap.set_meta("post_kaos_shoulder_cap", true)
	cap.mesh = mesh
	cap.material_override = material
	cap.position = Vector3(0.0, 110.8 * units, 0.0)
	cap.scale = Vector3(29.0, 5.2, 17.0) * units
	visual.add_child(cap)


static func _ensure_scontro_shoulder_fill(
	visual: Node3D,
	units: float,
	material: Material
) -> void:
	var old := visual.get_node_or_null("PetrifiedShoulderCap")
	if old != null:
		old.free()

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 64
	mesh.rings = 32

	var fill := MeshInstance3D.new()
	fill.name = "PetrifiedShoulderCap"
	fill.set_meta("visual_role", "PetrifiedShoulderCap")
	fill.set_meta("scontro_kaos_shoulder_fill", true)
	fill.mesh = mesh
	fill.material_override = material
	# Keep the opaque repair entirely inside the surviving upper torso.
	# The old 29 x 5 x 17 m ellipsoid protruded through Kaos' chest and back.
	# This compact plug overlaps the neck stump and reaches the lower edge of
	# the clipped upper-neck opening without escaping the body silhouette.
	fill.position = Vector3(0.0, 119.0 * units, 0.0)
	fill.scale = Vector3(12.4, 2.6, 9.8) * units
	visual.add_child(fill)


static func _ensure_scontro_neck_base(
	visual: Node3D,
	units: float,
	material: Material
) -> void:
	var old := visual.get_node_or_null("PetrifiedNeckBase")
	if old != null:
		old.free()

	var mesh := CylinderMesh.new()
	mesh.top_radius = 9.6 * units
	mesh.bottom_radius = 11.2 * units
	mesh.height = 8.0 * units
	mesh.radial_segments = 64

	var stump := MeshInstance3D.new()
	stump.name = "PetrifiedNeckBase"
	stump.set_meta("visual_role", "PetrifiedNeckBase")
	stump.set_meta("scontro_kaos_neck_base", true)
	stump.mesh = mesh
	stump.material_override = material
	stump.position = Vector3(0.0, 117.0 * units, 0.0)
	stump.scale = Vector3(1.0, 1.0, 0.92)
	visual.add_child(stump)


static func _add_anatomy_collisions(
	visual: Node3D,
	grid_excluded: bool,
	surface_label: String
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
		_add_mesh_collision(mesh_instance, grid_excluded, surface_label)


static func _add_mesh_collision(
	mesh_instance: MeshInstance3D,
	grid_excluded: bool,
	surface_label: String
) -> void:
	var shape: Shape3D = mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = BODY_COLLISION_NAME
	body.collision_layer = WALKABLE_LAYER
	body.collision_mask = 0
	body.add_to_group("tactical_platform")
	if grid_excluded:
		body.add_to_group(GRID_EXCLUDED_GROUP)
	body.set_meta("post_kaos_collision", true)
	body.set_meta("post_kaos_surface", surface_label)
	mesh_instance.add_child(body)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	body.add_child(collider)


static func _add_sphere_collision(scene: Node) -> void:
	var sphere_root := scene.get_node_or_null("KlothisRoot/SphereVisual") as Node3D
	if sphere_root == null:
		return
	var units := _scene_units(scene)
	if units <= 0.0:
		return

	var body := StaticBody3D.new()
	body.name = "WalkableSphereCollision"
	body.collision_layer = WALKABLE_LAYER
	body.collision_mask = 0
	body.add_to_group("tactical_platform")
	body.add_to_group(GRID_EXCLUDED_GROUP)
	body.set_meta("post_kaos_collision", true)
	body.set_meta("post_kaos_surface", "sphere")
	sphere_root.add_child(body)

	var shape := SphereShape3D.new()
	shape.radius = 220.0 * units
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	body.add_child(collider)


static func _add_anatomy_grid_proxies(
	visual: Node3D,
	surface_label: String
) -> void:
	for child in visual.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.visible:
			continue
		var role := String(
			mesh_instance.get_meta(
				"visual_role",
				mesh_instance.name
			)
		)
		if not role.begins_with("Anatomy"):
			continue
		_add_mesh_grid_proxy(mesh_instance, surface_label)


static func _add_mesh_grid_proxy(
	mesh_instance: MeshInstance3D,
	surface_label: String
) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var shape: Shape3D = mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return

	var body := StaticBody3D.new()
	body.name = "VolumetricGridSurfaceProxy"
	body.collision_layer = RIGHT_ARM_GRID_LAYER
	body.collision_mask = 0
	body.set_meta("post_kaos_collision", true)
	body.set_meta("post_kaos_surface", surface_label)
	body.set_meta("volumetric_grid_surface_proxy", true)
	mesh_instance.add_child(body)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	body.add_child(collider)


static func _add_sphere_grid_proxy(scene: Node) -> void:
	var sphere_root := scene.get_node_or_null(
		"KlothisRoot/SphereVisual"
	) as Node3D
	if sphere_root == null:
		return
	var units := _scene_units(scene)
	if units <= 0.0:
		return

	# The physical SphereShape is a filled volume. Feeding that directly to
	# VolumetricGrid would voxelize the whole interior, so use a concave
	# triangulated shell exclusively for grid detection.
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 220.0 * units
	shell_mesh.height = 440.0 * units
	shell_mesh.radial_segments = 96
	shell_mesh.rings = 48
	var shell_shape: Shape3D = shell_mesh.create_trimesh_shape()
	if shell_shape == null:
		return

	var body := StaticBody3D.new()
	body.name = "SphereVolumetricGridSurfaceProxy"
	body.collision_layer = RIGHT_ARM_GRID_LAYER
	body.collision_mask = 0
	body.set_meta("post_kaos_collision", true)
	body.set_meta("post_kaos_surface", "sphere_grid")
	body.set_meta("volumetric_grid_surface_proxy", true)
	sphere_root.add_child(body)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shell_shape
	body.add_child(collider)


static func _add_kaos_right_arm_grid_proxy(
	scene: Node,
	visual: Node3D
) -> void:
	var units := _scene_units(scene)
	if units <= 0.0:
		return
	var faces := PackedVector3Array()

	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if not role.begins_with("Anatomy"):
			continue

		var source: Mesh = mesh_instance.mesh
		for surface_index in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in range(vertices.size()):
					indices[index] = index
			for index in range(0, indices.size() - 2, 3):
				var p0 := mesh_instance.transform * vertices[indices[index]]
				var p1 := mesh_instance.transform * vertices[indices[index + 1]]
				var p2 := mesh_instance.transform * vertices[indices[index + 2]]
				var center := (p0 + p1 + p2) / 3.0 / units
				if (
					center.x < KAOS_RIGHT_ARM_MIN_X_METERS
					or center.y < KAOS_RIGHT_ARM_MIN_Y_METERS
					or center.y > KAOS_RIGHT_ARM_MAX_Y_METERS
					or center.z > KAOS_RIGHT_ARM_MAX_Z_METERS
					or center.z < KAOS_RIGHT_ARM_MIN_Z_METERS
					or _is_kaos_head_or_neck(center)
				):
					continue
				faces.append(p0)
				faces.append(p1)
				faces.append(p2)

	if faces.size() < 3:
		return

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	var body := StaticBody3D.new()
	body.name = "KaosRightArmGridProxy"
	# Grid-only collision. The exact anatomy collider remains on layer 1 and
	# is what tokens actually rest on; this proxy only tells VolumetricGrid
	# where to draw cells around Kaos' petrified right arm.
	body.collision_layer = RIGHT_ARM_GRID_LAYER
	body.collision_mask = 0
	body.set_meta("post_kaos_collision", true)
	body.set_meta("post_kaos_surface", "kaos_right_arm_grid")
	body.set_meta("post_kaos_right_arm_grid", true)
	body.set_meta("right_arm_side", "positive_x")
	visual.add_child(body)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	body.add_child(collider)


static func _remove_generated_collisions(scene: Node) -> void:
	var nodes: Array[Node] = []
	for node in scene.find_children("*", "StaticBody3D", true, false):
		if (
			bool(node.get_meta("post_kaos_collision", false))
			or bool(node.get_meta("post_kaos_body_collision", false))
		):
			nodes.append(node)
	for node in nodes:
		node.free()


static func _solid_surface_set_is_complete(
	scene: Node,
	full_grid_surfaces: bool = false
) -> bool:
	var found := {
		"kaos": false,
		"kaos_shoulders": false,
		"klothys": false,
		"sphere": false,
	}
	if full_grid_surfaces:
		found["kaos_grid"] = false
		found["klothys_grid"] = false
		found["sphere_grid"] = false
	else:
		found["kaos_right_arm_grid"] = false

	for node in scene.find_children("*", "StaticBody3D", true, false):
		if not bool(node.get_meta("post_kaos_collision", false)):
			continue
		var label := String(node.get_meta("post_kaos_surface", ""))
		if label in found:
			found[label] = true
	for value in found.values():
		if not bool(value):
			return false
	return true


static func _restore_klothys_hair(scene: Node, units: float) -> void:
	var visual := scene.get_node_or_null("KlothisRoot/KlothisVisual") as Node3D
	if visual == null:
		return

	var old_hair: Array[Node] = []
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		if _matches_any_term(label, KLOTHYS_HAIR_TERMS):
			old_hair.append(child)
	for child in old_hair:
		child.free()

	var temp := Node3D.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.69, 0.57, 0.44)
	body.roughness = 0.72
	body.emission_enabled = true
	body.emission = Color(0.69, 0.57, 0.44)
	body.emission_energy_multiplier = 0.07
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.51, 0.53, 0.51)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.62, 0.52, 0.35)
	preload("res://encounter/sculpted_giant_visual.gd").new().build(
		temp,
		units,
		body,
		marble,
		gold,
		true
	)

	var restored: Array[Node] = []
	for child in temp.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		if _matches_any_term(label, KLOTHYS_HAIR_TERMS):
			restored.append(child)
	for child in restored:
		temp.remove_child(child)
		visual.add_child(child)
	temp.free()


static func _restore_titan_faces(scene: Node, units: float) -> void:
	var sphere_root := scene.get_node_or_null("KlothisRoot/SphereVisual") as Node3D
	if sphere_root == null:
		return
	var old := sphere_root.get_node_or_null("CarvedTitanFaces")
	if old != null:
		old.free()
	var stone := _stone_material()
	preload("res://encounter/titan_reliefs.gd").new().build(
		sphere_root,
		units,
		stone
	)


static func _restore_ruins(scene: Node, units: float) -> void:
	var root := scene.get_node_or_null("Board/MapGeometry") as Node3D
	if root == null:
		return
	for node_name in RUIN_NODE_NAMES:
		var old := root.get_node_or_null(node_name)
		if old != null:
			old.free()
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.51, 0.53, 0.51)
	marble.roughness = 0.8
	preload("res://encounter/ruins_visual.gd").new().build(
		root,
		units,
		marble
	)


static func _ensure_decor_visible(scene: Node) -> void:
	var visual := scene.get_node_or_null("KlothisRoot/KlothisVisual") as Node3D
	if visual != null:
		for child in visual.get_children():
			if not child is MeshInstance3D:
				continue
			var label := String(child.get_meta("visual_role", child.name))
			if _matches_any_term(label, KLOTHYS_HAIR_TERMS):
				child.show()

	var titan_faces := scene.get_node_or_null(
		"KlothisRoot/SphereVisual/CarvedTitanFaces"
	) as VisualInstance3D
	if titan_faces != null:
		titan_faces.show()

	var ruins := scene.get_node_or_null("Board/MapGeometry") as Node3D
	if ruins != null:
		for node_name in RUIN_NODE_NAMES:
			var node := ruins.get_node_or_null(node_name) as VisualInstance3D
			if node != null:
				node.show()


static func _count_klothys_hair(scene: Node) -> int:
	var visual := scene.get_node_or_null("KlothisRoot/KlothisVisual") as Node3D
	if visual == null:
		return 0
	var hair_count := 0
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		if _matches_any_term(label, KLOTHYS_HAIR_TERMS):
			hair_count += 1
	return hair_count


static func _ruins_are_complete(scene: Node) -> bool:
	var ruins := scene.get_node_or_null("Board/MapGeometry") as Node3D
	if ruins == null:
		return false
	for node_name in RUIN_NODE_NAMES:
		if ruins.get_node_or_null(node_name) == null:
			return false
	return true


static func _decor_is_complete(scene: Node) -> bool:
	var visual := scene.get_node_or_null("KlothisRoot/KlothisVisual") as Node3D
	var sphere := scene.get_node_or_null("KlothisRoot/SphereVisual") as Node3D
	var ruins := scene.get_node_or_null("Board/MapGeometry") as Node3D
	if visual == null or sphere == null or ruins == null:
		return false

	var hair_count := 0
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		if _matches_any_term(label, KLOTHYS_HAIR_TERMS):
			hair_count += 1
	if hair_count < 100:
		return false
	if sphere.get_node_or_null("CarvedTitanFaces") == null:
		return false
	for node_name in RUIN_NODE_NAMES:
		if ruins.get_node_or_null(node_name) == null:
			return false
	return true


static func _matches_any_term(label: String, terms: Array[String]) -> bool:
	for term in terms:
		if term in label:
			return true
	return false
