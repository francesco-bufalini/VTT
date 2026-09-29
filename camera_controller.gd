extends Camera3D

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.002

var _first_person_target: CharacterBody3D = null
var _saved_free_transform: Transform3D = Transform3D.IDENTITY
var _has_saved_free_transform: bool = false
var _last_target_yaw: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(
			Vector3.RIGHT,
			-event.relative.y * mouse_sensitivity
		)


func _process(delta: float) -> void:
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


func enter_first_person(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return

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
