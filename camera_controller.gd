extends Camera3D

const TOP_DOWN_SLICE_PADDING := 0.12

@export_range(1.0, 100.0, 0.5) var speed: float = 5.0
@export_range(0.0002, 0.01, 0.0001) var mouse_sensitivity: float = 0.002
@export_range(2.0, 20.0, 0.5) var top_down_min_size: float = 4.0
@export_range(40.0, 800.0, 1.0) var top_down_max_size: float = 400.0
@export_range(0.1, 3.0, 0.05) var top_down_zoom_rate: float = 0.9
@export_range(12.0, 80.0, 1.0) var top_down_camera_height: float = 32.0

var _first_person_target: CharacterBody3D = null
var _saved_free_transform: Transform3D = Transform3D.IDENTITY
var _has_saved_free_transform: bool = false
var _last_target_yaw: float = 0.0
var _top_down_2d_enabled: bool = false
var _saved_2d_transform: Transform3D = Transform3D.IDENTITY
var _saved_2d_projection: int = Camera3D.PROJECTION_PERSPECTIVE
var _saved_2d_size: float = 20.0
var _saved_2d_fov: float = 75.0
var _saved_2d_near: float = 0.05
var _has_saved_2d_state: bool = false
var _top_down_center_y: float = 0.0
var _top_down_tilt_degrees: float = 0.0
var _top_down_floor_levels_provider: Callable = Callable()
var _top_down_clearance: float = 32.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _top_down_2d_enabled:
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.keycode == KEY_SPACE
			and not _text_input_has_focus()
		):
			step_top_down_level(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(
			Vector3.RIGHT,
			-event.relative.y * mouse_sensitivity
		)


func get_move_speed() -> float:
	return speed


func set_move_speed(value: float) -> void:
	speed = clampf(value, 1.0, 100.0)


func adjust_move_speed(delta_speed: float) -> float:
	set_move_speed(speed + delta_speed)
	return speed


func get_mouse_sensitivity() -> float:
	return mouse_sensitivity


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.0002, 0.01)


func _process(delta: float) -> void:
	if _top_down_2d_enabled:
		_process_top_down_2d(delta)
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if is_first_person():
		_update_first_person_camera()
		return

	var direction: Vector3 = Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x

	if Input.is_key_pressed(KEY_SPACE):
		if Input.is_key_pressed(KEY_SHIFT):
			direction += Vector3.DOWN
		else:
			direction += Vector3.UP

	if direction != Vector3.ZERO:
		global_position += direction.normalized() * speed * delta


func _process_top_down_2d(delta: float) -> void:
	if _text_input_has_focus():
		return

	var shift_pressed := Input.is_key_pressed(KEY_SHIFT)
	var zoom_direction := 0.0
	if shift_pressed and Input.is_key_pressed(KEY_W):
		zoom_direction -= 1.0
	if shift_pressed and Input.is_key_pressed(KEY_S):
		zoom_direction += 1.0

	if not is_zero_approx(zoom_direction):
		var zoom_step := (
			maxf(size, top_down_min_size)
			* top_down_zoom_rate
			* delta
		)
		size = clampf(
			size + zoom_direction * zoom_step,
			top_down_min_size,
			top_down_max_size
		)

	var pan := Vector3.ZERO
	if not shift_pressed and Input.is_key_pressed(KEY_W):
		pan.z -= 1.0
	if not shift_pressed and Input.is_key_pressed(KEY_S):
		pan.z += 1.0
	if Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		pan.x += 1.0

	if pan != Vector3.ZERO:
		var pan_speed := maxf(speed, size * 0.45)
		global_position += pan.normalized() * pan_speed * delta


func set_top_down_floor_levels_provider(provider: Callable) -> void:
	_top_down_floor_levels_provider = provider


func get_top_down_level() -> float:
	return _top_down_center_y


func _available_top_down_levels() -> Array[float]:
	var levels: Array[float] = []
	if not _top_down_floor_levels_provider.is_valid():
		return levels
	var value: Variant = _top_down_floor_levels_provider.call()
	if value is Array:
		for item: Variant in value:
			if item is float or item is int:
				var height: float = float(item)
				if not levels.has(height):
					levels.append(height)
	levels.sort()
	return levels


func step_top_down_level(direction: int) -> void:
	if not _top_down_2d_enabled or direction == 0:
		return
	var levels: Array[float] = _available_top_down_levels()
	if levels.is_empty():
		return
	var next_level: float = _top_down_center_y
	if direction > 0:
		for level: float in levels:
			if level > _top_down_center_y + 0.01:
				next_level = level
				break
	else:
		for index: int in range(levels.size() - 1, -1, -1):
			if levels[index] < _top_down_center_y - 0.01:
				next_level = levels[index]
				break
	set_top_down_level(next_level)


func set_top_down_level(level: float) -> void:
	if not _top_down_2d_enabled or is_equal_approx(level, _top_down_center_y):
		return
	var delta_height: float = level - _top_down_center_y
	_top_down_center_y = level
	var tilt_radians: float = deg_to_rad(_top_down_tilt_degrees)
	# Compensate tilt so the same XZ map point stays under the camera.
	global_position += Vector3(
		0.0,
		delta_height,
		delta_height * tan(tilt_radians)
	)


func _update_top_down_slice() -> void:
	# Clip surfaces above the selected floor, not just the camera position.
	# This keeps the lower floors visible without changing the map geometry.
	var radians: float = deg_to_rad(_top_down_tilt_degrees)
	near = maxf(
		0.05,
		_top_down_clearance / cos(radians) - TOP_DOWN_SLICE_PADDING
	)


func _text_input_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func enter_top_down_2d(
	center: Vector3 = Vector3.ZERO,
	fit_size: float = 30.0,
	tilt_degrees: float = 0.0
) -> void:
	if _top_down_2d_enabled:
		size = clampf(fit_size, top_down_min_size, top_down_max_size)
		_apply_top_down_pose(center, tilt_degrees)
		return

	if is_first_person():
		_first_person_target = null
		_has_saved_free_transform = false

	_saved_2d_transform = global_transform
	_saved_2d_projection = projection
	_saved_2d_size = size
	_saved_2d_fov = fov
	_saved_2d_near = near
	_has_saved_2d_state = true
	_top_down_2d_enabled = true

	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = clampf(fit_size, top_down_min_size, top_down_max_size)
	_apply_top_down_pose(center, tilt_degrees)


func _apply_top_down_pose(
	center: Vector3,
	tilt_degrees: float
) -> void:
	var tilt: float = clampf(tilt_degrees, 0.0, 30.0)
	_top_down_tilt_degrees = tilt
	_top_down_center_y = center.y
	_top_down_clearance = maxf(top_down_camera_height, 12.0)
	var height: float = _top_down_clearance
	_update_top_down_slice()
	if is_zero_approx(tilt):
		global_position = Vector3(center.x, center.y + height, center.z)
		global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		return

	# Una lieve inclinazione serve ai preset che usano alberi billboard:
	# a -90° esatti i piani verticali hanno area proiettata quasi nulla.
	# Spostiamo anche la camera così il centro ottico resta sulla mappa.
	var tilt_radians: float = deg_to_rad(tilt)
	global_position = Vector3(
		center.x,
		center.y + height,
		center.z + height * tan(tilt_radians)
	)
	look_at(center, Vector3.UP)


func exit_top_down_2d() -> void:
	if not _top_down_2d_enabled:
		return

	_top_down_2d_enabled = false
	if _has_saved_2d_state:
		projection = _saved_2d_projection
		size = _saved_2d_size
		fov = _saved_2d_fov
		near = _saved_2d_near
		global_transform = _saved_2d_transform
	_has_saved_2d_state = false


func is_top_down_2d() -> bool:
	return _top_down_2d_enabled


func focus_on_token(token: Node3D) -> void:
	if token == null or not is_instance_valid(token):
		return

	if _top_down_2d_enabled:
		var top_position := global_position
		top_position.x = token.global_position.x
		top_position.z = token.global_position.z
		global_position = top_position
		return

	# Il comando "occhio" deve essere una semplice inquadratura, non entrare
	# nella modalita' prima persona e non legare la camera al movimento futuro.
	if is_first_person():
		_first_person_target = null
		_has_saved_free_transform = false

	var token_cell_size := 1.0
	var token_height := 2.0
	var footprint := 1.0
	var cell_value: Variant = token.get("cell_size")
	if cell_value is float or cell_value is int:
		token_cell_size = maxf(float(cell_value), 0.001)
	var height_value: Variant = token.get("token_height_cells")
	if height_value is float or height_value is int:
		token_height = maxf(float(height_value), 0.5)
	if token.has_method("get_footprint_cells"):
		footprint = maxf(float(token.call("get_footprint_cells")), 0.5)

	var target := (
		token.global_position
		+ Vector3.UP * token_height * token_cell_size * 0.18
	)
	var token_forward := -token.global_transform.basis.z.normalized()
	var distance := maxf(
		3.0 * token_cell_size,
		footprint * token_cell_size * 2.4
	)
	var camera_height := maxf(
		1.1 * token_cell_size,
		token_height * token_cell_size * 0.45
	)
	global_position = (
		target
		+ token_forward * distance
		+ Vector3.UP * camera_height
	)
	look_at(target, Vector3.UP)


func enter_first_person(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return

	if _top_down_2d_enabled:
		exit_top_down_2d()

	if not is_first_person():
		_saved_free_transform = global_transform
		_has_saved_free_transform = true

	_first_person_target = token
	_last_target_yaw = token.global_rotation.y

	global_rotation = Vector3(0.0, _last_target_yaw, 0.0)
	_update_first_person_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func exit_first_person() -> void:
	_first_person_target = null

	if _has_saved_free_transform:
		global_transform = _saved_free_transform

	_has_saved_free_transform = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_first_person() -> bool:
	return (
		_first_person_target != null
		and is_instance_valid(_first_person_target)
	)


func get_first_person_target() -> CharacterBody3D:
	if is_first_person():
		return _first_person_target
	return null


func _update_first_person_camera() -> void:
	if _first_person_target == null \
	or not is_instance_valid(_first_person_target):
		exit_first_person()
		return

	var target_yaw: float = _first_person_target.global_rotation.y
	var yaw_delta: float = wrapf(
		target_yaw - _last_target_yaw,
		-PI,
		PI
	)

	if not is_zero_approx(yaw_delta):
		rotate_y(yaw_delta)

	_last_target_yaw = target_yaw
	_update_first_person_position()


func _update_first_person_position() -> void:
	if _first_person_target == null \
	or not is_instance_valid(_first_person_target):
		return

	if _first_person_target.has_method("get_first_person_camera_position"):
		var target_position: Variant = _first_person_target.call(
			"get_first_person_camera_position"
		)

		if target_position is Vector3:
			global_position = target_position
	else:
		global_position = (
			_first_person_target.global_position
			+ Vector3.UP * 0.75
		)
