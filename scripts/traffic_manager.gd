extends Node3D

# Traffic in the 3 active lanes (docs/GAMEPLAY_SPEC.md §16): lane assignment,
# forward movement, speed variation, spacing, spawning/despawning. No lane-changing AI.
# Also detects player crashes (Phase 1: crash -> damage, speed reset, shake).

const LANES := [-3.67, 0.0, 3.67]
const VEHICLE_SCENE := preload("res://scenes/traffic_vehicle.tscn")

# height = on-screen metres from wheels to roof (incl. roof racks), matched against
# the player trotro (~1.9 m). weight = how common the type is.
const TYPES := {
	"taxi":         {"height": 1.40, "half_length": 2.1, "weight": 4},
	"sedan":        {"height": 1.30, "half_length": 2.2, "weight": 3},
	"suv":          {"height": 1.55, "half_length": 2.3, "weight": 2},
	"pickup":       {"height": 1.60, "half_length": 2.5, "weight": 2},
	"van":          {"height": 1.75, "half_length": 2.4, "weight": 2},
	# Rival trotros appear ONLY in the rival event (owner rule), never as normal traffic: weight 0.
	"rival_trotro":   {"height": 1.90, "half_length": 2.5, "weight": 0},
	"rival_trotro_b": {"height": 1.90, "half_length": 2.5, "weight": 0},
	"motorbike":    {"height": 1.75, "half_length": 1.1, "weight": 3, "half_width": 0.45, "lane_jitter": 0.9},
}

@export var pool_size: int = 11 # one is always held back for the rival trotro
@export var spawn_interval: float = 1.0
@export var spawn_ahead_min: float = 170.0
@export var spawn_ahead_max: float = 240.0
@export var despawn_behind: float = 15.0
@export var min_speed: float = 10.0 # player cruises at 19.5+ m/s, so traffic is overtaken
@export var max_speed: float = 16.5
@export var min_same_lane_gap: float = 28.0
@export var follow_distance: float = 14.0
@export var wall_band: float = 22.0 # cars in all 3 lanes within this span = a wall
@export var crash_damage: float = 25.0
@export var stalled_interval_min: float = 25.0
@export var stalled_interval_max: float = 45.0
var stalled_timer: float = 20.0 # first breakdown after ~20 s

# Player footprint on the road (metres).
const PLAYER_HALF_WIDTH := 0.85
const PLAYER_HALF_LENGTH := 2.2
const CAR_HALF_WIDTH := 0.85

var pool: Array = []
var retired: Array = []
@onready var events = get_node_or_null("../RoadEvents")
var textures: Dictionary = {}
var type_bag: Array = []
var spawn_timer: float = 0.0

@onready var player = get_node("../PlayerTrotro")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")
@onready var hazards = get_node_or_null("../Hazards")

func _ready():
	for kind in TYPES:
		var views = {}
		# Only the views the game shows (owner choice: rear, then near-rear all the way past).
		# The wider 3/4, side and high-angle pictures stay in assets/ but aren't exported.
		for view in ["rear", "left_rear_slight", "right_rear_slight"]:
			var path = "res://assets/vehicles/%s/%s_%s.png" % [kind, kind, view]
			if ResourceLoader.exists(path): # extra views are optional
				views[view] = load(path)
		textures[kind] = views
		for i in TYPES[kind]["weight"]:
			type_bag.append(kind)
	for i in pool_size:
		var car = VEHICLE_SCENE.instantiate()
		add_child(car)
		car.deactivate()
		pool.append(car)
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.rebased.connect(_on_rebased)
	seed_traffic()

func seed_traffic():
	for i in 12:
		try_spawn(player.position.z - randf_range(45.0, spawn_ahead_max))

var auto_spawn: bool = true # off in the tutorial, which places its own cars

# The tutorial clears the road of the cars seeded at the start.
func clear_all():
	for car in pool:
		if car.active and not car.scripted:
			car.deactivate()

# Places one car (the tutorial's slow car to steer around).
func place_car(kind: String, x: float, z: float, speed: float) -> Node3D:
	for car in pool:
		if not car.active:
			var t = TYPES[kind]
			car.activate(kind, textures[kind], t["height"], t["half_length"], LANES.find(x), x, z, speed)
			car.half_width = t.get("half_width", CAR_HALF_WIDTH)
			car.shadow.scale.x = car.half_width * 2.2
			car.cruise_speed = speed
			return car
	return null

func _process(delta: float):
	if GameState.is_over:
		return
	spawn_timer += delta
	# Gentle difficulty ramp: traffic gets denser over the first ~4 km of a run.
	var ramp = clampf(GameState.distance / 4000.0, 0.0, 1.0)
	stalled_timer -= delta
	if stalled_timer <= 0.0 and auto_spawn:
		stalled_timer = randf_range(stalled_interval_min, stalled_interval_max)
		spawn_stalled()
	if auto_spawn and spawn_timer >= spawn_interval * lerpf(1.25, 0.8, ramp):
		spawn_timer = 0.0
		try_spawn(player.position.z - randf_range(spawn_ahead_min, spawn_ahead_max))

	for car in pool:
		if not car.active:
			continue
		if not car.scripted: # the rival trotro is driven by PickupManager
			var target = car.cruise_speed
			var leader = find_leader(car)
			if leader and not car.escaping:
				target = minf(target, leader.speed * 0.95)
			# The trotro is a leader too: after a crash it's slow, and cars catching up from
			# behind must queue behind it instead of driving through it.
			var behind = car.position.z - player.position.z # positive = car is behind the trotro
			if behind > 0.0 and behind < follow_distance and absf(car.position.x - player.position.x) < PLAYER_HALF_WIDTH + car.half_width + 0.3:
				target = minf(target, player.current_speed * 0.95)
				if behind < PLAYER_HALF_LENGTH + car.half_length + 1.0:
					car.speed = minf(car.speed, player.current_speed * 0.9) # too close: brake now
			car.speed = move_toward(car.speed, target, 6.0 * delta)
			car.position.z -= car.speed * delta
		car.update_view(camera.global_position)
		var rel = car.position.z - player.position.z
		check_near_miss(car, rel)
		if not car.scripted and (rel > despawn_behind or rel < -spawn_ahead_max - 150.0):
			car.deactivate()
			if car.jam:
				retired.append(car) # temporary go-slow cars leave the pool once passed
	for car in retired:
		pool.erase(car)
		car.queue_free()
	retired.clear()

	break_walls()
	check_crashes()

# Near miss (GAMEPLAY_SPEC §5): the trotro passes a vehicle with very little room to
# spare without touching it. Feeds the recklessness meter; it is not a reward.
const NEAR_MISS_MARGIN := 0.6
func check_near_miss(car, rel: float):
	var was_ahead = car.last_rel < 0.0
	car.last_rel = rel
	if not was_ahead or rel < 0.0 or car.has_hit_player or GameState.is_over or car.jam:
		return # weaving a go-slow isn't reckless: jam cars never count as near misses
	if player.is_turbo():
		return # turbo is paid for and legal; no slow-mo at 200 km/h either
	var gap = absf(player.position.x - car.position.x) - PLAYER_HALF_WIDTH - car.half_width
	if gap < NEAR_MISS_MARGIN and player.current_speed > car.speed + 2.0:
		GameState.add_recklessness(12.0)
		near_miss_rush()

# The thrill of a close call: a split second of slow motion, a whoosh and a camera punch.
# (Still reckless: the meter above has already gone up.)
var rush_cooldown_until: int = 0
func near_miss_rush():
	var now = Time.get_ticks_msec()
	if now < rush_cooldown_until:
		return
	rush_cooldown_until = now + 3000
	GameState.announce("CLOSE CALL!", "boost")
	Sfx.play("whoosh", -2.0, 1.2)
	Engine.time_scale = 0.35
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	var cam: Camera3D = get_node_or_null("../CameraRig/Camera3D")
	if cam:
		cam.fov += 6.0 # the chase camera eases back on its own

func find_leader(car) -> Node3D:
	var best = null
	for other in pool:
		if other == car or not other.active or other.lane != car.lane:
			continue
		var gap = car.position.z - other.position.z # positive = other is ahead
		if gap > 0.0 and gap < follow_distance and (best == null or other.position.z > best.position.z):
			best = other
	return best

func try_spawn(z: float) -> bool:
	if events and events.suppresses_traffic(z):
		return false # the go-slow has its own crawling traffic
	var car = null
	var free = 0
	for c in pool:
		if not c.active:
			free += 1
			if car == null:
				car = c
	# Always keep one vehicle in reserve so a rival trotro can be claimed.
	if car == null or free <= 1:
		return false
	var lanes = [0, 1, 2]
	lanes.shuffle()
	for lane in lanes:
		if lane_blocked_near(lane, z, min_same_lane_gap):
			continue
		if stalled_in_lane(lane, z, 70.0):
			continue # GAMEPLAY_SPEC §17: don't spawn traffic into a blocked lane
		if would_make_wall(lane, z):
			continue
		var kind = type_bag.pick_random()
		var t = TYPES[kind]
		# Okadas don't hold the lane centre; they ride off to one side.
		var x = LANES[lane] + randf_range(-1.0, 1.0) * t.get("lane_jitter", 0.0)
		car.activate(kind, textures[kind], t["height"], t["half_length"], lane, x, z, randf_range(min_speed, max_speed))
		car.half_width = t.get("half_width", CAR_HALF_WIDTH)
		car.shadow.scale.x = car.half_width * 2.2
		return true
	return false

# Hands a pooled vehicle to another system (the rival trotro). Returns null if the pool is
# busy. The caller moves it and must set scripted = false when it is done with it.
func claim_scripted(kind: String, lane: int, x: float, z: float, speed: float) -> Node3D:
	for c in pool:
		if not c.active:
			var t = TYPES[kind]
			c.activate(kind, textures[kind], t["height"], t["half_length"], lane, x, z, speed)
			c.half_width = t.get("half_width", CAR_HALF_WIDTH)
			c.shadow.scale.x = c.half_width * 2.2
			c.scripted = true
			return c
	return null

# Go-slow jam car (RoadEvents): an extra, temporary vehicle crawling in its lane.
func add_jam_car(lane: int, z: float, speed: float) -> Node3D:
	var car = VEHICLE_SCENE.instantiate()
	add_child(car)
	var kinds = ["taxi", "taxi", "sedan", "suv", "pickup", "van", "motorbike"]
	var kind = kinds.pick_random()
	var t = TYPES[kind]
	var x = LANES[lane] + randf_range(-1.0, 1.0) * t.get("lane_jitter", 0.25)
	car.activate(kind, textures[kind], t["height"], t["half_length"], lane, x, z, speed)
	car.half_width = t.get("half_width", CAR_HALF_WIDTH)
	car.shadow.scale.x = car.half_width * 2.2
	car.jam = true
	pool.append(car)
	return car

func stalled_in_lane(lane: int, z: float, span: float) -> bool:
	for c in pool:
		if c.active and c.stalled and c.lane == lane and absf(c.position.z - z) < span:
			return true
	return false

# Stalled vehicle (GAME_SPEC §12 / GAMEPLAY_SPEC §17): now and then a car has broken
# down in a lane ahead, stopped with hazards blinking. Never closes the last open lane.
func spawn_stalled():
	var z = player.position.z - randf_range(170.0, 220.0)
	var lanes = [0, 1, 2]
	lanes.shuffle()
	for lane in lanes:
		if lane_blocked_near(lane, z, min_same_lane_gap) or would_make_wall(lane, z):
			continue
		var car = null
		for c in pool:
			if not c.active:
				car = c
				break
		if car == null:
			return
		var kinds = ["taxi", "sedan", "suv", "pickup", "van"]
		var kind = kinds.pick_random()
		var t = TYPES[kind]
		car.activate(kind, textures[kind], t["height"], t["half_length"], lane, LANES[lane], z, 0.0)
		car.half_width = CAR_HALF_WIDTH
		car.cruise_speed = 0.0
		car.set_stalled(true)
		return

func lane_blocked_near(lane: int, z: float, gap: float) -> bool:
	for c in pool:
		if c.active and c.lane == lane and absf(c.position.z - z) < gap:
			return true
	return false

func would_make_wall(lane: int, z: float) -> bool:
	var occupied = {lane: true}
	for c in pool:
		if c.active and absf(c.position.z - z) < wall_band:
			occupied[c.lane] = true
	return occupied.size() >= LANES.size()

# Cars drift at different speeds, so three can line up side by side after spawning.
# If that happens ahead of the player, the fastest of them speeds off to reopen a lane.
func break_walls():
	for car in pool:
		if not car.active or car.escaping or car.jam or car.position.z > player.position.z - 10.0:
			continue
		var group = [car]
		var lanes = {car.lane: true}
		for other in pool:
			if other != car and other.active and not other.escaping and absf(other.position.z - car.position.z) < wall_band:
				group.append(other)
				lanes[other.lane] = true
		# Potholes block their lane too (two cars + a pothole side by side is a wall).
		if hazards:
			for p in hazards.pool:
				if p.get_meta("active") and absf(p.position.z - car.position.z) < wall_band:
					lanes[p.get_meta("lane")] = true
		if lanes.size() >= LANES.size():
			# Speed off the fastest car that has a clear run (never one queued behind a
			# stalled vehicle, which would drive straight through it).
			var fastest = null
			for g in group:
				if g.stalled or stalled_in_lane(g.lane, g.position.z - 30.0, 30.0):
					continue
				if fastest == null or g.speed > fastest.speed:
					fastest = g
			if fastest == null:
				continue
			fastest.escaping = true
			fastest.cruise_speed = player.max_speed + 4.0

const HIT_SHAVE_SIDE := 0.2 # metres of side-to-side overlap forgiven
const HIT_SHAVE_LENGTH := 0.3 # metres of front/back overlap forgiven

# dz passed on is between body centres: positive = the car is ahead of the trotro.
func check_crashes():
	if player.is_invulnerable():
		return
	for car in pool:
		if not car.active or car.has_hit_player:
			continue
		var dx = player.position.x - car.position.x
		# Both origins are rear bumpers with the bodies running forward (-z), so compare the
		# body centres. The hit area is a touch smaller than the bodies (HIT_SHAVE_*), so a
		# graze that only just touches doesn't count.
		var dz = (player.position.z - PLAYER_HALF_LENGTH) - (car.position.z - car.half_length)
		if absf(dx) < PLAYER_HALF_WIDTH + car.half_width - HIT_SHAVE_SIDE and absf(dz) < PLAYER_HALF_LENGTH + car.half_length - HIT_SHAVE_LENGTH:
			on_crash(car, dx, dz)
			return

# Trading paint with the rival: it wobbles and drops back; the trotro takes a small knock
# but keeps its speed. Risky (damage + recklessness), but it's how you win the duel.
const RIVAL_BUMP_DAMAGE := 8.0
func bump_rival(car, dx: float):
	GameState.apply_damage(RIVAL_BUMP_DAMAGE, "rival")
	GameState.add_recklessness(10.0)
	Sfx.play("crash", -6.0, 1.2)
	car.stun = 1.6
	car.speed *= 0.55
	car.has_hit_player = true
	car.bump_cooldown = 1.2
	# Shove it sideways away from the trotro; the trotro glances off the other way a little.
	var away = signf(car.position.x - player.position.x)
	if away == 0.0:
		away = 1.0
	car.position.x += away * 0.8
	player.target_x = clampf(player.position.x - away * 0.6, player.limit_left, player.limit_right)
	var rig = get_node_or_null("../CameraRig")
	if rig:
		rig.shake(0.25)

func on_crash(car, dx: float, dz: float):
	if player.is_shielded():
		shield_shove(car)
		return
	if car.scripted:
		bump_rival(car, dx)
		return
	var side_hit = absf(dz) < (PLAYER_HALF_LENGTH + car.half_length) * 0.6
	if car.stalled or car.jam:
		side_hit = true # can't get out of the way: glance the trotro off around it
	# Damage scales with the impact speed: a go-slow nudge stings, a real crash hurts.
	var impact = absf(player.current_speed - car.speed)
	var factor = 0.25 if car.jam else clampf(impact / 12.0, 0.3, 1.0)
	GameState.apply_damage(crash_damage * factor)
	GameState.add_recklessness(15.0)
	Sfx.play("crash")
	player.on_crash(car.position.x, car.speed, side_hit)
	# One car can only hurt the player once. A rear-ended car speeds off out of the
	# way, otherwise the recovering trotro would ram it again and again.
	car.has_hit_player = true
	if dz > 0.0 and not car.stalled and not car.jam:
		car.escaping = true
		car.cruise_speed = player.max_speed + 4.0
	var rig = get_node_or_null("../CameraRig")
	if rig:
		rig.shake(0.35)

# Turbo shield: the car is knocked out of the way (no damage, no slowdown), and the
# shield takes one of its four hits.
func shield_shove(car):
	car.has_hit_player = true
	var away = signf(car.position.x - player.position.x)
	if away == 0.0:
		away = 1.0 if randf() < 0.5 else -1.0
	var t = create_tween()
	t.tween_property(car, "position:x", car.position.x + away * 2.6, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not car.stalled and not car.jam and not car.scripted:
		car.escaping = true
	car.stun = 1.6 # a rival wobbles and drops back
	player.turbo.shield_hit()
	var rig = get_node_or_null("../CameraRig")
	if rig:
		rig.shake(0.25)

func _on_rebased(shift: float):
	for car in pool:
		car.position.z += shift
