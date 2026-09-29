extends CharacterBody3D

@export var cell_size: float = 1.0
@export var gravity_multiplier: float = 1.0
@export var terminal_velocity: float = 40.0
@export var token_height_cells: float = 2.0
@export var flying: bool = false

# D&D definisce la forma del cono, ma non una portata visiva universale.
# 12 celle = 60 ft è quindi solo un default configurabile.
@export var vision_cone_length_cells: float = 12.0

@onready var visuals: Node3D = $Visuals
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var selection_marker: MeshInstance3D = $SelectionMarker
@onready var facing_marker: Node3D = $FacingMarker
@onready var vision_cone: Node3D = $VisionCone

var _selected: bool = false
var _gravity: float = 9.8
var _footprint_cells: float = 1.0
var _size_name: String = "Medium"
var movement_validator: Callable
var grid_support: Node3D
var _support_transform: Transform3D


func _ready() -> void:
	add_to_group("dnd_token")
	platform_floor_layers = 1
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_gravity = float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	set_selected(false)
	set_vision_cone_visible(false)


func _physics_process(delta: float) -> void:
	if is_instance_valid(grid_support) and not flying:
		global_position = grid_support.global_transform * (_support_transform.affine_inverse() * global_position)
		_support_transform = grid_support.global_transform
		if grid_support.has_meta("passenger_deck_extent"):
			var local := grid_support.to_local(global_position)
			var extent: Vector2 = grid_support.get_meta("passenger_deck_extent")
			var half_height := token_height_cells*cell_size*.5
			if absf(local.x)<extent.x*.5 and absf(local.z)<extent.y*.5 and absf(local.y-half_height)<cell_size*.12:
				local.y = half_height+.01*cell_size
				global_position = grid_support.to_global(local)
				velocity = Vector3.ZERO
				return
			grid_support = null
	if flying:
		velocity.y = 0.0
	elif is_on_floor():
		velocity.y = -0.05
	else:
		velocity.y = maxf(
			velocity.y - (_gravity * gravity_multiplier * delta),
			-terminal_velocity
		)

	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	grid_support = null
	if not flying and is_on_floor():
		for index in range(get_slide_collision_count()):
			var hit := get_slide_collision(index)
			var body := hit.get_collider() as Node3D
			if body != null and body.is_in_group("tactical_platform") and hit.get_normal().dot(Vector3.UP) > 0.7:
				grid_support = body
				_support_transform = body.global_transform

	if is_on_floor() and not flying:
		_snap_horizontal_to_grid()


func set_flying(enabled: bool) -> void:
	flying = enabled
	velocity = Vector3.ZERO
	grid_support = null
	platform_floor_layers = 0 if enabled else 1
	if is_instance_valid(selection_marker):
		var material: StandardMaterial3D = selection_marker.mesh.material.duplicate()
		if enabled:
			material.albedo_color = Color(0.3, 0.85, 1)
			material.emission = Color(0.1, 0.5, 0.8)
		selection_marker.material_override = material


func nudge_vertical(steps: int) -> void:
	move_and_collide(Vector3.UP * steps * cell_size)
	velocity.y = 0
	grid_support = null


func configure(
	token_color: Color,
	new_cell_size: float = 1.0,
	size_name: String = "Medium",
	footprint_cells: float = 1.0
) -> void:
	cell_size = maxf(new_cell_size, 0.001)
	_size_name = size_name
	_footprint_cells = maxf(footprint_cells, 0.5)

	set_token_size(_footprint_cells)
	set_token_color(token_color)
	_snap_horizontal_to_grid()


func set_token_size(footprint_cells: float) -> void:
	_footprint_cells = maxf(footprint_cells, 0.5)

	var width: float = _footprint_cells * cell_size
	var height: float = token_height_cells * cell_size

	var new_shape: BoxShape3D = BoxShape3D.new()
	new_shape.size = Vector3(width, height, width)
	collision_shape.shape = new_shape

	var horizontal_visual_scale: float = maxf(0.55, _footprint_cells)
	visuals.scale = Vector3(
		horizontal_visual_scale,
		cell_size,
		horizontal_visual_scale
	)

	selection_marker.scale = Vector3(
		_footprint_cells,
		1.0,
		_footprint_cells
	)
	selection_marker.position.y = -(height * 0.5) + 0.02

	var facing_scale: float = clampf(_footprint_cells * 0.72, 0.62, 1.65)
	facing_marker.scale = Vector3(facing_scale, 1.0, facing_scale)
	facing_marker.position.y = -(height * 0.5) + 0.045

	var eye_height: float = height * 0.38
	var ground_y: float = -(height * 0.5) + 0.055

	if vision_cone.has_method("configure"):
		vision_cone.call(
			"configure",
			cell_size,
			vision_cone_length_cells,
			eye_height,
			ground_y
		)


func set_token_color(token_color: Color) -> void:
	var body_material: StandardMaterial3D = StandardMaterial3D.new()
	body_material.albedo_color = token_color
	body_material.roughness = 0.62
	body_material.metallic = 0.04

	var head_material: StandardMaterial3D = StandardMaterial3D.new()
	head_material.albedo_color = token_color.lightened(0.16)
	head_material.roughness = 0.7

	for child_node: Node in visuals.get_children():
		if child_node is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child_node as MeshInstance3D

			# Il piccolo visore frontale usa il proprio materiale dorato.
			if child_node.name == "FacingVisor":
				continue

			if child_node.name == "Head":
				mesh_instance.material_override = head_material
			else:
				mesh_instance.material_override = body_material


func set_selected(value: bool) -> void:
	_selected = value

	if is_instance_valid(selection_marker):
		selection_marker.visible = value


func is_selected() -> bool:
	return _selected


func set_vision_cone_visible(value: bool) -> void:
	if is_instance_valid(vision_cone):
		vision_cone.visible = value


func is_vision_cone_visible() -> bool:
	return is_instance_valid(vision_cone) and vision_cone.visible


func get_size_name() -> String:
	return _size_name


func get_footprint_cells() -> float:
	return _footprint_cells

func get_footprint_extent() -> Vector2:
	return Vector2.ONE*_footprint_cells*cell_size

func get_movement_exclusions() -> Array[RID]:
	return [get_rid()]


func get_first_person_camera_position() -> Vector3:
	var eye_height: float = token_height_cells * cell_size * 0.38
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var forward_offset: float = maxf(
		0.16,
		_footprint_cells * cell_size * 0.18
	)

	return (
		global_position
		+ Vector3.UP * eye_height
		+ forward * forward_offset
	)


func nudge_grid(grid_direction: Vector2i) -> void:
	# Le frecce sono relative all'orientamento del token:
	# su = avanti, giu = indietro, sinistra/destra = movimento laterale.
	# In questo modo "avanti" coincide sempre con la freccia dorata e con
	# la direzione della visuale in prima persona.
	var local_step: Vector3 = Vector3(
		float(grid_direction.x),
		0.0,
		float(grid_direction.y)
	)
	var world_step: Vector3 = global_transform.basis * local_step
	world_step.y = 0.0

	# Il token può essere orientato anche a 45°. L'arrotondamento produce
	# quindi il passo ortogonale o diagonale coerente con la direzione visiva.
	world_step.x = round(world_step.x)
	world_step.z = round(world_step.z)

	var destination := global_position + world_step * cell_size
	if movement_validator.is_valid() and not movement_validator.call(self, destination):
		return
	if move_and_collide(destination - global_position) == null:
		_snap_horizontal_to_grid()


func rotate_grid(rotation_steps: int) -> void:
	rotation.y += deg_to_rad(45.0 * float(rotation_steps))
	rotation.y = snappedf(rotation.y, PI / 4.0)


func _snap_horizontal_to_grid() -> void:
	if is_instance_valid(grid_support):
		var local_point := grid_support.to_local(global_position)
		local_point.x = _snap_coordinate(local_point.x)
		local_point.z = _snap_coordinate(local_point.z)
		global_position = grid_support.to_global(local_point)
		return
	global_position.x = _snap_coordinate(global_position.x)
	global_position.z = _snap_coordinate(global_position.z)


func _snap_coordinate(value: float) -> float:
	var rounded_footprint: int = int(round(_footprint_cells))

	if is_equal_approx(_footprint_cells, float(rounded_footprint)) \
	and rounded_footprint % 2 == 0:
		return round(value / cell_size) * cell_size

	return floor(value / cell_size) * cell_size + (cell_size * 0.5)

func snap_destination(point: Vector3, support: Node3D = null) -> Vector3:
	var local_point := support.to_local(point) if is_instance_valid(support) else point
	local_point.x = _snap_coordinate(local_point.x)
	local_point.z = _snap_coordinate(local_point.z)
	return support.to_global(local_point) if is_instance_valid(support) else local_point
