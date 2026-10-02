extends Node3D

# Forward speed is fully automatic (docs/GAMEPLAY_SPEC.md §2, §4): it creeps up
# while the player drives cleanly and counts as "speeding" above a threshold.
# The player's only driving input is left/right.
@export var base_speed: float = 19.5 # m/s (~70 km/h)
@export var max_speed: float = 31.0
@export var speed_creep_rate: float = 0.15 # m/s gained per second of clean driving
@export var speeding_threshold: float = 25.0 # ~90 km/h
@export var speed_response: float = 4.0 # m/s² toward the target speed
@export var steer_rate: float = 7.0 # m/s of lateral target movement
@export var road_half_width: float = 3.8

# Debug/capture harness can freeze the trotro; players never toggle this.
var auto_drive: bool = true
var current_speed: float = 16.0
var target_speed: float = 16.0
var is_speeding: bool = false

@export var crash_invulnerability: float = 1.0 # seconds of protection after a crash

var target_x: float = 0.0
var current_x: float = 0.0
var roll_angle: float = 0.0
var bob_phase: float = 0.0
var invulnerable_timer: float = 0.0
var pothole_jolt: float = 0.0
var jolt_side: float = 1.0
var smoke: CPUParticles3D
var exhaust: CPUParticles3D

# How far left/right the trotro may go. Normally the 3 lanes; PickupManager widens
# one side while a bus-stop pocket is alongside (the pocket is not a 4th lane).
var limit_left: float = -3.8
var limit_right: float = 3.8
# Automatic stop for boarding/alighting (GAME_SPEC §2 step 5; there is no brake input).
var stop_timer: float = 0.0
# Last-second pickup boost (GAMEPLAY_SPEC §19).
var boost_timer: float = 0.0
# Automatic speed limit set each frame by RoadEvents (INF when no event applies).
var speed_cap: float = INF
const BOOST_EXTRA_SPEED := 7.0
# FULL load handling (GAMEPLAY_SPEC §14): slower, heavier lateral response.
const FULL_STEER_FACTOR := 0.72
const FULL_LATERAL_RESPONSE := 3.4
const LATERAL_RESPONSE := 5.0
const TOUCH_RESPONSE_FACTOR := 3.0
# Touch: hold and drag to steer. The trotro's target follows the finger's
# horizontal movement (relative drag, so it works wherever the thumb lands).
@export var touch_metres_per_screen: float = 11.0 # dragging across the full screen width
var touch_active: bool = false

@onready var visual_holder = $VisualHolder
@onready var sprite = $VisualHolder/Sprite
@onready var shadow = $ContactShadow

func _ready():
	position.x = 0.0
	current_x = position.x
	target_x = current_x
	current_speed = base_speed
	target_speed = base_speed
	smoke = create_damage_smoke()
	add_child(smoke)
	exhaust = create_exhaust()
	add_child(exhaust)
	# The mate hangs out of the kerb-side (right) door, a little ahead of the rear, so
	# the trotro's body hides the hand gripping the door frame.
	var mate = Node3D.new()
	mate.set_script(load("res://scripts/mate.gd"))
	mate.name = "Mate"
	# His chest cut sits at window height, its outer corner on the body's right edge
	# (x = 0.73 in the rear picture), so the rear picture hides the cut.
	mate.position = Vector3(0.74, 1.0, -0.35)
	visual_holder.add_child(mate)
	GameState.health_changed.connect(_on_health_changed)
	turbo = Node3D.new()
	turbo.set_script(load("res://scripts/turbo.gd"))
	turbo.name = "Turbo"
	add_child(turbo)

var turbo: Node3D

func is_turbo() -> bool:
	return turbo != null and turbo.is_active()

func is_shielded() -> bool:
	return turbo != null and turbo.is_shielded()

func _process(delta: float):
	if GameState.is_over:
		# Broken down: coast to a stop, no steering.
		current_speed = move_toward(current_speed, 0.0, 10.0 * delta)
		position.z -= current_speed * delta
		Sfx.set_engine(false, 0.0)
		return
	Sfx.set_engine(auto_drive, current_speed)
	handle_input(delta)
	update_docking()
	var speed_before = current_speed
	update_auto_speed(delta)
	GameState.distance += current_speed * delta
	update_invulnerability(delta)
	update_exhaust((current_speed - speed_before) / maxf(delta, 0.001))

	# Forward motion along negative Z
	position.z -= current_speed * delta

	# Smooth lateral steering (lane changes); heavier when FULL.
	target_x = clampf(target_x, limit_left, limit_right)
	var response = lerpf(LATERAL_RESPONSE, FULL_LATERAL_RESPONSE, GameState.load_fraction()) # heavier as it fills
	if touch_active:
		# Dragging: follow the finger tightly (the soft ease is for keyboard steering).
		response *= TOUCH_RESPONSE_FACTOR
	# A stopped trotro can't move sideways: it waits at the stop, then pulls out as it gets
	# going. (While docking it still steers into the pocket as it brakes.)
	if dock_x == 0.0:
		response *= clampf(current_speed / 6.0, 0.0, 1.0)
	current_x = lerpf(current_x, target_x, delta * response)
	position.x = current_x

	# Suspension roll based on steering delta
	var steer_delta = (target_x - current_x)
	var target_roll = clampf(-steer_delta * 0.8, -4.5, 4.5)
	roll_angle = lerpf(roll_angle, target_roll, delta * 8.0)
	if visual_holder:
		visual_holder.rotation_degrees.z = roll_angle

		# Road vibration / trotro suspension bounce
		bob_phase += delta * current_speed * 1.5
		var bob_y = sin(bob_phase) * 0.015 * (current_speed / max_speed)
		# Pothole jolt: a hard drop, a bounce back up past level, and a lurch to one side,
		# over ~0.45 s.
		if pothole_jolt > 0.0:
			var k = 1.0 - pothole_jolt # 0 -> 1 through the jolt
			bob_y -= sin(k * TAU) * 0.2 * pothole_jolt
			visual_holder.rotation_degrees.z = roll_angle + sin(k * TAU) * 4.0 * pothole_jolt * jolt_side
			pothole_jolt = maxf(0.0, pothole_jolt - delta * 2.2)
		visual_holder.position.y = bob_y

func handle_input(delta: float):
	# Keyboard fallback (desktop/testing). Touch drag is handled in _input.
	var steer = Input.get_axis("steer_left", "steer_right")
	if steer != 0.0:
		var rate = steer_rate * lerpf(1.0, FULL_STEER_FACTOR, GameState.load_fraction())
		target_x = clampf(target_x + steer * rate * delta, limit_left, limit_right)

# Hold and drag to steer (the main mobile control). Mouse drag mirrors it on desktop.
func _input(event: InputEvent):
	if GameState.is_over:
		return
	var dx := 0.0
	if event is InputEventScreenTouch:
		touch_active = event.pressed
	elif event is InputEventScreenDrag:
		dx = event.relative.x
	elif event.device == InputEvent.DEVICE_ID_EMULATION:
		return # mouse events Godot synthesises from touches (kept on for the UI buttons)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		touch_active = event.pressed
	elif event is InputEventMouseMotion and touch_active:
		dx = event.relative.x
	if dx != 0.0:
		var width = get_viewport().get_visible_rect().size.x
		var gain = touch_metres_per_screen * lerpf(1.0, FULL_STEER_FACTOR, GameState.load_fraction())
		target_x = clampf(target_x + dx / width * gain, limit_left, limit_right)

func update_auto_speed(delta: float):
	if not auto_drive:
		current_speed = 0.0
		return
	if stop_timer > 0.0:
		# Pulled in at a stop: brake to a full halt automatically, and only then start the
		# wait (the old timer ran while still braking, so the trotro barely stopped).
		current_speed = move_toward(current_speed, 0.0, stop_decel * delta)
		if current_speed < 0.3:
			stop_timer -= delta
			if stop_timer <= 0.0:
				stop_decel = STOP_DECEL
		is_speeding = false
		return
	if is_turbo():
		# Turbo: a hard surge to 150/200 km/h, through any road-event limit, and legal.
		current_speed = move_toward(current_speed, turbo.goal_speed(), turbo.ACCEL * delta)
		is_speeding = false
		return
	target_speed = minf(target_speed + speed_creep_rate * delta, max_speed)
	var goal = target_speed
	if boost_timer > 0.0:
		boost_timer -= delta
		goal = target_speed + BOOST_EXTRA_SPEED
	# Road events (go-slow, market, speed bumps) cap the pace automatically.
	goal = minf(goal, speed_cap)
	# Pull away from a stop briskly, then settle; slow down for a cap firmly.
	var rate = speed_response * (2.0 if current_speed < base_speed * 0.6 else 1.0)
	if current_speed > goal:
		rate = maxf(rate, 9.0)
	current_speed = move_toward(current_speed, goal, rate * delta)
	# (Easing back down from a turbo, above the trotro's own top speed, isn't speeding.)
	is_speeding = current_speed >= speeding_threshold and speed_cap == INF and current_speed <= max_speed + 0.5

const STOP_DECEL := 16.0 # m/s² when pulling up at a stop
var stop_decel: float = STOP_DECEL

# Metres the trotro needs to brake to a halt from its current speed.
func braking_distance() -> float:
	return current_speed * current_speed / (2.0 * STOP_DECEL)

# Pull up within `metres` (a late swing into a stop brakes harder so it still halts beside
# the passengers), holding until something sets the wait (stop_timer).
func pull_up_within(metres: float):
	stop_decel = clampf(current_speed * current_speed / (2.0 * maxf(metres, 1.5)), STOP_DECEL, 45.0)
	stop_timer = 60.0
	stop_reason = ""

# Docking at a bus stop / mechanic: while it pulls up, the trotro steers itself fully into
# the pocket (dock_x = the pocket's centre line) so it never stops half on the road. If the
# player drags back out before it has stopped and `dock_cancelable`, the stop is called off.
var dock_x: float = 0.0
var dock_cancelable: bool = false

func dock(x: float, cancelable: bool):
	dock_x = x
	dock_cancelable = cancelable

func update_docking():
	if dock_x == 0.0:
		return
	if stop_timer <= 0.0:
		dock_x = 0.0 # the stop is over: steering is the player's again
		return
	if dock_cancelable and target_x * signf(dock_x) < absf(dock_x) - 2.0 and current_speed > 1.0:
		stop_timer = 0.0 # dragged back out: call it off
		stop_decel = STOP_DECEL
		dock_x = 0.0
		return
	target_x = dock_x

# Why the trotro is stopped ("" for stops, "police" for a pull-over or checkpoint check).
var stop_reason: String = ""

func stop_for(seconds: float, reason: String = ""):
	stop_timer = maxf(stop_timer, seconds)
	stop_reason = reason
	# Pulling up at a stop (or for the police) brings the pace back to normal, so a driver
	# who works the stops naturally stays out of the speeding/recklessness zone.
	reset_to_base_speed()

func is_stopped() -> bool:
	return stop_timer > 0.0

func start_boost(seconds: float):
	boost_timer = seconds

func is_boosting() -> bool:
	return boost_timer > 0.0 or is_turbo()

# Crash / police stop: drop back to normal driving speed (GAMEPLAY_SPEC owner decisions).
func reset_to_base_speed():
	target_speed = base_speed

# Pothole: a hard jolt of the suspension, no speed reset (it isn't a crash).
func on_pothole():
	pothole_jolt = 1.0
	jolt_side = -1.0 if randf() < 0.5 else 1.0

func is_invulnerable() -> bool:
	return invulnerable_timer > 0.0

# Called by TrafficManager. Damage itself is applied through GameState.
func on_crash(other_x: float, other_speed: float, side_hit: bool):
	reset_to_base_speed()
	# Jolt: lose speed to below the car we hit, then recover automatically.
	current_speed = minf(current_speed, other_speed * 0.7)
	if side_hit:
		# Bounce back away from the car we swiped.
		var away = signf(position.x - other_x)
		if away == 0.0:
			away = 1.0
		target_x = clampf(other_x + away * 2.2, -road_half_width, road_half_width)
	invulnerable_timer = crash_invulnerability

func update_invulnerability(delta: float):
	if invulnerable_timer <= 0.0:
		return
	invulnerable_timer -= delta
	# Blink while protected so the player can see it: the body, the mate hanging out of it
	# and its shadow together (blinking only the body left the mate floating in mid-air).
	var shown = invulnerable_timer <= 0.0 or int(invulnerable_timer * 12.0) % 2 == 0
	visual_holder.visible = shown
	shadow.visible = shown

func _on_health_changed(health: float, max_health: float):
	var damage = 1.0 - health / max_health
	# Visible wear: the trotro gets grimier as it takes damage.
	sprite.modulate = Color.WHITE.lerp(Color(0.68, 0.64, 0.6), damage)
	if health <= 0.0:
		visual_holder.visible = true
		shadow.visible = true
	# Smoke from half health (owner direction: noticeable but not plenty): a thin grey
	# wisp, turning darker below a quarter.
	smoke.emitting = health < max_health * 0.5
	if health < max_health * 0.25:
		smoke.color = Color(0.2, 0.2, 0.2, 0.5)
		smoke.scale_amount_max = 1.3
	else:
		smoke.color = Color(0.62, 0.62, 0.64, 0.32)
		smoke.scale_amount_max = 1.0

# Tailpipe smoke: light grey puffs normally; a thick dark belch when pulling away hard
# (after a stop) or boosting, the way an old diesel trotro does.
func update_exhaust(accel: float):
	var hard = accel > 2.5 or boost_timer > 0.0
	exhaust.emitting = current_speed > 0.5 or hard
	exhaust.color = Color(0.2, 0.2, 0.2, 0.55) if hard else Color(0.55, 0.55, 0.55, 0.22)
	exhaust.scale_amount_max = 1.6 if hard else 0.9

func create_exhaust() -> CPUParticles3D:
	var p = create_damage_smoke()
	p.name = "Exhaust"
	p.amount = 24
	p.lifetime = 0.9
	p.position = Vector3(-0.55, 0.3, 0.2) # tailpipe, low on the rear
	p.emission_sphere_radius = 0.08
	p.direction = Vector3(-0.3, 0.4, 1.0) # out and back toward the camera side
	p.spread = 20.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.color = Color(0.55, 0.55, 0.55, 0.35)
	return p # update_exhaust() switches it on once it's in the scene

func create_damage_smoke() -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.name = "DamageSmoke"
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.1
	p.local_coords = false # puffs stay behind in the world as the trotro drives on
	p.position = Vector3(0.0, 1.5, 0.4)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0, 0.8, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.3
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var grow = Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var puff = QuadMesh.new()
	puff.size = Vector2(0.7, 0.7)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var soft = GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	mat.albedo_texture = soft
	puff.material = mat
	p.mesh = puff
	return p

func set_lane(lane_x: float):
	target_x = lane_x
