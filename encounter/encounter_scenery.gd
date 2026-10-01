extends Node

@export var klothis_group_elevation_meters: float = 75.0
@export var sphere_extra_elevation_meters: float = 150.0

var _units: float
var _marble: StandardMaterial3D
var _gold: StandardMaterial3D
var _dark: StandardMaterial3D

func build(scene: Node3D) -> void:
	_units = scene.measurement_tool.meters_to_world(1.0)
	_marble = _material(Color(0.51, 0.53, 0.51))
	_gold = _material(Color(0.62, 0.52, 0.35), 0.3)
	_dark = _material(Color(0.11, 0.105, 0.10))
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 337 * _units
	water_mesh.bottom_radius = 337 * _units
	water_mesh.height = 0.2 * _units
	water_mesh.radial_segments = 128
	var water_material := ShaderMaterial.new()
	water_material.shader = preload("res://encounter/water.gdshader")
	water_mesh.material = water_material
	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	water.mesh = water_mesh
	water.position = Vector3(0, -0.18, -60) * _units
	scene.get_node("Board").add_child(water)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(120 * _units, 0.1, 180 * _units)
	scene.get_node("Board/FloorCollision/CollisionShape3D").shape = floor_shape
	scene.get_node("Board/FloorCollision").position.z = 85.5 * _units
	var orientation_marker := scene.get_node_or_null(
		"Board/MapGeometry/OrientationMarker"
	)
	if orientation_marker != null:
		orientation_marker.queue_free()
	var environment: Environment = scene.get_node("WorldEnvironment").environment.duplicate()
	environment.background_color = Color(0.014, 0.018, 0.023)
	environment.ambient_light_color = Color(0.88, 0.72, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.22
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.085, 0.10)
	environment.fog_density = 0.0007
	environment.glow_enabled = true
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_intensity = 0.7
	scene.get_viewport().msaa_3d = Viewport.MSAA_4X
	scene.get_node("WorldEnvironment").environment = environment
	var overhead: DirectionalLight3D = scene.get_node("DirectionalLight3D")
	overhead.rotation_degrees = Vector3(-90, 0, 0)
	overhead.light_color = Color(1, 0.94, 0.83)
	overhead.light_energy = 1.0
	overhead.shadow_opacity = 0.45
	overhead.directional_shadow_max_distance = 650 * _units
	var fill := DirectionalLight3D.new()
	fill.name = "SoftFill"
	fill.rotation_degrees = Vector3(-24, -25, 0)
	fill.light_color = Color(0.94, 0.81, 0.65)
	fill.light_energy = 0.24
	fill.shadow_enabled = false
	scene.add_child(fill)
	scene.camera.position = Vector3(260, 290, 510) * _units
	scene.camera.look_at(Vector3(0, 225, -65) * _units)
	scene.camera.speed = 35 * _units
	scene.camera.far = 1200 * _units
	var kaos_visual: Node3D = scene.get_node("KaosRoot/KaosVisual")
	if kaos_visual.get_child_count() == 0:
		_giant(kaos_visual, false)
	var klothis: Node3D = scene.get_node("KlothisRoot")
	klothis.position = Vector3(0, klothis_group_elevation_meters, -12) * _units
	var klothis_visual: Node3D = klothis.get_node("KlothisVisual")
	# Keep the veil and hair outside the sphere, with bindings reaching her back.
	klothis_visual.position = Vector3(0, sphere_extra_elevation_meters, 12) * _units
	if klothis_visual.get_child_count() == 0:
		_giant(klothis_visual, true)
	var sphere: Node3D = klothis.get_node("SphereVisual")
	sphere.position = Vector3(0, 160 + sphere_extra_elevation_meters, -218) * _units
	if sphere.get_child_count() == 0:
		var sphere_mesh := _sphere(sphere, 220, _dark)
		var stone := ShaderMaterial.new()
		stone.shader = preload("res://encounter/sphere_surface.gdshader")
		preload("res://encounter/pbr_assets.gd").apply(stone,"dark_rock")
		sphere_mesh.material_override = stone
		preload("res://encounter/titan_reliefs.gd").new().build(sphere,_units,stone)
		_bindings(sphere)
	var ruins: Node3D = scene.get_node("Board/MapGeometry")
	preload("res://encounter/ruins_visual.gd").new().build(ruins, _units, _marble)
	spawn_encounter_tokens(scene)

func spawn_encounter_tokens(
	scene: Node3D,
	chariot_deck_positions_world: Array[Vector3] = []
) -> void:
	var units: float = scene.measurement_tool.meters_to_world(1.0)
	var roster_start := scene.tokens_root.get_child_count()
	for index in range(6):
		var token: CharacterBody3D = scene.token_scene.instantiate()
		scene.tokens_root.add_child(token)
		token.position = Vector3(5 + index * 3, 3, 80) * units
		token.configure(
			Color(0.15 + index * 0.17, 0.68, 0.76 - index * 0.12),
			scene.cell_size,
			"Medium",
			1.0
		)
		preload("res://encounter/party_skins.gd").new().apply(token, index)
		token.set_meta("post_kaos_roster", true)

	for index in range(3):
		var chariot = scene.token_scene.instantiate()
		chariot.set_script(preload("res://encounter/chariot_token.gd"))
		chariot.cell_size = scene.cell_size
		scene.tokens_root.add_child(chariot)
		chariot.setup_chariot()
		_place_chariot(
			chariot,
			Vector3(-10 + index * 10, 150, 182) * units,
			chariot_deck_positions_world[index]
				if index < chariot_deck_positions_world.size()
				else Vector3.INF
		)
		chariot.set_flying(true)
		chariot.set_meta("post_kaos_roster", true)
		for seat in range(2):
			var rider_index := roster_start + index * 2 + seat
			var rider = scene.tokens_root.get_child(rider_index)
			rider.global_position = chariot.deck.to_global(
				Vector3(
					-.5 + seat,
					rider.token_height_cells * .5 + .015,
					-.5
				) * scene.cell_size
			)
			rider.grid_support = chariot.deck
			rider._support_transform = chariot.deck.global_transform

	var phenax_chariot = scene.token_scene.instantiate()
	phenax_chariot.name = "PhenaxChariot"
	phenax_chariot.set_script(preload("res://encounter/chariot_token.gd"))
	phenax_chariot.cell_size = scene.cell_size
	scene.tokens_root.add_child(phenax_chariot)
	phenax_chariot.setup_chariot()
	_place_chariot(
		phenax_chariot,
		Vector3(20, 150, 182) * units,
		chariot_deck_positions_world[3]
			if chariot_deck_positions_world.size() > 3
			else Vector3.INF
	)
	phenax_chariot.set_flying(true)
	phenax_chariot.set_meta("post_kaos_roster", true)

	var phenax = scene.token_scene.instantiate()
	phenax.name = "Phenax"
	phenax.token_height_cells = 3.0
	scene.tokens_root.add_child(phenax)
	phenax.configure(Color(.65, .30, .10), scene.cell_size, "Large", 2.0)
	preload("res://encounter/phenax_skin.gd").new().apply(phenax)
	phenax.global_position = phenax_chariot.deck.to_global(
		Vector3(0, 1.515, 0) * scene.cell_size
	)
	phenax.grid_support = phenax_chariot.deck
	phenax._support_transform = phenax_chariot.deck.global_transform
	phenax.set_meta("post_kaos_roster", true)

func _place_chariot(
	chariot: CharacterBody3D,
	default_root_world: Vector3,
	custom_deck_world: Vector3
) -> void:
	if custom_deck_world != Vector3.INF:
		var deck_offset_world := chariot.global_transform.basis * chariot.deck.position
		chariot.global_position = custom_deck_world - deck_offset_world
		return
	chariot.position = default_root_world
	# Deck surface, rather than the collision body's centre, is exactly 150 m up.
	chariot.position.y = default_root_world.y - chariot.deck.position.y

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.emission_enabled = emission > 0
	material.emission = color
	material.emission_energy_multiplier = emission
	return material

func _mesh(parent: Node3D, mesh: Mesh, position_m: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_m * _units
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, radius: float, material: Material, point: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius * _units
	mesh.height = radius * 2 * _units
	mesh.radial_segments = 128
	mesh.rings = 64
	return _mesh(parent, mesh, point, material)

func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.75 * _units
	mesh.bottom_radius = radius * _units
	mesh.height = from.distance_to(to) * _units
	mesh.radial_segments = 12
	var instance := _mesh(parent, mesh, (from + to) * 0.5, material)
	instance.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))

func _giant(parent: Node3D, luminous: bool) -> void:
	var body: Material = _material(Color(0.69, 0.57, 0.44), 0.07) if luminous else _cosmic_material()
	preload("res://encounter/sculpted_giant_visual.gd").new().build(parent, _units, body, _marble, _gold, luminous)

func _cosmic_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
void fragment() {
 vec2 p = UV * vec2(120.0, 240.0);
 float h = fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
 float star = step(0.982, h) * (1.0 - smoothstep(0.0, 0.16, length(fract(p) - 0.5)));
 float nebula = sin(UV.x*19.0+sin(UV.y*13.0))*sin(UV.y*21.0);
 ALBEDO = vec3(0.012, 0.016, 0.026) + nebula*vec3(0.008,0.006,0.014) + star * vec3(0.7, 0.63, 0.48);
 EMISSION = star * vec3(1.1, 0.85, 0.6);
 ROUGHNESS = 0.48;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _bindings(parent: Node3D) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _gold)
	# Fibers fan out from Klothis across the visible hemisphere.
	var anchor := Vector3(0, -20, 219.5)
	for strand in range(60):
		var angle := TAU * float(strand) / 60.0
		var last := anchor
		for segment in range(1, 25):
			var t := float(segment) / 24.0
			var a := t * 1.65
			var twist := angle + t * 0.55 + sin(t * 12 + strand) * 0.045
			var point := Vector3(sin(a) * cos(twist) * 220.3, sin(a) * sin(twist) * 220.3, cos(a) * 220.3)
			mesh.surface_add_vertex(last * _units)
			mesh.surface_add_vertex(point * _units)
			last = point
	mesh.surface_end()
	_mesh(parent, mesh, Vector3.ZERO, _gold)

func _sphere_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {
 vec2 p = UV * vec2(160.0, 80.0);
 float n = noise(p) * 0.6 + noise(p*2.3) * 0.27 + noise(p*5.7) * 0.13;
 float ridges = smoothstep(0.38, 0.6, n);
 ALBEDO = mix(vec3(0.022,0.025,0.024),vec3(0.19,0.18,0.15),ridges);
 ROUGHNESS = 0.95;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
