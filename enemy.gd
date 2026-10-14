extends CharacterBody3D
## Target dummy mage. Builds its own body, collision and HP bar in code.
## Takes damage from bolts, flashes, pops damage numbers, dies, respawns.

const MAX_HP := 100
const RESPAWN_TIME := 3.0
const BODY_COLOR := Color(0.55, 0.2, 0.25)
const BAR_WIDTH := 1.2

var hp := MAX_HP
var alive := true
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var col: CollisionShape3D
var mesh: MeshInstance3D
var body_mat: StandardMaterial3D
var bar: Node3D
var bar_fill: MeshInstance3D


func _ready() -> void:
	add_to_group("enemies")

	# Collision (capsule, 2m tall)
	col = CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	add_child(col)

	# Body
	mesh = MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	mesh.material_override = body_mat
	add_child(mesh)

	# HP bar floating above the head
	bar = Node3D.new()
	bar.position.y = 1.5
	add_child(bar)
	bar.add_child(make_box(Vector3(BAR_WIDTH + 0.06, 0.16, 0.01), Color(0.1, 0.1, 0.1)))
	bar_fill = make_box(Vector3(BAR_WIDTH, 0.1, 0.02), Color(0.3, 1.0, 0.4))
	bar.add_child(bar_fill)
	update_bar()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _process(_delta: float) -> void:
	# Keep the HP bar facing the camera
	var cam := get_viewport().get_camera_3d()
	if cam and bar.visible:
		bar.look_at(cam.global_position, Vector3.UP, true)


## Called by bolts.
func take_damage(amount: int, hit_pos: Vector3) -> void:
	if not alive:
		return
	hp = max(hp - amount, 0)
	update_bar()
	hit_flash()
	pop_number(amount, hit_pos)
	if hp == 0:
		die()


func update_bar() -> void:
	var ratio := float(hp) / MAX_HP
	bar_fill.scale.x = max(ratio, 0.001)
	bar_fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - ratio)  # shrink toward the left
	var m: StandardMaterial3D = bar_fill.material_override
	m.albedo_color = Color(1, 0.25, 0.25).lerp(Color(0.3, 1.0, 0.4), ratio)


func hit_flash() -> void:
	body_mat.albedo_color = Color.WHITE
	create_tween().tween_property(body_mat, "albedo_color", BODY_COLOR, 0.15)


func pop_number(amount: int, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = str(amount)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 72
	l.outline_size = 16
	l.pixel_size = 0.004
	l.modulate = Color(1, 0.85, 0.3)
	get_parent().add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, 0)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.6)
	t.chain().tween_callback(l.queue_free)


func die() -> void:
	alive = false
	col.set_deferred("disabled", true)
	bar.visible = false
	var t := create_tween()
	t.tween_property(mesh, "scale", Vector3(1.4, 0.05, 1.4), 0.2)  # squash
	t.tween_property(mesh, "scale", Vector3.ZERO, 0.15)               # vanish
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(respawn)


func respawn() -> void:
	hp = MAX_HP
	alive = true
	col.disabled = false
	bar.visible = true
	update_bar()
	mesh.scale = Vector3.ZERO
	create_tween().tween_property(mesh, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	return mi
