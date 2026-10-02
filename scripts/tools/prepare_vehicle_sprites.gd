extends SceneTree

# One-off asset tool: imports the approved traffic sprites from the web
# reference folder into res://assets/vehicles/.
#   godot --headless --path . --script res://scripts/tools/prepare_vehicle_sprites.gd
# - trims transparent padding so the wheels sit on the image's bottom edge
# - downsizes to MAX_SIZE px (phones don't need 1500 px sprites)
# - fixes taxi + rival_trotro, whose left/right 3/4 files are swapped in the source
# Source originals are never modified.

const SOURCE_DIR = "C:/Users/sedof/Downloads/trotrorush.dev"
const MAX_SIZE = 640
const VEHICLES = ["taxi", "sedan", "suv", "pickup", "van", "rival_trotro"]
const SWAPPED_SIDES = ["taxi", "rival_trotro"]

func _init():
	for vehicle in VEHICLES:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/vehicles/%s" % vehicle))
		for view in ["rear", "left_rear_3q", "right_rear_3q"]:
			var src_view = view
			if vehicle in SWAPPED_SIDES and view != "rear":
				src_view = "right_rear_3q" if view == "left_rear_3q" else "left_rear_3q"
			var src = "%s/%s/%s_%s.png" % [SOURCE_DIR, vehicle, vehicle, src_view]
			var img = Image.load_from_file(src)
			if img == null:
				push_error("Missing source sprite: " + src)
				continue
			img.convert(Image.FORMAT_RGBA8)
			# Work at an intermediate size so the per-pixel clean-up stays fast.
			var pre = minf(1.0, float(MAX_SIZE * 1.5) / maxf(img.get_width(), img.get_height()))
			img.resize(int(img.get_width() * pre), int(img.get_height() * pre), Image.INTERPOLATE_LANCZOS)
			remove_alpha_haze(img)
			img = img.get_region(img.get_used_rect())
			var scale = minf(1.0, float(MAX_SIZE) / maxf(img.get_width(), img.get_height()))
			img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)
			var dst = "res://assets/vehicles/%s/%s_%s.png" % [vehicle, vehicle, view]
			img.save_png(ProjectSettings.globalize_path(dst))
			print("%s <- %s_%s  %dx%d" % [dst, vehicle, src_view, img.get_width(), img.get_height()])
	# Player trotro: clean the haze in place only. Size and framing are kept, since the
	# player scene's pixel_size/offset are tuned to these exact dimensions.
	for f in ["player_trotro_rear", "player_trotro_left_rear_3q", "player_trotro_right_rear_3q"]:
		var path = ProjectSettings.globalize_path("res://assets/vehicles/player_trotro/%s.png" % f)
		var p = Image.load_from_file(path)
		if p == null:
			continue
		p.convert(Image.FORMAT_RGBA8)
		remove_alpha_haze(p)
		p.save_png(path)
		print("cleaned ", path)
	quit()

# The source cut-outs carry thousands of near-invisible (alpha < ~8%) pixels left
# over from background removal; they render as a dirty halo/box and defeat trimming.
func remove_alpha_haze(img: Image, threshold: int = 20):
	var data = img.get_data()
	for i in range(3, data.size(), 4):
		if data[i] < threshold:
			data[i] = 0
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
