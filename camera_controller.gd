extends Camera3D

@export_range(1.0, 100.0, 0.5) var speed: float = 5.0
@export_range(0.0002, 0.01, 0.0001) var mouse_sensitivity: float = 0.002
@export_range(2.0, 20.0, 0.5) var top_down_min_size: float = 4.0
@export_range(40.0, 800.0, 1.0) var top_down_max_size: float = 400.0
@export_range(0.1, 3.0, 0.05) var top_down_zoom_rate: float = 0.9

var _first_person_target: CharacterBody3D = null
var _saved_free_transform: Transform3D = Transform3D.IDENTITY
var _has_saved_free_transform: bool = false
var _last_target_yaw: float = 0.0
var _top_down_2d_enabled: bool = false
var _saved_2d_transform: Transform3D = Transform3D.IDENTITY
var _saved_2d_projection: int = Camera3D.PROJECTION_PERSPECTIVE
var _saved_2d_size: float = 20.0
var _saved_2d_fov: float = 75.0
var _has_saved_2d_state: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _top_down_2d_enabled:
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


func _text_input_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func enter_top_down_2d(
	center: Vector3 = Vector3.ZERO,
	fit_size: float = 30.0
) -> void:
	if _top_down_2d_enabled:
		size = clampf(fit_size, top_down_min_size, top_down_max_size)
		return

	if is_first_person():
		_first_person_target = null
		_has_saved_free_transform = false

	_saved_2d_transform = global_transform
	_saved_2d_projection = projection
	_saved_2d_size = size
	_saved_2d_fov = fov
	_has_saved_2d_state = true
	_top_down_2d_enabled = true

	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = clampf(fit_size, top_down_min_size, top_down_max_size)
	global_position = Vector3(
		center.x,
		maxf(global_position.y, maxf(10.0, fit_size)),
		center.z
	)
	global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)


func exit_top_down_2d() -> void:
	if not _top_down_2d_enabled:
		return

	_top_down_2d_enabled = false
	if _has_saved_2d_state:
		projection = _saved_2d_projection
		size = _saved_2d_size
		fov = _saved_2d_fov
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
