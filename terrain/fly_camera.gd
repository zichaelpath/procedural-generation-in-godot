extends Node3D

## Minimal fly rig: WASD + QE for up/down, mouse look while captured,
## Shift = 3x sprint (the sprint exists to outrun the streamer — that
## is Exercise 2, built into the controls on purpose).
## (Chapter 13, Listing 13.7.)

@export var move_speed: float = 24.0
@export var sprint_multiplier: float = 3.0
var _yaw: float = 0.0
var _pitch: float = -0.35

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * 0.0022
		_pitch = clampf(_pitch - mm.relative.y * 0.0022, -1.4, 1.4)
		rotation = Vector3(_pitch, _yaw, 0.0)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= basis.z
	if Input.is_key_pressed(KEY_S): dir += basis.z
	if Input.is_key_pressed(KEY_A): dir -= basis.x
	if Input.is_key_pressed(KEY_D): dir += basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	var speed: float = move_speed * (sprint_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if dir.length() > 0.01:
		position += dir.normalized() * speed * delta

## Direction of travel in world XZ, for queue prioritisation.
func travel_direction() -> Vector2:
	var v: Vector3 = -basis.z
	var flat := Vector2(v.x, v.z)
	return flat.normalized() if flat.length() > 0.01 else Vector2.ZERO
