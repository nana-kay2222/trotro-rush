extends Node

# Autoload "GameState": run-wide values shared by gameplay and UI.
# Scoring (GAMEPLAY_SPEC §21): score = total fares - total police fines (and, by owner
# decision, what's paid to roadside fitters).
# Run end (owner decisions): health reaching 0 ends the run (a negative balance from
# fines will also end it once police exist).

signal health_changed(health: float, max_health: float)
signal run_over(reason: String)
signal score_changed(fares: int, fines: int)
signal load_changed(is_full: bool)
signal announcement(text: String, kind: String) # short HUD banner: "fare", "warn", "info", "boost", "police"
signal recklessness_changed(value: float)
signal day_ended(success: bool)
signal app_hidden # the web page went into the background
var visibility_cb: JavaScriptObject # kept so the browser callback stays alive

# Daily "sales" (owner-approved): each run is a working day on a clock. The trotro owner
# expects a sales target by close of day; hit it and the next day asks for more.
# Owner direction: generous days at first, a little shorter every day.
# Day 1 lasts 4 min (real time for 6:00 AM -> 6:00 PM), 8 s less each day, never under 2.5 min.
# The target starts at GHS 60 and rises GHS 5 a day. Endless: no last day.
const FIRST_DAY_LENGTH := 240.0
const DAY_SHRINK := 8.0
const MIN_DAY_LENGTH := 150.0
const FIRST_TARGET := 60
const TARGET_STEP := 5

func day_length(d: int = -1) -> float:
	if d < 0:
		d = day
	return maxf(MIN_DAY_LENGTH, FIRST_DAY_LENGTH - DAY_SHRINK * (d - 1))

func target_for(d: int) -> int:
	return FIRST_TARGET + TARGET_STEP * (d - 1)
const OVERNIGHT_REPAIR := 25.0
var day: int = 1
var day_time: float = 0.0
var day_running: bool = false
var sales_target: int = FIRST_TARGET
var day_start_score: int = 0

const MAX_RECKLESSNESS := 100.0
var recklessness: float = 0.0

const MAX_HEALTH := 100.0
const FULL_DAMAGE_MULTIPLIER := 1.5 # GAMEPLAY_SPEC §14: damage is more severe when loaded
# Seats (owner change from binary EMPTY/FULL): a 15-seat trotro. Handling and damage
# scale gradually with the load; FULL means every seat is taken.
const SEATS := 15
var riders: int = 0
signal riders_changed(riders: int)

var health: float = MAX_HEALTH
var distance: float = 0.0 # metres driven this run

# Phones in a browser: draw the roadside a little less far ahead (owner: thick haze to
# hide the cut-off looked foggy, so the haze stays as on desktop), and step the 3D
# resolution down if the frame rate stays low.
var mobile_web: bool = OS.has_feature("web_android") or OS.has_feature("web_ios")
var view_range: float = 220.0 if mobile_web else 260.0
var slow_seconds: float = 0.0
var quality_lowered: bool = false

func watch_frame_rate(delta: float):
	if not mobile_web or quality_lowered or get_tree().paused:
		return
	if Engine.get_frames_per_second() < 24:
		slow_seconds += delta
		if slow_seconds > 5.0:
			quality_lowered = true
			get_viewport().scaling_3d_scale = 0.55
			print("[perf] low frame rate: 3D resolution lowered")
	else:
		slow_seconds = maxf(0.0, slow_seconds - delta)

func _ready():
	print("[boot] GameState ready ", Time.get_ticks_msec())
	var drawn = [0]
	var mark = func():
		drawn[0] += 1
		if drawn[0] <= 4:
			print("[boot] frame ", drawn[0], " ", Time.get_ticks_msec())
		# The web page keeps its loading screen up until the game has really drawn.
		if drawn[0] == 3 and OS.has_feature("web"):
			JavaScriptBridge.eval("window.trotroReady && window.trotroReady()")
	RenderingServer.frame_post_draw.connect(mark)
	if OS.has_feature("web"):
		# Switching tab or app, or locking the phone, hides the page: pause the run.
		visibility_cb = JavaScriptBridge.create_callback(func(_args):
			if JavaScriptBridge.eval("document.hidden"):
				app_hidden.emit())
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", visibility_cb)
	# Web builds opened with ?perf in the address log performance every 3 s (play-testing).
	if OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("perf"):
		var t = Timer.new()
		t.wait_time = 3.0
		t.process_mode = Node.PROCESS_MODE_ALWAYS
		t.autostart = true
		t.timeout.connect(func():
			print("[perf] fps %d | script %.1f ms | objects %d | draw calls %d | primitives %d" % [
				Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
			print_perf_breakdown())
		add_child(t)
		setup_perf_probes.call_deferred()

# ------------------------------------------------------------------ ?perf breakdown
# Each World child gets its own process priority with a probe node after it; a probe
# books the time since the previous probe to the system that just ran. Everything left
# at priority 0 (vehicles, sprites, particles, autoloads) is booked to "rest".
var perf_last_usec: int = 0
var perf_acc: Dictionary = {}
var perf_frames: int = 0

func setup_perf_probes():
	var world = get_tree().current_scene
	if world == null:
		return
	var probe_src = GDScript.new()
	probe_src.source_code = "extends Node\nvar label := \"\"\nfunc _process(_d):\n\tGameState.perf_mark(label)\n"
	probe_src.reload()
	add_probe(probe_src, "start", -1000)
	add_probe(probe_src, "rest", 1)
	var i = 1
	for child in world.get_children():
		if child.has_method("_process"):
			child.process_priority = i * 10
			add_probe(probe_src, child.name, i * 10 + 5)
			i += 1

func add_probe(src: GDScript, label: String, priority: int):
	var p = Node.new()
	p.set_script(src)
	p.set("label", label)
	p.process_priority = priority
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)

var perf_frame_start: int = 0
var perf_frame_parts: Dictionary = {}

func perf_mark(label: String):
	var now = Time.get_ticks_usec()
	if label == "start":
		perf_frames += 1
		# A hitch: report the whole frame (scripts + rendering) and what the scripts took.
		var frame_ms = (now - perf_frame_start) / 1000.0
		if perf_frame_start > 0 and frame_ms > 120.0 and not get_tree().paused:
			var scripts_ms = 0.0
			var worst = ""
			var worst_ms = 0.0
			for k in perf_frame_parts:
				var ms = perf_frame_parts[k] / 1000.0
				scripts_ms += ms
				if ms > worst_ms:
					worst_ms = ms
					worst = k
			print("[spike] frame %.0f ms (scripts %.0f ms, most in %s %.0f ms) at %.0f m" % [frame_ms, scripts_ms, worst, worst_ms, distance])
		perf_frame_start = now
		perf_frame_parts.clear()
	else:
		perf_acc[label] = perf_acc.get(label, 0) + (now - perf_last_usec)
		perf_frame_parts[label] = now - perf_last_usec
	perf_last_usec = now

func print_perf_breakdown():
	if perf_frames == 0:
		return
	var parts = []
	for k in perf_acc:
		parts.append([k, perf_acc[k] / 1000.0 / perf_frames])
	parts.sort_custom(func(a, b): return a[1] > b[1])
	var line = "[perf] ms/frame:"
	for p in parts:
		line += " %s %.1f," % p
	print(line)
	perf_acc.clear()
	perf_frames = 0
	# Phone browsers don't get the ".mobile" project overrides (their feature tags are
	# web_android / web_ios), so apply the same savings here: render 3D below native
	# resolution and use a smaller shadow map.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		get_viewport().scaling_3d_scale = 0.7
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
var is_over: bool = false
var fares: int = 0 # cedis
var fines: int = 0
var repairs: int = 0 # cedis paid to roadside fitters
var turbo_spent: int = 0 # cedis paid for turbo boosts
var is_full: bool = false
var passengers_carried: int = 0
var quick_restart: bool = false # set by "play again" so the start screen is skipped
var tutorial: bool = false # the interactive tutorial is running (scripts/tutorial.gd)

func reset():
	health = MAX_HEALTH
	distance = 0.0
	is_over = false
	fares = 0
	fines = 0
	repairs = 0
	turbo_spent = 0
	is_full = false
	riders = 0
	riders_changed.emit(riders)
	passengers_carried = 0
	recklessness = 0.0
	day = 1
	day_time = 0.0
	day_running = false
	sales_target = FIRST_TARGET
	day_start_score = 0
	recklessness_changed.emit(recklessness)
	health_changed.emit(health, MAX_HEALTH)
	score_changed.emit(fares, fines)
	load_changed.emit(is_full)

func score() -> int:
	return fares - fines - repairs - turbo_spent

# Roadside fitter (owner-approved): a paid, partial repair. PickupManager checks the
# trotro can afford it first, so paying never ends the run.
func pay_repair(cost: int, amount: float, cap: float):
	repairs += cost
	health = maxf(health, minf(cap, health + amount))
	health_changed.emit(health, MAX_HEALTH)
	score_changed.emit(fares, fines)
	check_money()

# Turbo bought from the HUD (it only offers it when the money covers it).
func pay_turbo(cost: int):
	turbo_spent += cost
	score_changed.emit(fares, fines)
	check_money()

# What the last damage came from ("crash", "pothole", "person", "rival"), so the HUD and the
# mate can react to it differently (a pothole gets no red flash and its own mate lines).
var last_damage_kind: String = ""

func apply_damage(amount: float, kind: String = "crash"):
	if is_over:
		return
	amount *= lerpf(1.0, FULL_DAMAGE_MULTIPLIER, load_fraction())
	health = maxf(0.0, health - amount)
	last_damage_kind = kind
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0.0:
		end_run("breakdown")

func add_fare(amount: int, heads: int = 1):
	fares += amount
	passengers_carried += heads
	score_changed.emit(fares, fines)
	check_target()

func load_fraction() -> float:
	return float(riders) / SEATS

func free_seats() -> int:
	return SEATS - riders

# Passengers climbing on / getting off. Keeps the FULL flag and signals in step.
func board(n: int) -> int:
	var got = mini(n, free_seats())
	set_riders(riders + got)
	return got

func alight(n: int) -> int:
	var off = mini(n, riders)
	set_riders(riders - off)
	return off

func set_riders(n: int):
	riders = clampi(n, 0, SEATS)
	riders_changed.emit(riders)
	set_full(riders >= SEATS)

func add_recklessness(amount: float):
	if is_over:
		return
	recklessness = clampf(recklessness + amount, 0.0, MAX_RECKLESSNESS)
	recklessness_changed.emit(recklessness)

func reset_recklessness():
	recklessness = 0.0
	recklessness_changed.emit(recklessness)

# Police fine (GAMEPLAY_SPEC §20). A negative balance ends the run (owner decision).
func add_fine(amount: int):
	fines += amount
	score_changed.emit(fares, fines)
	check_money()

# Owner direction: if the money goes below zero - overall, or today's takings on the day
# card - the run is lost.
func check_money():
	if score() < 0 or (day_running and day_sales() < 0):
		end_run("fines")

# Owner direction: hitting the day's target ends the day there and then (AYEKOO screen,
# next day); the next day's takings start again from zero.
func check_target():
	if day_running and not is_over and day_sales() >= sales_target:
		day_running = false
		day_ended.emit(true)

func set_full(full: bool):
	if is_full == full:
		return
	is_full = full
	load_changed.emit(is_full)

func announce(text: String, kind: String = "info"):
	announcement.emit(text, kind)

func _process(delta: float):
	watch_frame_rate(delta)
	if not day_running or is_over:
		return
	day_time += delta
	if day_time >= day_length():
		day_running = false
		var ok = day_sales() >= sales_target
		day_ended.emit(ok)
		if not ok:
			end_run("sales")

# Money made today (fares minus fines since the day began).
func day_sales() -> int:
	return score() - day_start_score

# 6:00 AM -> 6:00 PM, for the HUD clock.
func clock_text() -> String:
	var minutes = int(6 * 60 + day_time / day_length() * 12 * 60)
	var h = minutes / 60
	var m = minutes % 60
	var suffix = "AM" if h < 12 else "PM"
	var h12 = h if h <= 12 else h - 12
	return "%d:%02d %s" % [h12, m, suffix]

func start_next_day():
	day += 1
	day_time = 0.0
	day_start_score = score()
	sales_target = target_for(day)
	health = minf(MAX_HEALTH, health + OVERNIGHT_REPAIR) # the fitter patches it up overnight
	health_changed.emit(health, MAX_HEALTH)
	day_running = true

func health_fraction() -> float:
	return health / MAX_HEALTH

func end_run(reason: String):
	if is_over or tutorial: # nothing can end the tutorial's practice drive
		return
	is_over = true
	run_over.emit(reason)
