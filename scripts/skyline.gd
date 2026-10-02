extends MeshInstance3D

# Distant hazy Accra skyline: a big billboard that stays at a fixed distance ahead
# of the camera, so the horizon is never an empty edge of ground.

@export var distance: float = 650.0
@export var width: float = 1800.0
@export var repeats: float = 2.0 # the texture is repeated across the width
@export var base_y: float = -6.0

var camera: Camera3D

func _ready():
	var tex: Texture2D = load("res://assets/environment/skyline_accra.png")
	var q = QuadMesh.new()
	var aspect = float(tex.get_width()) / tex.get_height()
	var h = width / repeats / aspect
	q.size = Vector2(width, h)
	q.center_offset = Vector3(0, h * 0.5, 0)
	mesh = q
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.uv1_scale = Vector3(repeats, 1, 1)
	m.texture_repeat = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera = get_viewport().get_camera_3d()

func _process(_delta):
	if camera:
		global_position = Vector3(camera.global_position.x, base_y, camera.global_position.z - distance)
