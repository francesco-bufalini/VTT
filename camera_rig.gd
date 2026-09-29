extends Node3D

@export var move_speed: float = 12.0
@export var vertical_speed: float = 8.0
@export var mouse_sensitivity: float = 0.0035
@export var zoom_step: float = 1.5
@export var min_distance: float = 4.0
@export var max_distance: float = 45.0
@export var min_pitch_degrees: float = -80.0
@export var max_pitch_degrees: float = 80.0

var yaw: float = 0.0
var pitch: float = deg_to_rad(-35.0)
var distance: float = 18.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_update_camera()


func _process(delta: float) -> void:
	var planar_input := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		planar_input.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		planar_input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		planar_input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		planar_input.x += 1.0

	var movement := Vector3.ZERO

	if planar_input != Vector3.ZERO:
		var yaw_basis := Basis(Vector3.UP, yaw)
		var planar_move := yaw_basis * planar_input.normalized()
		planar_move.y = 0.0
		movement += planar_move.normalized() * move_speed

	# Spazio sale, Shift scende.
	if Input.is_key_pressed(KEY_SPACE):
		movement.y += vertical_speed
	if Input.is_key_pressed(KEY_SHIFT):
		movement.y -= vertical_speed

	if movement != Vector3.ZERO:
		global_position += movement * delta
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Quando il mouse e' catturato, ogni suo movimento orienta subito la camera.
	# Se un menu runtime libera il cursore, la visuale rimane ferma finche' il
	# cursore non viene catturato di nuovo.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clamp(
			pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		_update_camera()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - zoom_step)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + zoom_step)
			_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(camera):
		return

	# Camera orbitale attorno alla posizione del rig. La direzione del mouse
	# cambia continuamente yaw/pitch; WASD, Shift e Spazio spostano il rig.
	var horizontal := cos(pitch) * distance
	camera.position = Vector3(
		sin(yaw) * horizontal,
		-sin(pitch) * distance,
		cos(yaw) * horizontal
	)
	camera.look_at(global_position, Vector3.UP)
