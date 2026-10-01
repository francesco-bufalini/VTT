extends "res://dnd_base.gd"

const PostKaosHelpers = preload("res://encounter/post_kaos_helpers.gd")
const EncounterScenery = preload("res://encounter/encounter_scenery.gd")
const SculptedGiantVisual = preload("res://encounter/sculpted_giant_visual.gd")
const RuinsVisual = preload("res://encounter/ruins_visual.gd")
const TitanReliefs = preload("res://encounter/titan_reliefs.gd")

func _ready() -> void:
	super._ready()
	_ensure_missing_baked_visuals()
	PostKaosHelpers.remove_kaos_phase_two_token(self)
	PostKaosHelpers.remove_legacy_platforms(self)
	PostKaosHelpers.close_kaos_petrification_hole(self)
	PostKaosHelpers.ensure_body_collisions(self)
	_ensure_post_kaos_roster()
	_configure_post_kaos_surfaces()

func _configure_post_kaos_surfaces() -> void:
	volumetric_grid.collision_mask = 1 | 4
	measurement_tool.collision_mask = 1 | 4
	if volumetric_grid.has_method("refresh"):
		volumetric_grid.call_deferred("refresh")

func _ensure_post_kaos_roster() -> void:
	if PostKaosHelpers.has_post_roster(self):
		_move_existing_chariots_near_kaos()
		return
	var scenery := EncounterScenery.new()
	scenery.spawn_encounter_tokens(self, _chariot_deck_targets())

func _move_existing_chariots_near_kaos() -> void:
	var targets := _chariot_deck_targets()
	var index := 0
	for child in tokens_root.get_children():
		if not bool(child.get_meta("compound_chariot", false)):
			continue
		if index >= targets.size():
			break
		var chariot := child as CharacterBody3D
		if chariot == null:
			continue
		var deck := chariot.get_node_or_null("ChariotDeck") as Node3D
		if deck == null:
			continue
		var deck_offset_world := chariot.global_transform.basis * deck.position
		chariot.global_position = targets[index] - deck_offset_world
		index += 1

func _chariot_deck_targets() -> Array[Vector3]:
	var units: float = measurement_tool.meters_to_world(1.0)
	var kaos := get_node_or_null("KaosRoot") as Node3D
	var anchor: Node3D = null
	if kaos != null:
		anchor = kaos.get_node_or_null("ClimbingVisual/FaceAnchor") as Node3D
	var center := (
		anchor.global_position
		if anchor != null
		else (
			kaos.global_position + Vector3.UP * 105.0 * units
			if kaos != null
			else Vector3(0, 105, 0) * units
		)
	)
	return [
		center + Vector3(-24, -16, 30) * units,
		center + Vector3(-8, -10, 34) * units,
		center + Vector3(8, -10, 34) * units,
		center + Vector3(24, -16, 30) * units,
	]

func _ensure_missing_baked_visuals() -> void:
	var units: float = measurement_tool.meters_to_world(1.0)
	_ensure_soft_fill()
	_ensure_water(units)
	_ensure_ruins(units)
	_ensure_klothis(units)
	_ensure_sphere(units)
	_ensure_kaos(units)

func _ensure_soft_fill() -> void:
	if get_node_or_null("SoftFill") != null:
		return
	var fill := DirectionalLight3D.new()
	fill.name = "SoftFill"
	fill.rotation_degrees = Vector3(-24, -25, 0)
	fill.light_color = Color(0.94, 0.81, 0.65)
	fill.light_energy = 0.24
	fill.shadow_enabled = false
	add_child(fill)

func _ensure_water(units: float) -> void:
	var board := get_node_or_null("Board")
	if board == null or board.get_node_or_null("WaterSurface") != null:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 337 * units
	mesh.bottom_radius = 337 * units
	mesh.height = 0.2 * units
	mesh.radial_segments = 128
	var material := ShaderMaterial.new()
	material.shader = load("res://encounter/water.gdshader")
	mesh.material = material
	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	water.mesh = mesh
	water.position = Vector3(0, -0.18, -60) * units
	board.add_child(water)

func _ensure_ruins(units: float) -> void:
	var root := get_node_or_null("Board/MapGeometry") as Node3D
	if root == null or root.get_node_or_null("FlutedColumns") != null:
		return
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.51, 0.53, 0.51)
	marble.roughness = 0.8
	RuinsVisual.new().build(root, units, marble)

func _ensure_klothis(units: float) -> void:
	var visual := get_node_or_null("KlothisRoot/KlothisVisual") as Node3D
	if visual == null or not visual.find_children("*", "MeshInstance3D", true, false).is_empty():
		return
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
	SculptedGiantVisual.new().build(
		visual,
		units,
		body,
		marble,
		gold,
		true
	)

func _ensure_sphere(units: float) -> void:
	var root := get_node_or_null("KlothisRoot/SphereVisual") as Node3D
	if root == null or not root.find_children("*", "MeshInstance3D", true, false).is_empty():
		return
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 220 * units
	sphere_mesh.height = 440 * units
	sphere_mesh.radial_segments = 128
	sphere_mesh.rings = 64
	var stone := ShaderMaterial.new()
	stone.shader = load("res://encounter/sphere_surface.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	sphere_mesh.material = stone
	var sphere := MeshInstance3D.new()
	sphere.name = "SphereMesh"
	sphere.mesh = sphere_mesh
	root.add_child(sphere)
	TitanReliefs.new().build(root, units, stone)

func _ensure_kaos(units: float) -> void:
	var kaos := get_node_or_null("KaosRoot")
	if kaos == null:
		return
	var visual := kaos.get_node_or_null("ClimbingVisual") as Node3D
	if visual == null:
		visual = Node3D.new()
		visual.name = "ClimbingVisual"
		kaos.add_child(visual)
	if not visual.find_children("*", "MeshInstance3D", true, false).is_empty():
		visual.show()
		return
	var stone := ShaderMaterial.new()
	stone.shader = load("res://encounter/sphere_surface.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(stone, "dark_rock")
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.51, 0.53, 0.51)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.62, 0.52, 0.35)
	var builder := SculptedGiantVisual.new()
	builder.anatomy_override = "res://encounter/assets/characters/kaos_climbing.glb"
	builder.climbing = true
	builder.build(visual, units, stone, marble, gold, false)
	visual.show()
