extends Node3D

# Big road moments (owner-approved), one at a time from a shuffled rotation:
#   jam        - go-slow: crawling traffic in two of three lanes; the open lane moves now
#                and then (with room to change lanes). Hawkers work the lane lines and
#                sometimes cross. The trotro slows automatically.
#   market     - stalls packed on both walkways; shoppers cross the road.
#   checkpoint - trotro-only police check: the officer on the walkway waves you through or
#                flags you into the coned right lane (automatic stop beside him). Run it and
#                the bikes chase you down.
#   bumps      - a pair of speed bumps; the trotro slows automatically and bounces over.
# Speed changes are automatic (no brake): the event sets player.speed_cap each frame.

const LANES := [-3.67, 0.0, 3.67]
const HAWKERS := [
	preload("res://assets/characters/hawker_water.png"),
	preload("res://assets/characters/hawker_bread.png"),
	preload("res://assets/characters/hawker_chips.png"),
]
const STALLS := [
	preload("res://assets/props/stall_vegetables.png"),
	preload("res://assets/props/stall_clothes.png"),
	preload("res://assets/props/stall_momo.png"),
	preload("res://assets/props/kiosk_umbrella.png"),
	preload("res://assets/props/orange_stall.png"),
	preload("res://assets/props/polytank_stand.png"),
]
const OFFICER_WAVE := preload("res://assets/characters/police_officer_wave.png")
const OFFICER_STOP := preload("res://assets/characters/police_officer_stop.png")

const LENGTHS := {"jam": 170.0, "market": 220.0, "checkpoint": 90.0, "bumps": 40.0}
# Checkpoint (local z, negative = ahead): a cone line on the lane line between the middle
# and right lanes turns the right lane into the checkpoint lane. The officer stands on the
# right-hand walkway beside where a flagged trotro stops.
const CONE_X := 1.83
const CONES_FROM := -6.0
const CONES_TO := -50.0
const CHECKPOINT_WARN_AHEAD := 90.0 # metres before the first cone
const OFFICER_Z := -34.0
const CHECK_LANE_X := 2.6 # trotro centre beyond this = in the checkpoint lane
const WALKWAY_HEIGHT := 0.15

@export var first_event_after: float = 420.0 # metres into the run
@export var gap_min: float = 520.0
@export var gap_max: float = 760.0
@export var checkpoint_flag_chance: float = 0.45
@export var run_checkpoint_fine: int = 25

var events: Array = []
var bag: Array = []
var next_event_z: float = 0.0
var bump_texture: ImageTexture
var cone_mesh: ArrayMesh
var time: float = 0.0

@onready var player = get_node("../PlayerTrotro")
@onready var traffic = get_node("../Traffic")
@onready var police = get_node_or_null("../Police")

func _ready():
	next_event_z = player.position.z - first_event_after
	bump_texture = make_bump_texture()
	cone_mesh = make_cone_mesh()
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.rebased.connect(_on_rebased)

func _on_rebased(shift: float):
	next_event_z += shift
	for ev in events:
		ev["z_start"] += shift
		ev["node"].position.z += shift

var auto_spawn: bool = true # off in the tutorial, which places its own events

func _process(delta: float):
	time += delta
	if GameState.is_over:
		player.speed_cap = INF
		return
	if auto_spawn and player.position.z - next_event_z < 240.0:
		var type = next_type()
		spawn_event(type, next_event_z)
		next_event_z -= LENGTHS[type] + randf_range(gap_min, gap_max)
	var cap = INF
	for ev in events.duplicate():
		cap = minf(cap, update_event(ev, delta))
		if ev["z_start"] - LENGTHS[ev["type"]] > player.position.z + 30.0 and not jam_cars_ahead(ev):
			ev["node"].queue_free()
			events.erase(ev)
	player.speed_cap = cap

# A go-slow lasts until its creeping cars are all behind the trotro.
func jam_cars_ahead(ev: Dictionary) -> bool:
	for c in ev.get("cars", []):
		if is_instance_valid(c) and c.active and c.position.z < player.position.z + 10.0:
			return true
	return false

func next_type() -> String:
	if bag.is_empty():
		bag = ["jam", "market", "checkpoint", "bumps"]
		bag.shuffle()
	return bag.pop_back()

# ------------------------------------------------------------------ queries for other systems

func in_zone(ev: Dictionary, z: float, before: float = 0.0, after: float = 0.0) -> bool:
	return z <= ev["z_start"] + before and z >= ev["z_start"] - LENGTHS[ev["type"]] - after

# Sfx street background: a market or go-slow (crowds, hawkers) around this point.
func crowded_near(z: float) -> bool:
	for ev in events:
		if ev["type"] in ["market", "jam"] and in_zone(ev, z, 60.0, 20.0):
			return true
	return false

# TrafficManager: no normal traffic inside a go-slow (it has its own).
func suppresses_traffic(z: float) -> bool:
	for ev in events:
		if ev["type"] == "jam" and in_zone(ev, z, 30.0, 20.0):
			return true
	return false

# HUD (turbo offer): is the trotro in, or about to enter, a go-slow?
func in_go_slow(pz: float) -> bool:
	for ev in events:
		if ev["type"] == "jam" and in_zone(ev, pz, 40.0, 0.0):
			return true
	return false

# PickupManager / HazardManager: keep bus stops and potholes out of event zones.
func zone_overlaps(z_near: float, z_far: float) -> bool:
	for ev in events:
		if ev["type"] == "bumps":
			continue
		if not (z_far > ev["z_start"] + 20.0 or z_near < ev["z_start"] - LENGTHS[ev["type"]] - 20.0):
			return true
	return false

# PickupManager merges this into the steering limits. Along the checkpoint's cone line the
# trotro stays on whichever side of the cones it's on: in the checkpoint lane, or out of it.
func lane_limits(px: float, pz: float) -> Vector2:
	for ev in events:
		if ev["type"] == "checkpoint" and pz <= ev["z_start"] + CONES_FROM and pz >= ev["z_start"] + CONES_TO:
			if px > CONE_X:
				return Vector2(CONE_X + 1.0, INF)
			return Vector2(-INF, CONE_X - 1.0)
	return Vector2(-INF, INF)

# ------------------------------------------------------------------ spawning

func spawn_event(type: String, z_start: float):
	var pickups = get_node_or_null("../Pickups")
	if pickups and type != "bumps":
		pickups.remove_bays_in(z_start + 20.0, z_start - LENGTHS[type] - 20.0)
	var root = Node3D.new()
	root.position = Vector3(0, 0, z_start)
	add_child(root)
	var ev = {"type": type, "z_start": z_start, "node": root, "announced": false}
	match type:
		"jam": build_jam(ev)
		"market": build_market(ev)
		"checkpoint": build_checkpoint(ev)
		"bumps": build_bumps(ev, 0.0)
	events.append(ev)

func billboard(root: Node3D, tex: Texture2D, height: float, pos: Vector3, flip: bool = false) -> Sprite3D:
	var s = Sprite3D.new()
	s.texture = tex
	s.pixel_size = height / tex.get_height()
	s.offset = Vector2(0, tex.get_height() * 0.5)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.flip_h = flip
	s.position = pos
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	return s

func call_label(root: Node3D, text: String, pos: Vector3, size: float = 0.009) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 16
	l.outline_modulate = Color(0.05, 0.03, 0.0)
	l.pixel_size = size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	root.add_child(l)
	return l

# Go-slow: rows of crawling cars filling two lanes. The open lane holds for a few rows;
# when it moves, the old and the new lane both stay open for two rows (~22 m), which is
# the room the trotro needs to change lanes at jam speed without touching anyone.
func build_jam(ev: Dictionary):
	var gap = randi() % 3
	var next_gap = gap
	var rows = int((LENGTHS["jam"] - 16.0) / 11.0)
	var hold = randi_range(2, 3)
	var transition = 0
	var creep = randf_range(1.2, 1.6) # one pace for the whole queue keeps its shape
	ev["cars"] = []
	for r in rows:
		var z = ev["z_start"] - 8.0 - r * 11.0
		var open = [gap]
		if transition > 0:
			open.append(next_gap)
			transition -= 1
			if transition == 0:
				gap = next_gap
				hold = randi_range(2, 4)
		elif hold <= 0 and r < rows - 3:
			next_gap = clampi(gap + [-1, 1].pick_random(), 0, 2)
			if next_gap == gap:
				next_gap = 1 # from an edge lane the only neighbour is the middle
			open.append(next_gap)
			transition = 1 # this row and the next
		else:
			hold -= 1
		for lane in 3:
			if not open.has(lane):
				ev["cars"].append(traffic.add_jam_car(lane, z + randf_range(-0.6, 0.6), creep + randf_range(-0.05, 0.05)))
	ev["walkers"] = []
	ev["next_walker"] = 0.0
	ev["honk"] = 1.0

func build_market(ev: Dictionary):
	var root: Node3D = ev["node"]
	for side in [-1.0, 1.0]:
		var dz = -4.0
		while dz > -LENGTHS["market"]:
			var tex: Texture2D = STALLS.pick_random()
			var h = 3.0 if tex == STALLS[3] else 2.5
			billboard(root, tex, h, Vector3(side * randf_range(7.4, 8.6), 0.15, dz), side < 0.0)
			if randf() < 0.45:
				billboard(root, HAWKERS.pick_random(), 1.7, Vector3(side * randf_range(6.8, 7.2), 0.15, dz - 2.5), side > 0.0)
			dz -= randf_range(6.5, 10.0)
	build_bumps(ev, 6.0) # speed bumps at the market entrance
	ev["walkers"] = []
	ev["next_walker"] = 1.0

func build_checkpoint(ev: Dictionary):
	var root: Node3D = ev["node"]
	# Cone line on the lane line, opening with a short flare so the entry reads clearly.
	var z = CONES_FROM
	while z >= CONES_TO:
		add_cone(root, Vector3(CONE_X, 0.0, z))
		z -= 3.0
	for i in 3:
		add_cone(root, Vector3(CONE_X + 0.25 * (i + 1), 0.0, CONES_FROM + 3.0 * (i + 1)))
	# Officer on the walkway beside the stopping point.
	ev["officer"] = billboard(root, OFFICER_WAVE, 1.8, Vector3(7.2, WALKWAY_HEIGHT, OFFICER_Z), true)
	ev["officer_z_local"] = OFFICER_Z
	# Keep the walkway's power poles clear of the officer.
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.clear_poles(ev["z_start"] + CONES_FROM + 20.0, ev["z_start"] + CONES_TO)
	ev["decided"] = false
	ev["flagged"] = false
	ev["checked"] = false
	ev["ran"] = false

func build_bumps(ev: Dictionary, offset: float):
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = bump_texture
	mat.uv1_scale = Vector3(6.0, 1.0, 1.0)
	var zs = []
	for i in 2:
		var b = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(11.0, 0.12, 0.8)
		b.mesh = box
		b.material_override = mat
		var dz = offset - 4.0 - i * 10.0
		b.position = Vector3(0, 0.05, dz)
		ev["node"].add_child(b)
		zs.append(dz)
	ev["bumps"] = zs
	ev["bumps_hit"] = [false, false]

# One of each road-event material, for World.warm_up_shaders().
func add_warm_up_props(root: Node3D):
	add_cone(root, Vector3.ZERO)
	var ev = {"node": root}
	build_bumps(ev, 0.0)
	billboard(root, HAWKERS[0], 1.7, Vector3(1, 0, 0))
	billboard(root, OFFICER_WAVE, 1.8, Vector3(-1, 0, 0), true)
	call_label(root, "POLICE", Vector3(0, 2, 0))

func add_cone(root: Node3D, pos: Vector3):
	var c = MeshInstance3D.new()
	c.mesh = cone_mesh
	c.position = pos
	root.add_child(c)

# ------------------------------------------------------------------ per frame (returns speed cap)

func update_event(ev: Dictionary, delta: float) -> float:
	var pz = player.position.z
	var cap = INF
	# Automatic slow-down over speed bumps (their own or a market's entrance bumps).
	if ev.has("bumps"):
		for i in ev["bumps"].size():
			var bz = ev["z_start"] + ev["bumps"][i]
			if pz <= bz + 30.0 and pz >= bz - 6.0:
				cap = minf(cap, 10.0)
			if not ev["bumps_hit"][i] and pz < bz:
				ev["bumps_hit"][i] = true
				player.on_pothole()
				Sfx.play("pothole", -6.0, 1.3)
				shake(0.1)
	match ev["type"]:
		"jam": cap = minf(cap, update_jam(ev, delta, pz))
		"market": cap = minf(cap, update_market(ev, delta, pz))
		"checkpoint": cap = minf(cap, update_checkpoint(ev, pz))
		"bumps":
			pass # the painted humps and the automatic slow-down say it all
	return cap

# Owner direction: the go-slow's speed limit rises 10% each day (9 m/s on day 1), but never
# reaches normal driving speed.
func jam_speed_cap() -> float:
	return minf(9.0 * pow(1.1, GameState.day - 1), 18.0)

func update_jam(ev: Dictionary, delta: float, pz: float) -> float:
	var dist = pz - ev["z_start"]
	if not ev["announced"] and dist < 160.0:
		ev["announced"] = true
		GameState.announce("GO-SLOW AHEAD!", "warn")
	# Hawkers work the queue along the lane lines, a few at a time around the trotro.
	ev["next_walker"] -= delta
	if ev["next_walker"] <= 0.0 and in_zone(ev, pz, 60.0, -30.0):
		ev["next_walker"] = randf_range(1.2, 2.4) / crowd_factor()
		if count_walkers_near(ev, pz) < ceili(3.0 * crowd_factor()):
			spawn_jam_hawker(ev, pz)
	update_walkers(ev, delta, pz)
	# The jam's real extent is wherever its crawling cars are (they creep forward).
	var near_z = -INF
	var far_z = INF
	for c in ev.get("cars", []):
		if is_instance_valid(c) and c.active:
			near_z = maxf(near_z, c.position.z)
			far_z = minf(far_z, c.position.z)
	if near_z == -INF:
		return INF
	if pz <= near_z + 25.0 and pz >= far_z - 4.0:
		ev["honk"] -= delta
		if ev["honk"] <= 0.0:
			ev["honk"] = randf_range(1.6, 3.6) # the recorded horn is ~2.8 s long
			Sfx.play("horn", randf_range(-16.0, -9.0), randf_range(0.85, 1.15))
		return jam_speed_cap()
	return INF

func update_market(ev: Dictionary, delta: float, pz: float) -> float:
	var dist = pz - ev["z_start"]
	if not ev["announced"] and dist < 170.0:
		ev["announced"] = true
		GameState.announce("MARKET AHEAD!", "warn")
	# Shoppers crossing from one walkway to the other, sometimes in pairs.
	if in_zone(ev, pz, 60.0, -40.0):
		ev["next_walker"] -= delta
		if ev["next_walker"] <= 0.0:
			ev["next_walker"] = randf_range(1.6, 3.0) / crowd_factor()
			spawn_crosser(ev, pz)
	update_walkers(ev, delta, pz)
	if in_zone(ev, pz, 10.0, 0.0):
		return 15.0
	return INF

# ------------------------------------------------------------------ people on the road
# One walker system for go-slow hawkers and market shoppers. A walker follows a list of
# legs {x, speed, z_speed, pause}; the trotro can hit one (damage + recklessness) or only
# just miss one (they jump back in fright + recklessness).
const WALKWAY_X := 6.6
const LANE_LINES := [-1.83, 1.83]
const PERSON_HALF_WIDTH := 0.3
# Daylight between trotro and person that still scares them. Hawkers on a lane line have
# ~0.7 m when the trotro keeps to the middle of its lane, so only a real squeeze counts.
const NEAR_MISS_GAP := 0.45

# Owner direction: 7% more people crossing each day, up to day 10, then it holds there.
const CROWD_GROWTH := 1.07
const CROWD_MAX_DAY := 10

func crowd_factor() -> float:
	return pow(CROWD_GROWTH, mini(GameState.day, CROWD_MAX_DAY) - 1)

func count_walkers_near(ev: Dictionary, pz: float) -> int:
	var n = 0
	for w in ev["walkers"]:
		if absf(ev["z_start"] + w["sprite"].position.z - pz) < 70.0:
			n += 1
	return n

func add_walker(ev: Dictionary, tex: Texture2D, x: float, world_z: float, legs: Array) -> Dictionary:
	var s = billboard(ev["node"], tex, 1.7, Vector3(x, 0, world_z - ev["z_start"]))
	var w = {"sprite": s, "tex": tex, "walk": variant_texture(tex, "_walk"), "legs": legs, "leg": 0,
		"wait": 0.0, "phase": randf() * TAU, "hit": false, "scared": false, "react": 0.0, "dodge_x": 0.0}
	ev["walkers"].append(w)
	return w

# Crossing sideways: the side-on walking pose (drawn facing right; mirrored to walk left).
# Working along the queue or standing: the front-facing pose.
func update_look(w: Dictionary, leg: Dictionary, moving: bool):
	var s: Sprite3D = w["sprite"]
	var dx = leg["x"] - s.position.x
	if moving and absf(dx) > 0.05 and leg["speed"] >= 0.8:
		set_texture(s, w["walk"])
		s.flip_h = dx < 0.0
	else:
		set_texture(s, w["tex"])
		s.flip_h = false

func set_texture(s: Sprite3D, tex: Texture2D):
	if s.texture == tex:
		return
	s.texture = tex
	s.pixel_size = 1.7 / tex.get_height()
	s.offset = Vector2(0, tex.get_height() * 0.5)

# Go-slow hawker: most are already working a lane line between the cars; some walk in from
# the kerb. After a while they head off, usually back to the near walkway, sometimes right
# across the road to the far one.
func spawn_jam_hawker(ev: Dictionary, pz: float):
	var world_z = pz - randf_range(35.0, 60.0)
	if not in_zone(ev, world_z):
		return
	var line_x: float = LANE_LINES.pick_random() + randf_range(-0.15, 0.15)
	var near_side = signf(line_x)
	var exit_side = near_side if randf() < 0.65 else -near_side
	var legs = []
	var start_x = line_x
	if randf() < 0.4:
		start_x = near_side * WALKWAY_X
		legs.append({"x": line_x, "speed": 1.4, "z_speed": 0.0, "pause": 0.0})
	# Working the queue: walk back along the cars for a few metres, stop at a window, repeat.
	for i in randi_range(2, 3):
		legs.append({"x": line_x + randf_range(-0.12, 0.12), "speed": 0.3, "z_speed": 0.9, "time": randf_range(1.8, 3.0), "pause": randf_range(0.8, 1.8)})
	legs.append({"x": exit_side * (WALKWAY_X + 0.6), "speed": 1.5, "z_speed": 0.2, "pause": 0.0})
	add_walker(ev, HAWKERS.pick_random(), start_x, world_z, legs)

# Market shopper crossing the whole road, at a normal walking pace.
func spawn_crosser(ev: Dictionary, pz: float):
	var world_z = pz - randf_range(40.0, 65.0)
	if not in_zone(ev, world_z):
		return
	var side = -1.0 if randf() < 0.5 else 1.0
	var speed = randf_range(1.2, 1.6)
	var legs = [{"x": -side * (WALKWAY_X + 0.6), "speed": speed, "z_speed": 0.0, "pause": 0.0}]
	add_walker(ev, HAWKERS.pick_random(), side * WALKWAY_X, world_z, legs)
	if randf() < 0.3: # a friend walking alongside
		add_walker(ev, HAWKERS.pick_random(), side * (WALKWAY_X + 0.9), world_z - 0.9, legs.duplicate(true))

func update_walkers(ev: Dictionary, delta: float, pz: float):
	for w in ev["walkers"].duplicate():
		var s: Sprite3D = w["sprite"]
		if w["react"] > 0.0:
			animate_fright(w, delta)
		elif w["leg"] < w["legs"].size():
			var leg = w["legs"][w["leg"]]
			if w["wait"] > 0.0:
				w["wait"] -= delta # stopped at a car window
				update_look(w, leg, false)
			else:
				w["phase"] += delta * 7.0
				s.position.y = absf(sin(w["phase"])) * 0.05
				update_look(w, leg, true)
				s.position.x = move_toward(s.position.x, leg["x"], leg["speed"] * delta)
				s.position.z += leg["z_speed"] * delta
				# A leg ends on reaching its spot, or after its set time when it has one.
				var done = absf(s.position.x - leg["x"]) < 0.02
				if leg.has("time"):
					leg["time"] -= delta
					done = leg["time"] <= 0.0
				if done:
					s.position.y = 0.0
					w["wait"] = leg["pause"]
					w["leg"] += 1
		else:
			s.queue_free() # reached the walkway
			ev["walkers"].erase(w)
			continue
		check_walker_contact(ev, w, pz)

func check_walker_contact(ev: Dictionary, w: Dictionary, pz: float):
	if w["hit"]:
		return
	var s: Sprite3D = w["sprite"]
	var world_z = ev["z_start"] + s.position.z
	# The trotro's body runs from its rear bumper (pz) forward about 4.4 m.
	if world_z > pz + 0.3 or world_z < pz - 4.7:
		return
	var gap = absf(player.position.x - s.position.x) - traffic.PLAYER_HALF_WIDTH - PERSON_HALF_WIDTH
	if player.is_turbo() and gap < NEAR_MISS_GAP:
		# Turbo: they leap clear in time (the shield/turbo is legal - no damage, no meter).
		w["hit"] = true
		w["scared"] = true
		start_fright(w, 1.6)
		return
	if gap < 0.0:
		w["hit"] = true
		GameState.apply_damage(10.0, "person")
		GameState.add_recklessness(15.0)
		Sfx.play("crash", -8.0, 1.4)
		shake(0.2)
		start_fright(w, 1.6)
	elif gap < NEAR_MISS_GAP and not w["scared"]:
		w["scared"] = true
		GameState.add_recklessness(8.0)
		Sfx.play("whoosh", -10.0, 1.3)
		start_fright(w, 0.8)

# Fright: switch to the startled pose and jump away from the trotro.
func start_fright(w: Dictionary, distance: float):
	var s: Sprite3D = w["sprite"]
	var away = signf(s.position.x - player.position.x)
	if away == 0.0:
		away = 1.0
	w["react"] = FRIGHT_TIME
	w["from_x"] = s.position.x
	w["dodge_x"] = s.position.x + away * distance
	set_texture(s, variant_texture(w["tex"], "_scared"))
	s.flip_h = away < 0.0 # scared art recoils toward image-right; mirror to recoil the other way
	# Carry on to the kerb they were jumping toward afterwards.
	w["legs"] = [{"x": signf(w["dodge_x"]) * (WALKWAY_X + 0.6), "speed": 1.8, "z_speed": 0.0, "pause": 0.0}]
	w["leg"] = 0
	w["wait"] = 0.0

const FRIGHT_TIME := 1.1
const HOP_TIME := 0.32

func animate_fright(w: Dictionary, delta: float):
	var s: Sprite3D = w["sprite"]
	w["react"] -= delta
	var t = FRIGHT_TIME - w["react"] # time since the scare
	if t < HOP_TIME:
		var k = t / HOP_TIME
		var ease_k = 1.0 - pow(1.0 - k, 3.0)
		s.position.x = lerpf(w["from_x"], w["dodge_x"], ease_k)
		s.position.y = sin(k * PI) * 0.35 # a quick hop
		s.scale = Vector3(1.0 - 0.06 * sin(k * PI), 1.0 + 0.08 * sin(k * PI), 1.0)
	else:
		s.position.y = 0.0
		s.scale = Vector3.ONE
		# A small startled wobble while they catch their breath.
		s.rotation.z = sin(t * 18.0) * 0.04 * maxf(0.0, 1.0 - (t - HOP_TIME) / 0.5)
	if w["react"] <= 0.0:
		s.rotation.z = 0.0 # update_walkers picks the walking/standing pose again

# Another pose of a person's artwork: <name><suffix>.png beside it (e.g. _walk, _scared),
# or the artwork itself if that pose doesn't exist.
var variant_cache: Dictionary = {}
func variant_texture(tex: Texture2D, suffix: String) -> Texture2D:
	var key = tex.resource_path + suffix
	if not variant_cache.has(key):
		var path = tex.resource_path.get_basename() + suffix + ".png"
		variant_cache[key] = load(path) if ResourceLoader.exists(path) else tex
	return variant_cache[key]

func update_checkpoint(ev: Dictionary, pz: float) -> float:
	var officer: Sprite3D = ev["officer"]
	var oz = ev["z_start"] + ev["officer_z_local"]
	var dist = pz - ev["z_start"]
	# Owner: the warning comes close to the cones, ~90 m before the first one (its flare
	# starts 3 m before z_start): about 3.5-4.5 s of driving to get into the coned lane.
	if not ev["decided"] and dist < CHECKPOINT_WARN_AHEAD + CONES_FROM + 9.0:
		ev["decided"] = true
		ev["flagged"] = randf() < checkpoint_flag_chance
		if ev["flagged"]:
			officer.texture = OFFICER_STOP
			officer.pixel_size = 1.8 / OFFICER_STOP.get_height()
			officer.offset = Vector2(0, OFFICER_STOP.get_height() * 0.5)
			GameState.announce("POLICE CHECKPOINT!\nPull into the coned lane", "police")
			Sfx.play("siren", -10.0)
	# The officer's arm: a sweeping wave, or a firm stop signal.
	officer.rotation.z = sin(time * (7.0 if not ev["flagged"] else 2.0)) * (0.06 if not ev["flagged"] else 0.02)
	if ev["flagged"] and not ev["checked"] and not ev["ran"]:
		var inside = player.position.x > CHECK_LANE_X and pz <= ev["z_start"] + CONES_FROM
		if inside and pz <= oz + 2.0 and pz >= oz - 4.0:
			ev["checked"] = true
			player.stop_for(2.8, "police")
		elif pz < oz - 4.0:
			ev["ran"] = true
			if police:
				police.start_police(run_checkpoint_fine, "YOU RAN THE CHECKPOINT!", false)
	# Everyone eases off approaching a police check.
	if pz <= ev["z_start"] + 60.0 and pz >= ev["z_start"] + CONES_TO:
		return 16.0
	return INF

func shake(amount: float):
	var rig = get_node_or_null("../CameraRig")
	if rig:
		rig.shake(amount)

# ------------------------------------------------------------------ procedural assets

# Yellow/black painted hump stripes.
func make_bump_texture() -> ImageTexture:
	var img = Image.create(64, 16, true, Image.FORMAT_RGB8)
	for y in 16:
		for x in 64:
			img.set_pixel(x, y, Color(0.95, 0.78, 0.1) if (x / 16) % 2 == 0 else Color(0.08, 0.08, 0.08))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# Traffic cone: orange body with a white reflective band.
func make_cone_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var body = CylinderMesh.new()
	body.top_radius = 0.03
	body.bottom_radius = 0.17
	body.height = 0.7
	body.radial_segments = 8
	var orange = StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.42, 0.05)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lifted(body.get_mesh_arrays(), 0.35))
	mesh.surface_set_material(0, orange)
	var band = CylinderMesh.new()
	band.top_radius = 0.1
	band.bottom_radius = 0.12
	band.height = 0.12
	band.radial_segments = 8
	var white = StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lifted(band.get_mesh_arrays(), 0.4))
	mesh.surface_set_material(1, white)
	return mesh

# Primitive meshes are centred on the origin; raise one so it sits on the ground.
func lifted(arrays: Array, dy: float) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += dy
	arrays[Mesh.ARRAY_VERTEX] = v
	return arrays
