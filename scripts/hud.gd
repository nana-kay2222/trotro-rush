extends CanvasLayer

# Game UI: start screen, in-run HUD, banners, pause and game over.
# Built in code (no .tscn) so the whole look lives in one place; restyle here.
# Layout uses anchors, so it adapts to any screen size/orientation.

const GOLD := Color(0.98, 0.8, 0.32)
const MECHANIC_BLUE := Color(0.25, 0.65, 1.0) # the fitter's stop markings and alert
const PANEL_BG := Color(0.06, 0.07, 0.1, 0.72)
const GREEN := Color(0.16, 0.62, 0.36)
const AMBER := Color(0.93, 0.6, 0.16)
const RED := Color(0.86, 0.24, 0.22)
const SAVE_PATH := "user://save.cfg"

var font: SystemFont
var fare_label: Label
var fare_icon: TextureRect
var carried_label: Label
var load_badge: PanelContainer
var load_label: Label
var health_bar: ProgressBar
var health_fill: StyleBoxFlat
var health_card: Control
var rival_alert: PanelContainer
var rival_label: Label
var reckless_bar: ProgressBar
var reckless_fill: StyleBoxFlat
var reckless_title: Label
var score_title: Label
var go_title: Label
var speed_label: Label
var speeding_tag: PanelContainer
var alert: Control
var alert_label: Label
var alert_arrow: Polygon2D
var banner: Label
var damage_flash: ColorRect
var start_screen: Control
var pause_menu: Control
var game_over: Control
var go_stats: Label
var go_best: Label
var last_health: float = GameState.MAX_HEALTH
var player: Node3D
var pickups: Node

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Segoe UI Black", "Roboto", "Helvetica", "sans-serif"])
	font.font_weight = 900
	player = get_node_or_null("../PlayerTrotro")
	pickups = get_node_or_null("../Pickups")
	build_hud()
	build_banner()
	build_start_screen()
	build_pause()
	build_game_over()
	GameState.health_changed.connect(_on_health_changed)
	GameState.run_over.connect(_on_run_over)
	GameState.score_changed.connect(_on_score_changed)
	GameState.load_changed.connect(_on_load_changed)
	GameState.announcement.connect(show_banner)
	GameState.recklessness_changed.connect(_on_recklessness_changed)
	_on_recklessness_changed(GameState.recklessness)
	_on_health_changed(GameState.health, GameState.MAX_HEALTH)
	_on_score_changed(GameState.fares, GameState.fines)
	_on_load_changed(GameState.is_full)
	GameState.day_ended.connect(_on_day_ended)
	GameState.riders_changed.connect(_on_riders_changed)
	GameState.app_hidden.connect(pause_if_running)
	build_sales_card()
	build_day_screen()
	# Wait on the start screen until the player taps (skipped when replaying).
	if GameState.quick_restart:
		GameState.quick_restart = false
		get_viewport().size_changed.disconnect(fit_cover)
		start_screen.queue_free()
		start_screen = null
		cover_art = null
		cover_bg = null
		begin_day.call_deferred() # after World._ready has reset GameState
	else:
		move_child(start_screen, -1) # cover everything built after it (the sales card)
		get_tree().paused = true
		Sfx.set_music("menu")

func begin_day():
	GameState.day_running = true
	Sfx.set_music("game")
	show_banner("DAY %d: Owner wants GHS %d" % [GameState.day, GameState.sales_target], "info")

# ------------------------------------------------------------------ helpers

func label(text: String, size: int, color: Color = Color.WHITE, outline: int = 8) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05))
	l.add_theme_constant_override("outline_size", outline)
	return l

func card(bg: Color = PANEL_BG, border: Color = Color(1, 1, 1, 0.15), radius: int = 18) -> PanelContainer:
	var p = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", sb)
	return p

func icon(path: String, size: float) -> TextureRect:
	var t = TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.pivot_offset = Vector2(size, size) * 0.5
	return t

# Owner's button art (assets/ui/buttons). Pressing squeezes it a little; letting go springs
# it back slightly bigger, then it settles. The action runs once the spring has shown.
const BUTTON_ASPECT := 151.0 / 408.0
func image_button(name: String, on_press: Callable, width: float = 340.0) -> TextureButton:
	var b = TextureButton.new()
	b.texture_normal = load("res://assets/ui/buttons/btn_%s.png" % name)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(width, width * BUTTON_ASPECT)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_press_animation(b)
	b.pressed.connect(func():
		Sfx.play("click")
		get_tree().create_timer(0.12, true).timeout.connect(on_press))
	return b

func add_press_animation(b: Control):
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		var t = b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE * 0.88, 0.06).set_trans(Tween.TRANS_QUAD))
	b.button_up.connect(func():
		b.pivot_offset = b.size * 0.5
		var t = b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE * 1.1, 0.08).set_trans(Tween.TRANS_QUAD)
		t.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE))

func big_button(text: String, color: Color, on_press: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 6)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.15 if state == "pressed" else 0.0).lightened(0.08 if state == "hover" else 0.0)
		sb.set_corner_radius_all(22)
		sb.border_width_bottom = 2 if state == "pressed" else 8
		sb.border_color = color.darkened(0.45)
		sb.content_margin_left = 40
		sb.content_margin_right = 40
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		b.add_theme_stylebox_override(state, sb)
	b.custom_minimum_size = Vector2(320, 0)
	b.pressed.connect(func(): Sfx.play("click"))
	b.pressed.connect(on_press)
	return b

func pop(node: Control, amount: float = 1.25):
	node.pivot_offset = node.size * 0.5
	var t = create_tween()
	t.tween_property(node, "scale", Vector2.ONE * amount, 0.08)
	t.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ in-run HUD

func build_hud():
	var lines = Control.new()
	lines.set_script(load("res://scripts/speed_lines.gd"))
	add_child(lines)
	lines.player = player
	# Damage flash under everything else.
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

	# Top-left: fares + load state.
	var left = VBoxContainer.new()
	left.position = Vector2(20, 18)
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var fare_card = card(PANEL_BG, Color(GOLD, 0.7))
	left.add_child(fare_card)
	var fr = HBoxContainer.new()
	fr.add_theme_constant_override("separation", 12)
	fare_card.add_child(fr)
	fare_icon = icon("res://assets/ui/icon_coin.png", 46)
	fr.add_child(fare_icon)
	var fcol = VBoxContainer.new()
	fcol.add_theme_constant_override("separation", -6)
	fr.add_child(fcol)
	score_title = label("SCORE", 16, Color(1, 1, 1, 0.75), 4)
	fcol.add_child(score_title)
	fare_label = label("GHS 0", 36, GOLD, 6)
	fcol.add_child(fare_label)
	var lr = HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	left.add_child(lr)
	load_badge = card(GREEN, Color(1, 1, 1, 0.5), 30)
	lr.add_child(load_badge)
	var lb = HBoxContainer.new()
	lb.add_theme_constant_override("separation", 6)
	load_badge.add_child(lb)
	lb.add_child(icon("res://assets/ui/icon_passenger.png", 30))
	load_label = label("EMPTY", 22)
	lb.add_child(load_label)
	carried_label = label("0 carried", 20, Color(1, 1, 1, 0.85), 6)
	carried_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lr.add_child(carried_label)

	# Top-right: health.
	health_card = card()
	health_card.anchor_left = 1.0
	health_card.anchor_right = 1.0
	health_card.offset_left = -290
	health_card.offset_right = -20
	health_card.offset_top = 18
	add_child(health_card)
	var hr = HBoxContainer.new()
	hr.add_theme_constant_override("separation", 12)
	health_card.add_child(hr)
	hr.add_child(icon("res://assets/ui/icon_health.png", 42))
	var hcol = VBoxContainer.new()
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hcol.add_theme_constant_override("separation", 4)
	hr.add_child(hcol)
	hcol.add_child(label("TROTRO HEALTH", 16, Color(1, 1, 1, 0.75), 4))
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(180, 24)
	health_bar.show_percentage = false
	health_bar.max_value = GameState.MAX_HEALTH
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(13)
	health_fill = StyleBoxFlat.new()
	health_fill.set_corner_radius_all(13)
	health_fill.border_width_top = 4
	health_fill.border_color = Color(1, 1, 1, 0.35) # glossy top edge
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", health_fill)
	hcol.add_child(health_bar)
	# Recklessness meter (fills toward a police stop).
	var rrow = HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	hcol.add_child(rrow)
	reckless_title = label("RECKLESS", 13, Color(1, 1, 1, 0.7), 3)
	rrow.add_child(reckless_title)
	reckless_bar = ProgressBar.new()
	reckless_bar.custom_minimum_size = Vector2(0, 12)
	reckless_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reckless_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reckless_bar.show_percentage = false
	reckless_bar.max_value = GameState.MAX_RECKLESSNESS
	var rbg = StyleBoxFlat.new()
	rbg.bg_color = Color(0, 0, 0, 0.55)
	rbg.set_corner_radius_all(6)
	reckless_fill = StyleBoxFlat.new()
	reckless_fill.set_corner_radius_all(6)
	reckless_bar.add_theme_stylebox_override("background", rbg)
	reckless_bar.add_theme_stylebox_override("fill", reckless_fill)
	rrow.add_child(reckless_bar)

	# Pause button, top centre.
	var pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.add_theme_font_override("font", font)
	pause_btn.add_theme_font_size_override("font_size", 30)
	var psb = StyleBoxFlat.new()
	psb.bg_color = PANEL_BG
	psb.set_corner_radius_all(40)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 8
	psb.content_margin_bottom = 8
	for s in ["normal", "hover", "pressed", "focus"]:
		pause_btn.add_theme_stylebox_override(s, psb)
	pause_btn.anchor_left = 0.5
	pause_btn.anchor_right = 0.5
	pause_btn.offset_left = -34
	pause_btn.offset_top = 18
	pause_btn.pressed.connect(func(): set_paused(true))
	add_press_animation(pause_btn)
	add_child(pause_btn)

	build_turbo()

	# Bottom-left: speed.
	var speed_box = VBoxContainer.new()
	speed_box.anchor_top = 1.0
	speed_box.anchor_bottom = 1.0
	speed_box.offset_left = 20
	speed_box.offset_top = -150
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(speed_box)
	speeding_tag = card(RED, Color(1, 1, 1, 0.6), 24)
	speeding_tag.add_child(label("SPEEDING!", 22))
	speeding_tag.visible = false
	speed_box.add_child(speeding_tag)
	var sc = card()
	speed_box.add_child(sc)
	var srow = HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	sc.add_child(srow)
	srow.add_child(icon("res://assets/ui/icon_speed.png", 40))
	speed_label = label("58", 38, Color.WHITE, 6)
	srow.add_child(speed_label)
	var unit = label("km/h", 18, Color(1, 1, 1, 0.7), 4)
	unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	srow.add_child(unit)

	# Passenger alert at the screen edge on the passenger's side.
	alert = Control.new()
	alert.anchor_top = 0.42
	alert.anchor_bottom = 0.42
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alert)
	var ac = card(Color(0.08, 0.35, 0.12, 0.88), Color(GOLD, 0.9), 20)
	ac.name = "Card"
	alert.add_child(ac)
	var arow = HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	ac.add_child(arow)
	arow.add_child(icon("res://assets/ui/icon_passenger.png", 36))
	alert_label = label("", 22)
	arow.add_child(alert_label)
	alert_arrow = Polygon2D.new()
	alert_arrow.color = GOLD
	alert.add_child(alert_arrow)
	alert.visible = false

	# Rival warning, bottom centre: how close the rival trotro is.
	rival_alert = card(Color(0.55, 0.06, 0.06, 0.9), Color(1, 0.8, 0.3, 0.9), 22)
	rival_alert.anchor_left = 0.5
	rival_alert.anchor_right = 0.5
	rival_alert.anchor_top = 1.0
	rival_alert.anchor_bottom = 1.0
	# Zero-height rect anchored above the speedometer; the card sizes itself to its text.
	rival_alert.offset_top = -280
	rival_alert.offset_bottom = -280
	rival_alert.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rival_alert.grow_vertical = Control.GROW_DIRECTION_END
	rival_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rrow2 = HBoxContainer.new()
	rrow2.add_theme_constant_override("separation", 8)
	rival_alert.add_child(rrow2)
	rrow2.add_child(icon("res://assets/ui/icon_trotro.png", 40))
	rival_label = label("RIVAL BEHIND!", 26)
	rrow2.add_child(rival_label)
	rival_alert.visible = false
	add_child(rival_alert)

func build_banner():
	banner = label("", 42, GOLD, 12)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.anchor_top = 0.2
	banner.anchor_bottom = 0.2
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)

func show_banner(text: String, kind: String):
	var colors = {"fare": GOLD, "repair": MECHANIC_BLUE, "turbo1": TURBO_BLUE, "turbo2": TURBO_RED, "boost": Color(0.3, 0.95, 1.0), "warn": Color(1.0, 0.5, 0.3), "info": Color.WHITE, "police": Color(0.45, 0.65, 1.0)}
	banner.text = text
	banner.add_theme_color_override("font_color", colors.get(kind, Color.WHITE))
	banner.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 30)
	var t = create_tween()
	banner.scale = Vector2.ONE * 0.6
	banner.modulate.a = 1.0
	t.tween_property(banner, "scale", Vector2.ONE * 1.1, 0.12).set_trans(Tween.TRANS_BACK)
	t.tween_property(banner, "scale", Vector2.ONE, 0.1)
	t.tween_interval(1.1)
	t.tween_property(banner, "modulate:a", 0.0, 0.35)

# ------------------------------------------------------------------ screens

func overlay(dim: float) -> ColorRect:
	var o = ColorRect.new()
	o.color = Color(0.03, 0.03, 0.07, dim)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(o)
	return o

func centered_column(parent: Control) -> VBoxContainer:
	var c = CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	c.add_child(v)
	return v

# Cover screen (owner's cover art): the portrait or landscape picture fills the screen to
# match its shape (the title is part of the art), with a real PLAY button over the road.
# Loaded only while the cover is up (not preloaded): the two posters take ~8.5 MB of GPU
# memory, which is freed once the run starts.
const COVER_PORTRAIT := "res://assets/ui/cover_portrait.jpg"
const COVER_LANDSCAPE := "res://assets/ui/cover_landscape.jpg"
var cover_art: TextureRect
var cover_bg: TextureRect
# The poster may lose this share of its width to fill a tall screen (its side edges are
# palms and stalls; the title stays whole).
const COVER_MIN_WIDTH_SHOWN := 0.74
const COVER_BLUR_SHADER := """
shader_type canvas_item;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 14.0;
	vec4 c = vec4(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px);
		}
	}
	COLOR = vec4(c.rgb / 25.0 * 0.55, 1.0);
}
"""

func build_start_screen():
	start_screen = overlay(1.0)
	# Behind: the same art, blurred and dimmed, covering the whole screen, so any strip the
	# poster doesn't reach is filled with its colours instead of black.
	cover_bg = TextureRect.new()
	cover_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur = ShaderMaterial.new()
	blur.shader = Shader.new()
	blur.shader.code = COVER_BLUR_SHADER
	cover_bg.material = blur
	start_screen.add_child(cover_bg)
	cover_art = TextureRect.new()
	cover_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_screen.add_child(cover_art)
	fit_cover()
	get_viewport().size_changed.connect(fit_cover)
	# Bottom area: PLAY, the steering hint and the best score, on a soft dark fade so they
	# read over the busy art.
	var fade = TextureRect.new()
	var g = Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.02, 0.02, 0.05, 0.75))
	var gt = GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_left = 0.0
	fade.anchor_right = 1.0
	fade.anchor_top = 0.68
	fade.anchor_bottom = 1.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_screen.add_child(fade)
	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 6)
	v.anchor_left = 0.0
	v.anchor_right = 1.0
	v.anchor_top = 0.6
	v.anchor_bottom = 0.98
	start_screen.add_child(v)
	# Main menu: PLAY (pulsing), TUTORIAL, SETTINGS.
	var play = image_button("play", start_run, 380.0)
	v.add_child(play)
	# Once it has been laid out (needs its size); it may be gone by then (quick restart).
	var play_ref = weakref(play)
	(func(): if play_ref.get_ref(): pulse_button(play_ref.get_ref())).call_deferred()
	v.add_child(image_button("tutorial", start_tutorial, 300.0))
	v.add_child(image_button("settings", open_settings, 300.0))
	var best = load_best()
	if best > 0:
		var bl = label("BEST: GHS %d" % best, 24, GOLD, 6)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bl)
	build_settings()

func pulse_button(b: Control):
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	var t = b.create_tween().set_loops() # bound to the button, so it dies with the start screen
	t.tween_property(b, "scale", Vector2.ONE * 1.05, 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	if b is BaseButton:
		b.button_down.connect(t.kill) # the press animation takes over

func fit_cover():
	if cover_art == null or not is_instance_valid(cover_art):
		return
	var s = get_viewport().get_visible_rect().size
	var tex: Texture2D = load(COVER_LANDSCAPE if s.x > s.y * 1.1 else COVER_PORTRAIT)
	cover_art.texture = tex
	cover_bg.texture = tex
	# Fill the screen if possible, but never trim more than (1 - COVER_MIN_WIDTH_SHOWN) of
	# the poster's width; on very tall phones it stops just short of the bottom, where the
	# blurred copy shows through.
	var aw = float(tex.get_width())
	var ah = float(tex.get_height())
	var scale_cover = maxf(s.x / aw, s.y / ah)
	var scale_keep_title = s.x / (aw * COVER_MIN_WIDTH_SHOWN)
	var k = minf(scale_cover, scale_keep_title)
	var h = minf(ah * k, s.y)
	cover_art.position = Vector2(0, 0)
	cover_art.size = Vector2(s.x, h) # covered: the sides are trimmed evenly

# PLAY: the very first time, the tutorial comes first (it then starts the real day 1).
func start_run():
	if start_screen == null:
		return
	if not tutorial_done():
		start_tutorial()
		return
	close_start_screen()
	begin_day()

func close_start_screen():
	get_viewport().size_changed.disconnect(fit_cover)
	start_screen.queue_free()
	start_screen = null
	cover_art = null
	cover_bg = null
	settings_menu.visible = false
	get_tree().paused = false

# ------------------------------------------------------------------ tutorial
# Interactive tutorial (scripts/tutorial.gd): the first PLAY, or TUTORIAL on the main menu.
func tutorial_done() -> bool:
	var cfg = ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and bool(cfg.get_value("tutorial", "done", false))

func mark_tutorial_done():
	var cfg = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("tutorial", "done", true)
	cfg.save(SAVE_PATH)

func start_tutorial():
	if start_screen == null:
		return
	close_start_screen()
	GameState.tutorial = true
	Sfx.set_music("game")
	var tut = Node.new()
	tut.name = "Tutorial"
	tut.set_script(load("res://scripts/tutorial.gd"))
	get_parent().add_child(tut)

# The tutorial finished or was skipped: straight into a fresh real run, day 1.
func end_tutorial():
	mark_tutorial_done()
	GameState.tutorial = false
	_on_restart_pressed()

# Back to the cover (pause menu / game over): reload without skipping the start screen.
func go_main_menu():
	Engine.time_scale = 1.0
	GameState.tutorial = false
	GameState.quick_restart = false
	get_tree().paused = false
	get_tree().reload_current_scene()

# ------------------------------------------------------------------ settings
var settings_menu: Control
var music_buttons: Array = []

func build_settings():
	settings_menu = overlay(0.75)
	var v = centered_column(settings_menu)
	var t = label("SETTINGS", 64, Color.WHITE, 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var snd = image_button("sound_on", toggle_sound)
	sound_buttons.append(snd)
	v.add_child(snd)
	var mus = image_button("music_on", toggle_music)
	music_buttons.append(mus)
	v.add_child(mus)
	v.add_child(image_button("tutorial", start_tutorial))
	v.add_child(image_button("exit", func(): settings_menu.visible = false))
	update_sound_buttons()
	settings_menu.visible = false

func open_settings():
	settings_menu.visible = true
	move_child(settings_menu, -1)

func toggle_music():
	Sfx.set_music_muted(not Sfx.music_muted)
	update_sound_buttons()

func build_pause():
	pause_menu = overlay(0.6)
	var v = centered_column(pause_menu)
	var t = label("PAUSED", 70, Color.WHITE, 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(image_button("resume", func(): set_paused(false)))
	v.add_child(image_button("restart", _on_restart_pressed))
	var snd = image_button("sound_on", toggle_sound)
	sound_buttons.append(snd)
	v.add_child(snd)
	var mus = image_button("music_on", toggle_music)
	music_buttons.append(mus)
	v.add_child(mus)
	v.add_child(image_button("main_menu", go_main_menu))
	update_sound_buttons()
	pause_menu.visible = false

# Sound on/off (everything) and music on/off; Sfx remembers them on the device.
var sound_buttons: Array = []
const TEX_SOUND_ON := preload("res://assets/ui/buttons/btn_sound_on.png")
const TEX_SOUND_OFF := preload("res://assets/ui/buttons/btn_sound_off.png")
const TEX_MUSIC_ON := preload("res://assets/ui/buttons/btn_music_on.png")
const TEX_MUSIC_OFF := preload("res://assets/ui/buttons/btn_music_off.png")

func toggle_sound():
	Sfx.set_muted(not Sfx.muted)
	update_sound_buttons()

func update_sound_buttons():
	for b in sound_buttons:
		if is_instance_valid(b):
			b.texture_normal = TEX_SOUND_OFF if Sfx.muted else TEX_SOUND_ON
	for b in music_buttons:
		if is_instance_valid(b):
			b.texture_normal = TEX_MUSIC_OFF if Sfx.music_muted else TEX_MUSIC_ON

func set_paused(p: bool):
	if start_screen or GameState.is_over:
		return
	pause_menu.visible = p
	get_tree().paused = p

func _unhandled_input(event):
	if event.is_action_pressed("pause"):
		set_paused(not pause_menu.visible)

# Leaving the game (switching app or tab, locking the phone) pauses a run in progress, so
# nobody comes back to a crashed trotro. Screens that already pause the game stay as they are.
func _notification(what):
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		pause_if_running()

func pause_if_running():
	if not get_tree().paused:
		set_paused(true)

# ------------------------------------------------------------------ turbo
# Owner design: at random moments (every 20-40 s of driving) and with the money for it, the
# turbo icon appears bottom-right for 5 s. Two separate boosts:
#   tap once   = x1, GHS 10: a modest boost to 130 km/h for 5 s, no flames.
#   tap twice  = x2, GHS 15 in all: the full 200 km/h boost with the flames.
# One boost per appearance. A single tap waits a moment to see if a second tap follows.

const TURBO_COST_X1 := 10
const TURBO_COST_X2 := 15
const TURBO_OFFER_SECONDS := 5.0
const TURBO_GAP_MIN := 20.0 # seconds of driving between appearances
const TURBO_GAP_MAX := 40.0
const DOUBLE_TAP_SECONDS := 0.35
var turbo_gap: float = randf_range(TURBO_GAP_MIN, TURBO_GAP_MAX)
var turbo_tap_wait: float = 0.0 # > 0: one tap so far, waiting to see if a second comes
var turbo_rival_offered: int = 0 # the rival the booster was last offered for
var turbo_price2: Label
const TURBO_BLUE := Color(0.35, 0.75, 1.0)
const TURBO_RED := Color(1.0, 0.3, 0.25)
var turbo_btn: TextureButton
var turbo_box: Control
var turbo_timer_bar: ColorRect
var turbo_price: Label
var turbo_offer: float = 0.0 # seconds left in the current offer
var turbo_bought: int = 0
var turbo_blur: ColorRect
const TURBO_BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
uniform vec2 centre = vec2(0.5, 0.6);
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - centre;
	// Sharp around the trotro, streaking toward the edges.
	float k = strength * smoothstep(0.12, 0.55, length(d * vec2(1.0, 0.6)));
	vec4 c = vec4(0.0);
	for (int i = 0; i < 8; i++) {
		c += texture(screen_tex, uv - d * k * float(i) * 0.03);
	}
	COLOR = c / 8.0;
}
"""

func build_turbo():
	# The blur sits on its own layer between the 3D world and the HUD.
	var fx = CanvasLayer.new()
	fx.layer = -1
	add_child(fx)
	turbo_blur = ColorRect.new()
	turbo_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	turbo_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = TURBO_BLUR_SHADER
	turbo_blur.material = m
	m.set_shader_parameter("strength", 0.0)
	turbo_blur.visible = false
	fx.add_child(turbo_blur)
	# Bottom-right: the icon, its price and a bar for the time left to buy.
	turbo_box = VBoxContainer.new()
	turbo_box.anchor_left = 1.0
	turbo_box.anchor_right = 1.0
	turbo_box.anchor_top = 1.0
	turbo_box.anchor_bottom = 1.0
	turbo_box.offset_left = -230
	turbo_box.offset_right = -20
	turbo_box.offset_top = -330
	turbo_box.offset_bottom = -120
	turbo_box.alignment = BoxContainer.ALIGNMENT_END
	turbo_box.add_theme_constant_override("separation", 4)
	turbo_box.visible = false
	add_child(turbo_box)
	turbo_btn = TextureButton.new()
	turbo_btn.texture_normal = load("res://assets/ui/turbo_icon.png")
	turbo_btn.ignore_texture_size = true
	turbo_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	turbo_btn.custom_minimum_size = Vector2(150, 150)
	turbo_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	turbo_btn.pressed.connect(tap_turbo) # (straight away: double taps must be quick)
	add_press_animation(turbo_btn)
	turbo_box.add_child(turbo_btn)
	turbo_price = label("TAP  GHS %d" % TURBO_COST_X1, 22, TURBO_BLUE, 8)
	turbo_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turbo_box.add_child(turbo_price)
	turbo_price2 = label("TAP x2  GHS %d" % TURBO_COST_X2, 22, TURBO_RED, 8)
	turbo_price2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turbo_box.add_child(turbo_price2)
	var track = ColorRect.new()
	track.color = Color(0, 0, 0, 0.45)
	track.custom_minimum_size = Vector2(120, 8)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	turbo_box.add_child(track)
	turbo_timer_bar = ColorRect.new()
	turbo_timer_bar.color = TURBO_BLUE
	turbo_timer_bar.size = Vector2(120, 8)
	track.add_child(turbo_timer_bar)

func turbo_money() -> int:
	return mini(GameState.score(), GameState.day_sales())

# First tap: wait a moment for a second one. Second tap inside that moment: the full boost.
func tap_turbo():
	if turbo_offer <= 0.0 or turbo_bought > 0 or player == null:
		return
	if turbo_tap_wait > 0.0:
		turbo_tap_wait = 0.0
		buy_turbo(2 if turbo_money() >= TURBO_COST_X2 else 1)
	else:
		turbo_tap_wait = DOUBLE_TAP_SECONDS

func buy_turbo(level: int):
	var cost = TURBO_COST_X2 if level == 2 else TURBO_COST_X1
	if turbo_money() < cost:
		return
	turbo_bought = level
	GameState.pay_turbo(cost)
	player.turbo.start(level)
	show_banner("x%d BOOST" % level, "turbo%d" % level)
	turbo_offer = 0.0 # one boost per appearance

func update_turbo(delta: float):
	if player == null or turbo_box == null:
		return
	var driving = not GameState.is_over and not get_tree().paused and start_screen == null
	if driving and turbo_tap_wait > 0.0:
		turbo_tap_wait -= delta
		if turbo_tap_wait <= 0.0:
			buy_turbo(1) # no second tap came: the modest boost
	if turbo_offer > 0.0:
		if driving and turbo_tap_wait <= 0.0:
			turbo_offer -= delta
	elif driving and not player.is_stopped() and not player.is_turbo():
		# Counts down only while actually driving; appears when it runs out and you can pay.
		turbo_gap -= delta
		# Owner: a rival turning up also brings the booster (it's random otherwise, and you
		# shouldn't be left without it in a race).
		var rival = pickups.rival_info() if pickups and not GameState.tutorial else {}
		if not rival.is_empty() and rival["id"] != turbo_rival_offered:
			turbo_rival_offered = rival["id"]
			turbo_gap = 0.0
		if turbo_gap <= 0.0 and turbo_money() >= TURBO_COST_X1:
			# The gap runs from one appearance to the next, so it includes this offer's 5 s.
			turbo_gap = randf_range(TURBO_GAP_MIN, TURBO_GAP_MAX) - TURBO_OFFER_SECONDS
			turbo_offer = TURBO_OFFER_SECONDS
			turbo_bought = 0
			Sfx.play("click", -2.0, 1.5)
	var show = turbo_offer > 0.0 or turbo_tap_wait > 0.0
	if show:
		turbo_price2.visible = turbo_money() >= TURBO_COST_X2
	turbo_box.visible = show
	if show:
		turbo_timer_bar.size.x = 120.0 * clampf(turbo_offer / TURBO_OFFER_SECONDS, 0.0, 1.0)
		turbo_btn.pivot_offset = turbo_btn.size * 0.5
		if turbo_btn.scale.x <= 1.0001:
			var s = 1.0 + 0.06 * absf(sin(Time.get_ticks_msec() * 0.008))
			turbo_btn.modulate = Color(1, 1, 1, 0.85 + 0.15 * s)
	# Speed blur while the turbo runs: stronger for x2.
	var goal = 0.0
	if player.is_turbo():
		goal = 0.3 if player.turbo.level == 1 else 0.9
	var mat: ShaderMaterial = turbo_blur.material
	var cur: float = mat.get_shader_parameter("strength")
	cur = move_toward(cur, goal, delta * 2.5)
	mat.set_shader_parameter("strength", cur)
	turbo_blur.visible = cur > 0.01

# ------------------------------------------------------------------ daily sales

var sales_card: PanelContainer
var clock_label: Label
var sales_label: Label
var sales_bar: ProgressBar
var sales_fill: StyleBoxFlat
var day_screen: Control
var day_title: Label
var day_text: Label

func build_sales_card():
	sales_card = card(PANEL_BG, Color(1, 1, 1, 0.15), 16)
	sales_card.anchor_left = 0.5
	sales_card.anchor_right = 0.5
	sales_card.offset_top = 185
	sales_card.offset_bottom = 185
	sales_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sales_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sales_card)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	sales_card.add_child(col)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	clock_label = label("6:00 AM", 22, Color(1.0, 0.9, 0.55), 5)
	row.add_child(clock_label)
	sales_label = label("SALES GHS 0 / 60", 22, Color.WHITE, 5)
	row.add_child(sales_label)
	sales_bar = ProgressBar.new()
	sales_bar.custom_minimum_size = Vector2(300, 12)
	sales_bar.show_percentage = false
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(6)
	sales_fill = StyleBoxFlat.new()
	sales_fill.set_corner_radius_all(6)
	sales_fill.bg_color = GOLD
	sales_bar.add_theme_stylebox_override("background", bg)
	sales_bar.add_theme_stylebox_override("fill", sales_fill)
	col.add_child(sales_bar)

func update_sales_card():
	var sales = GameState.day_sales()
	var target = GameState.sales_target
	clock_label.text = GameState.clock_text()
	sales_label.text = "DAY %d   GHS %d / %d" % [GameState.day, sales, target]
	sales_bar.max_value = target
	sales_bar.value = clampf(sales, 0, target)
	var hit = sales >= target
	sales_fill.bg_color = GREEN if hit else GOLD
	# Last quarter of the day and still short: pulse red.
	var late = GameState.day_time > GameState.day_length() * 0.75 and not hit
	sales_card.modulate = Color(1, 0.55, 0.55).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)) if late else Color.WHITE

func build_day_screen():
	day_screen = overlay(0.7)
	var v = centered_column(day_screen)
	var c = card(Color(0.1, 0.1, 0.16, 0.96), Color(GOLD, 0.8), 28)
	v.add_child(c)
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	c.add_child(inner)
	var ic = CenterContainer.new()
	inner.add_child(ic)
	ic.add_child(icon("res://assets/ui/icon_coin.png", 90))
	day_title = label("", 54, GOLD, 14)
	day_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(day_title)
	day_text = label("", 28)
	day_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(day_text)
	var bc = CenterContainer.new()
	inner.add_child(bc)
	bc.add_child(image_button("next_day", _on_next_day))
	day_screen.visible = false

func _on_day_ended(success: bool):
	if not success:
		return # the run ends; the game-over screen explains
	Sfx.play("coin")
	Sfx.set_music("menu")
	day_title.text = "AYEKOO!\nDAY %d DONE" % GameState.day
	var next_target = GameState.target_for(GameState.day + 1)
	day_text.text = "Sales:  GHS %d  (target %d)\n\nThe fitter patched up the trotro.\nTomorrow the owner wants\nGHS %d" % [GameState.day_sales(), GameState.sales_target, next_target]
	day_screen.visible = true
	get_tree().paused = true

func _on_next_day():
	day_screen.visible = false
	GameState.start_next_day()
	get_tree().paused = false
	Sfx.set_music("game")
	show_banner("DAY %d: Owner wants GHS %d" % [GameState.day, GameState.sales_target], "info")

func build_game_over():
	game_over = overlay(0.72)
	var v = centered_column(game_over)
	var c = card(Color(0.1, 0.1, 0.16, 0.96), Color(GOLD, 0.8), 28)
	v.add_child(c)
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(inner)
	var ic = CenterContainer.new()
	inner.add_child(ic)
	ic.add_child(icon("res://assets/ui/icon_warning.png", 90))
	go_title = label("TROTRO\nBROKE DOWN!", 54, RED, 14)
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(go_title)
	go_stats = label("", 30)
	go_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(go_stats)
	go_best = label("", 26, GOLD, 8)
	go_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(go_best)
	inner.add_child(image_button("restart", _on_restart_pressed))
	inner.add_child(image_button("main_menu", go_main_menu))
	game_over.visible = false

# ------------------------------------------------------------------ updates

func _process(delta: float):
	if player:
		speed_label.text = "%d" % int(player.current_speed * 3.6)
		var speeding = player.is_speeding
		speeding_tag.visible = speeding
		if speeding:
			speeding_tag.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.008))
	update_alert()
	update_rival_alert()
	update_sales_card()
	update_turbo(delta)
	# Music intensity: rival chase / police / go-slow = full, speeding = half.
	var tense = 0.0
	if player:
		if player.is_speeding:
			tense = 0.5
		if player.speed_cap < 10.0:
			tense = 1.0
	if pickups and not pickups.rival_info().is_empty():
		tense = 1.0
	var police = get_node_or_null("../Police")
	if police and police.is_active():
		tense = 1.0
	Sfx.set_intensity(tense)
	Sfx.set_ambience(street_ambience())
	if damage_flash.color.a > 0.0:
		damage_flash.color.a = maxf(0.0, damage_flash.color.a - delta * 1.8)

# Owner's street recordings, quietly under the music while driving: busy at markets and
# go-slows, some people near a bus stop with passengers, quiet otherwise.
func street_ambience() -> String:
	if start_screen or GameState.is_over or day_screen.visible or player == null:
		return "off"
	var events = get_node_or_null("../RoadEvents")
	if events and events.crowded_near(player.position.z):
		return "busy"
	if player.is_stopped():
		return "some" # at a stop, the fitter or the police
	if pickups:
		var info = pickups.next_passenger_info()
		if not info.is_empty() and not info.get("mechanic", false) and info["distance"] < 110.0:
			return "some"
	return "quiet"

func update_alert():
	if pickups == null or GameState.is_over:
		alert.visible = false
		return
	var info = pickups.next_passenger_info()
	if info.is_empty():
		alert.visible = false
		return
	alert.visible = true
	var right = info["side"] > 0.0
	alert_label.text = "%s  %dm" % [info["destination"], int(info["distance"])]
	var card_node: Control = alert.get_node("Card")
	# Passenger alerts are green with gold; the fitter's alert is blue, like his stop.
	var mech = info.get("mechanic", false)
	var sb: StyleBoxFlat = card_node.get_theme_stylebox("panel")
	sb.bg_color = Color(0.06, 0.22, 0.55, 0.9) if mech else Color(0.08, 0.35, 0.12, 0.88)
	sb.border_color = Color(MECHANIC_BLUE, 0.95) if mech else Color(GOLD, 0.9)
	alert_arrow.color = MECHANIC_BLUE if mech else GOLD
	var w = card_node.size.x
	var screen_w = get_viewport().get_visible_rect().size.x
	var arrow = 34.0
	var h = card_node.size.y
	if right:
		alert.position.x = screen_w - w - arrow - 16
		card_node.position = Vector2(0, -h * 0.5)
		alert_arrow.polygon = PackedVector2Array([Vector2(w + 4, -arrow * 0.7), Vector2(w + arrow + 4, 0), Vector2(w + 4, arrow * 0.7)])
	else:
		alert.position.x = 16 + arrow
		card_node.position = Vector2(0, -h * 0.5)
		alert_arrow.polygon = PackedVector2Array([Vector2(-4, -arrow * 0.7), Vector2(-arrow - 4, 0), Vector2(-4, arrow * 0.7)])
	# Urgent pulse as the passenger gets close.
	var urgency = clampf(1.0 - info["distance"] / 120.0, 0.0, 1.0)
	alert.modulate.a = 0.75 + 0.25 * absf(sin(Time.get_ticks_msec() * (0.004 + urgency * 0.012)))

func update_rival_alert():
	var info = pickups.rival_info() if pickups and not GameState.is_over else {}
	rival_alert.visible = not info.is_empty()
	if info.is_empty():
		return
	var behind: float = info["behind"]
	rival_label.text = "RIVAL BEHIND!  %dm" % int(behind) if behind > 0.0 else "RIVAL AHEAD!"
	rival_alert.pivot_offset = rival_alert.size * 0.5
	var pulse = 1.0 + 0.06 * sin(Time.get_ticks_msec() * (0.012 if behind < 15.0 else 0.006))
	rival_alert.scale = Vector2.ONE * pulse

func _on_health_changed(health: float, max_health: float):
	var f = health / max_health
	var t = create_tween()
	t.tween_property(health_bar, "value", health, 0.25)
	health_fill.bg_color = GREEN if f > 0.5 else (AMBER if f > 0.25 else RED)
	if health < last_health:
		if GameState.last_damage_kind != "pothole": # a pothole is a jolt, not a crash
			damage_flash.color.a = 0.35
		var shake = create_tween()
		var base = health_card.position
		for i in 6:
			shake.tween_property(health_card, "position", base + Vector2(randf_range(-10, 10), randf_range(-5, 5)), 0.03)
		shake.tween_property(health_card, "position", base, 0.03)
	last_health = health

func _on_recklessness_changed(v: float):
	reckless_bar.value = v
	var f = v / GameState.MAX_RECKLESSNESS
	reckless_fill.bg_color = Color(0.95, 0.8, 0.2).lerp(RED, f)
	reckless_title.add_theme_color_override("font_color", RED if f > 0.75 else Color(1, 1, 1, 0.7))

# Main number is the score (fares - fines, GAMEPLAY_SPEC §21).
func _on_score_changed(fares: int, fines: int):
	fare_label.text = "GHS %d" % GameState.score() # fares minus fines and repairs
	score_title.text = "SCORE" if fines == 0 else "SCORE  (fines -%d)" % fines
	carried_label.text = "%d carried" % GameState.passengers_carried
	if fares > 0:
		pop(fare_icon, 1.4)
		pop(fare_label, 1.2)

func _on_load_changed(_full: bool):
	_on_riders_changed(GameState.riders)

# Seat count badge: "9/15", colour shifting green -> amber -> deep orange (FULL).
func _on_riders_changed(riders: int):
	var f = float(riders) / GameState.SEATS
	load_label.text = "FULL 15/15" if riders >= GameState.SEATS else "%d/%d" % [riders, GameState.SEATS]
	var sb: StyleBoxFlat = load_badge.get_theme_stylebox("panel").duplicate()
	sb.bg_color = GREEN.lerp(AMBER, clampf(f * 1.4, 0.0, 1.0)) if f < 1.0 else Color(0.85, 0.35, 0.12)
	load_badge.add_theme_stylebox_override("panel", sb)
	pop(load_badge, 1.15)

func _on_run_over(reason: String):
	var titles = {"fines": "FINED INTO\nTHE RED!", "sales": "THE OWNER\nSACKED YOU!", "breakdown": "TROTRO\nBROKE DOWN!"}
	go_title.text = titles.get(reason, "TROTRO\nBROKE DOWN!")
	Sfx.set_music("menu")
	await get_tree().create_timer(1.3).timeout
	var best = load_best()
	var score = GameState.score()
	var new_best = score > best
	if new_best:
		save_best(score)
	go_stats.text = "Days worked:  %d\nFares:  GHS %d\nFines:  -GHS %d\nRepairs:  -GHS %d\nTurbo:  -GHS %d\nPassengers:  %d\nDistance:  %.2f km\n\nSCORE:  GHS %d" % [GameState.day, GameState.fares, GameState.fines, GameState.repairs, GameState.turbo_spent, GameState.passengers_carried, GameState.distance / 1000.0, score]
	go_best.text = "NEW BEST!" if new_best and score > 0 else "Best:  GHS %d" % maxi(best, score)
	game_over.visible = true
	get_tree().paused = true

func _on_restart_pressed():
	Engine.time_scale = 1.0 # never carry a slow-mo moment into the next run
	GameState.quick_restart = true
	get_tree().paused = false
	get_tree().reload_current_scene()

func load_best() -> int:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return int(cfg.get_value("scores", "best", 0))
	return 0

func save_best(score: int):
	var cfg = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("scores", "best", score)
	cfg.save(SAVE_PATH)
