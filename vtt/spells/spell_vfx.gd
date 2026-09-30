extends RefCounted


static func attach(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	_shape: String,
	style: String,
	cell_size: float
) -> void:
	if root == null or not is_instance_valid(root):
		return
	if style not in [
	"burning_hands", "fireball", "darkness", "lightning_bolt",
	"acid_splash", "thunderclap", "color_spray", "fog_cloud",
	"grease", "sleep", "thunderwave", "ice_knife_burst",
	"witch_bolt", "cloud_of_daggers", "shatter", "web", "fear",
	"hypnotic_pattern", "sleet_storm", "slow", "stinking_cloud",
	"confusion", "ice_storm", "vitriolic_sphere", "cone_of_cold",
	"insect_plague", "synaptic_static", "chain_lightning",
	"circle_of_death", "globe_of_invulnerability",
	"otilukes_freezing_sphere", "sunbeam",
	"fire", "cold", "lightning", "acid", "poison", "necrotic",
	"radiant", "force", "psychic", "thunder", "fear",
	"enchantment", "arcane"
]:
		return

	var reach_world: float = maxf(
		start.distance_to(end),
		cell_size * 0.5
	)

	match style:
		"burning_hands":
			_attach_burning_hands(root, start, end, reach_world, cell_size)
		"fireball":
			_attach_fireball(root, start, reach_world, cell_size)
		"darkness":
			_attach_darkness(root, start, reach_world, cell_size)
		"lightning_bolt":
			_attach_lightning_bolt(root, start, end, reach_world, cell_size)
		"acid_splash":
			_add_sphere_layer(root, start, reach_world * 0.92, cell_size, 150, 1.0, Color(0.35, 1.0, 0.18, 0.58), 0.30, reach_world * 0.08)
		"thunderclap":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 170, 0.55, Color(0.5, 0.82, 1.0, 0.62), 0.24, reach_world * 0.12)
		"color_spray":
			_attach_color_spray(root, start, end, reach_world, cell_size)
		"fog_cloud":
			_attach_fog_cloud(root, start, reach_world, cell_size)
		"grease":
			_attach_grease(root, start, reach_world, cell_size)
		"sleep":
			_add_sphere_layer(root, start, reach_world * 0.9, cell_size, 130, 1.8, Color(0.62, 0.34, 1.0, 0.42), 0.26, reach_world * 0.035)
		"thunderwave":
			_attach_thunderwave(root, start, reach_world, cell_size)
		"ice_knife_burst":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 180, 0.75, Color(0.42, 0.9, 1.0, 0.62), 0.22, reach_world * 0.10)
		"witch_bolt":
			_attach_lightning_bolt(root, start, end, reach_world, cell_size)
		"cloud_of_daggers":
			_add_box_layer(root, start, reach_world, cell_size, 170, Color(0.84, 0.88, 0.96, 0.66), 0.16, 0.35)
		"shatter":
			_add_sphere_layer(root, start, reach_world * 0.95, cell_size, 180, 0.48, Color(0.62, 0.86, 1.0, 0.58), 0.24, reach_world * 0.14)
		"web":
			_add_box_layer(root, start, reach_world, cell_size, 220, Color(0.9, 0.92, 0.96, 0.32), 0.28, 0.035)
		"fear":
			_attach_colored_cone(root, start, end, reach_world, cell_size, Color(0.42, 0.08, 0.62, 0.55))
		"hypnotic_pattern":
			_add_box_layer(root, start, reach_world, cell_size, 130, Color(0.94, 0.2, 0.92, 0.56), 0.22, 0.09)
			_add_box_layer(root, start, reach_world * 0.9, cell_size, 100, Color(0.16, 0.82, 1.0, 0.5), 0.18, 0.07)
		"sleet_storm":
			_attach_cylinder_weather(root, start, end, cell_size, Color(0.72, 0.9, 1.0, 0.42), 280)
		"slow":
			_add_box_layer(root, start, reach_world, cell_size, 150, Color(0.58, 0.26, 0.86, 0.44), 0.20, 0.035)
		"stinking_cloud":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 330, 4.2, Color(0.5, 0.66, 0.08, 0.34), 0.68, reach_world * 0.025)
		"confusion":
			_add_sphere_layer(root, start, reach_world * 0.92, cell_size, 170, 1.0, Color(0.7, 0.24, 0.95, 0.46), 0.24, reach_world * 0.08)
		"ice_storm":
			_attach_cylinder_weather(root, start, end, cell_size, Color(0.48, 0.84, 1.0, 0.62), 360)
		"vitriolic_sphere":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 240, 0.9, Color(0.44, 0.96, 0.08, 0.6), 0.34, reach_world * 0.09)
		"cone_of_cold":
			_attach_colored_cone(root, start, end, reach_world, cell_size, Color(0.52, 0.9, 1.0, 0.62))
		"insect_plague":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 420, 1.8, Color(0.34, 0.25, 0.04, 0.55), 0.14, reach_world * 0.07)
		"synaptic_static":
			_add_sphere_layer(root, start, reach_world * 0.94, cell_size, 210, 0.6, Color(0.72, 0.24, 1.0, 0.62), 0.2, reach_world * 0.13)
		"chain_lightning":
			_attach_lightning_bolt(root, start, end, reach_world, cell_size)
		"circle_of_death":
			_add_sphere_layer(root, start, reach_world * 0.96, cell_size, 300, 1.0, Color(0.16, 0.02, 0.2, 0.56), 0.3, reach_world * 0.08)
		"globe_of_invulnerability":
			_add_sphere_layer(root, start, reach_world * 0.98, cell_size, 260, 2.5, Color(0.56, 0.82, 1.0, 0.32), 0.26, reach_world * 0.018)
		"otilukes_freezing_sphere":
			_add_sphere_layer(root, start, reach_world * 0.96, cell_size, 360, 1.1, Color(0.55, 0.92, 1.0, 0.58), 0.30, reach_world * 0.07)
		"sunbeam":
			_attach_sunbeam(root, start, end, reach_world, cell_size)
		"fire", "cold", "lightning", "acid", "poison", "necrotic", "radiant", "force", "psychic", "thunder", "fear", "enchantment", "arcane":
			_attach_generic_area(
				root,
				start,
				end,
				_shape,
				style,
				reach_world,
				cell_size
			)


static func _generic_style_color(style: String) -> Color:
	match style:
		"fire":
			return Color(1.0, 0.24, 0.03, 0.62)
		"cold":
			return Color(0.48, 0.9, 1.0, 0.60)
		"lightning":
			return Color(0.36, 0.84, 1.0, 0.72)
		"acid":
			return Color(0.5, 0.96, 0.12, 0.60)
		"poison":
			return Color(0.3, 0.76, 0.1, 0.52)
		"necrotic":
			return Color(0.28, 0.06, 0.34, 0.56)
		"radiant":
			return Color(1.0, 0.94, 0.58, 0.66)
		"force":
			return Color(0.72, 0.66, 1.0, 0.58)
		"psychic", "enchantment", "fear":
			return Color(0.72, 0.28, 1.0, 0.58)
		"thunder":
			return Color(0.46, 0.78, 1.0, 0.58)
		_:
			return Color(0.72, 0.34, 1.0, 0.54)


static func _attach_generic_area(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String,
	reach_world: float,
	cell_size: float
) -> void:
	var color: Color = _generic_style_color(style)
	match shape:
		"cone":
			_attach_colored_cone(
				root,
				start,
				end,
				reach_world,
				cell_size,
				color
			)
		"line":
			var direction: Vector3 = end - start
			if direction.length_squared() < 0.0001:
				direction = Vector3.FORWARD
			else:
				direction = direction.normalized()
			_add_lightning_layer(
				root,
				start,
				direction,
				reach_world,
				cell_size,
				150,
				color,
				0.11
			)
		"cube", "flat_square":
			_add_box_layer(
				root,
				start,
				reach_world,
				cell_size,
				150,
				color,
				0.16,
				0.08
			)
		"cylinder":
			_attach_cylinder_weather(
				root,
				start,
				end,
				cell_size,
				color,
				220
			)
		_:
			_add_sphere_layer(
				root,
				start,
				reach_world * 0.94,
				cell_size,
				180,
				1.1,
				color,
				0.22,
				reach_world * 0.06
			)


static func _attach_burning_hands(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	reach_world: float,
	cell_size: float
) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	_add_cone_fire_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		180,
		Color(1.0, 0.18, 0.015, 0.62),
		0.38
	)
	_add_cone_fire_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		110,
		Color(1.0, 0.72, 0.08, 0.72),
		0.24
	)


static func _attach_fireball(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	cell_size: float
) -> void:
	_add_sphere_layer(
		root,
		center,
		radius_world * 0.92,
		cell_size,
		240,
		0.95,
		Color(1.0, 0.12, 0.01, 0.58),
		0.42,
		radius_world * 0.10
	)
	_add_sphere_layer(
		root,
		center,
		radius_world * 0.78,
		cell_size,
		150,
		0.72,
		Color(1.0, 0.7, 0.08, 0.68),
		0.27,
		radius_world * 0.08
	)


static func _attach_darkness(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	cell_size: float
) -> void:
	_add_sphere_layer(
		root,
		center,
		radius_world * 0.94,
		cell_size,
		360,
		4.0,
		Color(0.01, 0.005, 0.025, 0.42),
		0.74,
		radius_world * 0.035
	)
	_add_sphere_layer(
		root,
		center,
		radius_world * 0.82,
		cell_size,
		220,
		5.2,
		Color(0.035, 0.015, 0.07, 0.32),
		0.55,
		radius_world * 0.025
	)


static func _attach_color_spray(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	reach_world: float,
	cell_size: float
) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var colors: Array[Color] = [
		Color(1.0, 0.18, 0.22, 0.62),
		Color(1.0, 0.72, 0.12, 0.62),
		Color(0.18, 0.72, 1.0, 0.62),
		Color(0.72, 0.22, 1.0, 0.62)
	]
	for color: Color in colors:
		_add_cone_fire_layer(
			root, start, direction, reach_world, cell_size,
			54, color, 0.20
		)


static func _attach_fog_cloud(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	cell_size: float
) -> void:
	_add_sphere_layer(
		root, center, radius_world * 0.96, cell_size,
		340, 4.6, Color(0.72, 0.76, 0.82, 0.30),
		0.72, radius_world * 0.02
	)
	_add_sphere_layer(
		root, center, radius_world * 0.82, cell_size,
		220, 5.4, Color(0.9, 0.92, 0.96, 0.18),
		0.56, radius_world * 0.015
	)


static func _attach_grease(
	root: Node3D,
	center: Vector3,
	half_side_world: float,
	cell_size: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "GreaseShimmer"
	particles.amount = 90
	particles.lifetime = 2.4
	particles.preprocess = 2.4
	particles.randomness = 0.9
	root.add_child(particles)
	particles.global_position = center + Vector3.UP * cell_size * 0.03

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		half_side_world,
		cell_size * 0.02,
		half_side_world
	)
	process.direction = Vector3.UP
	process.spread = 20.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = cell_size * 0.025
	process.color = Color(0.72, 0.64, 0.22, 0.38)
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * 0.13
	quad.material = _billboard_material(
		Color(0.8, 0.72, 0.28, 0.34),
		Color(0.36, 0.28, 0.04, 1.0),
		0.18
	)
	particles.draw_pass_1 = quad


static func _attach_thunderwave(
	root: Node3D,
	center: Vector3,
	half_side_world: float,
	cell_size: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "ThunderwaveParticles"
	particles.amount = 220
	particles.lifetime = 0.5
	particles.preprocess = 0.5
	particles.randomness = 0.8
	root.add_child(particles)
	particles.global_position = center

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3.ONE * half_side_world
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = cell_size * 0.25
	process.initial_velocity_max = cell_size * 1.0
	process.color = Color(0.36, 0.72, 1.0, 0.58)
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * 0.18
	quad.material = _billboard_material(
		Color(0.36, 0.72, 1.0, 0.58),
		Color(0.18, 0.56, 1.0, 1.0),
		1.4
	)
	particles.draw_pass_1 = quad


static func _attach_colored_cone(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	reach_world: float,
	cell_size: float,
	color: Color
) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	_add_cone_fire_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		220,
		color,
		0.24
	)


static func _add_box_layer(
	root: Node3D,
	center: Vector3,
	half_extent: float,
	cell_size: float,
	amount: int,
	color: Color,
	particle_scale: float,
	max_velocity_scale: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "SpellBoxParticles"
	particles.amount = amount
	particles.lifetime = 1.8
	particles.preprocess = 1.8
	particles.randomness = 0.9
	root.add_child(particles)
	particles.global_position = center

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3.ONE * half_extent
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = cell_size * max_velocity_scale
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * particle_scale
	quad.material = _billboard_material(color, color, 0.9)
	particles.draw_pass_1 = quad


static func _attach_cylinder_weather(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	cell_size: float,
	color: Color,
	amount: int
) -> void:
	var delta: Vector3 = end - start
	var radius_world: float = maxf(absf(delta.x), cell_size * 0.5)
	var height_world: float = maxf(absf(delta.y), cell_size * 0.5)

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "SpellCylinderParticles"
	particles.amount = amount
	particles.lifetime = 1.2
	particles.preprocess = 1.2
	particles.randomness = 0.85
	root.add_child(particles)
	particles.global_position = start + Vector3.UP * height_world * 0.5

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		radius_world,
		height_world * 0.5,
		radius_world
	)
	process.direction = Vector3.DOWN
	process.spread = 8.0
	process.gravity = Vector3(0.0, -cell_size * 1.8, 0.0)
	process.initial_velocity_min = cell_size * 0.6
	process.initial_velocity_max = cell_size * 1.5
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(
		cell_size * 0.10,
		cell_size * 0.28
	)
	quad.material = _billboard_material(color, color, 0.75)
	particles.draw_pass_1 = quad


static func _attach_sunbeam(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	reach_world: float,
	cell_size: float
) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	_add_lightning_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		220,
		Color(1.0, 0.96, 0.62, 0.92),
		0.16
	)
	_add_lightning_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		100,
		Color(1.0, 1.0, 1.0, 1.0),
		0.08
	)


static func _attach_lightning_bolt(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	reach_world: float,
	cell_size: float
) -> void:
	var direction: Vector3 = end - start
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	_add_lightning_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		190,
		Color(0.45, 0.88, 1.0, 0.95),
		0.13
	)
	_add_lightning_layer(
		root,
		start,
		direction,
		reach_world,
		cell_size,
		90,
		Color(0.92, 0.98, 1.0, 1.0),
		0.075
	)


static func _add_lightning_layer(
	root: Node3D,
	start: Vector3,
	direction: Vector3,
	reach_world: float,
	cell_size: float,
	amount: int,
	color: Color,
	particle_scale: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "LightningParticles"
	particles.amount = amount
	particles.lifetime = 0.18
	particles.preprocess = 0.18
	particles.randomness = 1.0
	root.add_child(particles)

	particles.global_position = (
		start + direction * reach_world * 0.5
	)
	particles.global_basis = Basis(
		Quaternion(Vector3.UP, direction)
	)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		cell_size * 0.32,
		reach_world * 0.5,
		cell_size * 0.32
	)
	process.direction = Vector3.RIGHT
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = cell_size * 0.1
	process.initial_velocity_max = cell_size * 0.65
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(
		cell_size * particle_scale,
		cell_size * particle_scale * 4.0
	)
	quad.material = _billboard_material(
		color,
		color,
		3.0
	)
	particles.draw_pass_1 = quad


static func attach_wall_segment(
	root: Node3D,
	start: Vector3,
	finish: Vector3,
	height_world: float,
	thickness_world: float,
	style: String,
	cell_size: float
) -> void:
	if style == "wall_of_stone":
		return

	var delta: Vector3 = finish - start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.0001:
		return
	var direction: Vector3 = delta / length
	var center: Vector3 = (
		(start + finish) * 0.5
		+ Vector3.UP * height_world * 0.5
	)

	if style in [
		"fire", "cold", "lightning", "acid", "poison", "necrotic",
		"radiant", "force", "psychic", "thunder", "fear",
		"enchantment", "arcane"
	]:
		var generic_color: Color = _generic_style_color(style)
		_add_wall_particle_box(
			root,
			center,
			direction,
			length,
			height_world,
			maxf(thickness_world, cell_size * 0.12),
			220,
			0.9,
			generic_color,
			cell_size * 0.14,
			Vector3.UP * cell_size * 0.32
		)
		return

	match style:
		"wall_of_fire":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world * 1.8, cell_size * 0.16),
				220, 0.78, Color(1.0, 0.22, 0.02, 0.68),
				cell_size * 0.22, Vector3.UP * cell_size * 0.9
			)
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.08),
				120, 0.62, Color(1.0, 0.78, 0.08, 0.72),
				cell_size * 0.14, Vector3.UP * cell_size * 0.7
			)
		"wind_wall":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world * 2.0, cell_size * 0.15),
				180, 1.1, Color(0.72, 0.9, 1.0, 0.32),
				cell_size * 0.18, Vector3.UP * cell_size * 0.45
			)
		"blade_barrier":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.2),
				240, 0.42, Color(0.9, 0.94, 1.0, 0.72),
				cell_size * 0.13, Vector3.UP * cell_size * 0.22
			)
		"wall_of_force":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.04),
				80, 1.8, Color(0.45, 0.72, 1.0, 0.18),
				cell_size * 0.09, Vector3.ZERO
			)
		"wall_of_ice":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.12),
				140, 1.4, Color(0.58, 0.92, 1.0, 0.42),
				cell_size * 0.12, Vector3.DOWN * cell_size * 0.08
			)
		"wall_of_thorns":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.3),
				180, 1.6, Color(0.18, 0.62, 0.12, 0.42),
				cell_size * 0.14, Vector3.UP * cell_size * 0.05
			)
		"wall_of_sand":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.25),
				260, 1.0, Color(0.76, 0.62, 0.3, 0.46),
				cell_size * 0.10, Vector3.UP * cell_size * 0.12
			)
		"wall_of_water":
			_add_wall_particle_box(
				root, center, direction, length, height_world,
				maxf(thickness_world, cell_size * 0.12),
				240, 0.9, Color(0.18, 0.66, 1.0, 0.42),
				cell_size * 0.12, Vector3.UP * cell_size * 0.3
			)
		"prismatic_wall":
			var colors: Array[Color] = [
				Color(1.0, 0.14, 0.14, 0.42),
				Color(1.0, 0.54, 0.08, 0.40),
				Color(1.0, 0.92, 0.12, 0.38),
				Color(0.2, 0.9, 0.32, 0.38),
				Color(0.22, 0.5, 1.0, 0.40),
				Color(0.48, 0.22, 0.95, 0.40),
				Color(0.8, 0.22, 1.0, 0.42)
			]
			for color: Color in colors:
				_add_wall_particle_box(
					root, center, direction, length, height_world,
					maxf(thickness_world, cell_size * 0.05),
					36, 1.0, color,
					cell_size * 0.10, Vector3.UP * cell_size * 0.08
				)


static func attach_wall_globe(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	style: String,
	_hemisphere: bool,
	cell_size: float
) -> void:
	var color: Color = Color(0.55, 0.82, 1.0, 0.28)
	if style in [
		"fire", "cold", "lightning", "acid", "poison", "necrotic",
		"radiant", "force", "psychic", "thunder", "fear",
		"enchantment", "arcane"
	]:
		color = _generic_style_color(style)
		color.a = 0.34
	match style:
		"wall_of_ice":
			color = Color(0.56, 0.92, 1.0, 0.38)
		"prismatic_wall":
			color = Color(0.84, 0.3, 1.0, 0.38)
		"wall_of_force":
			color = Color(0.5, 0.76, 1.0, 0.16)

	_add_sphere_layer(
		root,
		center,
		radius_world * 0.98,
		cell_size,
		220 if style != "prismatic_wall" else 320,
		2.0,
		color,
		0.14,
		radius_world * 0.018
	)


static func _add_wall_particle_box(
	root: Node3D,
	center: Vector3,
	direction: Vector3,
	length: float,
	height: float,
	thickness: float,
	amount: int,
	lifetime: float,
	color: Color,
	particle_size: float,
	velocity: Vector3
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "WallParticles"
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.randomness = 0.88
	root.add_child(particles)
	particles.global_position = center
	particles.global_basis = Basis(
		Quaternion(Vector3.FORWARD, direction)
	)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		thickness * 0.5,
		height * 0.5,
		length * 0.5
	)
	process.direction = (
		velocity.normalized()
		if velocity.length_squared() > 0.0001
		else Vector3.UP
	)
	process.spread = 30.0 if velocity.length_squared() > 0.0001 else 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = velocity.length() * 0.35
	process.initial_velocity_max = velocity.length()
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * particle_size
	quad.material = _billboard_material(
		color,
		Color(color.r, color.g, color.b, 1.0),
		1.15
	)
	particles.draw_pass_1 = quad


static func attach_projectile(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	style: String,
	duration_seconds: float,
	cell_size: float
) -> void:
	if root == null or not is_instance_valid(root):
		return

	root.global_position = start

	var sphere: MeshInstance3D = MeshInstance3D.new()
	sphere.name = "ProjectileOrb"
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = cell_size * 0.18
	sphere_mesh.height = cell_size * 0.36
	sphere_mesh.radial_segments = 20
	sphere_mesh.rings = 10
	sphere.mesh = sphere_mesh
	var palette: Dictionary = _projectile_palette(style)
	var primary: Color = palette.get("primary", Color.WHITE)
	var secondary: Color = palette.get(
		"secondary",
		Color(0.5, 0.7, 1.0, 0.72)
	)
	sphere.material_override = _projectile_material(
		style,
		primary
	)
	root.add_child(sphere)

	_add_projectile_trail(
		root,
		cell_size,
		primary,
		0.16
	)
	_add_projectile_trail(
		root,
		cell_size,
		secondary,
		0.10
	)

	var tween: Tween = root.create_tween()
	tween.tween_property(
		root,
		"global_position",
		end,
		duration_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(root.queue_free)


static func _add_projectile_trail(
	root: Node3D,
	cell_size: float,
	color: Color,
	particle_scale: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "ProjectileTrail"
	particles.amount = 72
	particles.lifetime = 0.65
	particles.preprocess = 0.25
	particles.randomness = 0.75
	particles.local_coords = false
	root.add_child(particles)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = cell_size * 0.08
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = cell_size * 0.02
	process.initial_velocity_max = cell_size * 0.12
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * particle_scale
	quad.material = _billboard_material(
		color,
		color,
		1.8
	)
	particles.draw_pass_1 = quad


static func _projectile_palette(style: String) -> Dictionary:
	match style:
		"fire":
			return {"primary": Color(1.0, 0.24, 0.03, 0.92), "secondary": Color(1.0, 0.78, 0.12, 0.76)}
		"cold":
			return {"primary": Color(0.48, 0.9, 1.0, 0.92), "secondary": Color(0.88, 0.98, 1.0, 0.78)}
		"lightning", "thunder":
			return {"primary": Color(0.4, 0.86, 1.0, 0.94), "secondary": Color(0.94, 1.0, 1.0, 0.82)}
		"acid", "poison":
			return {"primary": Color(0.42, 0.92, 0.12, 0.9), "secondary": Color(0.76, 1.0, 0.2, 0.72)}
		"necrotic":
			return {"primary": Color(0.34, 0.08, 0.42, 0.9), "secondary": Color(0.12, 0.04, 0.18, 0.72)}
		"radiant":
			return {"primary": Color(1.0, 0.94, 0.58, 0.96), "secondary": Color(1.0, 1.0, 0.9, 0.84)}
		"force":
			return {"primary": Color(0.76, 0.7, 1.0, 0.94), "secondary": Color(0.94, 0.9, 1.0, 0.78)}
		"psychic", "enchantment", "fear", "arcane":
			return {"primary": Color(0.74, 0.3, 1.0, 0.92), "secondary": Color(0.28, 0.76, 1.0, 0.74)}
		"fire_bolt":
			return {"primary": Color(1.0, 0.22, 0.02, 0.9), "secondary": Color(1.0, 0.75, 0.08, 0.75)}
		"ray_of_frost", "ice_knife":
			return {"primary": Color(0.45, 0.9, 1.0, 0.9), "secondary": Color(0.82, 0.98, 1.0, 0.78)}
		"poison_spray", "ray_of_sickness":
			return {"primary": Color(0.28, 0.92, 0.16, 0.86), "secondary": Color(0.68, 1.0, 0.18, 0.68)}
		"mind_sliver":
			return {"primary": Color(0.76, 0.28, 1.0, 0.88), "secondary": Color(1.0, 0.48, 0.92, 0.72)}
		"shocking_grasp":
			return {"primary": Color(0.42, 0.86, 1.0, 0.94), "secondary": Color(0.94, 1.0, 1.0, 0.82)}
		"magic_missile":
			return {"primary": Color(0.92, 0.9, 1.0, 0.96), "secondary": Color(0.46, 0.34, 1.0, 0.74)}
		"sorcerous_burst":
			return {"primary": Color(0.9, 0.32, 1.0, 0.92), "secondary": Color(0.18, 0.82, 1.0, 0.76)}
		"chill_touch":
			return {"primary": Color(0.38, 0.76, 0.72, 0.82), "secondary": Color(0.16, 0.28, 0.34, 0.7)}
		"mind_spike":
			return {"primary": Color(0.7, 0.22, 1.0, 0.9), "secondary": Color(0.95, 0.46, 1.0, 0.72)}
		"scorching_ray":
			return {"primary": Color(1.0, 0.18, 0.015, 0.94), "secondary": Color(1.0, 0.72, 0.06, 0.78)}
		"blight":
			return {"primary": Color(0.16, 0.05, 0.2, 0.92), "secondary": Color(0.38, 0.12, 0.42, 0.72)}
		"disintegrate":
			return {"primary": Color(0.16, 1.0, 0.32, 0.94), "secondary": Color(0.72, 1.0, 0.18, 0.76)}
		_:
			return {"primary": Color(0.75, 0.22, 1.0, 0.88), "secondary": Color(0.15, 0.8, 1.0, 0.72)}


static func _projectile_material(
	_style: String,
	primary: Color
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.albedo_color = primary
	material.emission = Color(primary.r, primary.g, primary.b, 1.0)
	material.emission_energy_multiplier = 2.8
	return material


static func _add_cone_fire_layer(
	root: Node3D,
	origin: Vector3,
	direction: Vector3,
	reach_world: float,
	cell_size: float,
	amount: int,
	color: Color,
	particle_scale: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "FireConeParticles"
	particles.amount = amount
	particles.lifetime = 0.85
	particles.preprocess = 0.85
	particles.randomness = 0.65
	root.add_child(particles)
	particles.global_position = origin
	particles.global_basis = Basis(
		Quaternion(Vector3.UP, direction)
	)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 27.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = reach_world * 0.28 / particles.lifetime
	process.initial_velocity_max = reach_world / particles.lifetime
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * particle_scale
	quad.material = _billboard_material(
		color,
		Color(1.0, 0.16, 0.015, 1.0),
		2.2
	)
	particles.draw_pass_1 = quad


static func _add_sphere_layer(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	cell_size: float,
	amount: int,
	lifetime: float,
	color: Color,
	particle_scale: float,
	max_velocity: float
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "SpellVolumeParticles"
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.randomness = 0.85
	root.add_child(particles)
	particles.global_position = center

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius_world
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3(0.0, max_velocity * 0.08, 0.0)
	process.initial_velocity_min = max_velocity * 0.25
	process.initial_velocity_max = max_velocity
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * particle_scale
	quad.material = _billboard_material(
		color,
		color,
		1.25 if color.r > 0.2 else 0.12
	)
	particles.draw_pass_1 = quad


static func _billboard_material(
	albedo: Color,
	emission: Color,
	emission_energy: float
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = albedo
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	return material
