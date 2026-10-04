extends RefCounted

# Data-driven animation overlay for spell areas. It knows only damage families
# and geometric volumes; there is no per-spell animation table.

const DAMAGE_TYPES: Array[String] = [
	"acid", "arcane", "bludgeoning", "cold", "darkness", "earth",
	"fire", "force", "lightning", "mist", "nature", "necrotic",
	"piercing", "poison", "prismatic", "psychic", "radiant",
	"silver_mist", "slashing", "thunder", "water", "wind",
]


static func supports(damage_type: String) -> bool:
	return damage_type.to_lower() in DAMAGE_TYPES


static func attach_area(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	shape: String,
	damage_type: String,
	cell_size: float
) -> void:
	var style: String = damage_type.to_lower()
	if root == null or not is_instance_valid(root) or not supports(style):
		return

	if style == "prismatic":
		for layer_style: String in [
			"fire", "cold", "lightning", "acid", "radiant", "psychic"
		]:
			attach_area(root, start, end, shape, layer_style, cell_size)
		return

	var delta: Vector3 = end - start
	var reach: float = maxf(delta.length(), cell_size * 0.5)
	var direction: Vector3 = (
		delta.normalized()
		if delta.length_squared() > 0.000001
		else Vector3.FORWARD
	)

	match shape:
		"line":
			_add_box(
				root,
				start + direction * reach * 0.5,
				Basis(Quaternion(Vector3.UP, direction)),
				Vector3(cell_size * 0.42, reach * 0.5, cell_size * 0.42),
				style,
				cell_size,
				180
			)
		"cone":
			_add_box(
				root,
				start + direction * reach * 0.58,
				Basis(Quaternion(Vector3.UP, direction)),
				Vector3(reach * 0.28, reach * 0.42, reach * 0.28),
				style,
				cell_size,
				180
			)
		"cube":
			_add_box(
				root, start, Basis.IDENTITY, Vector3.ONE * reach * 0.88,
				style, cell_size, 190
			)
		"flat_square":
			_add_box(
				root,
				start + Vector3.UP * cell_size * 0.04,
				Basis.IDENTITY,
				Vector3(reach * 0.9, cell_size * 0.05, reach * 0.9),
				style,
				cell_size,
				130
			)
		"cylinder":
			var radius_world: float = maxf(absf(delta.x), cell_size * 0.5)
			var height_world: float = maxf(absf(delta.y), cell_size * 0.5)
			_add_box(
				root,
				start + Vector3.UP * height_world * 0.5,
				Basis.IDENTITY,
				Vector3(
					radius_world * 0.85,
					height_world * 0.48,
					radius_world * 0.85
				),
				style,
				cell_size,
				220
			)
		_:
			_add_sphere(
				root, start, reach * 0.92, style, cell_size, 210
			)


static func attach_wall_segment(
	root: Node3D,
	start: Vector3,
	finish: Vector3,
	height_world: float,
	thickness_world: float,
	damage_type: String,
	cell_size: float
) -> void:
	var style: String = damage_type.to_lower()
	if root == null or not is_instance_valid(root) or not supports(style):
		return

	if style == "prismatic":
		for layer_style: String in [
			"fire", "cold", "lightning", "acid", "radiant", "psychic"
		]:
			attach_wall_segment(
				root, start, finish, height_world, thickness_world,
				layer_style, cell_size
			)
		return

	var delta: Vector3 = finish - start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.0001:
		return

	var direction: Vector3 = delta / length
	_add_box(
		root,
		(start + finish) * 0.5 + Vector3.UP * height_world * 0.5,
		Basis(Quaternion(Vector3.FORWARD, direction)),
		Vector3(
			maxf(thickness_world * 0.55, cell_size * 0.08),
			height_world * 0.48,
			length * 0.49
		),
		style,
		cell_size,
		220
	)


static func attach_wall_globe(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	damage_type: String,
	cell_size: float
) -> void:
	var style: String = damage_type.to_lower()
	if root == null or not is_instance_valid(root) or not supports(style):
		return
	if style == "prismatic":
		for layer_style: String in [
			"fire", "cold", "lightning", "acid", "radiant", "psychic"
		]:
			attach_wall_globe(
				root, center, radius_world, layer_style, cell_size
			)
		return
	_add_sphere(root, center, radius_world * 0.96, style, cell_size, 260)


static func _add_sphere(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	style: String,
	cell_size: float,
	amount: int
) -> void:
	var particles: GPUParticles3D = _base_particles(
		root, style, cell_size, amount
	)
	particles.global_position = center
	var process: ParticleProcessMaterial = (
		particles.process_material as ParticleProcessMaterial
	)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(radius_world, cell_size * 0.1)


static func _add_box(
	root: Node3D,
	center: Vector3,
	basis: Basis,
	extents: Vector3,
	style: String,
	cell_size: float,
	amount: int
) -> void:
	var particles: GPUParticles3D = _base_particles(
		root, style, cell_size, amount
	)
	particles.global_position = center
	particles.global_basis = basis
	var process: ParticleProcessMaterial = (
		particles.process_material as ParticleProcessMaterial
	)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		maxf(extents.x, cell_size * 0.02),
		maxf(extents.y, cell_size * 0.02),
		maxf(extents.z, cell_size * 0.02)
	)


static func _base_particles(
	root: Node3D,
	style: String,
	cell_size: float,
	amount: int
) -> GPUParticles3D:
	var color: Color = _color(style)
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "SpellDamageParticles"
	particles.amount = amount
	particles.lifetime = _lifetime(style)
	particles.preprocess = particles.lifetime
	particles.randomness = 0.86
	# Spell areas remain alive until clicked, so their particle animation must
	# loop instead of behaving like a one-shot impact.
	particles.one_shot = false
	particles.emitting = true
	root.add_child(particles)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	var motion: Vector3 = _motion(style, cell_size)
	process.direction = (
		motion.normalized()
		if motion.length_squared() > 0.000001
		else Vector3.UP
	)
	process.spread = _spread(style)
	process.gravity = _gravity(style, cell_size)
	process.initial_velocity_min = motion.length() * 0.2
	process.initial_velocity_max = maxf(motion.length(), cell_size * 0.05)
	process.color = color
	particles.process_material = process

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * _particle_scale(style)
	quad.material = _billboard_material(
		color,
		Color(color.r, color.g, color.b, 1.0),
		_emission_energy(style)
	)
	particles.draw_pass_1 = quad
	return particles


static func _color(style: String) -> Color:
	match style:
		"fire":
			return Color(1.0, 0.24, 0.03, 0.66)
		"cold":
			return Color(0.48, 0.9, 1.0, 0.62)
		"lightning":
			return Color(0.36, 0.84, 1.0, 0.76)
		"acid":
			return Color(0.5, 0.96, 0.12, 0.62)
		"poison":
			return Color(0.3, 0.76, 0.1, 0.54)
		"necrotic":
			return Color(0.28, 0.06, 0.34, 0.6)
		"radiant":
			return Color(1.0, 0.94, 0.58, 0.7)
		"force":
			return Color(0.72, 0.66, 1.0, 0.62)
		"psychic":
			return Color(0.72, 0.28, 1.0, 0.62)
		"arcane":
			return Color(0.72, 0.34, 1.0, 0.58)
		"silver_mist":
			return Color(0.86, 0.9, 0.98, 0.5)
		"mist":
			return Color(0.72, 0.78, 0.86, 0.46)
		"water":
			return Color(0.18, 0.66, 1.0, 0.58)
		"wind":
			return Color(0.78, 0.92, 1.0, 0.48)
		"earth":
			return Color(0.52, 0.4, 0.25, 0.58)
		"nature":
			return Color(0.28, 0.72, 0.18, 0.56)
		"darkness":
			return Color(0.06, 0.02, 0.12, 0.62)
		"thunder":
			return Color(0.46, 0.78, 1.0, 0.62)
		"bludgeoning":
			return Color(0.7, 0.72, 0.76, 0.6)
		"piercing", "slashing":
			return Color(0.88, 0.9, 0.94, 0.66)
		_:
			return Color(0.72, 0.34, 1.0, 0.58)


static func _motion(style: String, cell_size: float) -> Vector3:
	match style:
		"fire", "necrotic", "poison", "psychic", "radiant":
			return Vector3.UP * cell_size * 0.75
		"cold", "acid":
			return Vector3.DOWN * cell_size * 0.55
		"lightning", "thunder", "force":
			return Vector3.UP * cell_size * 0.25
		"mist", "silver_mist", "wind":
			return Vector3.UP * cell_size * 0.18
		"water":
			return Vector3.DOWN * cell_size * 0.28
		"earth":
			return Vector3.UP * cell_size * 0.08
		"nature":
			return Vector3.UP * cell_size * 0.42
		_:
			return Vector3.UP * cell_size * 0.35


static func _gravity(style: String, cell_size: float) -> Vector3:
	match style:
		"fire", "necrotic", "poison", "psychic", "radiant":
			return Vector3.UP * cell_size * 0.12
		"cold", "acid":
			return Vector3.DOWN * cell_size * 0.35
		_:
			return Vector3.ZERO


static func _spread(style: String) -> float:
	if style in ["lightning", "thunder", "force"]:
		return 180.0
	if style in ["fire", "necrotic", "poison", "psychic", "radiant"]:
		return 55.0
	return 95.0


static func _lifetime(style: String) -> float:
	if style in ["lightning", "thunder"]:
		return 0.34
	if style in ["fire", "acid"]:
		return 0.85
	return 1.25


static func _particle_scale(style: String) -> float:
	if style in ["lightning", "thunder"]:
		return 0.10
	if style in ["piercing", "slashing"]:
		return 0.11
	if style == "bludgeoning":
		return 0.16
	return 0.14


static func _emission_energy(style: String) -> float:
	if style in ["radiant", "lightning", "fire"]:
		return 1.8
	if style in ["cold", "force", "psychic", "thunder"]:
		return 1.25
	return 0.75


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
