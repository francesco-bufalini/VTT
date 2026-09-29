extends RefCounted


static func attach(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String,
	cell_size: float
) -> void:
	if root == null or not is_instance_valid(root):
		return
	if style not in ["burning_hands", "fireball", "darkness"]:
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
	particles.global_position = origin
	particles.global_basis = Basis(
		Quaternion(Vector3.UP, direction)
	)
	root.add_child(particles)

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
	particles.global_position = center
	root.add_child(particles)

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
