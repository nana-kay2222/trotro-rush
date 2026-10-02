extends SceneTree

# Measures every processed kit elevation (assets/buildings/kit/<name>_side.png + _end.png)
# and writes assets/buildings/kit/buildings.json with real-world dimensions, so the
# 3D building exactly fits its artwork. No API calls.
#   godot --headless --path . --script res://scripts/tools/build_building_kit.gd
#
# Scale comes from the eave height in metres per building (WALL_HEIGHT). The end
# elevation gives metres-per-pixel, which yields depth and ridge height; the side
# elevation's aspect ratio then gives the length.

const KIT = "res://assets/buildings/kit/"
const WALL_HEIGHT := {
	"pharmacy": 3.8, "compound_house_large": 3.6, "provision_shop": 3.6, "long_shop_row": 3.8,
	"chop_bar_local_food": 3.8, "telecom_electronics": 4.0, "momo_stall": 3.8, "drinking_spot_pub": 3.6,
	"mechanic_auto_shop": 4.2, "commercial_block_two_storey": 7.0, "commercial_block_two_storey_alt": 7.0,
	"compound_house_small": 3.4, "compound_house_large_alt": 3.6, "unfinished_concrete_building": 3.6,
	"church": 5.2, "school": 7.0, "apartment_block_medium": 9.2, "apartment_block_large": 9.6,
	"roadside_market_structure": 4.0,
	"stop_fitter": 4.2, # mechanic stop only ("stop_" buildings never appear as random roadside)
}

func _init():
	var out = {}
	for name in WALL_HEIGHT:
		var side_path = ProjectSettings.globalize_path(KIT + name + "_side.png")
		var end_path = ProjectSettings.globalize_path(KIT + name + "_end.png")
		if not FileAccess.file_exists(side_path) or not FileAccess.file_exists(end_path):
			continue
		var side = Image.load_from_file(side_path)
		var end_img = Image.load_from_file(end_path)
		var m = measure_end(end_img)
		var h_wall: float = WALL_HEIGHT[name]
		var ppm = float(m["wall_px"]) / h_wall
		out[name] = {
			"side": KIT + name + "_side.png",
			"end": KIT + name + "_end.png",
			"wall_height": h_wall,
			"length": snappedf(h_wall * float(side.get_width()) / side.get_height(), 0.01),
			"depth": snappedf(float(m["xr"] - m["xl"]) / ppm, 0.01),
			"ridge_height": snappedf(float(end_img.get_height()) / ppm, 0.01),
			"end_width": snappedf(float(end_img.get_width()) / ppm, 0.01),
			"end_wall_left": snappedf(float(m["xl"]) / ppm, 0.01), # metres from image left to wall's left edge
			"roof_color": m["roof_color"].to_html(false),
		}
		print(name, " ", out[name])
	var f = FileAccess.open(ProjectSettings.globalize_path(KIT + "buildings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote buildings.json with ", out.size(), " buildings")
	quit()

func measure_end(img: Image) -> Dictionary:
	img.convert(Image.FORMAT_RGBA8)
	var w = img.get_width()
	var h = img.get_height()
	# Eave line, found from the top down: the gable triangle widens until the eaves, which
	# are the widest part of the upper image. (Scanning from the bottom is unreliable:
	# compound walls and gates in front of a house are wider than the house itself.)
	# A flat-roofed building is already widest at the top, so its wall is the full height.
	var widths = []
	for y in h:
		var ext = row_extent(img, y)
		widths.append(ext.y - ext.x if ext.x >= 0 else 0)
	var upper = int(h * 0.5) # eaves are always in the top half; gate pillars/walls sit lower
	var max_w = 0
	for y in upper:
		max_w = maxi(max_w, widths[y])
	var wall_top = 0
	for y in upper:
		if widths[y] >= max_w * 0.97:
			wall_top = y
			break
	# Wall extent (for depth): just below the eaves.
	var ext_row = row_extent(img, wall_top + int((h - wall_top) * 0.15))
	var xl = ext_row.x
	var xr = ext_row.y
	# Roof colour: average of the opaque pixels in the top 6% of the image (roof edge / ridge).
	var acc = Color(0, 0, 0, 0)
	var n = 0
	for y in int(h * 0.06):
		for x in range(0, w, 3):
			var c = img.get_pixel(x, y)
			if c.a > 0.5:
				acc += c
				n += 1
	var roof = Color(0.5, 0.5, 0.52) if n == 0 else Color(acc.r / n, acc.g / n, acc.b / n)
	return {"xl": xl, "xr": xr, "wall_px": h - wall_top, "roof_color": roof}

# Leftmost and rightmost opaque pixel of a row (x = -1 if the row is empty).
func row_extent(img: Image, y: int) -> Vector2i:
	var l = -1
	var r = -1
	for x in range(0, img.get_width(), 2):
		if img.get_pixel(x, y).a > 0.5:
			if l < 0: l = x
			r = x
	return Vector2i(l, r)
