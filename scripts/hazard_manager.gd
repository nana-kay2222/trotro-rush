extends Node3D

# Potholes (GAMEPLAY_SPEC §15): static hazards painted into the lanes, avoided only by
# steering. Hitting one damages the trotro. At least one lane stays open (potholes and
# traffic together). FULL-load damage multiplier arrives with the passenger phase.

const LANES := [-3.67, 0.0, 3.67]
const POTHOLE_TEX := preload("res://assets/environment/pothole_decal.png")

@export var pool_size: int = 10
@export var spawn_interval: float = 2.8
@export var spawn_ahead_min: float = 150.0
@export var spawn_ahead_max: float = 220.0
@export var pothole_damage: float = 12.0
@export var clear_band: float = 18.0 # a lane counts as blocked by anything within this span

const HIT_HALF_WIDTH := 1.25 # player half-width + pothole radius
const HIT_BODY_LENGTH := 4.4 # the trotro's length, forward from its rear bumper

var pool: Array = []
var spawn_timer: float = 0.0
var material: StandardMaterial3D

@onready var player = get_node("../PlayerTrotro")
@onready var traffic = get_node_or_null("../Traffic")

# The artwork is drawn as a driver sees it (far inside wall lit, near edge in shadow), so
# every pothole keeps the same facing, only slightly turned, with the far wall ahead.
# Laid out stretched along the road like pavement 3D art: the chase camera sees the road
# at a shallow angle (~18 degrees at 12 m), which squashes it back to the painted view.
const POTHOLE_SIZE := 2.2 # width across the road
const POTHOLE_LENGTH := 4.2 # along the road

func _ready():
	material = StandardMaterial3D.new()
	material.albedo_texture = POTHOLE_TEX
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.roughness = 1.0
	material.albedo_color = Color(0.7, 0.66, 0.62) # tone the laterite down to road-dirt levels
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var rubble = make_rubble_mesh()
	for i in pool_size:
		var p = MeshInstance3D.new()
		var q = PlaneMesh.new()
		q.size = Vector2(POTHOLE_SIZE, POTHOLE_LENGTH)
		p.mesh = q
		p.material_override = material
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Broken asphalt heaped round the rim: real 3D edges that sell the depth.
		var r = MeshInstance3D.new()
		r.mesh = rubble
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.scale = Vector3(1.0, 1.0, POTHOLE_LENGTH / POTHOLE_SIZE) # follow the oval rim
		p.add_child(r)
		p.visible = false
		p.set_meta("active", false)
		p.set_meta("hit", false)
		p.set_meta("lane", 0)
		add_child(p)
		pool.append(p)
	var streamer = get_node_or_null("../WorldStreamer")
	if streamer:
		streamer.rebased.connect(func(shift): for p in pool: p.position.z += shift)

func _process(delta: float):
	if GameState.is_over:
		return
	spawn_timer += delta
	# Gentle difficulty ramp: potholes get more frequent over the first ~4 km.
	var ramp = clampf(GameState.distance / 4000.0, 0.0, 1.0)
	if auto_spawn and spawn_timer >= spawn_interval * lerpf(1.4, 0.85, ramp):
		spawn_timer = 0.0
		try_spawn(player.position.z - randf_range(spawn_ahead_min, spawn_ahead_max))
	for p in pool:
		if p.get_meta("active") and p.position.z > player.position.z + 15.0:
			p.set_meta("active", false)
			p.visible = false
	check_hits()

var auto_spawn: bool = true # off in the tutorial, which places its own pothole

func place_pothole(x: float, z: float) -> Node3D:
	for p in pool:
		if not p.get_meta("active"):
			p.position = Vector3(x, 0.015, z)
			p.set_meta("lane", LANES.find(x))
			p.set_meta("active", true)
			p.set_meta("hit", false)
			p.visible = true
			return p
	return null

func try_spawn(z: float):
	var events = get_node_or_null("../RoadEvents")
	if events and events.zone_overlaps(z + 5.0, z - 5.0):
		return # keep potholes out of go-slows, markets and checkpoints
	var p = null
	for c in pool:
		if not c.get_meta("active"):
			p = c
			break
	if p == null:
		return
	var lane = randi() % LANES.size()
	if near_stop(lane, z):
		return
	var blocked = {lane: true}
	for c in pool:
		if c.get_meta("active") and absf(c.position.z - z) < clear_band:
			blocked[c.get_meta("lane")] = true
	if traffic:
		for car in traffic.pool:
			if car.active and absf(car.position.z - z) < clear_band:
				blocked[car.lane] = true
	if blocked.size() >= LANES.size():
		return # would close every lane
	p.position = Vector3(LANES[lane] + randf_range(-0.6, 0.6), 0.015, z)
	p.rotation.y = randf_range(-0.12, 0.12)
	p.set_meta("lane", lane)
	p.set_meta("active", true)
	p.set_meta("hit", false)
	p.visible = true

# No potholes in the outer lane beside a bus stop or mechanic, from just before its
# entrance to its end: that's the lane the trotro swings through to pull in and out.
func near_stop(lane: int, z: float) -> bool:
	var pickups = get_node_or_null("../Pickups")
	if pickups == null or lane == 1:
		return false
	var side = -1.0 if lane == 0 else 1.0
	for bay in pickups.bays:
		if bay["side"] == side and z <= bay["z_near"] + 25.0 and z >= bay["z_near"] - pickups.BAY_LENGTH - 10.0:
			return true
	return false

func check_hits():
	for p in pool:
		if not p.get_meta("active") or p.get_meta("hit"):
			continue
		# The trotro's body runs from its rear bumper (position.z) forward 4.4 m: a pothole
		# counts once its middle is anywhere under that, never after the trotro has passed it.
		var ahead = player.position.z - p.position.z # how far the pothole is ahead of the rear bumper
		if absf(player.position.x - p.position.x) < HIT_HALF_WIDTH and ahead > 0.0 and ahead < HIT_BODY_LENGTH:
			p.set_meta("hit", true)
			if player.is_shielded():
				continue # the turbo shield takes it (it only breaks on cars)
			GameState.apply_damage(pothole_damage, "pothole")
			player.on_pothole()
			Sfx.play("pothole", 2.0, 0.8) # a deeper, heavier thud
			var rig = get_node_or_null("../CameraRig")
			if rig:
				rig.shake(0.38)

# Chunks of broken asphalt around a pothole's rim (merged into one mesh, shared by all
# potholes; each pothole spins to a random angle so they don't look alike).
func make_rubble_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var n = 14
	for i in n:
		var a = TAU * i / n + rng.randf_range(-0.15, 0.15)
		var rad = POTHOLE_SIZE * 0.44 + rng.randf_range(-0.05, 0.08)
		var c = Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var size = Vector3(rng.randf_range(0.14, 0.3), rng.randf_range(0.04, 0.09), rng.randf_range(0.1, 0.2))
		add_chunk(st, c, size, a + rng.randf_range(-0.4, 0.4), rng.randf_range(-0.35, 0.1))
	st.generate_normals()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.21)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # chunk faces aren't consistently wound
	st.set_material(mat)
	return st.commit()

# A slab of asphalt tilted so its inner edge dips toward the hole.
func add_chunk(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float, tilt: float):
	var basis = Basis(Vector3.UP, -yaw) * Basis(Vector3.FORWARD, tilt)
	var h = size * 0.5
	var corners = []
	for sx in [-1.0, 1.0]:
		for sy in [0.0, 2.0]:
			for sz in [-1.0, 1.0]:
				corners.append(c + basis * Vector3(sx * h.x, sy * h.y, sz * h.z))
	# Faces as corner-index quads: bottom, top, and the four sides.
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for tri in [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]:
			for k in tri:
				st.add_vertex(corners[k])
