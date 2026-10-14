extends Node3D
## Builds a Frieren-style ruins arena entirely in code:
##   grassy field, stone plaza with a giant faintly-glowing carved magic circle,
##   a ring of ruined pillars (some broken, some fallen), stone arches,
##   low broken walls for cover, scattered rocks, trees, distant snowy mountains,
##   plus a nicer sky, fog and late-afternoon sun.
## Attach to an empty Node3D named "Arena". Delete the old CSG floor/boxes first.

const PLAZA_RADIUS := 22.0
const RING_RADIUS := 34.0
const LAYOUT_SEED := 7   # change for a different random layout

var rng := RandomNumberGenerator.new()

var grass: StandardMaterial3D
var stone: StandardMaterial3D
var stone_dark: StandardMaterial3D
var plaza_stone: StandardMaterial3D
var bark: StandardMaterial3D
var mountain: StandardMaterial3D
var snow: StandardMaterial3D


func _ready() -> void:
	rng.seed = LAYOUT_SEED
	make_materials()
	setup_environment()
	build_ground()
	build_plaza()
	build_pillar_ring()
	build_arches()
	build_cover_walls()
	build_rocks()
	build_trees()
	build_mountains()


# ---------------------------------------------------------------- Look

func make_materials() -> void:
	grass = mat(Color(0.38, 0.52, 0.3), 1.0)
	stone = mat(Color(0.74, 0.72, 0.67), 0.9)
	stone_dark = mat(Color(0.56, 0.55, 0.52), 0.95)
	plaza_stone = mat(Color(0.66, 0.65, 0.62), 0.85)
	bark = mat(Color(0.35, 0.26, 0.2), 1.0)
	mountain = mat(Color(0.46, 0.52, 0.62), 1.0)
	snow = mat(Color(0.93, 0.95, 1.0), 0.8)


func mat(c: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	return m


func setup_environment() -> void:
	var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		add_child(we)
	if we.environment == null:
		we.environment = Environment.new()
	var env := we.environment

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.8, 0.85, 0.92)
	sky_mat.ground_horizon_color = Color(0.8, 0.85, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.84, 0.93)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.6
	env.ssao_enabled = true

	var sun := get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		add_child(sun)
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0


# ---------------------------------------------------------------- Builders

func build_ground() -> void:
	solid_box(Vector3(500, 1, 500), Vector3(0, -0.5, 0), grass)


func build_plaza() -> void:
	# Flat stone disc (visual only, sits just above the grass)
	var disc := CylinderMesh.new()
	disc.top_radius = PLAZA_RADIUS
	disc.bottom_radius = PLAZA_RADIUS
	disc.height = 0.1
	disc.radial_segments = 64
	deco(disc, plaza_stone, Vector3(0, 0.0, 0))

	# Raised rim
	var rim := TorusMesh.new()
	rim.inner_radius = PLAZA_RADIUS - 0.4
	rim.outer_radius = PLAZA_RADIUS + 0.4
	rim.rings = 64
	var r := deco(rim, stone, Vector3(0, 0.05, 0))
	r.scale = Vector3(1, 0.4, 1)

	# Giant carved magic circle glowing faintly in the floor
	var carved := MagicCircle.new(PLAZA_RADIUS * 1.75, Color(0.7, 0.85, 1.0), 0.35)
	carved.spin_speed = 0.04
	carved.rotation.x = deg_to_rad(-90)
	carved.position.y = 0.07
	add_child(carved)


func build_pillar_ring() -> void:
	var count := 16
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.05, 0.05)
		var pos := Vector3(cos(a), 0, sin(a)) * (RING_RADIUS + rng.randf_range(-1.0, 1.0))
		var roll := rng.randf()
		if roll < 0.15:
			continue                      # gap where a pillar used to be
		elif roll < 0.4:
			intact_pillar(pos)
		elif roll < 0.55:
			fallen_pillar(pos)
		else:
			broken_pillar(pos, rng.randf_range(2.0, 7.0))


func intact_pillar(pos: Vector3) -> void:
	var h := 9.0
	solid_box(Vector3(2.6, 0.8, 2.6), pos + Vector3(0, 0.4, 0), stone_dark)          # base
	solid_cyl(0.9, h, pos + Vector3(0, 0.8 + h / 2.0, 0), stone)                      # shaft
	solid_box(Vector3(2.6, 0.6, 2.6), pos + Vector3(0, 0.8 + h + 0.3, 0), stone_dark) # capital


func broken_pillar(pos: Vector3, h: float) -> void:
	solid_box(Vector3(2.6, 0.8, 2.6), pos + Vector3(0, 0.4, 0), stone_dark)
	var shaft := solid_cyl(0.9, h, pos + Vector3(0, 0.8 + h / 2.0, 0), stone)
	shaft.rotation = Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	# A chunk that broke off, lying nearby
	var chunk_pos := pos + Vector3(rng.randf_range(-3, 3), 0.6, rng.randf_range(-3, 3))
	var chunk := solid_cyl(0.9, rng.randf_range(1.0, 2.5), chunk_pos, stone)
	chunk.rotation = Vector3(0, rng.randf() * TAU, deg_to_rad(90))


func fallen_pillar(pos: Vector3) -> void:
	solid_box(Vector3(2.6, 0.8, 2.6), pos + Vector3(0, 0.4, 0), stone_dark)
	var length := rng.randf_range(6.0, 9.0)
	var yaw := rng.randf() * TAU
	var dir := Vector3(cos(yaw), 0, -sin(yaw))
	var body := solid_cyl(0.9, length, pos + dir * (length / 2.0 + 1.5) + Vector3(0, 0.9, 0), stone)
	body.rotation = Vector3(0, yaw, deg_to_rad(90))


func build_arches() -> void:
	for deg in [30.0, 150.0, 270.0]:
		var a := deg_to_rad(deg)
		var center := Vector3(cos(a), 0, sin(a)) * (RING_RADIUS + 5.0)
		var tangent := Vector3(-sin(a), 0, cos(a))
		var broken: bool = deg == 270.0
		arch_leg(center + tangent * 2.8, 7.0)
		arch_leg(center - tangent * 2.8, 3.5 if broken else 7.0)
		var lintel_size := Vector3(7.6, 1.2, 1.8)
		if broken:
			# Lintel fell and lies tilted on the ground
			var l := solid_box(lintel_size, center + Vector3(0, 0.7, 2.0), stone_dark)
			l.rotation = Vector3(0, yaw_for(tangent) + 0.3, 0.15)
		else:
			var l := solid_box(lintel_size, center + Vector3(0, 7.0 + 0.8 + 0.6, 0), stone_dark)
			l.rotation.y = yaw_for(tangent)


func arch_leg(pos: Vector3, h: float) -> void:
	solid_box(Vector3(2.0, 0.8, 2.0), pos + Vector3(0, 0.4, 0), stone_dark)
	solid_cyl(0.75, h, pos + Vector3(0, 0.8 + h / 2.0, 0), stone)


func build_cover_walls() -> void:
	var count := 5
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.2, 0.2) + 0.3
		var pos := Vector3(cos(a), 0, sin(a)) * rng.randf_range(11.0, 15.0)
		var tangent := Vector3(-sin(a), 0, cos(a))
		var w := rng.randf_range(4.0, 7.0)
		var h := rng.randf_range(1.8, 2.8)
		var wall := solid_box(Vector3(w, h, 1.0), pos + Vector3(0, h / 2.0, 0), stone_dark)
		wall.rotation.y = yaw_for(tangent)
		# Jagged broken top
		var top_w := w * rng.randf_range(0.3, 0.6)
		var top := solid_box(Vector3(top_w, 0.8, 1.0), Vector3.ZERO, stone_dark)
		top.rotation.y = wall.rotation.y
		top.position = pos + Vector3(0, h + 0.4, 0) + tangent * rng.randf_range(-w / 4.0, w / 4.0)


func build_rocks() -> void:
	for i in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(8.0, 70.0)
		var s := rng.randf_range(0.5, 1.8)
		var size := Vector3(s * rng.randf_range(0.8, 1.5), s, s * rng.randf_range(0.8, 1.5))
		var rock := solid_box(size, Vector3(cos(a) * d, s * 0.3, sin(a) * d), stone_dark)
		rock.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))


func build_trees() -> void:
	for i in 45:
		var a := rng.randf() * TAU
		var d := rng.randf_range(46.0, 100.0)
		var pos := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := rng.randf_range(3.5, 6.0)
		solid_cyl(0.35, h, pos + Vector3(0, h / 2.0, 0), bark)

		var leaf := mat(Color(0.24, 0.42, 0.22).lerp(Color(0.38, 0.55, 0.28), rng.randf()), 1.0)
		var crown := SphereMesh.new()
		crown.radius = rng.randf_range(2.0, 3.0)
		crown.height = crown.radius * 2.0
		var c := deco(crown, leaf, pos + Vector3(0, h + crown.radius * 0.6, 0))
		c.scale = Vector3(1, rng.randf_range(1.0, 1.4), 1)
		var crown2 := SphereMesh.new()
		crown2.radius = crown.radius * 0.7
		crown2.height = crown2.radius * 2.0
		deco(crown2, leaf, pos + Vector3(rng.randf_range(-1, 1), h + crown.radius * 1.3, rng.randf_range(-1, 1)))


func build_mountains() -> void:
	for i in 16:
		var a := TAU * i / 16 + rng.randf_range(-0.15, 0.15)
		var d := rng.randf_range(170.0, 230.0)
		var r := rng.randf_range(40.0, 70.0)
		var h := rng.randf_range(50.0, 110.0)
		var base := Vector3(cos(a) * d, 0, sin(a) * d)

		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r
		cone.height = h
		cone.radial_segments = 10
		var m := deco(cone, mountain, base + Vector3(0, h / 2.0 - 5.0, 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var hs := h * 0.3
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0
		cap.bottom_radius = r * 0.3
		cap.height = hs
		cap.radial_segments = 10
		var s := deco(cap, snow, base + Vector3(0, (h - 5.0) - hs / 2.0 + 0.2, 0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- Helpers

## Box with collision (you can stand on it / hide behind it).
func solid_box(size: Vector3, pos: Vector3, m: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	body.add_child(col)
	body.add_child(mi)
	add_child(body)
	body.position = pos
	return body


## Cylinder with collision.
func solid_cyl(radius: float, height: float, pos: Vector3, m: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = m
	body.add_child(col)
	body.add_child(mi)
	add_child(body)
	body.position = pos
	return body


## Visual only, no collision.
func deco(mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	add_child(mi)
	mi.position = pos
	return mi


## Yaw that points a box's long (X) axis along a direction.
func yaw_for(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)
