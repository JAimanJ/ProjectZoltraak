class_name MagicCircle
extends MeshInstance3D
## Procedural magic circle (rings + rotating rune band + hexagram + inner square),
## drawn entirely by a shader on a flat quad. Used for Zoltraak casting,
## the auto-barrier, and the boss.
##
## MagicCircle.new(size_in_meters, color, brightness)

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float reveal = 1.0;   // 0..1, circle 'draws itself' around
uniform float spin = 0.0;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float ring(float r, float radius, float w) {
	return 1.0 - smoothstep(0.0, w, abs(r - radius));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(0.0, w, length(pa - ba * h));
}

float polygon(vec2 p, int n, float radius, float w, float offset) {
	float m = 0.0;
	for (int i = 0; i < n; i++) {
		float a0 = offset + TAU * float(i) / float(n);
		float a1 = offset + TAU * float(i + 1) / float(n);
		m = max(m, seg(p, radius * vec2(cos(a0), sin(a0)), radius * vec2(cos(a1), sin(a1)), w));
	}
	return m;
}

float hash(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	float ang01 = fract(atan(p.y, p.x) / TAU + 0.25);
	float shown = step(ang01, reveal);

	float m = 0.0;

	// Outer double ring
	m = max(m, ring(r, 0.96, 0.012));
	m = max(m, ring(r, 0.84, 0.010));

	// Rune band between the rings (rotates)
	vec2 pr = rot(p, spin * 0.4);
	float a = fract(atan(pr.y, pr.x) / TAU);
	float cells = 40.0;
	float cell = floor(a * cells);
	float f = fract(a * cells);
	float glyph = step(0.2, f) * step(f, 0.35 + 0.5 * hash(cell));
	glyph *= step(abs(r - 0.90), 0.012 + 0.022 * hash(cell + 7.0));
	m = max(m, glyph);

	// Hexagram (counter-rotates)
	vec2 ps = rot(p, -spin * 0.6);
	m = max(m, polygon(ps, 3, 0.80, 0.012, 1.5708));
	m = max(m, polygon(ps, 3, 0.80, 0.012, -1.5708));

	// Inner ring + square + core ring
	m = max(m, ring(r, 0.42, 0.010));
	m = max(m, polygon(rot(p, spin), 4, 0.40, 0.010, 0.0));
	m = max(m, ring(r, 0.16, 0.012));

	// Soft core glow
	m = max(m, 0.5 * (1.0 - smoothstep(0.0, 0.14, r)));

	ALBEDO = color.rgb * intensity * m * shown;
}
"""

static var _shader: Shader

var mat: ShaderMaterial
var spin := 0.0
var spin_speed := 1.0


func _init(size: float = 1.0, color: Color = Color(0.9, 0.95, 1.0), brightness: float = 3.0) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mesh = q
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	mat = ShaderMaterial.new()
	mat.shader = _shader
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.set_shader_parameter("color", color)
	set_intensity(brightness)
	set_reveal(1.0)


func _process(delta: float) -> void:
	spin += delta * spin_speed
	mat.set_shader_parameter("spin", spin)


func set_intensity(v: float) -> void:
	mat.set_shader_parameter("intensity", v)


func set_reveal(v: float) -> void:
	mat.set_shader_parameter("reveal", v)


## Point the circle's face along a direction (works even straight up/down).
func face(dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	look_at(global_position + dir, up)
