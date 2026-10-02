extends SceneTree

# Turns raw images from tools/imagegen/raw/ into game-ready sprites (no API calls).
#   godot --headless --path . --script res://scripts/tools/process_generated_images.gd
# For each job in tools/imagegen/jobs.json that has a raw image:
#   magenta chroma-key (only if the model didn't return real transparency)
#   -> remove near-invisible haze -> optional split into columns -> trim -> downsize
#   -> save to the job's outputs (+ a horizontally mirrored copy if mirror_output is set).

const KEY_COLOR := Color(1.0, 0.0, 1.0)
const KEY_TOLERANCE := 0.35
const HAZE_ALPHA := 20

func _init():
	var root_dir = ProjectSettings.globalize_path("res://")
	var jobs_doc = JSON.parse_string(FileAccess.get_file_as_string(root_dir + "tools/imagegen/jobs.json"))
	# Optional: -- id1,id2 processes only those jobs (leaves every other output untouched).
	var only: Array = []
	var user_args = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		only = Array(user_args[0].split(","))
	for job in jobs_doc["jobs"]:
		if not only.is_empty() and not only.has(job["id"]):
			continue
		var raw_path = root_dir + "tools/imagegen/raw/%s.png" % job["id"]
		if not FileAccess.file_exists(raw_path):
			continue
		var img = Image.load_from_file(raw_path)
		img.convert(Image.FORMAT_RGBA8)
		if job.get("kind", "sprite") == "texture":
			process_texture(job, img, root_dir)
			continue
		if not has_real_transparency(img):
			chroma_key(img)
		remove_haze(img)
		var parts = split_columns(img, int(job.get("split", 1)))
		for i in parts.size():
			if i >= job["outputs"].size():
				break
			var part: Image = parts[i]
			if parts.size() > 1:
				keep_main_blob(part) # drop scraps of the neighbouring subject cut by the split
			var used = part.get_used_rect()
			if used.size.x <= 0 or used.size.y <= 0:
				push_error("%s part %d is empty after keying" % [job["id"], i])
				continue
			part = part.get_region(used)
			fit(part, int(job.get("max_size", 512)))
			var out = root_dir + job["outputs"][i]
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			part.save_png(out)
			print("wrote ", job["outputs"][i], " ", part.get_size())
			if i == 0 and job.has("mirror_output"):
				var mirrored = part.duplicate()
				mirrored.flip_x()
				var mout = root_dir + job["mirror_output"]
				mirrored.save_png(mout)
				print("wrote ", job["mirror_output"], " (mirrored)")
	quit()

# Opaque surface textures (ground, asphalt, walls): no keying or trimming.
# "tileable": blend in a half-offset copy near the edges so the texture repeats without seams.
func process_texture(job: Dictionary, img: Image, root_dir: String):
	var size = int(job.get("max_size", 1024))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if job.get("tileable", false):
		img = make_tileable(img)
	img.convert(Image.FORMAT_RGB8)
	var out = root_dir + job["outputs"][0]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("wrote ", job["outputs"][0], " ", img.get_size(), " (texture)")

func make_tileable(img: Image) -> Image:
	var w = img.get_width()
	var h = img.get_height()
	var out = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var margin = 0.3 # fraction of the half-size used for the cross-fade
	for y in h:
		for x in w:
			var a = img.get_pixel(x, y)
			var b = img.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			# 0 in the middle of the image, 1 at its edges: edges come from the shifted
			# copy (whose own seams sit in the middle, where the original is used).
			var ex = absf(float(x) / (w - 1) - 0.5) * 2.0
			var ey = absf(float(y) / (h - 1) - 0.5) * 2.0
			var t = smoothstep(1.0 - margin, 1.0, maxf(ex, ey))
			out.set_pixel(x, y, a.lerp(b, t))
	return out

func has_real_transparency(img: Image) -> bool:
	# If the corners are already see-through, the API honoured background=transparent.
	var w = img.get_width() - 1
	var h = img.get_height() - 1
	for p in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		if img.get_pixelv(p).a > 0.1:
			return false
	return true

func chroma_key(img: Image):
	for y in img.get_height():
		for x in img.get_width():
			var c = img.get_pixel(x, y)
			var d = Vector3(c.r - KEY_COLOR.r, c.g - KEY_COLOR.g, c.b - KEY_COLOR.b).length()
			if d < KEY_TOLERANCE:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d < KEY_TOLERANCE * 1.6:
				# Edge pixels: fade out and pull the magenta spill back toward neutral.
				var a = clampf((d - KEY_TOLERANCE) / (KEY_TOLERANCE * 0.6), 0.0, 1.0)
				var g = c.g
				img.set_pixel(x, y, Color(minf(c.r, g + 0.25), g, minf(c.b, g + 0.25), c.a * a))

func remove_haze(img: Image):
	var data = img.get_data()
	for i in range(3, data.size(), 4):
		if data[i] < HAZE_ALPHA:
			data[i] = 0
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)

# Keeps only the largest connected opaque region (on a 1/4-scale mask, slightly grown
# so detached leaves/fingers near the subject survive) and clears everything else.
func keep_main_blob(img: Image):
	var s = 4
	var mw = img.get_width() / s
	var mh = img.get_height() / s
	var solid = PackedByteArray()
	solid.resize(mw * mh)
	for y in mh:
		for x in mw:
			solid[y * mw + x] = 1 if img.get_pixel(x * s + s / 2, y * s + s / 2).a > 0.3 else 0
	var label = PackedInt32Array()
	label.resize(mw * mh)
	label.fill(-1)
	var best_id = -1
	var best_size = 0
	var next_id = 0
	for start in mw * mh:
		if solid[start] == 0 or label[start] >= 0:
			continue
		var stack = [start]
		label[start] = next_id
		var size = 0
		while not stack.is_empty():
			var i = stack.pop_back()
			size += 1
			var cx = i % mw
			var cy = i / mw
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx = cx + dx
					var ny = cy + dy
					if nx < 0 or ny < 0 or nx >= mw or ny >= mh:
						continue
					var j = ny * mw + nx
					if solid[j] == 1 and label[j] < 0:
						label[j] = next_id
						stack.append(j)
		if size > best_size:
			best_size = size
			best_id = next_id
		next_id += 1
	if next_id <= 1:
		return
	# Grow the kept region by 3 mask cells, then clear pixels outside it.
	var keep = PackedByteArray()
	keep.resize(mw * mh)
	for i in mw * mh:
		if label[i] == best_id:
			var cx = i % mw
			var cy = i / mw
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var nx = cx + dx
					var ny = cy + dy
					if nx >= 0 and ny >= 0 and nx < mw and ny < mh:
						keep[ny * mw + nx] = 1
	for y in img.get_height():
		for x in img.get_width():
			var mx = mini(x / s, mw - 1)
			var my = mini(y / s, mh - 1)
			if keep[my * mw + mx] == 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

func split_columns(img: Image, n: int) -> Array:
	if n <= 1:
		return [img]
	var out = []
	var w = img.get_width() / n
	for i in n:
		out.append(img.get_region(Rect2i(i * w, 0, w, img.get_height())))
	return out

func fit(img: Image, max_size: int):
	var s = minf(1.0, float(max_size) / maxf(img.get_width(), img.get_height()))
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
