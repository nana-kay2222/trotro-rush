extends Node3D

enum CameraMode {
	CHASE = 1,
	FAR = 2,
	MEDIUM = 3,
	PASSING = 4
}

@export var current_mode: CameraMode = CameraMode.CHASE
@export var follow_smoothness: float = 8.0

var player_trotro: Node3D = null

# Portrait chase camera. The camera keeps its horizontal field of view (keep_aspect =
# width), so all 3 lanes and both bus-stop pockets fit on a tall phone screen.
const CHASE_HEIGHT := 3.9
const CHASE_DISTANCE := 6.2
const CHASE_PITCH := -15.0
const BASE_FOV := 64.0
@onready var camera: Camera3D = $Camera3D

func _ready():
	# Locate player trotro in world
	player_trotro = get_node_or_null("../PlayerTrotro")
	update_camera_mode(current_mode, true)

var shake_strength: float = 0.0
var turbo_push: float = 0.0

func _process(delta: float):
	handle_mode_keys()
	update_camera_transform(delta)
	update_shake(delta)

# Short impact shake (crashes). Uses the camera's view offsets so it never
# fights the follow logic.
func shake(amount: float):
	shake_strength = maxf(shake_strength, amount)

func update_shake(delta: float):
	if not camera:
		return
	if shake_strength > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake_strength
		camera.v_offset = randf_range(-1.0, 1.0) * shake_strength
		shake_strength = move_toward(shake_strength, 0.0, 1.2 * delta)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func handle_mode_keys():
	# Inspection cameras are a developer tool; release builds stay on the chase cam.
	if not OS.is_debug_build():
		return
	if Input.is_key_pressed(KEY_1):
		set_camera_mode(CameraMode.CHASE)
	elif Input.is_key_pressed(KEY_2):
		set_camera_mode(CameraMode.FAR)
	elif Input.is_key_pressed(KEY_3):
		set_camera_mode(CameraMode.MEDIUM)
	elif Input.is_key_pressed(KEY_4):
		set_camera_mode(CameraMode.PASSING)

func set_camera_mode(mode: CameraMode):
	if current_mode != mode:
		current_mode = mode
		update_camera_mode(mode, false)
		var hud = get_node_or_null("../UI/ControlsHUD")
		if hud:
			var mode_name = ""
			match mode:
				CameraMode.CHASE: mode_name = "1: DRIVING CHASE CAM"
				CameraMode.FAR: mode_name = "2: FAR DISTANCE VIEW"
				CameraMode.MEDIUM: mode_name = "3: MEDIUM DISTANCE VIEW"
				CameraMode.PASSING: mode_name = "4: CLOSE PASSING VIEW"
			hud.text = "MODE: " + mode_name + "\n[1] Chase  [2] Far  [3] Medium  [4] Passing  |  [A/D] Steer  [P] Screenshot"

func update_camera_mode(mode: CameraMode, instant: bool):
	if not camera:
		return
		
	match mode:
		CameraMode.CHASE:
			camera.fov = BASE_FOV
		CameraMode.FAR:
			camera.fov = 55.0
			camera.global_position = Vector3(1.0, 7.5, 32.0)
			camera.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
		CameraMode.MEDIUM:
			camera.fov = 52.0
			camera.global_position = Vector3(8.5, 4.0, -18.0)
			camera.rotation_degrees = Vector3(-6.0, 22.0, 0.0)
		CameraMode.PASSING:
			camera.fov = 58.0
			camera.global_position = Vector3(6.8, 1.8, -68.0)
			camera.rotation_degrees = Vector3(-2.0, 155.0, 0.0)

func update_camera_transform(delta: float):
	if not player_trotro or not camera:
		return
		
	match current_mode:
		CameraMode.CHASE:
			# Follow behind trotro along road
			# Higher and steeper than before so the view matches the angle the
			# vehicle artwork is drawn from (slightly above, roof visible).
			# Turbo: the trotro surges ahead of the camera (further for x2) - the camera
			# falls back and rises a little, then catches up when it ends.
			var push_goal = 0.0
			if "turbo" in player_trotro and player_trotro.turbo != null and player_trotro.turbo.is_active():
				push_goal = 2.2 if player_trotro.turbo.level == 1 else 4.2
			turbo_push = lerpf(turbo_push, push_goal, delta * (2.5 if push_goal > turbo_push else 1.5))
			var target_pos = player_trotro.global_position + Vector3(0, CHASE_HEIGHT + turbo_push * 0.25, CHASE_DISTANCE + turbo_push)
			# Subtle lateral lag for driving feel
			camera.global_position.x = lerpf(camera.global_position.x, target_pos.x * 0.7, delta * 6.0)
			camera.global_position.y = target_pos.y
			camera.global_position.z = target_pos.z
			camera.rotation_degrees = Vector3(CHASE_PITCH, 0.0, 0.0)
			# Sense of speed: the view widens as the trotro gathers pace, more in a boost.
			var fov_goal = BASE_FOV
			if "current_speed" in player_trotro:
				fov_goal += maxf(0.0, player_trotro.current_speed - player_trotro.base_speed) * 0.45
			if player_trotro.has_method("is_boosting") and player_trotro.is_boosting():
				fov_goal += 7.0
			camera.fov = lerpf(camera.fov, minf(fov_goal, 88.0), delta * 3.0)
			
		CameraMode.FAR:
			# High vantage point showing the road corridor and buildings
			var look_target = Vector3(0, 2.0, player_trotro.global_position.z - 20.0)
			camera.look_at(look_target, Vector3.UP)
			
		CameraMode.MEDIUM:
			# Medium view: track trotro approaching the compound house & mosque
			var look_target = Vector3(player_trotro.global_position.x * 0.5, 1.5, player_trotro.global_position.z)
			camera.look_at(look_target, Vector3.UP)
			
		CameraMode.PASSING:
			# Ground tracking pass: watch the trotro zoom past the buildings
			var look_target = Vector3(player_trotro.global_position.x, 1.2, player_trotro.global_position.z)
			camera.look_at(look_target, Vector3.UP)
