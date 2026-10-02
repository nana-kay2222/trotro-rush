extends Node3D

# The trotro's mate: hangs out of the kerb-side door, waves cedis and shouts the route.
# Atmosphere only (owner rule): he never changes which passengers can be picked up.

# Head, shoulders and waving arm out of the side window: the artwork is cut at mid-chest
# and the cut's outer corner (the pivot) sits at the trotro's right edge, so the cut is
# hidden inside the body and he leans only a little way out.
const TEX := preload("res://assets/characters/trotro_mate.png")
const FIGURE_HEIGHT := 1.3 # metres for the whole (uncut) figure
const CUT_Y := 180.0 # mid-chest, in artwork pixels
const TORSO_RIGHT_X := 233.0 # outer edge of the torso at the cut (the pivot)
const LEAN := -0.2 # radians, out toward the road side
# Owner's wording; each line has the owner's recording (assets/audio/voice/<id>.wav).
const ROUTE_CALLS := ["Circle! Circle! Circle!", "Kaneshie, Kaneshie!", "Madina! Madina!", "Accra, Accra, Accra!", "Lapaz! Lapaz!", "Tema Station!", "Achimota! Achimota!", "Kasoa, Kasoa!"]
const PASSENGER_CALLS := ["Driver, passenger!", "Driver, stop there!", "Passenger, passenger!", "Driver, enter enter!"]
const MECHANIC_CALLS := ["Driver, fitter dey there!", "Driver driver, fitter dey there!", "Make we fix the car!"]
const CRASH_CALLS := ["Driver, take time!", "Ei driver!", "Chale, slow down!"]
const POTHOLE_CALLS := ["Ei driver!", "Driver, see the hole!", "This road, dierrr!"]
const FULL_CALLS := ["Full, no seat!", "Seats finished!"]
const POLICE_CALLS := ["Ei, police!", "Driver, papers!"]
const VOICES := {
	"Circle! Circle! Circle!": "mate_route_circle", "Kaneshie, Kaneshie!": "mate_route_kaneshie",
	"Madina! Madina!": "mate_route_madina", "Accra, Accra, Accra!": "mate_route_accra",
	"Lapaz! Lapaz!": "mate_route_lapaz", "Tema Station!": "mate_route_tema_station",
	"Achimota! Achimota!": "mate_route_achimota", "Kasoa, Kasoa!": "mate_route_kasoa",
	"Driver, passenger!": "mate_driver_passenger", "Driver, stop there!": "mate_driver_stop_there",
	"Passenger, passenger!": "mate_passenger_passenger", "Driver, enter enter!": "mate_driver_enter_enter",
	"Driver, fitter dey there!": "mate_driver_fitter_dey_there",
	"Driver driver, fitter dey there!": "mate_driver_driver_fitter_dey_there",
	"Make we fix the car!": "mate_make_we_fix_the_car",
	"Driver, take time!": "mate_driver_take_time", "Ei driver!": "mate_ei_driver", "Chale, slow down!": "mate_chale_slow_down",
	"Driver, see the hole!": "mate_driver_see_the_hole", "This road, dierrr!": "mate_this_road_dierrr",
	"Full, no seat!": "mate_full_no_seat", "Seats finished!": "mate_seats_finished",
	"Ei, police!": "mate_ei_police", "Driver, papers!": "mate_driver_papers",
}
# He's in the trotro, right by the camera, but the voices sit in the street mix, not over it.
const VOICE_DB := -10.1 # (owner: +15% on the first -11 dB, then -3%)

var sprite: Sprite3D
var bubble: Label3D
var bubble_time: float = 0.0
var next_call: float = 3.0
var phase: float = 0.0
var alerted_for: Variant = null
var pickups: Node

func _ready():
	sprite = Sprite3D.new()
	sprite.texture = TEX
	sprite.pixel_size = FIGURE_HEIGHT / TEX.get_height()
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, TEX.get_width(), CUT_Y)
	sprite.offset = Vector2(TEX.get_width() * 0.5 - TORSO_RIGHT_X, CUT_Y * 0.5)
	sprite.rotation.z = LEAN
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	bubble = Label3D.new()
	bubble.font_size = 64
	bubble.outline_size = 16
	bubble.outline_modulate = Color(0.05, 0.03, 0.0)
	bubble.modulate = Color(1, 1, 1)
	bubble.pixel_size = 0.007
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.position = Vector3(0.1, 0.75, 0)
	bubble.visible = false
	add_child(bubble)
	pickups = get_node_or_null("../../../Pickups") # Mate -> VisualHolder -> PlayerTrotro -> World
	GameState.health_changed.connect(_on_health)
	GameState.load_changed.connect(_on_load)
	GameState.announcement.connect(_on_announcement)

func _on_load(full: bool):
	if full:
		shout(FULL_CALLS.pick_random())

func _on_announcement(text: String, kind: String):
	if kind == "police" and text.begins_with("POLICE"):
		shout(POLICE_CALLS.pick_random())

var last_health: float = 100.0
func _on_health(h: float, _m: float):
	if h < last_health and h > 0.0:
		shout((POTHOLE_CALLS if GameState.last_damage_kind == "pothole" else CRASH_CALLS).pick_random())
	last_health = h

# Owner direction: with no stop coming up he ducks back inside now and then, and leans out
# again to shout the route, call a stop, or react to a crash or the police.
const STOP_NEAR := 200.0 # metres: a bus stop or mechanic this close keeps him out
const IN_OFFSET := Vector3(-0.6, -0.45, 0.0) # slid in and down behind the trotro's body
var out_amount: float = 1.0 # 1 = leaning out, 0 = inside
var leaning_out: bool = true
var state_time: float = 7.0 # seconds left before he next ducks in / pops out

func shout(text: String):
	if not leaning_out:
		leaning_out = true
		state_time = randf_range(6.0, 10.0) # just popped out: stay out a while
	else:
		state_time = maxf(state_time, 2.5) # finish the shout before ducking in
	bubble.text = text
	bubble.visible = true
	bubble_time = 2.0
	if VOICES.has(text):
		var length = Sfx.play_voice(VOICES[text], VOICE_DB, "mate")
		bubble_time = clampf(length, 2.0, 3.5)
	bubble.scale = Vector3.ONE * 0.6
	create_tween().tween_property(bubble, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK)

func _process(delta: float):
	# A small sway with the ride, livelier while he's shouting.
	var excited = 2.0 if bubble.visible else 1.0
	phase += delta * 5.0 * excited
	sprite.rotation.z = LEAN + sin(phase) * 0.04 * excited
	# Slide in and out of the window (the trotro's own picture hides him when inside).
	out_amount = move_toward(out_amount, 1.0 if leaning_out else 0.0, delta * 3.0)
	var k = out_amount * out_amount * (3.0 - 2.0 * out_amount) # smoothstep
	sprite.position = IN_OFFSET.lerp(Vector3.ZERO, k)
	sprite.visible = out_amount > 0.02
	if bubble.visible:
		bubble_time -= delta
		if bubble_time <= 0.0:
			bubble.visible = false
	if GameState.is_over:
		return
	var info = pickups.next_passenger_info() if pickups else {}
	var trotro = get_parent().get_parent() # Mate -> VisualHolder -> PlayerTrotro
	if trotro.is_stopped() and trotro.stop_reason == "police":
		# The officer is talking to the driver: the mate keeps his mouth shut.
		bubble.visible = false
		Sfx.stop_voice("mate")
		next_call = maxf(next_call, 3.0)
		return
	var stop_near = (not info.is_empty() and info["distance"] < STOP_NEAR) or trotro.is_stopped()
	# Call out to the driver when a passenger (or the fitter) is close.
	if not info.is_empty() and info["distance"] < 70.0 and alerted_for != info["destination"]:
		alerted_for = info["destination"]
		shout((MECHANIC_CALLS if info.get("mechanic", false) else PASSENGER_CALLS).pick_random())
		return
	state_time -= delta
	if stop_near:
		if not leaning_out:
			leaning_out = true
			state_time = randf_range(6.0, 10.0)
	elif leaning_out:
		if state_time <= 0.0 and not bubble.visible:
			leaning_out = false # nothing coming up: duck inside for a while
			state_time = randf_range(4.0, 8.0)
	elif state_time <= 0.0:
		leaning_out = true # pops back out, shouting the route if he hasn't lately
		state_time = randf_range(6.0, 10.0)
		route_call()
		return
	next_call -= delta
	if leaning_out and next_call <= 0.0 and not bubble.visible:
		route_call()

# Route calls are long recordings (3-7 s), so he leaves a good gap between them and never
# starts one over himself.
func route_call():
	if next_call > 0.0 or Sfx.voice_playing("mate"):
		return
	shout(ROUTE_CALLS.pick_random())
	next_call = randf_range(14.0, 22.0)
