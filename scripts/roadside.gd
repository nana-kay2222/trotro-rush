extends Node3D

# Lines one road segment with buildings on both sides (GAME_SPEC Â§19: varied, dense
# Accra roadside, not repeated generic assets). Called again whenever the segment is
# recycled ahead, so the street changes instead of looping.

const FRONT_X := 9.35 # road-facing walls start just behind the walkway
const Z_NEAR := 60.0
const Z_FAR := -300.0
const MOSQUE_SCENE := preload("res://scenes/mosque.tscn")
# The hand-built mosque's footprint in its own space: road wall at x = -5.27 (it was
# authored for the right side), z from +10.6 (near) to -12.5.
const MOSQUE_ROAD_X := 5.27
const MOSQUE_NEAR_Z := 10.6
const MOSQUE_LENGTH := 23.1
# How far ahead roadside pieces are drawn: GameState.view_range (shorter on phones).

var rng := RandomNumberGenerator.new()
var recent: Array = []

func _ready():
	rng.randomize()
	populate(false)

# spread = build a few pieces per frame (a recycled stretch far ahead, mid-run); building
# a whole stretch in one frame caused a visible hitch. At startup it's built at once.
const PIECES_PER_FRAME := 6
var pieces_this_frame: int = 0
var build_id: int = 0

func populate(spread: bool = true):
	build_id += 1
	var my_build = build_id
	for c in get_children():
		c.queue_free()
	var kit = BuildingKit.load_meta()
	if kit.is_empty():
		return
	# "stop_" buildings (the fitter) only ever stand at their own stops.
	var names = kit.keys().filter(func(n): return not n.begins_with("stop_"))
	var mosque_placed = false
	pieces_this_frame = 0
	for side in [-1.0, 1.0]:
		var z = Z_NEAR - rng.randf_range(0.0, 8.0)
		while true:
			if spread:
				pieces_this_frame += 1
				if pieces_this_frame >= PIECES_PER_FRAME:
					pieces_this_frame = 0
					await get_tree().process_frame
					if my_build != build_id or not is_inside_tree():
						return # recycled again before finishing
			# A fitter's building already stands here: leave the frontage to it.
			if cleared(side, z):
				z -= 4.0
				if z < Z_FAR:
					break
				continue
			# Occasional landmark mosque on the right-hand side.
			if side > 0.0 and not mosque_placed and rng.randf() < 0.08 and z - MOSQUE_LENGTH > Z_FAR \
					and not cleared(side, z - MOSQUE_LENGTH) and not cleared(side, z - MOSQUE_LENGTH * 0.5):
				var mq = MOSQUE_SCENE.instantiate()
				mq.position = Vector3(FRONT_X + MOSQUE_ROAD_X, 0, z - MOSQUE_NEAR_Z)
				mq.set_meta("len", MOSQUE_LENGTH)
				mq.set_meta("near_z", z)
				add_child(mq)
				mosque_placed = true
				z -= MOSQUE_LENGTH + rng.randf_range(2.0, 5.0)
				continue
			var name = pick(names)
			var length: float = kit[name]["length"]
			if cleared(side, z - length) or cleared(side, z - length * 0.5):
				z -= 4.0 # it would run into a fitter's frontage
				continue
			if z - length < Z_FAR:
				# Not enough room for another building: fill the end of the stretch with
				# roadside life instead of leaving bare ground at the segment seam.
				while z > Z_FAR + 3.0:
					if randf() < 0.6:
						add_prop(Vector3(side * (FRONT_X + rng.randf_range(0.5, 2.5)), 0, z - 2.0), side)
					else:
						add_plant(["plantain", "neem_tree"].pick_random(), Vector3(side * (FRONT_X + rng.randf_range(1.0, 3.0)), 0, z - 2.0))
					z -= rng.randf_range(4.0, 7.0)
				break
			var b = MeshInstance3D.new()
			b.name = name
			b.mesh = BuildingKit.get_mesh(name, side)
			# Small setback variation keeps the frontage from looking ruler-straight.
			b.position = Vector3(side * (FRONT_X + rng.randf_range(0.0, 1.2)), 0, z)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			# Beyond this the haze has swallowed the building anyway; don't draw it.
			b.visibility_range_end = GameState.view_range
			b.set_meta("len", length)
			add_child(b)
			z -= length
			# Mostly tight gaps; sometimes an open yard with a plantain or neem tree in it.
			if rng.randf() < 0.3:
				var gap = rng.randf_range(6.0, 11.0)
				var kind = "plantain" if rng.randf() < 0.55 else "neem_tree"
				add_plant(kind, Vector3(side * (FRONT_X + rng.randf_range(1.0, 3.0)), 0, z - gap * 0.5))
				z -= gap
			elif rng.randf() < 0.25:
				# A kiosk, umbrella stall or polytank squeezed between buildings.
				var gap2 = rng.randf_range(4.0, 6.0)
				add_prop(Vector3(side * (FRONT_X + rng.randf_range(0.3, 1.2)), 0, z - gap2 * 0.5), side)
				z -= gap2
			else:
				z -= rng.randf_range(1.0, 4.5)
		# Palms and shade trees behind the rows, at varied depths, rising over the roofs.
		var tz = Z_NEAR - rng.randf_range(0.0, 15.0)
		while tz > Z_FAR:
			if spread:
				pieces_this_frame += 1
				if pieces_this_frame >= PIECES_PER_FRAME * 2:
					pieces_this_frame = 0
					await get_tree().process_frame
					if my_build != build_id or not is_inside_tree():
						return
			var tree = "palm_tree" if rng.randf() < 0.65 else "neem_tree"
			add_plant(tree, Vector3(side * (FRONT_X + rng.randf_range(12.0, 40.0)), 0, tz))
			tz -= rng.randf_range(12.0, 30.0)

# Vegetation billboards (GAMEPLAY_SPEC Â§25): 2D cards that turn to face the camera.
const PLANT_TEXTURES := {
	"palm_tree": preload("res://assets/vegetation/palm_tree.png"),
	"plantain": preload("res://assets/vegetation/plantain.png"),
	"neem_tree": preload("res://assets/vegetation/neem_tree.png"),
}
const PLANT_HEIGHT := {"palm_tree": Vector2(10.0, 15.0), "plantain": Vector2(3.5, 5.0), "neem_tree": Vector2(7.0, 10.0)}

func add_plant(kind: String, pos: Vector3):
	var tex: Texture2D = PLANT_TEXTURES[kind]
	var s = Sprite3D.new()
	s.texture = tex
	var range_h: Vector2 = PLANT_HEIGHT[kind]
	s.pixel_size = rng.randf_range(range_h.x, range_h.y) / tex.get_height()
	s.offset = Vector2(0, tex.get_height() * 0.5) # base on the ground
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.flip_h = rng.randf() < 0.5
	s.position = pos
	s.visibility_range_end = GameState.view_range
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)

const PROPS := [
	preload("res://assets/props/kiosk_umbrella.png"),
	preload("res://assets/props/orange_stall.png"),
	preload("res://assets/props/polytank_stand.png"),
	preload("res://assets/props/stall_momo.png"),
	preload("res://assets/props/stall_vegetables.png"),
]

func add_prop(pos: Vector3, side: float):
	var tex: Texture2D = PROPS[rng.randi() % PROPS.size()]
	var s = Sprite3D.new()
	s.texture = tex
	s.pixel_size = rng.randf_range(2.4, 2.9) / tex.get_height()
	s.offset = Vector2(0, tex.get_height() * 0.5)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.flip_h = side < 0.0
	s.position = pos
	s.visibility_range_end = GameState.view_range
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)

# Is this spot of frontage (local z) reserved for a fitter's building? Asks WorldStreamer.
func cleared(side: float, local_z: float) -> bool:
	var streamer = get_parent().get_parent() if get_parent() else null
	if streamer == null or not streamer.has_method("frontage_cleared"):
		return false
	return streamer.frontage_cleared(side, get_parent().position.z + local_z)

# Random building, avoiding the last few picks so neighbours differ.
func pick(names: Array) -> String:
	var pool = names.filter(func(n): return not recent.has(n))
	if pool.is_empty():
		pool = names
	var n = pool[rng.randi() % pool.size()]
	recent.append(n)
	if recent.size() > mini(6, names.size() - 1):
		recent.pop_front()
	return n
