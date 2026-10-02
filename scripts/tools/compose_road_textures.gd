extends SceneTree

# Builds the road textures from the generated asphalt (no API calls):
#   road_accra.png   - asphalt + worn/faded white lane markings for the 11 m, 3-lane road.
#                      One texture = full road width x 12 m of road length.
#   kerb_stripes.png - weathered black/white painted kerb blocks (1 m each), as in Accra.
#   godot --headless --path . --script res://scripts/tools/compose_road_textures.gd

const ROAD_WIDTH_M := 11.0
const TILE_LENGTH_M := 12.0
const LINE_WIDTH_M := 0.13
const DASH_M := 3.0 # dash length; the gap is also 3 m (2 dashes per tile)

var noise := FastNoiseLite.new()

func _init():
	noise.seed = 7
	noise.frequency = 0.02
	var base = Image.load_from_file(ProjectSettings.globalize_path("res://assets/environment/asphalt_accra.png"))
	base.convert(Image.FORMAT_RGBA8)
	tone_down(base)
	var w = base.get_width()
	var h = base.get_height()
	var px_per_m = w / ROAD_WIDTH_M
	var line_px = int(LINE_WIDTH_M * px_per_m)
	var paint = Color(0.93, 0.93, 0.9)
	# Edge lines just inside each kerb; dashed dividers between the 3 lanes.
	for x_m in [0.35, ROAD_WIDTH_M - 0.35]:
		paint_line(base, int(x_m * px_per_m), line_px, paint, false, h)
	for x_m in [ROAD_WIDTH_M / 3.0, ROAD_WIDTH_M * 2.0 / 3.0]:
		paint_line(base, int(x_m * px_per_m), line_px, paint, true, h)
	base.convert(Image.FORMAT_RGB8)
	base.save_png(ProjectSettings.globalize_path("res://assets/environment/road_accra.png"))
	print("wrote road_accra.png ", base.get_size())
	make_kerb()
	quit()

# The generated asphalt reads as pale loose gravel up close: soften the stone
# contrast (blend with a blurred copy) and darken it to sun-worn tarmac.
func tone_down(img: Image):
	var blurred = img.duplicate()
	blurred.resize(img.get_width() / 8, img.get_height() / 8, Image.INTERPOLATE_BILINEAR)
	blurred.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	for y in img.get_height():
		for x in img.get_width():
			var c = img.get_pixel(x, y).lerp(blurred.get_pixel(x, y), 0.55)
			var grey = (c.r + c.g + c.b) / 3.0
			c = c.lerp(Color(grey, grey, grey), 0.35) * 0.62
			c.a = 1.0
			img.set_pixel(x, y, c)

func paint_line(img: Image, cx: int, width: int, paint: Color, dashed: bool, h: int):
	var px_per_m_v = h / TILE_LENGTH_M
	for y in h:
		if dashed:
			var m = fmod(y / px_per_m_v, DASH_M * 2.0)
			if m > DASH_M:
				continue
		for x in range(cx - width / 2, cx + width / 2 + 1):
			# Sun-faded paint: patchy coverage, worn more in tyre-free spots randomly.
			var wear = (noise.get_noise_2d(x * 3.0, y * 1.5) + 1.0) * 0.5
			var chip = noise.get_noise_2d(x * 40.0, y * 40.0)
			var strength = clampf(0.35 + wear * 0.6, 0.0, 0.85)
			if chip > 0.45:
				strength *= 0.3
			var under = img.get_pixel(x, y)
			img.set_pixel(x, y, under.lerp(paint, strength))

func make_kerb():
	# 256 x 64: u runs along the road (2 m = one black + one white block), v across the kerb.
	var img = Image.create(256, 64, false, Image.FORMAT_RGB8)
	var white = Color(0.86, 0.85, 0.8)
	var black = Color(0.12, 0.12, 0.12)
	for y in 64:
		for x in 256:
			var c = white if x < 128 else black
			var grime = (noise.get_noise_2d(x * 6.0, y * 6.0) + 1.0) * 0.5
			var dust = Color(0.55, 0.48, 0.4)
			c = c.lerp(dust, 0.12 + grime * 0.25)
			if x % 128 < 3: # joint between kerb blocks
				c = c.darkened(0.45)
			img.set_pixel(x, y, c)
	img.save_png(ProjectSettings.globalize_path("res://assets/environment/kerb_stripes.png"))
	print("wrote kerb_stripes.png")
