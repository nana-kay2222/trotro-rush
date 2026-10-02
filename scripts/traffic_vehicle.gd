extends Node3D

# One pooled traffic car. TrafficManager drives it; this script only holds its
# state and picks which of the 3 approved sprite views to show.

# Each picture is drawn for one viewing angle, and is shown at its own proportions (never
# stretched) on a card that faces the camera. The angle between the camera and the car
# picks the picture:
#   under 5 deg  -> rear (the car is straight ahead, e.g. in your lane)
#   over 5 deg   -> *_rear_slight (mostly the rear plus a sliver of the side)
# Owner direction: cars keep the near-rear look all the way past; the wider 3/4, side and
# high-angle pictures (still in assets/vehicles) all looked wrong close to the camera.
# The card faces the camera; the near-rear card stands a little along the car
# (CARD_DEPTH, share of its length) instead of on the rear bumper.
# Art naming: "right_*" shows the car's RIGHT side, which is what you see when the car is
# to the camera's LEFT (and vice versa).
const VIEW_ANGLES := [["rear", 0.0], ["rear_slight", 5.0]]
const HYSTERESIS_DEG := 1.5
const CARD_DEPTH := {"rear": 0.0, "rear_slight": 0.12, "rear_3q": 0.3, "side": 0.45}

var kind: String = ""
var lane: int = 0
var speed: float = 0.0
var cruise_speed: float = 0.0
var half_length: float = 2.2
var height: float = 1.4
var active: bool = false
var escaping: bool = false # speeding away (breaking a three-lane wall, or after being rear-ended)
var has_hit_player: bool = false
var half_width: float = 0.85
var scripted: bool = false # moved by another system (rival trotro), not the traffic AI
var stalled: bool = false # broken down in its lane (GAMEPLAY_SPEC §17), hazards blinking
var hazard_lights: Array = []
var bump_cooldown: float = 0.0 # rival: seconds until it can be bumped again
var stun: float = 0.0 # rival: seconds of wobble/slowdown after being bumped
var jam: bool = false # temporary go-slow car (removed from the pool once passed)
var last_rel: float = -1.0 # z relative to the player last frame (near-miss detection)
var textures: Dictionary = {}
var view: String = ""

@onready var sprite: Sprite3D = $Sprite
@onready var shadow: MeshInstance3D = $Shadow

func activate(p_kind: String, p_textures: Dictionary, p_height: float, p_half_length: float, p_lane: int, p_x: float, p_z: float, p_speed: float):
	kind = p_kind
	textures = p_textures
	height = p_height
	half_length = p_half_length
	lane = p_lane
	cruise_speed = p_speed
	speed = p_speed
	escaping = false
	has_hit_player = false
	scripted = false
	jam = false
	stun = 0.0
	last_rel = -1.0
	set_stalled(false)
	position = Vector3(p_x, 0.0, p_z)
	view = ""
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED # update_view() aims it each frame
	sprite.transform = Transform3D.IDENTITY
	set_view("rear")
	# The shadow quad is laid flat (rotated -90° on X), so its local Y runs along the road.
	# The car body runs from the rear bumper (z = 0) forward; centre the shadow under it.
	shadow.scale = Vector3(1.75, half_length * 1.9, 1.0)
	shadow.position = Vector3(0.0, 0.03, -half_length)
	active = true
	visible = true

# Broken down: stopped in its lane with amber hazard lights blinking at the rear corners.
func set_stalled(on: bool):
	stalled = on
	if on and hazard_lights.is_empty():
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.6, 0.05)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		for i in 2:
			var q = MeshInstance3D.new()
			var m = QuadMesh.new()
			m.size = Vector2(0.28, 0.28)
			q.mesh = m
			q.material_override = mat
			add_child(q)
			hazard_lights.append(q)
	for q in hazard_lights:
		q.visible = false
	if on:
		# Rear corners of the current sprite.
		hazard_lights[0].position = Vector3(-half_width * 0.85, height * 0.42, 0.1)
		hazard_lights[1].position = Vector3(half_width * 0.85, height * 0.42, 0.1)

func _process(delta):
	if bump_cooldown > 0.0:
		bump_cooldown -= delta
		if bump_cooldown <= 0.0 and scripted:
			has_hit_player = false # the rival can be bumped again
	if stalled and active:
		var on = int(Time.get_ticks_msec() / 400) % 2 == 0
		for q in hazard_lights:
			q.visible = on

func deactivate():
	active = false
	visible = false

func set_view(v: String):
	if v == view or not textures.has(v):
		return
	view = v
	var tex: Texture2D = textures[v]
	sprite.texture = tex
	sprite.pixel_size = height / tex.get_height()
	# Sprites are trimmed so the wheels touch the image's bottom edge; anchor there.
	sprite.offset = Vector2(0.0, tex.get_height() * 0.5)

func update_view(camera_pos: Vector3):
	var dx = global_position.x - camera_pos.x
	var ahead = maxf(camera_pos.z - global_position.z, 0.1) # camera looks toward -Z
	var angle = rad_to_deg(atan2(absf(dx), ahead))
	# A car to the right of the camera shows its LEFT side (see the note at the top).
	var side = "right" if dx < 0.0 else "left"
	var current = view.trim_prefix("left_").trim_prefix("right_")
	var cur_idx = -1
	for i in VIEW_ANGLES.size():
		if VIEW_ANGLES[i][0] == current:
			cur_idx = i
	var pick = "rear"
	for i in VIEW_ANGLES.size():
		var name: String = VIEW_ANGLES[i][0]
		# Lean toward the current picture near a boundary so it doesn't flicker.
		var from: float = VIEW_ANGLES[i][1] + (-HYSTERESIS_DEG if i <= cur_idx else HYSTERESIS_DEG)
		var full = name if name == "rear" else side + "_" + name
		if angle >= from and textures.has(full):
			pick = name
	set_view(pick if pick == "rear" else side + "_" + pick)
	# The card stands up facing the camera, a little along the car for angled pictures.
	var to_cam = camera_pos - global_position
	to_cam.y = 0.0
	var z_axis = to_cam.normalized() if to_cam.length() > 0.01 else Vector3.BACK
	var x_axis = Vector3.UP.cross(z_axis)
	var depth: float = CARD_DEPTH[view.trim_prefix("left_").trim_prefix("right_")]
	sprite.transform = Transform3D(Basis(x_axis, Vector3.UP, z_axis), Vector3(0.0, 0.0, -half_length * 2.0 * depth))
