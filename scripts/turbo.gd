extends Node3D

# Turbo (owner-designed power-up), the trotro side of it. The HUD sells it (TurboButton);
# this node runs the effect:
#   x1 (one tap): 5 s at a modest 130 km/h, no flames.
#   x2 (double tap): 5 s at 200 km/h with twin flames from under the rear.
#   - Ignores road-event speed limits (go-slow, market, bumps) and isn't "speeding".
#   - Shield (both): crashes, potholes and people don't hurt while it holds. It breaks
#     (with a shatter) on the 4th car hit; after that hits count as normal.
#   - The trotro pushes ahead of the camera and the screen edges blur (TurboBlur); both
#     stronger for x2.

const SPEEDS := [0.0, 36.1, 55.6] # m/s for x0/x1/x2 (130 / 200 km/h)
const DURATION := 5.0
const SHIELD_HITS := 4
const ACCEL := 22.0 # m/s² while the turbo kicks in

var level: int = 0
var timer: float = 0.0
var shield_hits_left: int = 0
var flames: Array = []
var bubble: MeshInstance3D
var bubble_mat: ShaderMaterial
var shards: CPUParticles3D

@onready var trotro = get_parent()

func _ready():
	for x in [-0.42, 0.42]:
		var f = make_flame()
		f.position = Vector3(x, 0.28, 0.3) # under the rear bumper, shooting back
		trotro.get_node("VisualHolder").add_child(f)
		flames.append(f)
	make_bubble()
	shards = make_shards()
	trotro.add_child(shards)

func is_active() -> bool:
	return timer > 0.0

func is_shielded() -> bool:
	return timer > 0.0 and shield_hits_left > 0

func goal_speed() -> float:
	return SPEEDS[level] if timer > 0.0 else 0.0

# Bought from the HUD: x1 (one tap) or x2 (double tap).
func start(new_level: int):
	if timer <= 0.0:
		shield_hits_left = SHIELD_HITS # a fresh shield for a fresh turbo
	level = new_level
	timer = DURATION
	Sfx.play("whoosh", 2.0, 0.8 if level == 1 else 0.6)
	var rig = trotro.get_node_or_null("../CameraRig")
	if rig:
		rig.shake(0.2 + 0.1 * level)

# A car hit while shielded: TrafficManager shoves the car aside and calls this.
func shield_hit():
	if shield_hits_left <= 0:
		return
	shield_hits_left -= 1
	Sfx.play("crash", -6.0, 1.6)
	var pulse = create_tween()
	bubble.scale = Vector3.ONE * 1.12
	pulse.tween_property(bubble, "scale", Vector3.ONE, 0.18)
	if shield_hits_left == 0:
		break_shield()

func break_shield():
	shards.restart()
	shards.emitting = true
	Sfx.play("crash", 0.0, 2.2)
	Sfx.play("pothole", -2.0, 2.6)
	var t = create_tween().set_parallel()
	t.tween_property(bubble, "scale", Vector3.ONE * 1.6, 0.25).set_trans(Tween.TRANS_QUAD)
	t.tween_method(func(a): bubble_mat.set_shader_parameter("alpha", a), 1.0, 0.0, 0.25)
	GameState.announce("SHIELD BROKEN!", "warn")
	var rig = trotro.get_node_or_null("../CameraRig")
	if rig:
		rig.shake(0.45)

func _process(delta: float):
	if timer > 0.0 and not get_tree().paused:
		timer -= delta
		if timer <= 0.0:
			level = 0
	var on = timer > 0.0 and level == 2 # flames are the full boost's alone
	for f in flames:
		f.emitting = on
		f.initial_velocity_min = 9.0 if level == 2 else 6.0
		f.initial_velocity_max = 12.0 if level == 2 else 8.0
		f.scale_amount_max = 1.6 if level == 2 else 1.1
	# The shield bubble shows while it holds; a shimmer and a fade at the very end.
	if is_shielded():
		bubble.visible = true
		var fade = clampf(timer / 0.4, 0.0, 1.0)
		bubble_mat.set_shader_parameter("alpha", fade * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02)))
	elif bubble_mat.get_shader_parameter("alpha") <= 0.01 or timer <= 0.0:
		bubble.visible = false # (a breaking shield fades itself out first)
		bubble.scale = Vector3.ONE

# ------------------------------------------------------------------ visuals

func make_flame() -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.16
	p.emitting = false
	p.local_coords = true # a jet fixed to the trotro (world-space puffs trailed behind at 150 km/h)
	p.direction = Vector3(0, -0.15, 1) # back toward the camera
	p.spread = 7.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 4.5
	p.initial_velocity_max = 6.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var shrink = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = shrink
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
	ramp.add_point(0.25, Color(1.0, 0.8, 0.2, 0.95))
	ramp.add_point(0.6, Color(1.0, 0.35, 0.05, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.1, 0.0, 0.0))
	p.color_ramp = ramp
	var q = QuadMesh.new()
	q.size = Vector2(0.32, 0.32)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	q.material = mat
	p.mesh = q
	return p

func make_bubble():
	bubble = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	bubble.mesh = s
	bubble_mat = ShaderMaterial.new()
	bubble_mat.shader = Shader.new()
	bubble_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform float alpha = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0 - TIME * 6.0);
	vec3 c = vec3(0.25, 0.7, 1.0) * (rim * 1.4 + bands * 0.06);
	ALBEDO = c * alpha;
}
"""
	bubble.material_override = bubble_mat
	bubble_mat.set_shader_parameter("alpha", 0.0)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# An egg around the trotro body (it runs from the rear bumper forward ~4.4 m): a unit
	# sphere inside a stretched holder.
	var holder = Node3D.new()
	holder.scale = Vector3(1.45, 1.35, 2.9)
	trotro.get_node("VisualHolder").add_child(holder)
	holder.add_child(bubble)
	bubble.position = Vector3(0, 0.82, -0.7)
	bubble.visible = false

func make_shards() -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.position = Vector3(0, 1.2, -1.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 1.6
	p.direction = Vector3(0, 0.6, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.7, 0.95, 1.0, 1.0))
	ramp.set_color(1, Color(0.2, 0.5, 1.0, 0.0))
	p.color_ramp = ramp
	# Triangular glass shards.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0.16, 0), Vector3(-0.08, -0.08, 0), Vector3(0.1, -0.06, 0)]:
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(v)
	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	p.mesh = mesh
	return p

static var _dot: GradientTexture2D
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot
