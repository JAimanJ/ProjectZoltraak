class_name Bolt
extends Node3D
## Zoltraak bolt: glowing orb + streak, flies forward,
## raycasts each frame so it never tunnels through walls,
## and on hit spawns a flash + debris and tells the shooter (hit-stop + shake).

const SPEED := 60.0
const LIFETIME := 3.0
const DAMAGE := 20
const CORE_COLOR := Color(1.0, 0.9, 0.55)
const TRAIL_COLOR := Color(1.0, 0.55, 0.2)

var velocity := Vector3.ZERO
var shooter: Node3D
var age := 0.0


func _ready() -> void:
	# Glowing core
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	core.mesh = sphere
	core.material_override = glow_mat(CORE_COLOR, 8.0)
	add_child(core)

	# Tapered streak behind it (bolt flies along -Z, so +Z is behind)
	var streak := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.09
	cyl.height = 2.0
	streak.mesh = cyl
	streak.material_override = glow_mat(TRAIL_COLOR, 4.0)
	streak.rotation.x = deg_to_rad(90)
	streak.position.z = 1.0
	add_child(streak)

	# Light so it lights up the walls as it flies
	var light := OmniLight3D.new()
	light.light_color = CORE_COLOR
	light.light_energy = 3.0
	light.omni_range = 5.0
	add_child(light)


func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFETIME:
		queue_free()
		return

	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		# Damage whatever we hit, if it can take damage
		var target = hit.collider
		if target and target.has_method("take_damage"):
			target.take_damage(DAMAGE, hit.position)
		explode(hit.position, hit.normal)
		queue_free()
	else:
		global_position = to


func explode(pos: Vector3, normal: Vector3) -> void:
	var world := get_parent()

	# White flash that expands and fades
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	flash.mesh = s
	var fm := glow_mat(Color.WHITE, 12.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = fm
	world.add_child(flash)
	flash.global_position = pos
	var t := flash.create_tween().set_parallel()
	t.tween_property(flash, "scale", Vector3.ONE * 4.0, 0.25)
	t.tween_property(fm, "albedo_color:a", 0.0, 0.25)
	t.chain().tween_callback(flash.queue_free)

	# Light burst
	var burst := OmniLight3D.new()
	burst.light_color = CORE_COLOR
	burst.light_energy = 12.0
	burst.omni_range = 12.0
	world.add_child(burst)
	burst.global_position = pos + normal * 0.5
	var lt := burst.create_tween()
	lt.tween_property(burst, "light_energy", 0.0, 0.3)
	lt.tween_callback(burst.queue_free)

	# Debris chunks
	var debris_mat := StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.3, 0.3, 0.33)
	for i in 12:
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
		rb.linear_velocity = (normal + rand_vec() * 0.8).normalized() * randf_range(4.0, 10.0)
		rb.angular_velocity = rand_vec() * 10.0
		get_tree().create_timer(3.0).timeout.connect(rb.queue_free)

	# Hit-stop + screen shake live on the player (it outlives the bolt)
	if shooter and shooter.has_method("impact"):
		shooter.impact(pos)


static func rand_vec() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))


static func glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
