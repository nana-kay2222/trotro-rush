extends Node

# Autoload "Sfx": every sound is synthesised at startup (no audio files, tiny download).
#   Sfx.play("horn") / "coin" / "crash" / "pothole" / "siren" / "whoosh" / "drop" / "click"
# plus a continuous engine hum whose pitch follows the trotro's speed (set_engine()).
# The hum is one seamless loop rendered at startup and re-pitched, not synthesised live:
# per-frame synthesis in script cost ~30 ms a frame in the browser.

const RATE := 22050
const VOICES := 8
const ENGINE_LOOP_HZ := 50.0 # fundamental of the rendered loop (a whole number of cycles per second)

var sounds: Dictionary = {}
var players: Array = []
var next_voice: int = 0
var engine_speed: float = 0.0 # m/s
var engine_is_synth: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	sounds["horn"] = make(horn())
	sounds["coin"] = make(coin())
	sounds["crash"] = make(crash())
	sounds["pothole"] = make(pothole())
	sounds["siren"] = make(siren())
	sounds["whoosh"] = make(whoosh())
	sounds["drop"] = make(drop())
	sounds["click"] = make(tone([900.0], 0.05, 0.25))
	# Real recordings win: any res://assets/audio/sfx/<name>.ogg|.wav replaces the synth.
	for name in sounds.keys():
		for ext in ["ogg", "wav", "mp3"]:
			var path = "res://assets/audio/sfx/%s.%s" % [name, ext]
			if ResourceLoader.exists(path):
				sounds[name] = load(path)
				recorded[name] = true
				break
	setup_music()
	for ext in ["ogg", "wav", "mp3"]:
		var path = "res://assets/audio/sfx/engine_loop.%s" % ext
		if ResourceLoader.exists(path):
			engine_sample = load(path)
			break
	if engine_sample == null:
		engine_sample = make(engine_loop())
		engine_sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		engine_sample.loop_end = RATE * ENGINE_LOOP_SECONDS
		engine_is_synth = true
		sample_player.volume_db = -16.0
	sample_player.stream = engine_sample
	load_muted()
	# Every sound plays through the browser's own audio ("sample" playback). Mixing inside
	# Godot runs on the game's thread on the web, and every hitch crackled the speakers,
	# even while paused. Each engine pitch change restarts the browser sound, so the pitch
	# moves in steps (ENGINE_PITCH_STEP) rather than every frame.

# The owner's recordings (assets/audio/sfx) sit in the background for now; real voices come
# later. Extra trim per recording, on top of each call's own volume.
const RECORDING_TRIM := {"horn": -5.0}
var recorded: Dictionary = {}

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0):
	if not sounds.has(name) or muted:
		return
	var p: AudioStreamPlayer = players[next_voice]
	next_voice = (next_voice + 1) % VOICES
	p.stream = sounds[name]
	p.volume_db = volume_db + (RECORDING_TRIM.get(name, 0.0) if recorded.has(name) else 0.0)
	p.pitch_scale = pitch
	p.play()

# ------------------------------------------------------------------ voices
# Owner's voice callouts (assets/audio/voice, cleaned with a slight room echo). One player
# per speaker ("mate", "passenger", "mechanic"), so a speaker never talks over themselves.
# Every voice sits under the music and the street: VOICE_DB on top of each call's own level.
const VOICE_DB := -4.0
var voice_streams: Dictionary = {}
var voice_players: Dictionary = {}

# Returns the clip's length in seconds (0 if there's no such clip).
func play_voice(id: String, volume_db: float, speaker: String) -> float:
	if not voice_streams.has(id):
		var path = "res://assets/audio/voice/%s.wav" % id
		voice_streams[id] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = voice_streams[id]
	if stream == null:
		return 0.0
	if not muted:
		if not voice_players.has(speaker):
			var p = AudioStreamPlayer.new()
			add_child(p)
			voice_players[speaker] = p
		var player: AudioStreamPlayer = voice_players[speaker]
		player.stream = stream
		player.volume_db = volume_db + VOICE_DB
		player.play()
	return stream.get_length()

func stop_voice(speaker: String):
	if voice_players.has(speaker):
		voice_players[speaker].stop()

func voice_playing(speaker: String) -> bool:
	return voice_players.has(speaker) and voice_players[speaker].playing

func set_engine(on: bool, speed: float):
	engine_speed = speed
	on = on and not muted # (the bus mute alone may not reach the browser's own sounds)
	if on and not sample_player.playing:
		sample_player.play()
	elif not on and sample_player.playing:
		sample_player.stop()
	var pitch: float
	if engine_is_synth:
		# Same pitch curve the live synth had: 38 Hz idle rising 2.6 Hz per m/s.
		pitch = (38.0 + speed * 2.6) / ENGINE_LOOP_HZ
	else:
		pitch = clampf(0.75 + speed / 40.0, 0.7, 1.6) # a recorded loop
	pitch = snappedf(pitch, ENGINE_PITCH_STEP)
	# Each change restarts the browser sound (a tiny click), so change at most every 2 s.
	var now = Time.get_ticks_msec()
	if absf(pitch - sample_player.pitch_scale) > 0.001 and now - last_pitch_change > 2000:
		sample_player.pitch_scale = pitch
		last_pitch_change = now
	if sample_player.stream_paused != get_tree().paused:
		sample_player.stream_paused = get_tree().paused

# ------------------------------------------------------------------ music
# res://assets/audio/music/ (owner's tracks):
#   music_menu  - cover screen, day-complete and game-over screens ("Griot Strings")
#   music_main  - while driving ("Savanna Drive")
#   music_intense (optional) - crossfades in during tense moments (set_intensity)
# set_music("menu"/"game") crossfades between the two. The driving track pauses with the
# pause menu; the menu track keeps playing on its (paused-game) screens.

const MUSIC_DB := -8.0
const ENGINE_PITCH_STEP := 0.2
var last_pitch_change: int = -100000
# The music files were trimmed to where the music really ends (tools/trim_mp3.py), so they
# loop with no silent gap.
const MUSIC_FADE := 1.2 # seconds
var engine_sample: AudioStream
var sample_player: AudioStreamPlayer
var music_main: AudioStreamPlayer
var music_intense: AudioStreamPlayer
var music_menu: AudioStreamPlayer
var music_mode: String = ""
var intensity: float = 0.0
var intensity_goal: float = 0.0
var menu_mix: float = 0.0 # 1 = menu track fully up, 0 = driving track
var menu_mix_goal: float = 0.0

func setup_music():
	sample_player = AudioStreamPlayer.new()
	sample_player.volume_db = -10.0
	add_child(sample_player)
	if OS.has_feature("web"):
		var has_page_music = JavaScriptBridge.eval("typeof window.trotroMusic === 'function'")
		print("[music] page music available: ", has_page_music)
		if has_page_music:
			page_music = true
			return
	music_main = make_music_player("music_main")
	music_intense = make_music_player("music_intense")
	music_menu = make_music_player("music_menu")

func make_music_player(name: String) -> AudioStreamPlayer:
	for ext in ["ogg", "mp3", "wav"]:
		var path = "res://assets/audio/music/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			var p = AudioStreamPlayer.new()
			var stream = load(path)
			if "loop" in stream:
				stream.loop = true
			p.stream = stream
			p.volume_db = -80.0
			add_child(p)
			return p
	return null

# Web builds: the page streams the music itself (tools/web/loader.html, trotroMusic()), so
# the songs aren't part of the game download and play on the browser's own audio path.
var page_music: bool = false
var page_hold: bool = false

func set_music(mode: String):
	if mode == music_mode:
		return
	music_mode = mode
	if page_music:
		JavaScriptBridge.eval("window.trotroMusic('%s')" % mode)
		return
	menu_mix_goal = 1.0 if mode == "menu" else 0.0
	for p in [music_menu if mode == "menu" else music_main, music_intense if mode == "game" else null]:
		if p and not p.playing:
			p.play()

# Sound on/off (the mute button on the cover and in the pause menu); remembered on the device.
# Music on/off (Settings) only silences the songs; sound on/off silences everything.
const SETTINGS_PATH := "user://settings.cfg"
var muted: bool = false
var music_muted: bool = false

func load_muted():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
		music_muted = bool(cfg.get_value("audio", "music_muted", false))
	apply_muted()

func set_muted(on: bool):
	muted = on
	apply_muted()
	save_setting("muted", on)

func set_music_muted(on: bool):
	music_muted = on
	apply_muted()
	save_setting("music_muted", on)

func save_setting(key: String, value):
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep anything else in it
	cfg.set_value("audio", key, value)
	cfg.save(SETTINGS_PATH)

func apply_muted():
	AudioServer.set_bus_mute(0, muted)
	if page_music:
		JavaScriptBridge.eval("window.trotroMusic('%s')" % ("mute" if muted or music_muted else "unmute"))
		JavaScriptBridge.eval("window.trotroAmbience && window.trotroAmbience('%s')" % ("mute" if muted else "unmute"))

# ------------------------------------------------------------------ street background
# Owner's recordings of Accra streets (assets/audio/ambience), quietly under the music while
# driving; HUD picks "busy" / "some" / "quiet" / "off". On the web the page streams them
# (trotroAmbience in tools/web/loader.html); elsewhere Godot plays and crossfades them.
const AMB_DB := {"busy": -4.4, "some": -15.9, "quiet": -8.4} # balanced against each other
var ambience: String = "off"
var amb_players: Dictionary = {}
var amb_level: Dictionary = {}

func set_ambience(mode: String):
	if mode == ambience:
		return
	ambience = mode
	if page_music:
		JavaScriptBridge.eval("window.trotroAmbience && window.trotroAmbience('%s')" % mode)
		return
	if amb_players.is_empty():
		for k in AMB_DB:
			var path = "res://assets/audio/ambience/amb_%s.mp3" % k
			if ResourceLoader.exists(path):
				var p = AudioStreamPlayer.new()
				var stream = load(path)
				stream.loop = true
				p.stream = stream
				p.volume_db = -80.0
				add_child(p)
				amb_players[k] = p
				amb_level[k] = 0.0

func update_ambience(delta: float):
	for k in amb_players:
		var p: AudioStreamPlayer = amb_players[k]
		amb_level[k] = move_toward(amb_level[k], 1.0 if k == ambience else 0.0, delta / 1.5)
		if amb_level[k] > 0.0 and not p.playing:
			p.play()
		elif amb_level[k] <= 0.0 and p.playing:
			p.stop()
		var db = linear_to_db(maxf(amb_level[k], 0.0001)) + AMB_DB[k]
		if absf(db - p.volume_db) > 0.05:
			p.volume_db = db
		p.stream_paused = get_tree().paused

func set_intensity(v: float):
	intensity_goal = clampf(v, 0.0, 1.0)

func update_music(delta: float):
	if page_music:
		var hold_now = get_tree().paused and music_mode == "game"
		if hold_now != page_hold:
			page_hold = hold_now
			JavaScriptBridge.eval("window.trotroMusic('%s')" % ("pause" if hold_now else "resume"))
		return
	intensity = move_toward(intensity, intensity_goal, delta * 0.8)
	menu_mix = move_toward(menu_mix, menu_mix_goal, delta / MUSIC_FADE)
	var game_level = 0.0 if music_muted else 1.0 - menu_mix
	if music_main:
		var main_level = game_level * (lerpf(1.0, 0.25, intensity) if music_intense else 1.0)
		set_volume(music_main, main_level)
	if music_intense:
		set_volume(music_intense, game_level * intensity)
	if music_menu:
		set_volume(music_menu, 0.0 if music_muted else menu_mix)
		if menu_mix <= 0.0 and music_menu.playing:
			music_menu.stop() # restarts from the top next time the cover comes up
	# The driving music pauses with the pause menu (but not during the cross-fade to it).
	var hold = get_tree().paused and music_mode == "game"
	for m in [music_main, music_intense]:
		if m and m.stream_paused != hold:
			m.stream_paused = hold

# Only touch a player's volume when it actually changes (each change goes to the browser).
func set_volume(p: AudioStreamPlayer, level: float):
	var db = linear_to_db(maxf(level, 0.0001)) + MUSIC_DB
	if absf(db - p.volume_db) > 0.05:
		p.volume_db = db

func _process(delta):
	update_music(delta)
	if not page_music:
		update_ambience(delta)

# ENGINE_LOOP_SECONDS of diesel-ish hum at ENGINE_LOOP_HZ: fundamental + harmonics +
# rumble, seamless at the loop point; set_engine() re-pitches it. Long on purpose: in the
# browser each pass of the loop restarts the sound, which can click.
const ENGINE_LOOP_SECONDS := 12
func engine_loop() -> PackedFloat32Array:
	# One seamless second, copied ENGINE_LOOP_SECONDS times (cheap to build at start-up).
	var n = RATE
	var out = PackedFloat32Array()
	out.resize(n)
	var noise = PackedFloat32Array()
	noise.resize(n)
	var lp = 0.0
	for i in n:
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.08)
		noise[i] = lp
	# Ease the rumble's tail onto its first sample so there's no click at the loop point.
	var fade = 2000
	for i in fade:
		var k = float(i + 1) / fade
		noise[n - fade + i] = lerpf(noise[n - fade + i], noise[0], k * k)
	for i in n:
		var ph = float(i) * ENGINE_LOOP_HZ / RATE * TAU
		var s = sin(ph) * 0.55 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.12
		out[i] = (s + noise[i] * 0.25) * 0.5
	var long = PackedFloat32Array()
	for i in ENGINE_LOOP_SECONDS:
		long.append_array(out)
	return long

# ------------------------------------------------------------------ synthesis

func make(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w

func env(t: float, length: float, attack: float = 0.01, release: float = 0.05) -> float:
	if t < attack:
		return t / attack
	if t > length - release:
		return maxf(0.0, (length - t) / release)
	return 1.0

func tone(freqs: Array, length: float, gain: float) -> PackedFloat32Array:
	var n = int(length * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t = float(i) / RATE
		var s = 0.0
		for f in freqs:
			s += sin(TAU * f * t)
		out[i] = s / freqs.size() * gain * env(t, length)
	return out

# Two-tone "beep-beep" like a minibus horn: slightly clipped square-ish chord.
func horn() -> PackedFloat32Array:
	var out = PackedFloat32Array()
	for blast in [0.22, 0.34]:
		var n = int(blast * RATE)
		for i in n:
			var t = float(i) / RATE
			var s = sin(TAU * 415.0 * t) + sin(TAU * 523.0 * t) + 0.4 * sin(TAU * 830.0 * t)
			out.append(clampf(s * 0.9, -0.8, 0.8) * 0.55 * env(t, blast, 0.005, 0.03))
		for i in int(0.07 * RATE):
			out.append(0.0)
	return out

func coin() -> PackedFloat32Array:
	var a = tone([988.0, 1976.0], 0.09, 0.35)
	var b = tone([1319.0, 2637.0], 0.28, 0.35)
	for i in b.size():
		b[i] *= exp(-float(i) / RATE * 7.0)
	a.append_array(b)
	return a

func crash() -> PackedFloat32Array:
	var n = int(0.5 * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var lp = 0.0
	for i in n:
		var t = float(i) / RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.35 - t * 0.5)
		out[i] = (lp * 1.4 + sin(TAU * 55.0 * t) * 0.5) * exp(-t * 7.0) * 0.8
	return out

func pothole() -> PackedFloat32Array:
	var n = int(0.28 * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var lp = 0.0
	for i in n:
		var t = float(i) / RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.15)
		out[i] = (sin(TAU * (90.0 - t * 150.0) * t) * 0.9 + lp * 0.5) * exp(-t * 14.0) * 0.8
	return out

func siren() -> PackedFloat32Array:
	var length = 1.6
	var n = int(length * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var phase = 0.0
	for i in n:
		var t = float(i) / RATE
		var f = 700.0 + 250.0 * sin(TAU * 1.25 * t) # wail
		phase += f / RATE
		out[i] = sin(TAU * phase) * 0.35 * env(t, length, 0.05, 0.2)
	return out

func whoosh() -> PackedFloat32Array:
	var length = 0.7
	var n = int(length * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var lp = 0.0
	for i in n:
		var t = float(i) / RATE
		var k = 0.05 + 0.4 * (t / length)
		lp = lerpf(lp, randf_range(-1.0, 1.0), k)
		out[i] = lp * 0.6 * sin(PI * t / length)
	return out

func drop() -> PackedFloat32Array:
	var a = tone([660.0], 0.12, 0.3)
	a.append_array(tone([523.0], 0.22, 0.3))
	return a
