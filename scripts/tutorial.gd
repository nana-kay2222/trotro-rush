extends Node

# Interactive tutorial (owner design): a real drive on a quiet road. At each lesson the game
# pauses, dims, and shows what to do with an arrow at the thing; tap to carry on, then do
# it. SKIP is always there. Nothing can end the run here (GameState.tutorial), the clock is
# stopped, and money doesn't count: at the end (or on SKIP) a fresh day 1 starts.
# Started by HUD.start_tutorial() (first PLAY, or TUTORIAL on the main menu).

var world: Node
var player: Node3D
var hud: CanvasLayer
var traffic: Node
var hazards: Node
var pickups: Node
var events: Node
var layer: CanvasLayer
var dim: ColorRect
var tap_catcher: Control
var card_box: PanelContainer
var card_label: Label
var tap_hint: Label
var arrow: Node2D
var finger: Node2D
var skip_btn: TextureButton
var target_fn: Callable = Callable() # returns a screen point for the arrow, or null
var tapped: bool = false
var card_shown_at: int = 0
var booster_open: bool = false
var t: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = get_parent()
	player = world.get_node("PlayerTrotro")
	hud = world.get_node("HUD")
	traffic = world.get_node("Traffic")
	hazards = world.get_node("Hazards")
	pickups = world.get_node("Pickups")
	events = world.get_node("RoadEvents")
	# A quiet road: the lessons place everything themselves.
	traffic.auto_spawn = false
	traffic.clear_all()
	hazards.auto_spawn = false
	for p in hazards.pool:
		p.set_meta("active", false)
		p.visible = false
	pickups.auto_spawn = false
	pickups.rival_chance = 0.0
	events.auto_spawn = false
	events.checkpoint_flag_chance = 1.0
	GameState.fares = 60 # practice money for the booster and the fitter (not kept)
	GameState.score_changed.emit(GameState.fares, GameState.fines)
	build_ui()
	run()

func _process(delta: float):
	t += delta
	# Nothing goes wrong by accident in the tutorial.
	GameState.recklessness = 0.0
	GameState.health = maxf(GameState.health, 35.0)
	pickups.rival_today = true # no surprise rivals: the rival lesson plans its own
	pickups.rival_day = GameState.day
	if not booster_open:
		hud.turbo_gap = 999.0
	# The pause menu covers the lesson (its own buttons must be reachable).
	layer.visible = not hud.pause_menu.visible
	update_arrow()
	if finger.visible:
		finger.position.x = get_viewport().get_visible_rect().size.x * 0.5 + sin(t * 2.6) * 150.0

# ------------------------------------------------------------------ the lessons

func pause_s(seconds: float):
	var until = t + seconds
	await wait_until(func(): return t >= until)

# Tests can start part-way through (scripted play-throughs only).
static var debug_from: int = 1

func run():
	await pause_s(1.0)
	var lessons = [steer_lesson, car_lesson, pothole_lesson, bus_stop_lesson, money_lesson, health_lesson,
		booster_lesson, checkpoint_lesson, rival_lesson, tips_lesson]
	for i in lessons.size():
		if i + 1 >= debug_from:
			print("[tutorial] lesson ", i + 1)
			await lessons[i].call()
	finish()

func steer_lesson():
	hint("Hold and drag anywhere to steer.\nDrag LEFT into the left lane.")
	finger.visible = true
	await wait_until(func(): return player.position.x < -2.5)
	hint("Now drag RIGHT, across to the right lane.")
	await wait_until(func(): return player.position.x > 2.5)
	finger.visible = false
	clear_hint()
	await pause_s(0.8)

func car_lesson():
	var car = traffic.place_car("sedan", nearest_lane(), player.position.z - 110.0, 9.0)
	await wait_until(func(): return car.position.z - player.position.z > -24.0)
	await card("A slow car ahead!\nSteer around cars: every crash costs health.", func(): return world_point(car.global_position + Vector3(0, 1.4, 0)))
	await wait_until(func(): return car.position.z > player.position.z + 2.0)
	await pause_s(0.8)

func pothole_lesson():
	var hole = hazards.place_pothole(nearest_lane(), player.position.z - 110.0)
	await wait_until(func(): return hole.position.z - player.position.z > -24.0)
	await card("Pothole!\nDodge them. They jolt the trotro and hurt it.", func(): return world_point(hole.global_position))
	await wait_until(func(): return hole.position.z > player.position.z + 3.0)
	await pause_s(0.8)

func money_lesson():
	await card("Fares add up here.\nReach the day's target before 6 PM to finish the day.", func(): return control_point(hud.sales_card, true))

func health_lesson():
	await card("This is the trotro's health. If it runs out, the run ends.\nSpeeding and near misses fill RECKLESS. Full means a police fine.", func(): return control_point(hud.health_card, true))
	GameState.health = 55.0
	GameState.health_changed.emit(GameState.health, GameState.MAX_HEALTH)
	pickups.spawn_bay(player.position.z - 170.0, "mechanic")
	var mech = pickups.bays[-1]
	await wait_until(func(): return player.position.z - mech["z_near"] < 75.0)
	await card("A blue MECHANIC stop!\nSwing in on the right and the fitter repairs the trotro for GHS 15.", func(): return world_point(mech["node"].global_position + Vector3(mech["side"] * 7.0, 1.0, -12.0)))
	await wait_until(func(): return player.position.z < mech["z_near"] - pickups.BAY_LENGTH - 2.0 and not player.is_stopped())
	await pause_s(0.8)

func checkpoint_lesson():
	events.spawn_event("checkpoint", player.position.z - 200.0)
	var ev = events.events[-1]
	print("[tutorial] checkpoint ", int(player.position.z - ev["z_start"]), " m ahead")
	await wait_until(func(): return ev["decided"])
	await card("POLICE CHECKPOINT!\nThe officer is flagging you: get into the coned lane on the RIGHT.\nThe trotro stops beside him by itself.", func(): return world_point(ev["officer"].global_position + Vector3(0, 1.0, 0)))
	await wait_until(func(): return ev["checked"] or ev["ran"])
	if ev["ran"]:
		hint("You drove past him. That's a fine!\nIn a real day, always stop when flagged.")
		await pause_s(3.0)
		clear_hint()
	await wait_until(func(): return not player.is_stopped())
	await pause_s(1.0)

func tips_lesson():
	await card("Watch out for GO-SLOWS (crawling traffic: find the open lane) and MARKETS (people crossing the road).")
	await card("You're ready!\nThe owner wants his sales.\nHit the day's target before 6 PM. Ayekoo!")

func bus_stop_lesson():
	while true:
		pickups.spawn_bay(player.position.z - 170.0, "bus")
		var bay = pickups.bays[-1]
		var side_name = "LEFT" if bay["side"] < 0.0 else "RIGHT"
		await wait_until(func(): return player.position.z - bay["z_near"] < 80.0)
		await card("Passengers waiting!\nSwing into the yellow BUS STOP on the %s.\nThe trotro stops by itself while they board." % side_name, func(): return world_point(bay["passenger"].global_position + Vector3(0, 1.0, 0)) if is_instance_valid(bay["passenger"]) else null)
		await wait_until(func(): return bay["state"] != "waiting")
		if bay["state"] == "picked":
			await wait_until(func(): return not player.is_stopped())
			hint("Nice! Every passenger pays a fare.")
			await pause_s(2.5)
			clear_hint()
			return
		hint("Missed them! Let's try another stop.")
		await pause_s(2.5)
		clear_hint()

func booster_lesson():
	booster_open = true
	for attempt in 3:
		hud.turbo_gap = 0.0
		await wait_until(func(): return hud.turbo_box.visible)
		await card("BOOSTER!\nTap once: x1 boost for GHS 10.\nDouble-tap: the full x2 boost with flames for GHS 15.\nIt only stays for 5 seconds: try it now!", func(): return control_point(hud.turbo_btn, false))
		await wait_until(func(): return player.is_turbo() or not hud.turbo_box.visible)
		if player.is_turbo():
			hint("While boosting, a shield protects the trotro.")
			await wait_until(func(): return not player.is_turbo())
			clear_hint()
			break
	booster_open = false
	hud.turbo_gap = 999.0
	await pause_s(0.8)

func rival_lesson():
	pickups.spawn_bay(player.position.z - 300.0, "bus")
	var bay = pickups.bays[-1]
	bay["rival_planned"] = true
	await wait_until(func(): return bay.has("rival") or bay["state"] != "waiting")
	if bay.has("rival"):
		await pause_s(0.6)
		await card("A RIVAL TROTRO wants your passenger!\nGet into the stop first, or steer in front of it to block it.", func(): return control_point(hud.rival_alert, true))
	await wait_until(func(): return bay["state"] != "waiting")
	hint("You beat the rival!" if bay["state"] == "picked" else "The rival got there first. Be quicker next time!")
	await pause_s(2.5)
	clear_hint()

func finish():
	hud.end_tutorial()

# ------------------------------------------------------------------ helpers

signal never # never emitted: a lesson parks on it once the tutorial is gone (skipped)

func wait_until(cond: Callable):
	while true:
		if not is_inside_tree():
			await never # skipped / left: stop the lesson script for good
		if cond.call():
			return
		await get_tree().process_frame

func nearest_lane() -> float:
	var best = 0.0
	for x in [-3.67, 0.0, 3.67]:
		if absf(player.position.x - x) < absf(player.position.x - best):
			best = x
	return best

# Pauses the game, dims it and shows the card (with the arrow on the target, if any) until
# the player taps.
func card(text: String, target: Callable = Callable()):
	card_label.text = text
	tap_hint.visible = true
	card_box.visible = true
	dim.visible = true
	tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	target_fn = target
	get_tree().paused = true
	tapped = false
	card_shown_at = Time.get_ticks_msec()
	pop(card_box)
	await wait_until(func(): return tapped)
	card_box.visible = false
	dim.visible = false
	tap_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_fn = Callable()
	get_tree().paused = false

# A card that doesn't pause or need a tap (while the player does the thing).
func hint(text: String):
	card_label.text = text
	tap_hint.visible = false
	card_box.visible = true
	pop(card_box)

func clear_hint():
	card_box.visible = false

func pop(c: Control):
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * 0.85
	var tw = c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_tap(event: InputEvent):
	var released = (event is InputEventMouseButton and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if released and card_box.visible and Time.get_ticks_msec() - card_shown_at > 450:
		tapped = true

# Screen point of a 3D spot (null when it's behind the camera).
func world_point(p: Vector3) -> Variant:
	var cam = get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)

# A HUD control: point at its bottom edge (below = true) or its top edge.
func control_point(c: Control, below: bool) -> Variant:
	if c == null or not c.is_visible_in_tree():
		return null
	var r = c.get_global_rect()
	return Vector2(r.get_center().x, r.end.y if below else r.position.y)

func update_arrow():
	var p = target_fn.call() if target_fn.is_valid() else null
	arrow.visible = p != null
	if p == null:
		return
	var bob = absf(sin(t * 5.0)) * 16.0
	var screen_h = get_viewport().get_visible_rect().size.y
	if p.y < screen_h * 0.3:
		# Target near the top (HUD cards): the arrow sits below it, pointing up.
		arrow.rotation = PI
		arrow.position = p + Vector2(0, 14 + bob)
	else:
		arrow.rotation = 0.0
		arrow.position = p - Vector2(0, 14 + bob)

# ------------------------------------------------------------------ ui

func build_ui():
	layer = CanvasLayer.new()
	layer.layer = 20 # above the HUD
	add_child(layer)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	layer.add_child(dim)
	tap_catcher = Control.new()
	tap_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tap_catcher.gui_input.connect(_on_tap)
	layer.add_child(tap_catcher)
	# The instruction card, upper middle.
	card_box = hud.card(Color(0.08, 0.09, 0.14, 0.94), Color(hud.GOLD, 0.9), 22)
	card_box.anchor_left = 0.06
	card_box.anchor_right = 0.94
	card_box.anchor_top = 0.56 # below the road ahead, so the arrows' targets stay clear
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.visible = false
	layer.add_child(card_box)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card_box.add_child(v)
	card_label = hud.label("", 34, Color.WHITE, 8)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(card_label)
	tap_hint = hud.label("TAP TO CONTINUE", 24, hud.GOLD, 6)
	tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tap_hint)
	# The pointing arrow: a fat yellow arrow with a dark outline, pointing down at (0, 0).
	arrow = Node2D.new()
	var pts = PackedVector2Array([Vector2(0, 0), Vector2(-38, -46), Vector2(-16, -46), Vector2(-16, -96), Vector2(16, -96), Vector2(16, -46), Vector2(38, -46)])
	var outline = Polygon2D.new()
	var big = PackedVector2Array()
	for q in pts:
		big.append(q * 1.12 + Vector2(0, 4))
	outline.polygon = big
	outline.color = Color(0.05, 0.03, 0.0)
	arrow.add_child(outline)
	var fill = Polygon2D.new()
	fill.polygon = pts
	fill.color = hud.GOLD
	arrow.add_child(fill)
	arrow.visible = false
	layer.add_child(arrow)
	# Steering lesson: a fingertip sliding left and right near the bottom.
	finger = Node2D.new()
	var ring = Polygon2D.new()
	var circle = PackedVector2Array()
	for i in 24:
		circle.append(Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0)) * 34.0)
	ring.polygon = circle
	ring.color = Color(1, 1, 1, 0.75)
	finger.add_child(ring)
	var lr = hud.label("<   DRAG   >", 30, Color.WHITE, 8)
	lr.position = Vector2(-110, 44)
	finger.add_child(lr)
	finger.position = Vector2(360, get_viewport().get_visible_rect().size.y * 0.72)
	finger.visible = false
	layer.add_child(finger)
	# SKIP, always available.
	skip_btn = hud.image_button("skip", finish, 210.0)
	skip_btn.anchor_left = 0.5
	skip_btn.anchor_right = 0.5
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -105
	skip_btn.offset_right = 105
	skip_btn.offset_top = -100
	skip_btn.offset_bottom = -22
	layer.add_child(skip_btn)
