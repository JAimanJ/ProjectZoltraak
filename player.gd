extends CharacterBody3D
## First-person controller: WASD move, mouse look, Space jump,
## R reloads the scene, Esc frees the mouse, click to recapture.

const SPEED := 7.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.003

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var spawn_point: Vector3

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	spawn_point = global_position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam.rotate_x(-event.relative.y * MOUSE_SENS)
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Click to recapture the mouse
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_R:
				get_tree().reload_current_scene()  # resets everything


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD relative to where you're facing
	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if dir:
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Fell off the map? Back to spawn.
	if global_position.y < -20:
		global_position = spawn_point
		velocity = Vector3.ZERO
