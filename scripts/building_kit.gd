class_name BuildingKit
extends RefCounted

# Builds low-poly buildings from the kit elevations (GAME_SPEC §18: simple 3D body +
# correctly mapped 2D artwork, never a perspective image wrapped on a box).
# Local space of a built building:
#   x = 0 is the road-facing wall; the body extends away from the road toward side * X
#   (side = -1 for buildings left of the road, +1 for the right). z = 0 is the end facing
#   oncoming traffic; the building runs back to z = -length.
# Only surfaces the chase camera can see are built: road wall, near end (with gable), roof.

const KIT_JSON := "res://assets/buildings/kit/buildings.json"
const EAVE_OVERHANG := 0.35
const ROOF_TILE_M := 1.2

static var meta: Dictionary = {}
static var _meshes: Dictionary = {}
static var _roof_texture: ImageTexture

static func load_meta() -> Dictionary:
	if meta.is_empty() and FileAccess.file_exists(KIT_JSON):
		meta = JSON.parse_string(FileAccess.get_file_as_string(KIT_JSON))
	return meta

# length_override > 0 stretches the building to that length by repeating its road-wall
# artwork a whole number of times (used to make the fitter cover a whole stop).
static func get_mesh(name: String, side: float, length_override: float = 0.0) -> ArrayMesh:
	var key = "%s_%d_%d" % [name, int(side), int(length_override)]
	if _meshes.has(key):
		return _meshes[key]
	var m = load_meta()[name]
	var h: float = m["wall_height"]
	var l: float = m["length"] if length_override <= 0.0 else length_override
	var repeats: float = 1.0 if length_override <= 0.0 else maxf(1.0, floorf(length_override / m["length"]))
	var d: float = m["depth"]
	var r: float = maxf(m["ridge_height"], h)
	var s = side
	var mesh = ArrayMesh.new()
	var road_normal = Vector3(-s, 0, 0)

	# Road-facing wall. The viewer at the road reads the texture left-to-right; for a
	# left-hand building that runs from the near end back, for a right-hand one the reverse.
	var u_near = 0.0 if s < 0 else repeats # u runs 0..repeats across the wall
	var u_far = repeats - u_near
	add_quad(mesh, material_for(m["side"], name.begins_with("stop_")),
		[Vector3(0, 0, 0), Vector3(0, h, 0), Vector3(0, h, -l), Vector3(0, 0, -l)],
		[Vector2(u_near, 1), Vector2(u_near, 0), Vector2(u_far, 0), Vector2(u_far, 1)],
		road_normal)

	# Near end wall (faces oncoming traffic, +Z) including its gable; the transparent
	# parts of the artwork cut the outline (alpha scissor).
	var ew: float = m["end_width"]
	var el: float = m["end_wall_left"]
	var x_left: float
	if s < 0:
		x_left = -d - el # wall's right edge sits on the road-facing wall
	else:
		x_left = -el
	add_quad(mesh, material_for(m["end"], true),
		[Vector3(x_left, 0, 0.02), Vector3(x_left, m["ridge_height"], 0.02), Vector3(x_left + ew, m["ridge_height"], 0.02), Vector3(x_left + ew, 0, 0.02)],
		[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
		Vector3(0, 0, 1))

	# Roof: a gable along the road, or a flat slab if the end elevation has no gable.
	var roof = roof_material(Color(m["roof_color"]))
	var z0 = EAVE_OVERHANG
	var z1 = -l - EAVE_OVERHANG
	if r - h < 0.3:
		var y = h + 0.05
		roof_quad(mesh, roof, Vector3(-s * 0.2, y, z0), Vector3(s * (d + 0.2), y, z0), z1)
	else:
		var eave_front = Vector3(-s * EAVE_OVERHANG, h - 0.1, 0)
		var ridge = Vector3(s * d * 0.5, r, 0)
		var eave_back = Vector3(s * (d + EAVE_OVERHANG), h - 0.1, 0)
		roof_quad(mesh, roof, eave_front + Vector3(0, 0, z0), ridge + Vector3(0, 0, z0), z1)
		roof_quad(mesh, roof, ridge + Vector3(0, 0, z0), eave_back + Vector3(0, 0, z0), z1)
	_meshes[key] = mesh
	return mesh

static func add_quad(mesh: ArrayMesh, mat: Material, p: Array, uv: Array, normal: Vector3):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uv[i])
		st.add_vertex(p[i])
	st.set_material(mat)
	st.commit(mesh)

# Sloped (or flat) roof strip from edge a to edge b (both at z0), extruded back to z1.
# Corrugations run down the slope: u follows the road direction, v follows the slope.
static func roof_quad(mesh: ArrayMesh, mat: Material, a: Vector3, b: Vector3, z1: float):
	var slope = a.distance_to(Vector3(b.x, b.y, a.z))
	var run = a.z - z1
	var normal = (Vector3(b.x - a.x, b.y - a.y, 0)).cross(Vector3(0, 0, -1)).normalized()
	if normal.y < 0:
		normal = -normal
	var pts = [a, b, Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]
	var uvs = [Vector2(0, 0), Vector2(0, slope / ROOF_TILE_M), Vector2(run / ROOF_TILE_M, slope / ROOF_TILE_M), Vector2(run / ROOF_TILE_M, 0)]
	add_quad(mesh, mat, pts, uvs, normal)

static var _materials: Dictionary = {}

static func material_for(path: String, cutout: bool) -> StandardMaterial3D:
	if _materials.has(path):
		return _materials[path]
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(path)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	_materials[path] = mat
	return mat

static func roof_material(tint: Color) -> StandardMaterial3D:
	var key = "roof_" + tint.to_html(false)
	if _materials.has(key):
		return _materials[key]
	if _roof_texture == null:
		_roof_texture = make_corrugated_texture()
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = _roof_texture
	mat.albedo_color = tint.lightened(0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.6
	mat.metallic = 0.2
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = mat
	return mat

# Neutral corrugated metal (8 ridges per tile) with light rust streaks; tinted per building.
static func make_corrugated_texture() -> ImageTexture:
	var img = Image.create(128, 128, true, Image.FORMAT_RGB8)
	var noise = FastNoiseLite.new()
	noise.frequency = 0.05
	for y in 128:
		for x in 128:
			var ridge = 0.78 + 0.22 * sin(float(x) / 128.0 * TAU * 8.0)
			var rust = clampf(noise.get_noise_2d(x * 0.5, y * 3.0), 0.0, 1.0) * 0.35
			var c = Color(ridge, ridge, ridge).lerp(Color(0.55, 0.32, 0.18), rust)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
