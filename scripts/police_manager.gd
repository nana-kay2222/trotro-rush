extends Node3D

# Recklessness and police (GAMEPLAY_SPEC §5, §15, §20).
# The meter rises with sustained speeding (here), near misses and crashes (TrafficManager)
# and drains when driving calmly. When full, an MTTD police motorbike rides up, pulls the
# trotro over for a few seconds, issues a fine, then leaves. No chase, no escape.

# The bike always shows its rear (like the okadas): a slim bike reads fine that way.
const TEX := {
	"rear": preload("res://assets/vehicles/police_bike/police_bike_rear.png"),
}
const VEHICLE_SCENE := preload("res://scenes/traffic_vehicle.tscn")

@export var speeding_grace: float = 1.5 # seconds of speeding before the meter starts filling
@export var speeding_rate: float = 5.0 # meter per second while speeding
@export var calm_delay: float = 10.0 # seconds without reckless driving before it drains
@export var drain_rate: float = 1.0 # slow cool-down: recklessness lingers
@export var fine_amount: int = 10
@export var pullover_seconds: float = 3.2

var current_fine: int = 10
var from_meter: bool = true
var speeding_time: float = 0.0
var calm_time: float = 0.0
var last_value: float = 0.0
var state: String = "idle" # idle -> approach -> stopped -> leave
var timer: float = 0.0
var bike: Node3D
# Beacons are faked with glowing additive cards (a flare on the bike plus a pool of
# colour on the road) instead of real lights: on the web every real light makes the GPU
# compile extra versions of every material it touches, which cost a long first load.
var light_red: Node3D
var light_blue: Node3D

@onready var player = get_node("../PlayerTrotro")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")

func _ready():
	bike = VEHICLE_SCENE.instantiate()
	add_child(bike)
	bike.deactivate()
	light_red = make_light(Color(1.0, 0.15, 0.1), -0.18)
	light_blue = make_light(Color(0.15, 0.35, 1.0), 0.18)
	GameState.recklessness_changed.connect(_on_recklessness_changed)
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.rebased.connect(func(shift): bike.position.z += shift)

# Any rise (near miss, crash, speeding) restarts the calm countdown before draining.
func _on_recklessness_changed(v: float):
	if v > last_value:
		calm_time = 0.0
	last_value = v

static var glow_tex: GradientTexture2D

func make_light(c: Color, x: float) -> Node3D:
	if glow_tex == null:
		var g = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		glow_tex = GradientTexture2D.new()
		glow_tex.gradient = g
		glow_tex.fill = GradientTexture2D.FILL_RADIAL
		glow_tex.fill_from = Vector2(0.5, 0.5)
		glow_tex.fill_to = Vector2(1.0, 0.5)
		glow_tex.width = 64
		glow_tex.height = 64
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = glow_tex
	mat.albedo_color = c
	var root = Node3D.new()
	root.visible = false
	bike.add_child(root)
	# The beacon flare itself, always facing the camera.
	var flare = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	flare.mesh = q
	var flare_mat = mat.duplicate()
	flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flare_mat.no_depth_test = true
	flare.material_override = flare_mat
	flare.position = Vector3(x, 1.75, 0.1)
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flare)
	# Its colour splashed on the road around the bike.
	var pool = MeshInstance3D.new()
	var p = PlaneMesh.new()
	p.size = Vector2(7.0, 7.0)
	pool.mesh = p
	var pool_mat = mat.duplicate()
	pool_mat.albedo_color = Color(c.r, c.g, c.b, 0.55)
	pool.material_override = pool_mat
	pool.position = Vector3(x * 4.0, 0.05, -0.8)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	return root

# World.warm_up_shaders(): show the bike and both beacons as a speck for a few frames.
func warm_up(on: bool):
	if on:
		bike.activate("police_bike", TEX, 1.8, 1.2, 0, player.position.x, player.position.z - 12.0, 0.0)
		bike.scale = Vector3.ONE * 0.01
		bike.update_view(camera.global_position)
		light_red.visible = true
		light_blue.visible = true
	elif state == "idle":
		bike.scale = Vector3.ONE
		bike.deactivate()
		light_red.visible = false
		light_blue.visible = false

func _process(delta: float):
	if GameState.is_over:
		return
	match state:
		"idle":
			track_meter(delta)
			if GameState.recklessness >= GameState.MAX_RECKLESSNESS and not player.is_stopped():
				start_police()
		"approach":
			# Ride up from behind, alongside the trotro.
			bike.position.x = move_toward(bike.position.x, pullover_x(), 3.0 * delta)
			bike.position.z -= (player.current_speed + 9.0) * delta
			if bike.position.z <= player.position.z - 2.5:
				state = "stopped"
				timer = pullover_seconds
				player.stop_for(pullover_seconds, "police")
				player.reset_to_base_speed()
		"stopped":
			bike.position.z -= player.current_speed * delta # halts together with the trotro
			timer -= delta
			if timer <= 0.0:
				GameState.announce("FINE  -GHS %d" % current_fine, "police")
				Sfx.play("drop", 0.0, 0.7)
				if from_meter:
					GameState.reset_recklessness()
				GameState.add_fine(current_fine)
				state = "leave"
		"leave":
			bike.position.z -= (player.current_speed + 12.0) * delta
			if bike.position.z < player.position.z - 150.0:
				bike.deactivate()
				state = "idle"
	if bike.active:
		bike.update_view(camera.global_position)
		# Alternating red/blue beacon.
		var flash = int(Time.get_ticks_msec() / 120) % 2 == 0
		light_red.visible = flash
		light_blue.visible = not flash
	else:
		light_red.visible = false
		light_blue.visible = false

func track_meter(delta: float):
	if player.is_speeding:
		speeding_time += delta
		if speeding_time > speeding_grace:
			GameState.add_recklessness(speeding_rate * delta)
	else:
		speeding_time = 0.0
		calm_time += delta
		if calm_time > calm_delay and GameState.recklessness > 0.0:
			GameState.add_recklessness(-drain_rate * delta)

# The bike pulls up on the trotro's right if there's room, otherwise its left.
func pullover_x() -> float:
	return player.position.x + (2.3 if player.position.x < 2.0 else -2.3)

# Called for a full recklessness meter, or by RoadEvents when the trotro runs a
# police checkpoint (a bigger fine, and the meter is left alone).
func start_police(fine: int = -1, text: String = "POLICE! PULL OVER", meter: bool = true):
	if state != "idle":
		return
	current_fine = fine if fine > 0 else fine_amount
	from_meter = meter
	state = "approach"
	bike.activate("police_bike", TEX, 1.8, 1.2, 0, player.position.x + 2.3, player.position.z + 20.0, 0.0)
	bike.shadow.scale.x = 1.0
	bike.half_width = 0.4
	GameState.announce(text, "police")
	Sfx.play("siren", -2.0)

func is_active() -> bool:
	return state != "idle"
