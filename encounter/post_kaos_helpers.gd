extends RefCounted

const WALKABLE_LAYER := 4
const BODY_COLLISION_NAME := "WalkableBodyCollision"

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

static func close_kaos_petrification_hole(scene: Node) -> void:
	var kaos := scene.get_node_or_null("KaosRoot") as Node3D
	if kaos == null:
		return
	var visual := kaos.get_node_or_null("ClimbingVisual") as Node3D
	if visual == null or not visual.visible:
		visual = kaos.get_node_or_null("KaosVisual") as Node3D
	if visual == null:
		return

	var stone := ShaderMaterial.new()
	stone.shader = load("res://encounter/sphere_surface.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not mesh_instance.visible:
			continue
		mesh_instance.material_override = stone

static func ensure_body_collisions(scene: Node) -> void:
	for path in [
		"KaosRoot/ClimbingVisual",
		"KaosRoot/KaosVisual",
		"KlothisRoot/KlothisVisual",
	]:
		var visual := scene.get_node_or_null(path)
		if visual == null or not visual.visible:
			continue
		_add_anatomy_collisions(visual)

static func _add_anatomy_collisions(visual: Node) -> void:
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
		if mesh_instance.has_node(BODY_COLLISION_NAME):
			continue
		var shape: Shape3D = mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = BODY_COLLISION_NAME
		body.collision_layer = WALKABLE_LAYER
		body.collision_mask = 0
		body.add_to_group("tactical_platform")
		body.set_meta("post_kaos_body_collision", true)
		mesh_instance.add_child(body)

		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		collider.shape = shape
		body.add_child(collider)

static func has_post_roster(scene: Node) -> bool:
	var tokens := scene.get_node_or_null("Tokens")
	if tokens == null:
		return false
	for child in tokens.get_children():
		if bool(child.get_meta("post_kaos_roster", false)):
			return true
	return false
