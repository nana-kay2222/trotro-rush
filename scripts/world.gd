extends Node3D

@onready var player_trotro = $PlayerTrotro
@onready var camera_rig = $CameraRig
@onready var camera = $CameraRig/Camera3D
@onready var hud = $UI/ControlsHUD

var capture_queue = []
var capture_timer = 0.0
var capturing = false
var auto_capture_mode = false

func _ready():
	print("[boot] world ready ", Time.get_ticks_msec())
	if OS.has_feature("web"):
		# Browsers compile every shader variant on first use, and real-time sun shadows
		# roughly double that work (measured: ~40 s of a first visit on a laptop) and cost
		# frame rate on phones. Vehicles keep their painted contact shadows.
		$SunLight.shadow_enabled = false
	# GameState is an autoload and survives scene reloads, so each run starts fresh here.
	GameState.reset()
	warm_up_shaders.call_deferred()
	
	# Accept the flag before or after "--" (Godot 4 puts args after "--" in user args).
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--auto-capture":
			auto_capture_mode = true
		elif arg == "--trailer":
			# Self-driving bot for recording the trailer (tools/trailer).
			var bot = Node.new()
			bot.name = "TrailerBot"
			bot.set_script(load("res://tools/trailer/trailer_bot.gd"))
			add_child.call_deferred(bot)
			
	if auto_capture_mode:
		print("Auto-capture mode requested: starting test pass sequence...")
		start_auto_capture_sequence()

# The GPU prepares each kind of material the first time it's drawn, which freezes the game
# for a moment (seconds, in a browser). Draw a speck-sized copy of everything that only
# appears later in a run (road-event props, people, signs, the police bike and its flares)
# for a few frames now, behind the start screen.
func warm_up_shaders():
	var root = Node3D.new()
	root.position = Vector3(player_trotro.position.x, 0.0, player_trotro.position.z - 12.0)
	root.scale = Vector3.ONE * 0.01
	add_child(root)
	$RoadEvents.add_warm_up_props(root)
	$Police.warm_up(true)
	for i in 4:
		await get_tree().process_frame
	$Police.warm_up(false)
	root.queue_free()

func _input(event):
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			capture_screenshot("manual_%d.png" % Time.get_ticks_msec())
		elif event.keycode == KEY_C:
			start_auto_capture_sequence()

func start_auto_capture_sequence():
	capture_queue = [
		{
			"name": "1_buildings_far_away.png",
			"trotro_pos": Vector3(0.0, 0.0, 10.0),
			"trotro_speed": 0.0,
			"cam_pos": Vector3(0.0, 2.8, 17.5),
			"cam_rot": Vector3(-6.0, 0.0, 0.0),
			"cam_fov": 58.0,
			"desc": "1. Buildings Far Away (3-Lane Road Straightaway Approach)"
		},
		{
			"name": "2_medium_distance.png",
			"trotro_pos": Vector3(0.0, 0.0, -18.0),
			"trotro_speed": 0.0,
			"cam_pos": Vector3(1.5, 2.5, -9.0),
			"cam_rot": Vector3(-4.0, 8.0, 0.0),
			"cam_fov": 54.0,
			"desc": "2. Medium Distance (Approaching Compound House & Mosque Minaret)"
		},
		{
			"name": "3_close_passing_compound_house.png",
			"trotro_pos": Vector3(-1.2, 0.0, -45.0),
			"trotro_speed": 0.0,
			"cam_pos": Vector3(2.2, 2.0, -35.0),
			"cam_rot": Vector3(-2.0, 24.0, 0.0),
			"cam_fov": 56.0,
			"desc": "3. Close Passing View - Ghanaian Compound House (Volume, Veranda & Breeze Wall)"
		},
		{
			"name": "4_trotro_driving_past_mosque.png",
			"trotro_pos": Vector3(1.2, 0.0, -100.0),
			"trotro_speed": 0.0,
			"cam_pos": Vector3(-2.5, 2.3, -88.0),
			"cam_rot": Vector3(-1.0, -26.0, 0.0),
			"cam_fov": 58.0,
			"desc": "4. Trotro Driving Past Mosque (Minaret Silhouette, Dome & Prayer Hall)"
		},
		{
			"name": "5_driver_chase_cam.png",
			"trotro_pos": Vector3(0.0, 0.0, -65.0),
			"trotro_speed": 16.0,
			"cam_pos": Vector3(0.0, 2.3, -58.8),
			"cam_rot": Vector3(-5.5, 0.0, 0.0),
			"cam_fov": 62.0,
			"desc": "5. Standard Driver Chase Cam (In-Motion Driving View)"
		}
	]
	capturing = true
	capture_timer = 0.5

func _process(delta: float):
	if capturing and capture_queue.size() > 0:
		capture_timer -= delta
		if capture_timer <= 0.0:
			var item = capture_queue[0]
			apply_capture_setup(item)
			capture_timer = 0.35
			await get_tree().create_timer(0.2).timeout
			save_current_viewport(item["name"])
			capture_queue.pop_front()
			if capture_queue.size() == 0:
				capturing = false
				print("All test screenshots captured successfully!")
				if auto_capture_mode:
					get_tree().quit()
				else:
					if camera_rig:
						camera_rig.set_camera_mode(1)
					if player_trotro:
						player_trotro.auto_drive = true

func apply_capture_setup(item: Dictionary):
	print("Setting up view: ", item["desc"])
	if player_trotro:
		player_trotro.global_position = item["trotro_pos"]
		player_trotro.target_x = item["trotro_pos"].x
		player_trotro.current_x = item["trotro_pos"].x
		player_trotro.current_speed = item["trotro_speed"]
		player_trotro.auto_drive = (item["trotro_speed"] > 0)
	
	if camera:
		camera.global_position = item["cam_pos"]
		camera.rotation_degrees = item["cam_rot"]
		camera.fov = item["cam_fov"]
		
	if camera_rig:
		camera_rig.current_mode = 0
		
	if hud:
		hud.text = item["desc"]

func save_current_viewport(filename: String):
	var img = get_viewport().get_texture().get_image()
	var full_path = "res://screenshots/" + filename
	var global_path = ProjectSettings.globalize_path(full_path)
	img.save_png(global_path)
	print("Saved screenshot: ", global_path)

func capture_screenshot(filename: String):
	await RenderingServer.frame_post_draw
	save_current_viewport(filename)
