extends CharacterBody3D
## Boss: a big floating sphere with a magic circle beneath it.
## Every few seconds it glows, then launches a SAM-style missile barrage:
## missiles boost straight up, then curve down and home in on you (limited turn rate,
## so you can outrun the turn, break line with cover, or let the barrier eat them).
## Place it in the scene as a CharacterBody3D at around (0, 8, -30) and attach this script.

const MAX_HP := 1200
const RADIUS := 3.0
const BODY_COLOR := Color(0.16, 0.1, 0.2)
const GLOW_COLOR := Color(1.0, 0.3, 0.35)

# Flight
const FLY_SPEED := 11.0          # max speed while repositioning
const FLY_ACCEL := 1.5           # how quickly it changes direction (higher = twitchier)
const KEEP_MIN := 18.0           # preferred distance from the player
const KEEP_MAX := 32.0
const MIN_ALT := 5.0
const MAX_ALT := 28.0
const ARENA_LIMIT := 48.0        # stays within this radius of the arena center
const REPOSITION := 2.2          # seconds between picking a new spot

# Barrage tuning
const BARRAGE_INTERVAL := 3.0    # seconds between barrages
const WINDUP := 0.5              # warning glow before launching
const MISSILES := 4              # per barrage
const MISSILE_GAP := 0.12        # seconds between each launch
const MISSILE_SPEED := 22.0
const MISSILE_TURN := 1.8        # radians/sec (lower = easier to dodge)
const MISSILE_BOOST := 0.4       # seconds of vertical boost before homing
const MISSILE_DAMAGE := 10

const RESPAWN_TIME := 6.0        # test mode: comes back after dying

var hp := MAX_HP
var alive := true
var home: Vector3
var t := 0.0
var barrage_timer := 2.0
var winding := false
var player: Node3D
var goal := Vector3.ZERO
var reposition_timer := 0.0

var col: CollisionShape3D
var mesh: MeshInstance3D
var mat: StandardMaterial3D
var circle: MagicCircle
var bar_root: Control
var bar_fill: ColorRect
var status_label: Label


func _ready() -> void:
	add_to_group("enemies")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	home = global_position
	goal = home

	col = CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	col.shape = shape
	add_child(col)

	mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	mesh.mesh = sm
	mat = StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.metallic = 0.3
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = GLOW_COLOR
	mat.emission_energy_multiplier = 0.3
	mesh.material_override = mat
	add_child(mesh)

	circle = MagicCircle.new(RADIUS * 3.0, GLOW_COLOR, 1.5)
	circle.spin_speed = 0.5
	circle.rotation.x = deg_to_rad(-90)   # lie flat, facing up
	circle.position.y = -RADIUS - 0.6
	add_child(circle)

	build_hud()


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	bar_root = Control.new()
	bar_root.anchor_left = 0.5
	bar_root.anchor_right = 0.5
	bar_root.offset_left = -320
	bar_root.offset_right = 320
	bar_root.offset_top = 24
	bar_root.offset_bottom = 70
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bar_root)

	var name_label := Label.new()
	name_label.text = "THE SPHERE"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.anchor_right = 1.0
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	bar_root.add_child(name_label)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.anchor_right = 1.0
	bg.offset_top = 30
	bg.offset_bottom = 44
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(bg)

	bar_fill = ColorRect.new()
	bar_fill.color = GLOW_COLOR
	bar_fill.anchor_bottom = 1.0
	bar_fill.anchor_right = 1.0
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(bar_fill)

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 64)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 14)
	layer.add_child(status_label)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	t += delta

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	fly(delta)

	if player.get("dead"):
		return

	barrage_timer -= delta
	if barrage_timer <= WINDUP and not winding:
		winding = true
		var tw := create_tween().set_parallel()
		tw.tween_property(mat, "emission_energy_multiplier", 4.0, WINDUP)
		tw.tween_method(circle.set_intensity, 1.5, 5.0, WINDUP)
	if barrage_timer <= 0.0:
		winding = false
		barrage_timer = BARRAGE_INTERVAL
		var tw := create_tween().set_parallel()
		tw.tween_property(mat, "emission_energy_multiplier", 0.3, 0.4)
		tw.tween_method(circle.set_intensity, 5.0, 1.5, 0.4)
		launch_barrage()


## Keeps repositioning around the player in 3D: circles, changes altitude, keeps its distance.
func fly(delta: float) -> void:
	reposition_timer -= delta
	if reposition_timer <= 0.0 or global_position.distance_to(goal) < 2.0:
		reposition_timer = REPOSITION + randf_range(-0.5, 0.5)
		pick_goal()

	var to_goal := goal - global_position
	var desired := to_goal.limit_length(FLY_SPEED)
	velocity = velocity.lerp(desired, clampf(FLY_ACCEL * delta, 0.0, 1.0))
	velocity.y += sin(t * 2.0) * 0.4   # gentle bob
	move_and_slide()


func pick_goal() -> void:
	var p := player.global_position
	var ang := randf() * TAU
	var dist := randf_range(KEEP_MIN, KEEP_MAX)
	var g := Vector3(p.x + cos(ang) * dist, 0.0, p.z + sin(ang) * dist)
	# stay inside the arena
	var flat := Vector2(g.x, g.z)
	if flat.length() > ARENA_LIMIT:
		flat = flat.normalized() * ARENA_LIMIT
	g.x = flat.x
	g.z = flat.y
	g.y = clampf(p.y + randf_range(2.0, 12.0), MIN_ALT, MAX_ALT)
	goal = g


func launch_barrage() -> void:
	var spin := randf() * TAU
	for i in MISSILES:
		if not alive:
			return
		fire_missile(spin + TAU * i / MISSILES)
		await get_tree().create_timer(MISSILE_GAP).timeout


func fire_missile(angle: float) -> void:
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var origin := global_position + Vector3.UP * RADIUS * 0.9 + out * RADIUS * 0.5
	var dir := (Vector3.UP + out * 0.6).normalized()   # vertical launch, fanned out

	var m := Bolt.new()
	m.style = "missile"
	m.shooter = self
	m.speed = MISSILE_SPEED
	m.damage = MISSILE_DAMAGE
	m.core_color = Color(1.0, 0.35, 0.3)
	m.trail_color = Color(1.0, 0.55, 0.2)
	m.homing_target = player
	m.turn_rate = MISSILE_TURN
	m.boost_time = MISSILE_BOOST
	m.max_distance = 400.0
	m.lifetime = 8.0
	m.velocity = dir * MISSILE_SPEED * 0.7   # slower during boost
	get_parent().add_child(m)
	m.global_position = origin
	m.face_velocity()


## Called by your Zoltraak.
func take_damage(amount: int, hit_pos: Vector3) -> void:
	if not alive:
		return
	hp = max(hp - amount, 0)
	bar_fill.anchor_right = float(hp) / MAX_HP
	mat.albedo_color = Color.WHITE
	create_tween().tween_property(mat, "albedo_color", BODY_COLOR, 0.15)
	pop_number(amount, hit_pos)
	if hp == 0:
		die()


func pop_number(amount: int, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = str(amount)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 96
	l.outline_size = 18
	l.pixel_size = 0.005
	l.modulate = Color(1, 0.85, 0.3)
	get_parent().add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.5, 0.5), 0.5, 0)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.5, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)


func die() -> void:
	alive = false
	col.set_deferred("disabled", true)
	bar_root.visible = false
	status_label.text = "BOSS DEFEATED"
	status_label.modulate.a = 1.0

	# Big burst: huge flaring circle + shrink away
	var burst := MagicCircle.new(RADIUS * 6.0, Color.WHITE, 8.0)
	burst.spin_speed = 4.0
	get_parent().add_child(burst)
	burst.global_position = global_position
	var cam := get_viewport().get_camera_3d()
	if cam:
		burst.face(cam.global_position - global_position)
	var bt := burst.create_tween()
	bt.tween_method(burst.set_intensity, 8.0, 0.0, 1.0)
	bt.tween_callback(burst.queue_free)

	var tw := create_tween()
	tw.tween_property(mesh, "scale", Vector3.ONE * 1.3, 0.15)
	tw.tween_property(mesh, "scale", Vector3.ZERO, 0.3)
	circle.visible = false

	get_tree().create_timer(RESPAWN_TIME).timeout.connect(respawn)


func respawn() -> void:
	hp = MAX_HP
	alive = true
	winding = false
	barrage_timer = 2.0
	velocity = Vector3.ZERO
	global_position = home
	goal = home
	bar_fill.anchor_right = 1.0
	bar_root.visible = true
	status_label.text = ""
	mat.albedo_color = BODY_COLOR
	mat.emission_energy_multiplier = 0.3
	circle.set_intensity(1.5)
	circle.visible = true
	col.set_deferred("disabled", false)
	mesh.scale = Vector3.ZERO
	create_tween().tween_property(mesh, "scale", Vector3.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
