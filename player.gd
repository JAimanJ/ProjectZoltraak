extends CharacterBody3D
## First-person mage: WASD move, mouse look, Space jump,
## Left click = Zoltraak, R = reset, Esc frees the mouse.

const SPEED := 7.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.003
const FIRE_COOLDOWN := 0.15

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var spawn_point: Vector3
var fire_timer := 0.0
var shake := 0.0

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	Engine.time_scale = 1.0
	spawn_point = global_position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Turn on glow so the magic actually glows
	var we := get_tree().root.find_child("WorldEnvironment", true, false)
	if we and we.environment:
		we.environment.glow_enabled = true
		we.environment.glow_intensity = 1.0
		we.environment.glow_bloom = 0.1


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	# Mouse look
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam.rotate_x(-event.relative.y * MOUSE_SENS)
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Click: recapture mouse, or fire if already captured
	if event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			fire()

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_R:
				Engine.time_scale = 1.0
				get_tree().reload_current_scene()


func fire() -> void:
	if fire_timer > 0.0:
		return
	fire_timer = FIRE_COOLDOWN
	var forward := -cam.global_transform.basis.z
	var bolt := Bolt.new()
	bolt.shooter = self
	get_parent().add_child(bolt)
	bolt.global_transform = cam.global_transform
	bolt.global_position += forward * 0.8
	bolt.velocity = forward * Bolt.SPEED


## Called by a bolt when it hits something.
func impact(pos: Vector3) -> void:
	var dist := global_position.distance_to(pos)
	shake = max(shake, clamp(1.0 - dist / 40.0, 0.15, 1.0) * 0.25)
	# Hit-stop: near-freeze for a split second
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.06, true, false, true).timeout
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	fire_timer = max(fire_timer - delta, 0.0)
	# Screen shake (offsets don't mess with your aim)
	cam.h_offset = randf_range(-1, 1) * shake
	cam.v_offset = randf_range(-1, 1) * shake
	shake = move_toward(shake, 0.0, delta * 1.5)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

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

	if global_position.y < -20:
		global_position = spawn_point
		velocity = Vector3.ZERO
