extends SceneTree

# One-off: road_3lane.png had a yellow left edge line and a white right one
# (US divided-highway style). Make both edge lines the same white.
#   godot --headless --path . --script res://scripts/tools/fix_road_edge_line.gd
func _init():
	var path = ProjectSettings.globalize_path("res://assets/environment/road_3lane.png")
	var img = Image.load_from_file(path)
	img.convert(Image.FORMAT_RGBA8)
	var white = img.get_pixel(img.get_width() - 20, 10) # right edge line colour
	var changed = 0
	for y in img.get_height():
		for x in 48: # left edge line lives in the first ~40 px
			var c = img.get_pixel(x, y)
			if c.r > 0.6 and c.g > 0.45 and c.b < 0.35 and c.r - c.b > 0.35:
				img.set_pixel(x, y, Color(white.r, white.g, white.b, c.a))
				changed += 1
	img.save_png(path)
	print("recoloured ", changed, " px; edge white = ", white)
	quit()
