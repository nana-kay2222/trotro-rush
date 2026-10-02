extends SceneTree

# Owner's turbo icon (glowing blue chevrons on black) -> assets/ui/turbo_icon.png:
# cropped to the badge, rotated so the arrows point up, black turned into transparency
# (the glow keeps its soft edge: alpha follows brightness), sized for the HUD.
#   godot --headless --path . --script res://scripts/tools/make_turbo_icon.gd

const SRC := "res://tools/imagegen/raw/turbo_icon_src.jpg"
const OUT := "res://assets/ui/turbo_icon.png"
const SIZE := 256

func _init():
	var img = Image.load_from_file(ProjectSettings.globalize_path(SRC))
	img.convert(Image.FORMAT_RGBA8)
	# Square crop around the badge (it sits in the middle of the picture).
	var side = img.get_height()
	var x0 = (img.get_width() - side) / 2
	img = img.get_region(Rect2i(x0, 0, side, side))
	img.rotate_90(COUNTERCLOCKWISE) # arrows pointed right -> now point up
	for y in img.get_height():
		for x in img.get_width():
			var c = img.get_pixel(x, y)
			var v = maxf(c.r, maxf(c.g, c.b))
			var a = clampf((v - 0.04) / 0.35, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Un-premultiply against black so the glow stays blue, not grey.
				img.set_pixel(x, y, Color(minf(c.r / a, 1.0), minf(c.g / a, 1.0), minf(c.b / a, 1.0), a))
	var used = img.get_used_rect()
	img = img.get_region(used)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
