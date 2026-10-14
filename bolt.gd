class_name Bolt
extends Node3D
## Projectile used by everyone. Raycasts each frame so it never tunnels through walls.
##   style "beam"    = Zoltraak (player): long continuous beam from the cast point to the head,
##                     white core / cyan glow / purple edge, lingers and thins out after impact
##   style "orb"     = basic enemy bolt
##   style "missile" = boss SAM: launches up, then homes in, leaves a smoke trail

const BLOCK_RANGE := 2.6    # how close an enemy shot gets before the auto-barrier triggers
const BEAM_MAX_LEN := 40.0  # how long the Zoltraak beam can stretch behind its head
const BEAM_FADE := 0.35     # seconds for the beam to thin out after it ends

var style := "orb"
var speed := 60.0
var damage := 20
var core_color := Color(1.0, 0.9, 0.55)
var trail_color := Color(1.0, 0.55, 0.2)
var outer_color := Color(0.55, 0.3, 1.0)   # beam only: purple edge
var collision_mask := 0xFFFFFFFF
var max_distance := 200.0
var lifetime := 4.0
var hit_scale := 1.0
var blockable := false

# Homing (missiles)
var homing_target: Node3D
var turn_rate := 0.0
var boost_time := 0.0

var velocity := Vector3.ZERO
var shooter: Node3D
var age := 0.0
var traveled := 0.0
var puff_timer := 0.0

# Beam state
var beam_vis: Node3D
var beam_parts: Array[MeshInstance3D] = []
var beam_light: OmniLight3D
var origin_pos := Vector3.ZERO
var origin_set := false
var finished := false


func _ready() -> void:
	if is_instance_valid(shooter) and shooter.is_in_group("enemies"):
		blockable = true

	match style:
		"beam":
			build_beam()
		"missile":
			build_missile()
		_:
			build_orb()


# ---------------------------------------------------------------- Visuals

func build_beam() -> void:
	beam_vis = Node3D.new()
	add_child(beam_vis)
	# Three nested layers, like the anime: white-hot core, cyan glow, purple fringe
	beam_parts.append(beam_layer(0.07, glow_mat(core_color, 12.0)))
	beam_parts.append(beam_layer(0.17, add_mat(trail_color, 4.0)))
	beam_parts.append(beam_layer(0.32, add_mat(outer_color, 2.5)))
	var tip := make_sphere(0.14, glow_mat(core_color, 14.0))
	beam_vis.add_child(tip)
	beam_light = make_light(trail_color, 5.0, 8.0)
	add_child(beam_light)
	set_beam_length(0.01)


func beam_layer(radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 1.0
	c.radial_segments = 16
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.rotation.x = deg_to_rad(90)   # lie along Z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_vis.add_child(mi)
	return mi


## Stretch the beam so it reaches back toward where it was cast.
func set_beam_length(length: float) -> void:
	for mi in beam_parts:
		mi.scale.y = maxf(length, 0.01)
		mi.position.z = length * 0.5   # +Z is behind the head


func build_orb() -> void:
	add_child(make_sphere(0.15, glow_mat(core_color, 8.0)))
	add_child(make_cyl(0.0, 0.09, 2.0, glow_mat(trail_color, 4.0), 1.0))
	add_child(make_light(core_color, 3.0, 5.0))


func build_missile() -> void:
	add_child(make_sphere(0.18, glow_mat(core_color, 8.0)))
	add_child(make_cyl(0.0, 0.1, 0.9, glow_mat(trail_color, 5.0), 0.45))
	add_child(make_light(core_color, 2.0, 4.0))


# ---------------------------------------------------------------- Flight

func _physics_process(delta: float) -> void:
	if finished:
		return
	if not origin_set:
		origin_pos = global_position
		origin_set = true

	age += delta
	if age > lifetime or traveled > max_distance:
		fizzle()
		return

	steer(delta)

	# Player's automatic barrier
	if blockable:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p and p.has_method("try_block") \
				and global_position.distance_to(p.global_position) < BLOCK_RANGE \
				and p.try_block(global_position, velocity):
			explode(global_position, -velocity.normalized(), false)
			finish()
			return

	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit and hit.collider and hit.collider.get("dashing"):
		hit = {}  # target is mid-dash: shot passes straight through

	if hit:
		var target = hit.collider
		if target and not same_team(target):
			if target.has_method("take_hit"):      # player: also gets knocked back
				target.take_hit(damage, hit.position, velocity.normalized())
			elif target.has_method("take_damage"):
				target.take_damage(damage, hit.position)
		global_position = hit.position
		update_beam()
		explode(hit.position, hit.normal, true)
		finish()
		return

	global_position = to
	traveled += from.distance_to(to)
	face_velocity()
	update_beam()

	if style == "missile":
		puff_timer -= delta
		if puff_timer <= 0.0:
			puff_timer = 0.03
			spawn_puff()


func update_beam() -> void:
	if style == "beam":
		set_beam_length(minf(global_position.distance_to(origin_pos), BEAM_MAX_LEN))


## SAM guidance: fly straight during boost, then turn toward the target at a limited rate.
func steer(delta: float) -> void:
	if turn_rate <= 0.0 or age < boost_time:
		return
	if not is_instance_valid(homing_target) or homing_target.get("dead"):
		return
	var aim := homing_target.global_position + Vector3(0, 0.5, 0)
	var desired := (aim - global_position).normalized()
	var cur := velocity.normalized()
	var ang := cur.angle_to(desired)
	# Forgiving: once it has flown past you (target behind it), it loses lock for good
	if age > boost_time + 0.3 and ang > deg_to_rad(100.0):
		homing_target = null
		return
	if ang > 0.0001:
		cur = cur.slerp(desired, minf(1.0, turn_rate * delta / ang))
	velocity = cur * speed


func face_velocity() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var d := velocity.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD
	look_at(global_position + d, up)


func same_team(target: Object) -> bool:
	return is_instance_valid(shooter) \
		and shooter.is_in_group("enemies") and target.is_in_group("enemies")


## End of the line. Beams linger and thin out; everything else just disappears.
func finish() -> void:
	if style != "beam":
		queue_free()
		return
	finished = true
	var t := create_tween().set_parallel()
	t.tween_property(beam_vis, "scale", Vector3(0.001, 0.001, 1.0), BEAM_FADE).set_ease(Tween.EASE_IN)
	t.tween_property(beam_light, "light_energy", 0.0, BEAM_FADE)
	t.chain().tween_callback(queue_free)


# ---------------------------------------------------------------- Effects

func explode(pos: Vector3, normal: Vector3, with_debris: bool) -> void:
	var world := get_parent()
	var s := hit_scale

	var flash := make_sphere(0.5, glow_mat(Color.WHITE, 12.0))
	var fm: StandardMaterial3D = flash.material_override
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	world.add_child(flash)
	flash.global_position = pos
	var t := flash.create_tween().set_parallel()
	t.tween_property(flash, "scale", Vector3.ONE * 4.0 * s, 0.25)
	t.tween_property(fm, "albedo_color:a", 0.0, 0.25)
	t.chain().tween_callback(flash.queue_free)

	var burst := make_light(trail_color if style == "beam" else core_color, 12.0 * s, 12.0 * s)
	world.add_child(burst)
	burst.global_position = pos + normal * 0.5
	var lt := burst.create_tween()
	lt.tween_property(burst, "light_energy", 0.0, 0.3)
	lt.tween_callback(burst.queue_free)

	if with_debris:
		var debris_mat := StandardMaterial3D.new()
		debris_mat.albedo_color = Color(0.45, 0.43, 0.4)
		for i in int(10 * s):
			var size := randf_range(0.15, 0.4)
			var rb := RigidBody3D.new()
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3.ONE * size
			col.shape = box
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = box.size
			mi.mesh = bm
			mi.material_override = debris_mat
			rb.add_child(col)
			rb.add_child(mi)
			world.add_child(rb)
			rb.global_position = pos + normal * 0.3 + rand_vec() * 0.3
			rb.linear_velocity = (normal + rand_vec() * 0.8).normalized() * randf_range(4.0, 10.0) * s
			rb.angular_velocity = rand_vec() * 10.0
			get_tree().create_timer(3.0).timeout.connect(rb.queue_free)

		if is_instance_valid(shooter) and shooter.has_method("impact"):
			shooter.impact(pos, s)


## Ran out of range.
func fizzle() -> void:
	if style == "beam":
		finish()
		return
	var puff := make_sphere(0.2, glow_mat(core_color, 4.0))
	var pm: StandardMaterial3D = puff.material_override
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	get_parent().add_child(puff)
	puff.global_position = global_position
	var t := puff.create_tween().set_parallel()
	t.tween_property(puff, "scale", Vector3.ONE * 3.0, 0.3)
	t.tween_property(pm, "albedo_color:a", 0.0, 0.3)
	t.chain().tween_callback(puff.queue_free)
	queue_free()


func spawn_puff() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.8, 0.8, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puff := make_sphere(0.12, m)
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(puff)
	puff.global_position = global_position
	var t := puff.create_tween().set_parallel()
	t.tween_property(puff, "scale", Vector3.ONE * 3.0, 0.9)
	t.tween_property(m, "albedo_color:a", 0.0, 0.9)
	t.chain().tween_callback(puff.queue_free)


# ---------------------------------------------------------------- Helpers

func make_cyl(top: float, bottom: float, h: float, m: Material, back_offset: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	mi.mesh = c
	mi.material_override = m
	mi.rotation.x = deg_to_rad(90)
	mi.position.z = back_offset
	return mi


static func make_sphere(radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	mi.material_override = m
	return mi


static func make_light(c: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = light_range
	return l


static func rand_vec() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))


static func glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Additive glow layer: adds light on top of whatever's behind it (looks like energy).
static func add_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m
