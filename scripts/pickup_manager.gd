extends Node3D

# Passenger pickups at roadside bus-stop pockets (GAMEPLAY_SPEC §6-13, §19).
# - Pockets sit beside the 3 lanes on either side (random, never strict alternation).
#   They are not a 4th lane: the trotro may only steer into one while it is alongside.
# - Pickup is automatic and proximity based: inside the pocket, close to the passenger,
#   before passing them. The trotro stops briefly on its own while they board.
# - Fare is paid at pickup and the trotro becomes FULL. A FULL trotro drops its
#   passengers at the next pocket it pulls into (owner decision); at a pocket with someone
#   waiting, the drop-off and the new pickup happen in the same stop.
# - Passing the passenger misses the fare; nothing else happens.
# - Swinging in at the last moment gives a short speed boost.

const ROAD_EDGE := 5.5
const BAY_OUTER := 9.0
const BAY_CENTRE := 7.3
const BAY_LENGTH := 36.0
const PASSENGER_FROM_NEAR := 24.0 # passenger stands this far into the pocket
const PICKUP_RADIUS := 4.0
const IN_BAY_X := 5.6 # trotro centre beyond this = inside the pocket
const LATE_ENTRY_FRACTION := 0.35 # entered with less than this share of the approach left = skill pickup
const BOARD_SECONDS := 1.3
const DROP_SECONDS := 1.0
const BOOST_SECONDS := 2.5

const DESTINATIONS := ["Circle", "Kaneshie", "Madina", "Lapaz", "Achimota", "Tema Station", "Accra Central", "Kasoa", "Spintex", "Dansoman", "Nima", "Osu"]
# Passengers' calls (owner's wording). The voiced ones depend on who's at the front of the
# group: women "Trotro! Trotro!", men "Bossu, stop stop!". Destination calls stay silent.
const CITY_CALLOUTS := ["Driver, %s!", "%s!", "Please, %s!", "%s, %s!"]
const PASSENGER_TEXTURES := [
	preload("res://assets/characters/passenger_man_wave.png"),
	preload("res://assets/characters/passenger_woman_wave.png"),
	preload("res://assets/characters/passenger_student_wave.png"),
	preload("res://assets/characters/passenger_headload_wave.png"),
	preload("res://assets/characters/passenger_elder_wave.png"),
	preload("res://assets/characters/passenger_office_wave.png"),
]
# Women: the kente dress, the headload seller, the office worker (men: kente shirt,
# schoolboy, elder).
func is_female(tex: Texture2D) -> bool:
	var f = tex.resource_path.get_file()
	return f.begins_with("passenger_woman") or f.begins_with("passenger_headload") or f.begins_with("passenger_office")
const SIGN_TEXTURE := preload("res://assets/props/bus_stop_sign.png")

@export var first_bay_ahead: float = 170.0
@export var spacing_min: float = 170.0 # (was 230-380: a day held only ~5 waiting groups)
@export var spacing_max: float = 260.0
@export var passenger_chance: float = 0.9
@export var fare_min: int = 4 # per head
@export var fare_max: int = 7
const FARE_BONUS := 1.15 # owner: every fare paid +15%, rounded to the nearest cedi

# Owner rule: slightly more stops from day 4: 3% closer together each day, at most 15%
# (day 8 on: every ~145-220 m instead of 170-260 m).
func spacing_scale() -> float:
	return 1.0 - clampf(0.03 * (GameState.day - 3), 0.0, 0.15)

var bays: Array = []
var next_bay_z: float = 0.0
var last_side: float = 0.0
var same_side_count: int = 0
var bay_material: StandardMaterial3D
var line_material: StandardMaterial3D
var time: float = 0.0
var bays_spawned: int = 0

@export var rival_chance: float = 0.14 # per waiting stop, on top of the guaranteed one a day

# Roadside fitter (owner-approved): some right-hand pockets are a mechanic instead of a
# bus stop. Pull in and he works on the trotro for a few seconds: +30 health, never past
# 80%, for GHS 15. If the trotro can't afford it, he waves it on (no negative balance).
const MECHANIC_TEXTURE := preload("res://assets/characters/mechanic_wave.png")
const FITTER_LENGTH := 38.0 # covers the whole 36 m pocket
const FITTER_X := 9.35 # road wall on the roadside building line, just behind the pocket

# Bus-stop shelters (owner: 3D like the surroundings, three along each stop): steel posts,
# a curved corrugated roof painted blue with a yellow fascia, and a slatted bench. Built
# once as a mesh for the right-hand side; a left-hand stop uses a mirrored copy.
const SHELTER_LENGTH := 9.0
const SHELTER_FRONT_X := 8.15 # roof edge toward the road (the trotro's side reaches ~8.15)
const SHELTER_BACK_X := 9.3
const SHELTER_HEIGHT := 2.7
static var shelter_mesh: ArrayMesh

func add_shelters(root: Node3D, s: float):
	if shelter_mesh == null:
		shelter_mesh = make_shelter_mesh()
	for i in 3:
		var m = MeshInstance3D.new()
		m.mesh = shelter_mesh
		# Spread along the 36 m pocket; the middle one covers where passengers wait (~24 m in).
		m.position = Vector3(0, 0.23, -4.5 - i * (SHELTER_LENGTH + 2.0))
		m.scale = Vector3(s, 1, 1) # mirrored on the left (materials are double-sided)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.visibility_range_end = GameState.view_range
		root.add_child(m)

func make_shelter_mesh() -> ArrayMesh:
	var steel = shelter_mat(Color(0.12, 0.33, 0.66))
	var yellow = shelter_mat(Color(0.98, 0.78, 0.12))
	var wood = shelter_mat(Color(0.55, 0.33, 0.18))
	var roof = BuildingKit.roof_material(Color(0.16, 0.42, 0.78))
	var posts = SurfaceTool.new(); posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim = SurfaceTool.new(); trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bench = SurfaceTool.new(); bench.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sheet = SurfaceTool.new(); sheet.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L = SHELTER_LENGTH
	var fx = SHELTER_FRONT_X + 0.35 # front posts stand a little in from the roof edge
	for z in [0.0, -L * 0.5, -L]:
		box(posts, Vector3(fx, 0, z), Vector3(0.1, SHELTER_HEIGHT, 0.1))
		box(posts, Vector3(SHELTER_BACK_X, 0, z), Vector3(0.1, SHELTER_HEIGHT - 0.2, 0.1))
	# Curved roof: an arc from the back (lower) over to the front edge, along the shelter.
	var n = 8
	var pts = []
	for i in n + 1:
		var t = float(i) / n
		var x = lerpf(SHELTER_BACK_X + 0.15, SHELTER_FRONT_X, t)
		var y = SHELTER_HEIGHT - 0.25 + sin(t * PI * 0.85) * 0.45
		pts.append(Vector2(x, y))
	for i in n:
		var a = pts[i]; var b = pts[i + 1]
		var quad = [Vector3(a.x, a.y, 0.2), Vector3(b.x, b.y, 0.2), Vector3(b.x, b.y, -L - 0.2), Vector3(a.x, a.y, -L - 0.2)]
		var uvs = [Vector2(0, i * 0.4), Vector2(0, (i + 1) * 0.4), Vector2((L + 0.4) / 1.2, (i + 1) * 0.4), Vector2((L + 0.4) / 1.2, i * 0.4)]
		for k in [0, 1, 2, 0, 2, 3]:
			sheet.set_uv(uvs[k])
			sheet.add_vertex(quad[k])
	# Yellow fascia along the front edge of the roof, and a beam along the back.
	var front = pts[n]
	box(trim, Vector3(front.x, front.y - 0.1, -L * 0.5), Vector3(0.06, 0.2, L + 0.4), true)
	box(trim, Vector3(SHELTER_BACK_X, SHELTER_HEIGHT - 0.32, -L * 0.5), Vector3(0.12, 0.12, L), true)
	# Slatted bench against the back, plus its legs.
	for i in 3:
		box(bench, Vector3(SHELTER_BACK_X - 0.55 + i * 0.13, 0.45, -L * 0.5), Vector3(0.1, 0.04, L - 1.6), true)
	for i in 2:
		box(bench, Vector3(SHELTER_BACK_X - 0.08, 0.6 + i * 0.16, -L * 0.5), Vector3(0.04, 0.1, L - 1.6), true)
	for z in [-1.2, -L * 0.5, -L + 1.2]:
		box(posts, Vector3(SHELTER_BACK_X - 0.4, 0, z), Vector3(0.06, 0.45, 0.06))
	var mesh = ArrayMesh.new()
	for pair in [[posts, steel], [trim, yellow], [bench, wood], [sheet, roof]]:
		pair[0].generate_normals()
		pair[0].set_material(pair[1])
		pair[0].commit(mesh)
	return mesh

# Box of the given size: standing on p (base centre), or centred on p when `centred`.
func box(st: SurfaceTool, p: Vector3, size: Vector3, centred: bool = false):
	var lo = p - Vector3(size.x * 0.5, size.y * 0.5 if centred else 0.0, size.z * 0.5)
	var hi = lo + size
	var c = [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c[f[k]])

func shelter_mat(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
const REPAIR_COST := 15
const REPAIR_AMOUNT := 30.0
const REPAIR_CAP := 80.0
const REPAIR_SECONDS := 3.0
const MECHANIC_BLUE := Color(0.25, 0.65, 1.0) # the fitter's markings (bus stops are yellow)
const MECHANIC_FROM_NEAR := 12.0 # the fitter stands this far into his pocket
var mechanic_line_material: StandardMaterial3D
@export var mechanic_chance: float = 0.2 # about one stop in five
@export var mechanic_chance_damaged: float = 0.6 # when health is under half
var bays_since_mechanic: int = 0
const RIVAL_SPEED_FACTOR := 0.85 # slower than the trotro, so it can be overtaken before the stop
const RIVAL_BRAKE_DISTANCE := 16.0

@onready var player = get_node("../PlayerTrotro")
@onready var traffic = get_node_or_null("../Traffic")
@onready var events = get_node_or_null("../RoadEvents")

func _ready():
	bay_material = StandardMaterial3D.new()
	bay_material.albedo_texture = load("res://assets/environment/asphalt_accra.png")
	bay_material.albedo_color = Color(0.62, 0.6, 0.58)
	bay_material.uv1_scale = Vector3(0.9, 9.0, 1)
	bay_material.roughness = 0.95
	line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 0.82, 0.1)
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mechanic_line_material = line_material.duplicate()
	mechanic_line_material.albedo_color = MECHANIC_BLUE
	next_bay_z = player.position.z - first_bay_ahead
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.rebased.connect(_on_rebased)

var auto_spawn: bool = true # off in the tutorial, which places its own stops

func _process(delta: float):
	time += delta
	if GameState.is_over:
		return
	if auto_spawn and player.position.z - next_bay_z < 300.0:
		var was_mechanic = spawn_bay(next_bay_z)
		# A mechanic is an extra stop slotted in between bus stops (it used to take a bus
		# stop's place, which starved later days of passengers): the next bus stop follows
		# a short way after it.
		next_bay_z -= randf_range(120.0, 160.0) if was_mechanic else randf_range(spacing_min, spacing_max) * spacing_scale()
	update_limits()
	for bay in bays.duplicate():
		update_bay(bay, delta)

# ------------------------------------------------------------------ spawning

func pick_side() -> float:
	var side = -1.0 if randf() < 0.5 else 1.0
	if side == last_side and same_side_count >= 2:
		side = -side
	same_side_count = same_side_count + 1 if side == last_side else 1
	last_side = side
	return side

# Returns true if it placed a mechanic stop. The tutorial forces the kind ("bus" or
# "mechanic") and the side.
func spawn_bay(z_near: float, force_kind: String = "", force_side: float = 0.0) -> bool:
	# No bus stop inside a road event (go-slow, market, checkpoint).
	if force_kind == "" and events and events.zone_overlaps(z_near, z_near - BAY_LENGTH):
		return false
	var chance = mechanic_chance_damaged if GameState.health < GameState.MAX_HEALTH * 0.5 else mechanic_chance
	var mechanic = bays_spawned >= 2 and bays_since_mechanic >= 2 and GameState.health < REPAIR_CAP and randf() < chance
	if force_kind != "":
		mechanic = force_kind == "mechanic"
	bays_since_mechanic = 0 if mechanic else bays_since_mechanic + 1
	var side = 1.0 if mechanic else (force_side if force_side != 0.0 else pick_side())
	var root = Node3D.new()
	root.position = Vector3(0, 0, z_near)
	add_child(root)
	if mechanic:
		build_pocket(root, side, "MECHANIC", false, mechanic_line_material, MECHANIC_BLUE)
	else:
		build_pocket(root, side)
		add_shelters(root, side) # three along the stop, over where people wait
	if side > 0.0: # the power poles stand on the right-hand walkway
		var streamer = get_node_or_null("../WorldStreamer")
		if streamer:
			streamer.clear_poles(z_near, z_near - BAY_LENGTH - (8.0 if mechanic else 0.0))
	var bay = {
		"node": root, "side": side, "z_near": z_near, "passenger": null, "label": null,
		"state": "empty", "entered": false, "late": false, "dropped": false, "wave_phase": randf() * TAU,
	}
	if mechanic:
		add_mechanic(bay)
		bays_spawned += 1
		bays.append(bay)
		return true
	if force_kind == "bus" or randf() < passenger_chance:
		add_passenger(bay)
		# Rare rival trotro racing for this passenger (GAMEPLAY_SPEC §18).
		bay["rival_planned"] = bays_spawned >= 2 and randf() < rival_chance
	bays_spawned += 1
	bays.append(bay)
	return false

func build_pocket(root: Node3D, s: float, painted: String = "BUS STOP", with_sign: bool = true,
		lines: Material = null, paint_color: Color = Color(1.0, 0.85, 0.15)):
	if lines == null:
		lines = line_material
	var mid = -BAY_LENGTH * 0.5
	# Raised lay-by surface over the kerb/drain/walkway, with a ramp up from the road.
	add_flat(root, bay_material, (ROAD_EDGE - 0.05 + BAY_OUTER) * 0.5 * s, 0.23, BAY_OUTER - ROAD_EDGE + 0.05, BAY_LENGTH, mid)
	var ramp = MeshInstance3D.new()
	var rq = PlaneMesh.new()
	rq.size = Vector2(0.45, BAY_LENGTH)
	ramp.mesh = rq
	ramp.material_override = bay_material
	ramp.position = Vector3(s * (ROAD_EDGE - 0.2), 0.115, mid)
	ramp.rotation.z = -s * atan2(0.23, 0.45)
	root.add_child(ramp)
	# Bay markings (yellow for a bus stop, blue for the fitter): outer edge and both ends.
	add_flat(root, lines, s * (BAY_OUTER - 0.12), 0.235, 0.14, BAY_LENGTH, mid)
	for z in [-0.1, -BAY_LENGTH + 0.1]:
		add_flat(root, lines, (ROAD_EDGE + BAY_OUTER) * 0.5 * s, 0.235, BAY_OUTER - ROAD_EDGE, 0.14, z)
	# Painted "BUS STOP" on the pocket surface, readable from the approaching trotro.
	var paint = Label3D.new()
	paint.text = painted
	paint.font_size = 96
	paint.outline_size = 0
	paint.modulate = paint_color
	paint.pixel_size = 0.0075
	paint.scale = Vector3(1.0, 2.6, 1.0) # stretched along the road, like real road lettering
	paint.rotation_degrees = Vector3(-90, 0, 0)
	paint.position = Vector3(s * BAY_CENTRE, 0.24, -6.0)
	root.add_child(paint)
	if not with_sign:
		return
	# Sign on a pole at the start of the pocket.
	var sign = Sprite3D.new()
	sign.texture = SIGN_TEXTURE
	sign.pixel_size = 3.2 / SIGN_TEXTURE.get_height()
	sign.offset = Vector2(0, SIGN_TEXTURE.get_height() * 0.5)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sign.position = Vector3(s * (BAY_OUTER + 0.25), 0.23, -1.5) # before the first shelter
	root.add_child(sign)

func add_flat(root: Node3D, mat: Material, cx: float, y: float, w: float, l: float, cz: float):
	var mi = MeshInstance3D.new()
	var q = PlaneMesh.new()
	q.size = Vector2(w, l)
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(cx, y, cz)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

# The fitter waves a spanner at the pocket's edge where the trotro stops; his shack stands
# on the walkway just past the pocket.
func add_mechanic(bay: Dictionary):
	var s: float = bay["side"]
	var m = Sprite3D.new()
	m.texture = MECHANIC_TEXTURE
	m.pixel_size = 1.75 / MECHANIC_TEXTURE.get_height()
	m.offset = Vector2(0, MECHANIC_TEXTURE.get_height() * 0.5)
	m.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	m.shaded = true
	m.position = Vector3(s * (BAY_OUTER - 0.35), 0.23, -MECHANIC_FROM_NEAR)
	bay["node"].add_child(m)
	# His callout, in the stop's blue (passenger callouts are yellow).
	var label = Label3D.new()
	label.text = "Chale, come fix your car!" # the owner's recording says this
	label.font_size = 96
	label.outline_size = 22
	label.outline_modulate = Color(0.02, 0.05, 0.15)
	label.modulate = Color(0.55, 0.82, 1.0)
	label.pixel_size = 0.018
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = m.position + Vector3(-s * 1.2, 3.0, 0)
	label.visible = false
	bay["node"].add_child(label)
	bay["label"] = label
	bay["from_near"] = MECHANIC_FROM_NEAR
	# His workshop: one 3D building (like the roadside ones) along the whole stop. The
	# random roadside buildings give it the frontage.
	var shop = MeshInstance3D.new()
	shop.mesh = BuildingKit.get_mesh("stop_fitter", s, FITTER_LENGTH)
	shop.position = Vector3(s * FITTER_X, 0, 1.0)
	shop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shop.visibility_range_end = GameState.view_range
	bay["node"].add_child(shop)
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.clear_frontage(bay["z_near"] + 3.0, bay["z_near"] + 1.0 - FITTER_LENGTH - 2.0, s)
	bay["kind"] = "mechanic"
	bay["passenger"] = m # waves like a passenger (animate_passenger)
	bay["group"] = [m]
	bay["state"] = "mechanic"
	bay["serviced"] = false

func update_mechanic(bay: Dictionary, inside: bool, pz: float, delta: float):
	if not bay["serviced"]:
		animate_passenger(bay, delta)
	# Once in the blue pocket, the trotro brakes to halt beside the fitter.
	if bay["serviced"] or not inside or pz - passenger_z(bay) > player.braking_distance() + 1.5:
		return
	bay["serviced"] = true
	bay["passenger"].rotation.z = 0.0
	bay["label"].visible = false
	if GameState.health >= REPAIR_CAP:
		return # nothing for him to fix; drive on
	if mini(GameState.score(), GameState.day_sales()) < REPAIR_COST: # never into the red
		GameState.announce("No money for the fitter", "warn")
		return
	var brake_time = player.current_speed / player.STOP_DECEL # the wait starts once stopped
	player.stop_for(REPAIR_SECONDS)
	player.dock(bay["side"] * BAY_CENTRE, false)
	for i in 3: # spanner on metal
		get_tree().create_timer(brake_time + 0.5 + i * 0.8, false).timeout.connect(func(): Sfx.play("pothole", -8.0, 1.8))
	get_tree().create_timer(brake_time + REPAIR_SECONDS - 0.2, false).timeout.connect(func():
		if GameState.is_over:
			return
		GameState.pay_repair(REPAIR_COST, REPAIR_AMOUNT, REPAIR_CAP)
		Sfx.play("coin", -4.0, 0.8)
		GameState.announce("-GHS %d  Repair" % REPAIR_COST, "repair") # in blue, like a fare
		if bay["late"]:
			# Same reward as a bus stop for swinging in at the last moment: a burst of
			# speed as the trotro pulls away (it starts once the wait is over).
			player.start_boost(BOOST_SECONDS)
			get_tree().create_timer(0.2, false).timeout.connect(func():
				Sfx.play("whoosh")
				GameState.announce("LAST-SECOND STOP!  BOOST", "boost")))

# Voices at the stop (owner's recordings): called once as the trotro comes into earshot and
# again closer in, quieter the further away the speaker is (about -6 dB per doubling of the
# distance past 8 m), so they sit in the street, not on top of it.
const CALL_DISTANCES := [55.0, 22.0]
func call_out(bay: Dictionary, voice: String, speaker: String):
	var ahead = player.position.z - passenger_z(bay)
	var n: int = bay.get("calls_made", 0)
	if n >= CALL_DISTANCES.size() or ahead > CALL_DISTANCES[n] or ahead < 0.0:
		return
	bay["calls_made"] = n + 1
	var side = absf(bay["side"] * BAY_OUTER - player.position.x)
	var dist = sqrt(ahead * ahead + side * side)
	var level = -6.0 + (0.55 if speaker == "passenger" else 0.0) # owner: passengers +10%, then -3%
	Sfx.play_voice(voice, -20.0 * log(maxf(dist, 8.0) / 8.0) / log(10.0) + level, speaker)

func add_passenger(bay: Dictionary):
	var s: float = bay["side"]
	var tex: Texture2D = PASSENGER_TEXTURES.pick_random()
	var p = Sprite3D.new()
	p.texture = tex
	p.pixel_size = 1.75 / tex.get_height()
	p.offset = Vector2(0, tex.get_height() * 0.5)
	p.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	p.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	p.shaded = true
	# Stand at the pocket's outer edge, facing the road (flip so the waving arm is roadside).
	p.flip_h = s < 0.0
	p.position = Vector3(s * (BAY_OUTER - 0.35), 0.23, -PASSENGER_FROM_NEAR)
	bay["node"].add_child(p)
	# A group of 1-4 waiting together (15-seat trotro): the others stand around the first.
	var size = [1, 1, 1, 2, 2, 2, 2, 3, 3, 4].pick_random()
	var group = [p]
	for i in range(1, size):
		var t2: Texture2D = PASSENGER_TEXTURES.pick_random()
		var q = Sprite3D.new()
		q.texture = t2
		q.pixel_size = randf_range(1.6, 1.8) / t2.get_height()
		q.offset = Vector2(0, t2.get_height() * 0.5)
		q.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		q.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		q.shaded = true
		q.flip_h = s < 0.0
		q.position = p.position + Vector3(s * randf_range(0.1, 0.6), 0, -1.0 * i + randf_range(-0.2, 0.2))
		bay["node"].add_child(q)
		group.append(q)
	bay["group"] = group
	var dest = DESTINATIONS.pick_random()
	# Half the stops call out loud (the front passenger's own line and recording); the rest
	# show a destination call, silent for now (owner).
	var female = is_female(tex)
	var line: String
	if randf() < 0.5:
		line = "Trotro! Trotro!" if female else "Bossu, stop stop!"
		bay["voice"] = "passenger_female_trotro_trotro" if female else "passenger_male_bossu_stop_stop"
	else:
		line = CITY_CALLOUTS.pick_random()
		line = line % [dest, dest] if line.count("%s") == 2 else line % dest
	var label = Label3D.new()
	label.text = line
	label.font_size = 96
	label.outline_size = 22
	label.outline_modulate = Color(0.08, 0.05, 0.02)
	label.modulate = Color(1.0, 0.93, 0.35)
	label.pixel_size = 0.018 # ~1.7 m tall text: readable from well down the road
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = p.position + Vector3(-s * 1.2, 3.0, 0) # nudged toward the road
	bay["node"].add_child(label)
	bay["passenger"] = p
	bay["label"] = label
	bay["destination"] = dest
	bay["fare"] = randi_range(fare_min, fare_max) # per head
	bay["state"] = "waiting"
	if size > 1:
		label.text = "%s  (x%d)" % [line, size]

# ------------------------------------------------------------------ per frame

func passenger_z(bay: Dictionary) -> float:
	return bay["z_near"] - bay.get("from_near", PASSENGER_FROM_NEAR)

# While a pocket is alongside, the trotro may steer into it on that side only.
func update_limits():
	var left = -3.8
	var right = 3.8
	for bay in bays:
		var pz = player.position.z
		if pz <= bay["z_near"] + 3.0 and pz >= bay["z_near"] - BAY_LENGTH + 4.0:
			if bay["side"] > 0.0:
				right = BAY_CENTRE
			else:
				left = -BAY_CENTRE
	if events:
		var lim: Vector2 = events.lane_limits(player.position.x, player.position.z) # checkpoint cones
		left = maxf(left, lim.x)
		right = minf(right, lim.y)
	player.limit_left = left
	player.limit_right = right

func update_bay(bay: Dictionary, delta: float):
	var s: float = bay["side"]
	var pz = player.position.z
	var inside = player.position.x * s > IN_BAY_X and pz <= bay["z_near"] and pz >= bay["z_near"] - BAY_LENGTH
	# Record how late the trotro swung in (share of the approach still left).
	if inside and not bay["entered"]:
		bay["entered"] = true
		var frac = (pz - passenger_z(bay)) / bay.get("from_near", PASSENGER_FROM_NEAR)
		bay["late"] = frac < LATE_ENTRY_FRACTION

	if bay.get("kind") == "mechanic":
		update_mechanic(bay, inside, pz, delta)
		if not bay["serviced"]:
			call_out(bay, "mechanic_chale_come_fix_your_car", "mechanic")
	else:
		update_rival(bay, delta)
		if bay.has("voice") and bay["state"] == "waiting":
			call_out(bay, bay["voice"], "passenger")
	if bay.get("arriving", false) and bay["state"] != "waiting" and bay["state"] != "picked":
		bay["arriving"] = false # the rival got them first: don't stay parked
		player.stop_timer = 0.0
		player.stop_decel = player.STOP_DECEL
	if bay["state"] == "mechanic":
		pass
	elif bay["state"] == "waiting":
		animate_passenger(bay, delta)
		var dz = pz - passenger_z(bay) # > 0: the passengers are still ahead
		if bay.get("arriving", false):
			# Pulling up beside them; they board once the trotro has stopped.
			if not player.is_stopped():
				bay["arriving"] = false # the player dragged back out (see PlayerTrotro.dock)
			elif player.current_speed < 0.3:
				player.dock_cancelable = false # stopped: they're boarding
				pick_up(bay)
		elif inside and dz > -PICKUP_RADIUS and dz <= player.braking_distance() + 1.5:
			# Start braking now so the trotro halts right beside the waiting passengers, and
			# steer it fully into the pocket while it does.
			bay["arriving"] = true
			player.pull_up_within(dz + 1.0) # held until they've boarded (pick_up sets the wait)
			player.dock(s * BAY_CENTRE, true)
		elif dz < -2.5:
			miss(bay)
	elif inside and GameState.riders > 0 and not bay["dropped"] and pz < bay["z_near"] - BAY_LENGTH * 0.45:
		# No one waiting here: some riders get off.
		bay["dropped"] = true
		var off = drop_some(false)
		player.stop_for(DROP_SECONDS)
		player.dock(s * BAY_CENTRE, false)
		Sfx.play("drop")
		alight(bay, off)

	# Remove pockets well behind the camera.
	if bay["z_near"] - BAY_LENGTH > pz + 25.0:
		remove_bay(bay)

func remove_bay(bay: Dictionary):
	if bay.has("rival") and is_instance_valid(bay["rival"]) and bay["rival"].scripted:
		bay["rival"].scripted = false # hand a still-scripted rival back to traffic
	bay["node"].queue_free()
	bays.erase(bay)

# RoadEvents: a go-slow, market or checkpoint was placed over these pockets (they were
# spawned first, far ahead in the haze), so they go.
func remove_bays_in(z_near: float, z_far: float):
	for bay in bays.duplicate():
		if bay["z_near"] - BAY_LENGTH <= z_near and bay["z_near"] >= z_far and bay["z_near"] < player.position.z - 150.0:
			remove_bay(bay)

# ------------------------------------------------------------------ rival trotro
# (GAMEPLAY_SPEC §18 + owner direction.) A rare rival trotro charges up from BEHIND,
# faster than the player, horn blaring, heading for the same passenger. It weaves around
# the player and traffic rather than ramming anyone. Whoever reaches the passenger first
# gets the fare: the player wins by getting into the pocket before the rival passes.

const LANE_X := [-3.67, 0.0, 3.67]
const RIVAL_SPAWN_BEHIND := 28.0
const RIVAL_EXTRA_SPEED := 5.0
const RIVAL_GAP := 13.0 # how close behind something before it swerves or backs off
# At least one rival a day (owner rule): the day's forced stop and whether one has come yet.
var rival_day: int = -1
var rival_today: bool = false
var stops_reached_today: int = 0
var rival_forced_at: int = 3

# Owner rule: a very slightly more aggressive rival each day: it charges at 1.20x the
# trotro's speed on day 1, +0.01x a day, up to 1.30x (day 11).
func rival_chase_factor() -> float:
	return minf(1.2 + 0.01 * (GameState.day - 1), 1.3)

# Owner rule, against the booster (its speed as a share of the boosted trotro's). Over a
# 5 s boost with the rival ~12 m behind:
#   x1: days 1-4 it falls away; from day 5 it gains (1.04x: a few metres) a bit more each
#       day, and by day 9-10 (1.12-1.14x) it gets past.
#   x2: days 1-5 it falls away; day 6-8 it hangs on (0.96-0.99x), day 9 it creeps closer
#       (1.01x) and from day 10 (1.03x) it can just edge past one that was already close.
func rival_boost_factor(level: int) -> float:
	var d = GameState.day
	if level >= 2:
		return 0.85 if d <= 5 else minf(0.96 + 0.015 * (d - 6), 1.03)
	return 0.85 if d <= 4 else minf(1.04 + 0.02 * (d - 5), 1.14)

# Once it may compete with a boost, it can accelerate as hard as the boost does.
func rival_boost_can_compete(level: int) -> bool:
	return GameState.day >= (6 if level >= 2 else 5)

func update_rival(bay: Dictionary, delta: float):
	var s: float = bay["side"]
	var pz = passenger_z(bay)
	if not bay.has("rival") and bay["state"] == "waiting" and traffic:
		var dist = player.position.z - pz
		if dist < 150.0 and dist > 105.0:
			if not bay.has("rival_counted"):
				# Another stop with people waiting reached today (counted on arrival, not when
				# the stop was laid out, since stops are laid out ahead across day changes).
				bay["rival_counted"] = true
				if GameState.day != rival_day:
					rival_day = GameState.day
					rival_today = false
					stops_reached_today = 0
					# 2nd or 3rd waiting stop: day 1 can hit its target in as few as ~4 stops.
				rival_forced_at = randi_range(2, 3)
				stops_reached_today += 1
			# Owner rule: at least one rival a day. If none has come by the day's forced stop
			# (its 2nd or 3rd waiting stop), this one gets it; the random chance still adds more.
			var forced = not rival_today and stops_reached_today >= rival_forced_at
			if bay.get("rival_planned", false) or forced:
				spawn_rival(bay)
	if not bay.has("rival"):
		return
	var car = bay["rival"]
	if not is_instance_valid(car) or not car.scripted:
		return
	match bay["rival_phase"]:
		"chase":
			var target_speed = maxf(player.current_speed * rival_chase_factor(), player.current_speed + RIVAL_EXTRA_SPEED)
			if player.is_turbo():
				target_speed = player.current_speed * rival_boost_factor(player.turbo.level)
			var want_x = s * 3.67 # the lane beside the stop
			if car.stun > 0.0:
				# Just got bumped: snakes about and drops back behind the trotro.
				car.stun -= delta
				car.speed = move_toward(car.speed, player.current_speed * 0.75, 12.0 * delta)
				car.position.x += sin(time * 18.0) * 2.5 * delta
				car.position.z -= car.speed * delta
				return
			var blocker = blocker_ahead(car, car.position.x)
			if blocker != null:
				# Something in the way: swerve to a clear lane, leaning on the horn.
				var best = find_clear_lane(car)
				if best != INF:
					want_x = best
				else:
					target_speed = minf(target_speed, blocker_speed(blocker) - 0.5)
				honk(bay, car, delta, 0.9)
			var accel = 8.0
			if player.is_turbo() and rival_boost_can_compete(player.turbo.level):
				accel = player.turbo.ACCEL
			car.speed = move_toward(car.speed, target_speed, accel * delta)
			car.position.x = move_toward(car.position.x, want_x, 4.5 * delta)
			rival_pressure(bay, car, delta)
			if bay["state"] != "waiting":
				leave_rival(bay, bay["state"] == "picked")
			elif car.position.z <= bay["z_near"] + 2.0 and car.position.z < player.position.z - 7.0:
				# Only cuts in once clearly ahead, so it never swerves into the trotro.
				bay["rival_phase"] = "enter"
		"enter":
			if car.stun > 0.0:
				bay["rival_phase"] = "chase" # bumped out of its line into the stop
				return
			car.position.x = move_toward(car.position.x, s * BAY_CENTRE, 5.0 * delta)
			if car.position.z - pz < RIVAL_BRAKE_DISTANCE:
				car.speed = move_toward(car.speed, 0.0, 10.0 * delta)
			if bay["state"] != "waiting":
				leave_rival(bay, bay["state"] == "picked")
			elif car.position.z - pz < 1.5:
				# Rival got there first.
				bay["state"] = "rival"
				for p in group_of(bay):
					p.visible = false
				bay["label"].visible = false
				bay["rival_phase"] = "boarding"
				bay["rival_timer"] = 1.0
				GameState.announce("The rival took your passenger!", "warn")
				Sfx.play("horn", -2.0, 1.05)
		"boarding":
			car.speed = 0.0
			bay["rival_timer"] -= delta
			if bay["rival_timer"] <= 0.0:
				leave_rival(bay, false)
		"leave":
			car.speed = move_toward(car.speed, player.max_speed + 4.0, 6.0 * delta)
			var clear = find_clear_lane(car)
			car.position.x = move_toward(car.position.x, clear if clear != INF else s * 3.67, 3.0 * delta)
			bay["rival_timer"] -= delta
			if bay["rival_timer"] <= 0.0:
				# Hand it back to ordinary traffic, speeding off ahead.
				car.scripted = false
				car.escaping = true
				car.cruise_speed = player.max_speed + 4.0
				bay["rival_phase"] = "done"
	if car.scripted:
		car.position.z -= car.speed * delta

func spawn_rival(bay: Dictionary):
	# Start behind the player, in a lane the player isn't in.
	var start_x = LANE_X[0] if player.position.x > 0.0 else LANE_X[2]
	# Rival liveries (owner rule: these trotros only ever appear as rivals).
	var kinds = ["rival_trotro"]
	if traffic.textures.get("rival_trotro_b", {}).has("rear"):
		kinds.append("rival_trotro_b")
	var lane = LANE_X.find(start_x)
	var car = traffic.claim_scripted(kinds.pick_random(), lane, start_x, player.position.z + RIVAL_SPAWN_BEHIND, player.current_speed + RIVAL_EXTRA_SPEED)
	if car == null:
		return
	bay["rival"] = car
	bay["rival_phase"] = "chase"
	rival_today = true
	bay["honk_timer"] = 0.0
	GameState.announce("RIVAL TROTRO BEHIND!", "warn")
	Sfx.play("horn", 0.0)
	shake(0.35)

# Nearby-behind menace: camera rumble and horn blasts while it closes in.
func rival_pressure(bay: Dictionary, car: Node3D, delta: float):
	var behind = car.position.z - player.position.z
	if behind > 0.0 and behind < 18.0:
		shake(0.05 + 0.08 * (1.0 - behind / 18.0))
		honk(bay, car, delta, 1.6)

func honk(bay: Dictionary, car: Node3D, delta: float, interval: float):
	bay["honk_timer"] -= delta
	if bay["honk_timer"] <= 0.0:
		bay["honk_timer"] = interval + 1.2 + randf() * 0.6 # the recorded horn is ~2.8 s long
		var dist = absf(car.position.z - player.position.z)
		Sfx.play("horn", clampf(-dist * 0.25, -14.0, 0.0), randf_range(0.97, 1.04))

func shake(amount: float):
	var rig = get_node_or_null("../CameraRig")
	if rig:
		rig.shake(amount)

# The player or a traffic vehicle within RIVAL_GAP ahead of the rival in its lane.
func blocker_ahead(car: Node3D, x: float) -> Variant:
	var gap_p = car.position.z - player.position.z
	if gap_p > 0.0 and gap_p < RIVAL_GAP and absf(player.position.x - x) < 2.2:
		return player
	for other in traffic.pool:
		if other == car or not other.active:
			continue
		var gap = car.position.z - other.position.z
		if gap > 0.0 and gap < RIVAL_GAP and absf(other.position.x - x) < 2.2:
			return other
	return null

func blocker_speed(b: Node3D) -> float:
	return b.current_speed if b == player else b.speed

func find_clear_lane(car: Node3D) -> float:
	var best = INF
	for x in LANE_X:
		if blocker_ahead(car, x) == null and (best == INF or absf(x - car.position.x) < absf(best - car.position.x)):
			best = x
	return best

func leave_rival(bay: Dictionary, player_won: bool):
	if player_won:
		GameState.announce("You beat the rival!", "boost")
	else:
		Sfx.play("horn", -3.0, 1.08) # a cheeky parting honk
	bay["rival_phase"] = "leave"
	bay["rival_timer"] = 3.0

# For the HUD: an active rival still chasing, with how far behind (+) or ahead (-) it is.
func rival_info() -> Dictionary:
	for bay in bays:
		if bay.has("rival") and bay.get("rival_phase", "") in ["chase", "enter"]:
			var car = bay["rival"]
			if is_instance_valid(car):
				return {"behind": car.position.z - player.position.z, "id": car.get_instance_id()}
	return {}

func animate_passenger(bay: Dictionary, delta: float):
	bay["wave_phase"] += delta * 9.0
	var i = 0
	for p in group_of(bay):
		var ph = bay["wave_phase"] + i * 1.3 # each waves on their own beat
		p.rotation.z = sin(ph) * 0.07
		p.position.y = 0.23 + absf(sin(ph * 0.5)) * 0.06
		i += 1
	var label: Label3D = bay["label"]
	if label == null:
		return # the mechanic has no callout
	var dist = player.position.z - passenger_z(bay)
	label.visible = dist < 160.0 and dist > -2.0
	# Big enough to read from far off, shrinking as the trotro closes in so it never
	# swamps the screen.
	var near_scale = clampf(dist / 55.0, 0.35, 1.0)
	label.scale = Vector3.ONE * near_scale * (1.0 + 0.08 * sin(time * 6.0))

# Riders getting off at a stop. Where people are boarding, only a few get off (often
# nobody), so the trotro fills up over several stops; at a stop with no one waiting,
# a bigger share gets off (at least one). A full trotro always frees at least one seat.
func drop_some(boarding_stop: bool = true) -> int:
	if GameState.riders == 0:
		return 0
	var share = randf_range(0.0, 0.3) if boarding_stop else randf_range(0.25, 0.5)
	var n = int(round(GameState.riders * share))
	if not boarding_stop or GameState.is_full:
		n = maxi(1, n)
	return GameState.alight(n)

func group_of(bay: Dictionary) -> Array:
	return bay.get("group", [bay["passenger"]])

func pick_up(bay: Dictionary):
	bay["state"] = "picked"
	bay["label"].visible = false
	var stop_time = BOARD_SECONDS
	# Same stop: some riders get off first, making room.
	var off = drop_some()
	if off > 0:
		stop_time += DROP_SECONDS * 0.5
		alight(bay, off)
	# This stop is used up: the ones who just boarded ride to a later stop.
	bay["dropped"] = true
	var group = group_of(bay)
	var boarded = GameState.board(group.size())
	# Those who got a seat step over to the trotro and climb in; anyone left waits on.
	var door_x = player.position.x + bay["side"] * 0.9
	for i in group.size():
		var p: Sprite3D = group[i]
		p.rotation.z = 0.0
		if i >= boarded:
			p.modulate = Color(0.8, 0.8, 0.8) # no seat for them
			continue
		p.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED # allow a smooth fade
		var t = create_tween().set_parallel()
		t.tween_property(p, "position:x", door_x, BOARD_SECONDS * 0.8).set_delay(i * 0.15)
		t.tween_property(p, "modulate:a", 0.0, BOARD_SECONDS * 0.4).set_delay(BOARD_SECONDS * 0.5 + i * 0.15)
		t.chain().tween_callback(func(): p.visible = false)
	var fare: int = roundi(bay["fare"] * boarded * FARE_BONUS)
	GameState.add_fare(fare, boarded)
	player.stop_timer = stop_time # replaces the hold set while pulling up
	player.reset_to_base_speed()
	var who = "%s" % bay["destination"] if boarded == 1 else "%d x %s" % [boarded, bay["destination"]]
	GameState.announce("+GHS %d  %s" % [fare, who], "fare")
	if boarded < group.size():
		GameState.announce("Trotro full! %d left behind" % (group.size() - boarded), "warn")
	Sfx.play("coin")
	if bay["late"]:
		# Boost starts when the trotro pulls away again.
		get_tree().create_timer(stop_time).timeout.connect(func():
			if is_instance_valid(player):
				player.start_boost(BOOST_SECONDS)
				Sfx.play("whoosh")
				GameState.announce("LAST-SECOND PICKUP!  BOOST", "boost"))

# Drop-off: the riders getting off step out of the trotro and walk off the pocket
# (up to 3 shown, to keep it light).
func alight(bay: Dictionary, count: int = 2):
	var s: float = bay["side"]
	var root: Node3D = bay["node"]
	for i in mini(count, 3):
		var tex: Texture2D = PASSENGER_TEXTURES.pick_random()
		var p = Sprite3D.new()
		p.texture = tex
		p.pixel_size = 1.75 / tex.get_height()
		p.offset = Vector2(0, tex.get_height() * 0.5)
		p.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		p.shaded = true
		p.flip_h = s > 0.0
		# Start at the trotro's kerb-side door, in the bay node's local space.
		p.position = Vector3(player.position.x + s * 0.9, 0.23, player.position.z - root.position.z - 1.0 - i * 1.2)
		root.add_child(p)
		var t = create_tween().set_parallel()
		t.tween_property(p, "position:x", s * (BAY_OUTER + 1.5 + i), 1.8).set_delay(0.3 + i * 0.35)
		t.tween_property(p, "modulate:a", 0.0, 0.6).set_delay(1.6 + i * 0.35)
		t.chain().tween_callback(p.queue_free)

func miss(bay: Dictionary):
	bay["state"] = "missed"
	bay["label"].visible = false
	for p in group_of(bay):
		p.rotation.z = 0.0
		p.modulate = Color(0.8, 0.8, 0.8)

func _on_rebased(shift: float):
	next_bay_z += shift
	for bay in bays:
		bay["z_near"] += shift
		bay["node"].position.z += shift

# For the HUD: the next passenger still waiting ahead, or {} if none is near.
func next_passenger_info() -> Dictionary:
	for bay in bays:
		var mechanic = bay["state"] == "mechanic" and not bay["serviced"] and GameState.health < REPAIR_CAP
		if bay["state"] != "waiting" and not mechanic:
			continue
		var dist = player.position.z - passenger_z(bay)
		if dist > 0.0 and dist < 200.0:
			if mechanic:
				return {"side": bay["side"], "distance": dist, "destination": "Mechanic", "mechanic": true}
			return {"side": bay["side"], "distance": dist, "destination": bay["destination"]}
	return {}
