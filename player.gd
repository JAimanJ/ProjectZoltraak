extends CharacterBody3D
## Frieren-style flying mage.
##   WASD move (relative to where you look), Space = rise, Ctrl / C = descend
##   HOLD left click = charge Zoltraak (longer = more damage + more range), release to fire
##   Automatic barrier blocks incoming attacks (limited charges, recharges over time)
##   Getting hit = impact frames + hit-stop + launched backwards
##   V = first / third person    R = restart    Esc = free mouse

const MOUSE_SENS := 0.003
const MAX_HP := 100

# Flight
const FLY_SPEED := 12.0
const RISE_SPEED := 9.0
const ACCEL := 60.0               # how snappy movement feels
const MIN_HEIGHT := -20.0         # safety net

# Zoltraak
const CHARGE_TIME := 0.8
const FIRE_COOLDOWN := 0.12
const DMG_MIN := 15.0
const DMG_MAX := 70.0
const RANGE_MIN := 40.0
const RANGE_MAX := 180.0
const SPEED_MIN := 80.0
const SPEED_MAX := 130.0
const ZOLTRAAK_CORE := Color(1.0, 1.0, 1.0)
const ZOLTRAAK_SHEATH := Color(0.72, 0.78, 1.0)

# Auto-barrier
const BARRIER_MAX := 6
const BARRIER_RECHARGE := 3.0     # seconds per charge
const BARRIER_COLOR := Color(0.65, 0.9, 1.0)

# Getting hit
const KNOCKBACK := 26.0           # launch speed
const KNOCK_UP := 6.0
const STUN_TIME := 0.35           # no control while flying backwards
const STUN_DRAG := 40.0
const HIT_INVULN := 0.6           # brief mercy window after a hit

# Camera
const TP_DISTANCE := 3.5
const TP_SHOULDER := 0.6

const IMPACT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float mode = 1.0;        // 1 = inverted black/white, 2 = black/white
uniform float threshold = 0.55;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float bw = step(threshold, l);
	COLOR = vec4(vec3(mode > 1.5 ? bw : 1.0 - bw), 1.0);
}
"""

var spawn_point: Vector3
var shake := 0.0
var hp := MAX_HP
var dead := false

var charging := false
var charge := 0.0
var held := 0.0
var fire_timer := 0.0
var circle: MagicCircle

var barrier_charges := BARRIER_MAX
var barrier_timer := 0.0

var stun := 0.0
var invuln := 0.0

var third_person := false
var head: Node3D
var arm: SpringArm3D
var body_mesh: MeshInstance3D

var hp_label: Label
var barrier_label: Label
var damage_flash: ColorRect
var charge_bg: ColorRect
var charge_fill: ColorRect
var impact_rect: ColorRect
var impact_mat: ShaderMaterial

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # flying: no floor logic
	Engine.time_scale = 1.0
	spawn_point = global_position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	setup_camera_rig()
	build_body()
	build_hud()
	update_hud()

	var we := get_tree().root.find_child("WorldEnvironment", true, false)
	if we and we.environment:
		we.environment.glow_enabled = true
		we.environment.glow_intensity = 1.0
		we.environment.glow_bloom = 0.1


# ---------------------------------------------------------------- Camera / body

## Player -> Head (pitch) -> SpringArm (3rd-person distance) -> Camera
func setup_camera_rig() -> void:
	head = Node3D.new()
	head.position = Vector3(0, 0.6, 0)
	add_child(head)
	arm = SpringArm3D.new()
	arm.spring_length = 0.0
	arm.margin = 0.2
	arm.add_excluded_object(get_rid())
	head.add_child(arm)
	cam.reparent(arm, false)
	cam.transform = Transform3D.IDENTITY


func build_body() -> void:
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = CapsuleMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.92, 0.97)
	body_mesh.material_override = m
	add_child(body_mesh)
	body_mesh.visible = false


func toggle_view() -> void:
	third_person = not third_person
	body_mesh.visible = third_person
	var t := create_tween().set_parallel()
	t.tween_property(arm, "spring_length", TP_DISTANCE if third_person else 0.0, 0.25)
	t.tween_property(arm, "position:x", TP_SHOULDER if third_person else 0.0, 0.25)


func hand_pos() -> Vector3:
	return head.global_transform * Vector3(0.28, -0.18, -0.45)


func aim_point() -> Vector3:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else to


func aim_dir() -> Vector3:
	return (aim_point() - hand_pos()).normalized()


# ---------------------------------------------------------------- HUD

func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Impact frames overlay (hidden until you get hit)
	impact_rect = ColorRect.new()
	impact_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	impact_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = IMPACT_SHADER
	impact_mat = ShaderMaterial.new()
	impact_mat.shader = sh
	impact_rect.material = impact_mat
	impact_rect.visible = false
	layer.add_child(impact_rect)

	damage_flash = ColorRect.new()
	damage_flash.color = Color(1, 0, 0, 0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(damage_flash)

	hp_label = make_label(Vector2(24, 24), 32)
	layer.add_child(hp_label)
	barrier_label = make_label(Vector2(24, 64), 32)
	layer.add_child(barrier_label)

	var hint := make_label(Vector2(24, 0), 20)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -48
	hint.text = "Hold LMB: Zoltraak    WASD + Space / Ctrl: fly    V: view    R: restart"
	hint.modulate.a = 0.7
	layer.add_child(hint)

	layer.add_child(centered_rect(Vector2(-3, -3), Vector2(3, 3), Color(1, 1, 1, 0.9)))

	charge_bg = centered_rect(Vector2(-40, 16), Vector2(40, 21), Color(0, 0, 0, 0.5))
	layer.add_child(charge_bg)
	charge_fill = ColorRect.new()
	charge_fill.color = ZOLTRAAK_SHEATH
	charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_fill.anchor_bottom = 1.0
	charge_bg.add_child(charge_fill)
	charge_bg.visible = false


func make_label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	return l


func centered_rect(top_left: Vector2, bottom_right: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.5
	r.anchor_right = 0.5
	r.anchor_top = 0.5
	r.anchor_bottom = 0.5
	r.offset_left = top_left.x
	r.offset_top = top_left.y
	r.offset_right = bottom_right.x
	r.offset_bottom = bottom_right.y
	return r


func update_hud() -> void:
	hp_label.text = "HP  %d / %d" % [hp, MAX_HP]
	hp_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3).lerp(Color.WHITE, float(hp) / MAX_HP))
	barrier_label.text = "BARRIER  %d / %d" % [barrier_charges, BARRIER_MAX]
	barrier_label.add_theme_color_override("font_color",
		BARRIER_COLOR if barrier_charges > 0 else Color(1, 0.4, 0.3))


# ---------------------------------------------------------------- Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				restart()
				return
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_V:
				toggle_view()

	if dead:
		return
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event is InputEventMouseButton:
		if event.pressed and not captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_charge()
			else:
				release_charge()


# ---------------------------------------------------------------- Zoltraak

func start_charge() -> void:
	if charging or fire_timer > 0.0:
		return
	charging = true
	charge = 0.0
	held = 0.0
	circle = MagicCircle.new(0.75, ZOLTRAAK_SHEATH, 2.0)
	circle.set_reveal(0.0)
	get_parent().add_child(circle)
	update_circle()
	charge_bg.visible = true


func update_circle() -> void:
	var dir := aim_dir()
	circle.global_position = hand_pos() + dir * 0.35
	circle.face(dir)
	circle.set_reveal(minf(1.0, held / 0.15))
	circle.set_intensity(2.0 + 4.0 * charge)
	circle.spin_speed = 1.0 + 6.0 * charge
	circle.scale = Vector3.ONE * (0.8 + 0.2 * charge)
	charge_fill.anchor_right = charge
	charge_fill.color = Color.WHITE if charge >= 1.0 else ZOLTRAAK_SHEATH


func release_charge() -> void:
	if not charging:
		return
	charging = false
	charge_bg.visible = false
	fire_timer = FIRE_COOLDOWN
	fire(circle.global_position, charge)

	var c := circle
	circle = null
	c.set_reveal(1.0)
	var t := c.create_tween()
	t.tween_method(c.set_intensity, 8.0, 0.0, 0.3)
	t.tween_callback(c.queue_free)


func fire(origin: Vector3, power: float) -> void:
	var dir := (aim_point() - origin).normalized()
	var b := Bolt.new()
	b.style = "beam"
	b.shooter = self
	b.core_color = ZOLTRAAK_CORE
	b.trail_color = Color(0.5, 0.88, 1.0)
	b.outer_color = Color(0.55, 0.3, 1.0)
	b.damage = int(lerpf(DMG_MIN, DMG_MAX, power))
	b.speed = lerpf(SPEED_MIN, SPEED_MAX, power)
	b.max_distance = lerpf(RANGE_MIN, RANGE_MAX, power)
	b.hit_scale = lerpf(0.7, 1.6, power)
	b.lifetime = 4.0
	b.velocity = dir * b.speed
	get_parent().add_child(b)
	b.global_position = origin
	b.face_velocity()
	shake = max(shake, 0.03 + 0.07 * power)


## Called by your Zoltraak when it hits something.
func impact(pos: Vector3, strength: float = 1.0) -> void:
	var dist := global_position.distance_to(pos)
	shake = max(shake, clamp(1.0 - dist / 60.0, 0.15, 1.0) * 0.2 * strength)
	if strength >= 1.55:
		impact_frames()   # fully charged hit gets the anime treatment too
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.03 + 0.04 * strength, true, false, true).timeout
	Engine.time_scale = 1.0


## Two flashed frames (inverted, then black & white) during a near-freeze.
func impact_frames() -> void:
	impact_rect.visible = true
	impact_mat.set_shader_parameter("mode", 1.0)
	Engine.time_scale = 0.03
	await get_tree().create_timer(0.06, true, false, true).timeout
	impact_mat.set_shader_parameter("mode", 2.0)
	await get_tree().create_timer(0.06, true, false, true).timeout
	impact_rect.visible = false
	Engine.time_scale = 0.3 if dead else 1.0


# ---------------------------------------------------------------- Defense

## Called by enemy shots that get close. Returns true if the barrier blocked it.
func try_block(pos: Vector3, incoming_velocity: Vector3) -> bool:
	if dead or invuln > 0.0 or barrier_charges <= 0:
		return false
	barrier_charges -= 1

	var b := MagicCircle.new(1.8, BARRIER_COLOR, 4.0)
	b.spin_speed = 3.0
	get_parent().add_child(b)
	b.global_position = pos
	b.face(-incoming_velocity)
	b.scale = Vector3.ONE * 0.3
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.15)
	t.tween_method(b.set_intensity, 4.0, 0.0, 0.3)
	t.tween_callback(b.queue_free)

	shake = max(shake, 0.1)
	update_hud()
	return true


## Called by enemy shots that got through. push = direction the shot was travelling.
func take_hit(amount: int, _hit_pos: Vector3, push: Vector3) -> void:
	if dead or invuln > 0.0:
		return
	hp = max(hp - amount, 0)
	invuln = HIT_INVULN
	update_hud()

	# Launched back
	var dir := push.normalized()
	if dir == Vector3.ZERO:
		dir = global_transform.basis.z
	velocity = dir * KNOCKBACK + Vector3.UP * KNOCK_UP
	stun = STUN_TIME
	if charging:
		cancel_charge()   # getting smacked breaks your cast

	shake = max(shake, 0.35)
	damage_flash.color.a = 0.4
	create_tween().tween_property(damage_flash, "color:a", 0.0, 0.4)
	impact_frames()

	if hp == 0:
		die()


## Fallback for anything that calls the older API.
func take_damage(amount: int, hit_pos: Vector3) -> void:
	take_hit(amount, hit_pos, global_position - hit_pos)


func cancel_charge() -> void:
	charging = false
	charge_bg.visible = false
	if circle:
		circle.queue_free()
		circle = null


func die() -> void:
	dead = true
	if charging:
		cancel_charge()
	Engine.time_scale = 0.3
	get_tree().create_timer(1.5, true, false, true).timeout.connect(end_slowmo)
	if get_tree().get_nodes_in_group("game").is_empty():
		get_tree().create_timer(1.5, true, false, true).timeout.connect(restart)
	else:
		get_tree().call_group("game", "on_player_died")


func end_slowmo() -> void:
	Engine.time_scale = 1.0


func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Loop

func _process(delta: float) -> void:
	fire_timer = max(fire_timer - delta, 0.0)
	invuln = max(invuln - delta, 0.0)

	if charging:
		held += delta
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
		update_circle()
		if charge >= 1.0:
			shake = max(shake, 0.015)

	if barrier_charges < BARRIER_MAX:
		barrier_timer += delta
		if barrier_timer >= BARRIER_RECHARGE:
			barrier_timer = 0.0
			barrier_charges += 1
			update_hud()
	else:
		barrier_timer = 0.0

	# Blink while invulnerable (third person)
	body_mesh.transparency = 0.5 if invuln > 0.0 and fmod(invuln, 0.1) < 0.05 else 0.0

	cam.h_offset = randf_range(-1, 1) * shake
	cam.v_offset = randf_range(-1, 1) * shake
	shake = move_toward(shake, 0.0, delta * 1.5)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = velocity.move_toward(Vector3.ZERO, STUN_DRAG * delta)
		move_and_slide()
		return

	# Knocked back: no control, just slide to a stop
	if stun > 0.0:
		stun -= delta
		velocity = velocity.move_toward(Vector3.ZERO, STUN_DRAG * delta)
		move_and_slide()
		return

	# Flight: WASD on the horizontal plane, Space/Ctrl for altitude
	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var vertical := float(Input.is_key_pressed(KEY_SPACE)) \
		- float(Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C))

	var wish := (transform.basis * Vector3(input.x, 0, input.y)).normalized() * FLY_SPEED
	wish.y = vertical * RISE_SPEED
	velocity = velocity.move_toward(wish, ACCEL * delta)
	move_and_slide()

	if global_position.y < MIN_HEIGHT:
		global_position = spawn_point
		velocity = Vector3.ZERO
