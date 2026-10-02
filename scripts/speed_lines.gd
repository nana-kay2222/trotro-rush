extends Control

# Subtle streaks rushing out from the edges of the screen when the trotro is flying
# (high speed or a boost). Pure 2D overlay, cheap to draw.

const COUNT := 26

var player: Node3D
var lines: Array = []
var intensity: float = 0.0

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in COUNT:
		lines.append(new_line())

func new_line() -> Dictionary:
	# Angle around the screen centre; lines live near the edges, not over the road.
	return {"angle": randf() * TAU, "pos": randf_range(0.55, 1.0), "len": randf_range(0.08, 0.2), "speed": randf_range(1.6, 2.6)}

func _process(delta: float):
	if player == null:
		return
	var goal = 0.0
	if player.has_method("is_boosting") and player.is_boosting():
		goal = 1.0
	elif player.current_speed > player.speeding_threshold:
		goal = clampf((player.current_speed - player.speeding_threshold) / 6.0, 0.0, 0.45)
	if GameState.is_over:
		goal = 0.0
	intensity = move_toward(intensity, goal, delta * 2.0)
	if intensity <= 0.01:
		queue_redraw()
		return
	for l in lines:
		l["pos"] += l["speed"] * delta
		if l["pos"] > 1.25:
			var n = new_line()
			n["pos"] = 0.55
			l.merge(n, true)
	queue_redraw()

func _draw():
	if intensity <= 0.01:
		return
	var c = size * 0.5
	var r = size.length() * 0.5
	for l in lines:
		var dir = Vector2.RIGHT.rotated(l["angle"])
		var a = c + dir * r * l["pos"]
		var b = c + dir * r * (l["pos"] + l["len"])
		draw_line(a, b, Color(1, 1, 1, 0.22 * intensity), 3.0, true)
