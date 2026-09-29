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
	if style not in ["burning_hands", "fireball", "darkness", "lightning_bolt"]:
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
	sphere.material_override = _projectile_material(style)
	root.add_child(sphere)

	_add_projectile_trail(
		root,
		cell_size,
		Color(0.75, 0.22, 1.0, 0.78),
		0.16
	)
	_add_projectile_trail(
		root,
		cell_size,
		Color(0.15, 0.8, 1.0, 0.72),
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


static func _projectile_material(style: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true

	if style == "chromatic_orb":
		material.albedo_color = Color(0.68, 0.22, 1.0, 0.96)
		material.emission = Color(0.42, 0.12, 1.0, 1.0)
		material.emission_energy_multiplier = 3.0
	else:
		material.albedo_color = Color.WHITE
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 2.0

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
