extends RefCounted

const BACKDROP_RADIUS_METERS := 398.0
const BACKDROP_BOTTOM_METERS := -18.0
const BACKDROP_TOP_METERS := 540.0


static func install(scene: Node3D, include_arena_ring: bool = true) -> void:
	if scene == null:
		return

	var measurement := scene.get_node_or_null("MeasurementTool")
	if measurement == null or not measurement.has_method("meters_to_world"):
		return
	var units := float(measurement.call("meters_to_world", 1.0))
	if units <= 0.0:
		return

	# The old apse is only a partial arc. Its hard end is the black diagonal
	# seam visible from the battle platform. Keep the node for compatibility
	# with the Post-Kaos helpers, but let the new 360-degree backdrop replace
	# it visually in this encounter.
	var old_wall := scene.get_node_or_null(
		"Board/MapGeometry/ContinuousApseWall"
	) as VisualInstance3D
	if old_wall != null:
		old_wall.hide()

	var old_backdrop := scene.get_node_or_null("CosmicBackdrop")
	if old_backdrop != null:
		old_backdrop.free()

	if include_arena_ring:
		var root := Node3D.new()
		root.name = "CosmicBackdrop"
		root.set_meta("scontro_cosmic_backdrop", true)
		scene.add_child(root)

		var material := _backdrop_material()
		var ring := _build_ring(units, material)
		root.add_child(ring)

	_install_star_sky(scene)


static func _build_ring(
	units: float,
	material: Material
) -> MeshInstance3D:
	var height_m := BACKDROP_TOP_METERS - BACKDROP_BOTTOM_METERS
	var mesh := CylinderMesh.new()
	mesh.top_radius = BACKDROP_RADIUS_METERS * units
	mesh.bottom_radius = BACKDROP_RADIUS_METERS * units
	mesh.height = height_m * units
	mesh.radial_segments = 192
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.material = material

	var ring := MeshInstance3D.new()
	ring.name = "StarfieldRing"
	ring.mesh = mesh
	# Overlap the arena plane slightly so there is never a visible black gap
	# between the platform/water edge and the backdrop at shallow camera
	# angles.
	ring.position.y = (
		(BACKDROP_BOTTOM_METERS + BACKDROP_TOP_METERS)
		* 0.5
		* units
	)
	ring.set_meta("scontro_cosmic_backdrop", true)
	return ring


static func _backdrop_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

float hash21(vec2 p) {
	return fract(
		sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123
	);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 wrapped = vec2(
		cos(uv.x * 6.2831853),
		sin(uv.x * 6.2831853)
	);
	float n1 = noise21(
		wrapped * 5.2 + vec2(uv.y * 2.5, uv.y * 1.7)
	);
	float n2 = noise21(
		wrapped * 11.0 + vec2(uv.y * 6.0, -uv.y * 4.0)
	);
	float nebula = smoothstep(
		0.46,
		0.82,
		n1 * 0.70 + n2 * 0.30
	);
	float band = exp(
		-pow(
			(uv.y - 0.56)
			+ sin(uv.x * 6.2831853 * 1.6) * 0.10,
			2.0
		) * 26.0
	);
	nebula *= 0.35 + 0.65 * band;

	vec2 star_grid = floor(
		uv * vec2(1500.0, 620.0)
	);
	float star_hash = hash21(star_grid);
	float star = step(0.9955, star_hash);
	float bright_star = step(0.99935, star_hash);

	vec3 base = vec3(0.0025, 0.0045, 0.012);
	vec3 blue_nebula = vec3(0.035, 0.075, 0.19);
	vec3 violet_nebula = vec3(0.09, 0.035, 0.12);
	float color_mix = noise21(
		wrapped * 3.1 + vec2(uv.y * 2.0)
	);
	vec3 nebula_color = mix(
		blue_nebula,
		violet_nebula,
		color_mix
	);

	vec3 star_color = mix(
		vec3(0.68, 0.78, 1.0),
		vec3(1.0, 0.83, 0.60),
		hash21(star_grid + 19.7)
	);
	vec3 color = (
		base
		+ nebula_color * nebula * 0.72
		+ star_color * star * 1.25
		+ vec3(1.0) * bright_star * 2.4
	);
	ALBEDO = color;
	EMISSION = color * 1.25;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


static func _install_star_sky(scene: Node3D) -> void:
	var world_environment := scene.get_node_or_null(
		"WorldEnvironment"
	) as WorldEnvironment
	if world_environment == null:
		return

	var environment := (
		world_environment.environment.duplicate(true) as Environment
		if world_environment.environment != null
		else Environment.new()
	)
	if environment == null:
		environment = Environment.new()

	var sky_shader := Shader.new()
	sky_shader.code = """shader_type sky;

float hash31(vec3 p) {
	return fract(
		sin(dot(p, vec3(127.1, 311.7, 74.7)))
		* 43758.5453123
	);
}

float noise31(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 cell = floor(d * 1150.0);
	float h = hash31(cell);
	float star = step(0.9978, h);
	float bright = step(0.99965, h);

	float n1 = noise31(d * 3.5 + vec3(2.0, 5.0, 1.0));
	float n2 = noise31(d * 8.0 - vec3(4.0, 1.0, 3.0));
	float galactic_band = exp(
		-pow(d.y + 0.10 + 0.20 * sin(d.x * 3.6), 2.0)
		* 8.0
	);
	float nebula = smoothstep(
		0.48,
		0.84,
		n1 * 0.70 + n2 * 0.30
	) * galactic_band;

	vec3 base = vec3(0.0015, 0.0030, 0.010);
	vec3 nebula_color = mix(
		vec3(0.025, 0.065, 0.18),
		vec3(0.11, 0.035, 0.13),
		clamp(d.x * 0.5 + 0.5, 0.0, 1.0)
	);
	vec3 star_color = mix(
		vec3(0.62, 0.75, 1.0),
		vec3(1.0, 0.78, 0.52),
		hash31(cell + vec3(17.0))
	);
	COLOR = (
		base
		+ nebula_color * nebula * 0.62
		+ star_color * star
		+ vec3(1.0) * bright * 2.0
	);
}
"""
	var sky_material := ShaderMaterial.new()
	sky_material.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Keep the encounter's warm controlled lighting. The sky is visual only,
	# so changing the backdrop does not recolor Kaos, Klothys or the platform.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.fog_sky_affect = 0.08
	world_environment.environment = environment
