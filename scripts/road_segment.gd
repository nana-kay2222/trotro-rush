extends Node3D

# One streamed stretch of Accra road, built at runtime from simple geometry.
# Cross-section from the centre outwards (per side):
#   asphalt (3 lanes, 11 m total) | painted kerb | open concrete drain | walkway | dusty ground
# Local z runs from +NEAR_END (toward the camera) to FAR_END, same span as the old road.tscn.

const NEAR_END := 60.0
const FAR_END := -300.0
const ROAD_HALF := 5.5
const KERB_W := 0.25
const KERB_H := 0.2
const DRAIN_W := 0.8
const DRAIN_DEPTH := 0.45
const WALK_W := 2.5
const WALK_H := 0.15
const GROUND_W := 300.0
const POLE_SPACING := 40.0

static var mats: Dictionary = {}

func _ready():
	build()

static func material(key: String) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m = StandardMaterial3D.new()
	m.roughness = 0.95
	match key:
		"road":
			m.albedo_texture = load("res://assets/environment/road_accra.png")
		"kerb":
			m.albedo_texture = load("res://assets/environment/kerb_stripes.png")
		"walk":
			m.albedo_texture = load("res://assets/environment/pavement_slabs.png")
		"ground":
			m.albedo_texture = load("res://assets/environment/ground_dust.png")
		"drain":
			m.albedo_texture = load("res://assets/environment/pavement_slabs.png")
			m.albedo_color = Color(0.45, 0.43, 0.4) # shaded, stained concrete channel
		"drain_bottom":
			m.albedo_color = Color(0.16, 0.15, 0.13)
		"pole":
			m.albedo_color = Color(0.42, 0.38, 0.33)
		"wire":
			m.albedo_color = Color(0.08, 0.08, 0.08)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[key] = m
	return m

func build():
	var length = NEAR_END - FAR_END
	var mid_z = (NEAR_END + FAR_END) * 0.5
	# Road: the texture covers the full width and 12 m of length.
	add_flat("Asphalt", "road", 0.0, 0.0, ROAD_HALF * 2.0, length, mid_z, Vector2(1.0, length / 12.0))
	for side in [-1.0, 1.0]:
		var x = ROAD_HALF
		# Kerb: top and the road-facing face, 1 m black/white blocks along the road.
		add_flat("KerbTop", "kerb", side * (x + KERB_W * 0.5), KERB_H, KERB_W, length, mid_z, Vector2(length / 2.0, 1.0), true)
		add_wall("KerbFace", "kerb", side * x, 0.0, KERB_H, length, mid_z, -side, Vector2(length / 2.0, 1.0))
		x += KERB_W
		# Open drain: inner walls, dark bottom.
		add_wall("DrainInner", "drain", side * x, -DRAIN_DEPTH, KERB_H + DRAIN_DEPTH, length, mid_z, side, Vector2(length / 3.0, 0.2))
		add_flat("DrainBottom", "drain_bottom", side * (x + DRAIN_W * 0.5), -DRAIN_DEPTH, DRAIN_W, length, mid_z, Vector2.ONE)
		add_wall("DrainOuter", "drain", side * (x + DRAIN_W), -DRAIN_DEPTH, WALK_H + DRAIN_DEPTH, length, mid_z, -side, Vector2(length / 3.0, 0.2))
		x += DRAIN_W
		# Walkway slabs (texture = 3 x 3 slabs of 1 m).
		add_flat("Walkway", "walk", side * (x + WALK_W * 0.5), WALK_H, WALK_W, length, mid_z, Vector2(WALK_W / 3.0, length / 3.0))
		x += WALK_W
		add_flat("Ground", "ground", side * (x + GROUND_W * 0.5), 0.02, GROUND_W, length, mid_z, Vector2(GROUND_W / 6.0, length / 6.0))
	build_poles(FAR_END, NEAR_END)

# Horizontal quad at height y, w wide (across the road) and l long.
# uv_scale = texture repeats along the quad's u and v. PlaneMesh's u normally runs
# across the road; along_u turns the quad so u runs along the road instead (kerb stripes).
func add_flat(n: String, mat: String, cx: float, y: float, w: float, l: float, cz: float, uv_scale: Vector2, along_u: bool = false):
	var mi = MeshInstance3D.new()
	mi.name = n
	var q = PlaneMesh.new()
	q.size = Vector2(w, l)
	if along_u:
		q.size = Vector2(l, w)
		mi.rotation_degrees.y = 90.0
	mi.mesh = q
	mi.position = Vector3(cx, y, cz)
	var m = material(mat).duplicate()
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# Vertical quad running along the road at x, from y0 up h metres, facing +X (face=1) or -X.
func add_wall(n: String, mat: String, x: float, y0: float, h: float, l: float, cz: float, face: float, uv_scale: Vector2):
	var mi = MeshInstance3D.new()
	mi.name = n
	var q = QuadMesh.new()
	q.size = Vector2(l, h)
	mi.mesh = q
	mi.position = Vector3(x, y0 + h * 0.5, cz)
	mi.rotation_degrees.y = 90.0 if face > 0.0 else -90.0
	var m = material(mat).duplicate()
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# Stretches of the right-hand walkway that must stay clear of poles (bus-stop pockets,
# the police checkpoint), as Vector2(near_z, far_z) in this segment's local space.
var pole_gaps: Array = []
var poles_mesh: MeshInstance3D

# Set by WorldStreamer; rebuilds the merged pole mesh (a small job) only when they change.
func set_pole_gaps(gaps: Array):
	var padded = gaps.map(func(g): return Vector2(g.x + 2.0, g.y - 2.0))
	if padded == pole_gaps:
		return
	pole_gaps = padded
	build_poles(FAR_END, NEAR_END)

func in_pole_gap(z: float) -> bool:
	for g in pole_gaps:
		if z <= g.x and z >= g.y:
			return true
	return false

# ECG-style wooden poles on the right-hand walkway with sagging wires between them.
# All poles, cross-arms and wires of the segment are merged into one mesh (2 draw calls).
func build_poles(z_from: float, z_to: float):
	if poles_mesh:
		poles_mesh.queue_free()
	var x = ROAD_HALF + KERB_W + DRAIN_W + 0.4
	var poles = SurfaceTool.new()
	poles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wires = SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z = z_to - 10.0
	var prev_top: Vector3 = Vector3.INF
	var pole_count = 0
	var wire_count = 0
	while z > z_from:
		if in_pole_gap(z):
			prev_top = Vector3.INF # the wires break off where a pole is left out
			z -= POLE_SPACING
			continue
		add_box(poles, Vector3(x, 0, z), Vector3(x, 8.0, z), 0.22)
		add_box(poles, Vector3(x - 0.9, 7.6, z), Vector3(x + 0.9, 7.6, z), 0.1)
		pole_count += 1
		var top = Vector3(x, 7.65, z)
		if prev_top != Vector3.INF:
			wire_count += 1
			for dx in [-0.8, 0.8]:
				var a = prev_top + Vector3(dx, 0, 0)
				var b = top + Vector3(dx, 0, 0)
				var sag = (a + b) * 0.5 + Vector3(0, -0.9, 0)
				add_box(wires, a, sag, 0.035)
				add_box(wires, sag, b, 0.035)
		prev_top = top
		z -= POLE_SPACING
	if pole_count == 0:
		poles_mesh = null
		return
	var mesh = ArrayMesh.new()
	poles.generate_normals()
	poles.set_material(material("pole"))
	poles.commit(mesh)
	if wire_count > 0:
		wires.generate_normals()
		wires.set_material(material("wire"))
		wires.commit(mesh)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	poles_mesh = mi

# Square-section beam from a to b with the given thickness.
func add_box(st: SurfaceTool, a: Vector3, b: Vector3, t: float):
	var dir = (b - a).normalized()
	var up = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var s1 = dir.cross(up).normalized() * t * 0.5
	var s2 = dir.cross(s1).normalized() * t * 0.5
	var c = [s1 + s2, s1 - s2, -s1 - s2, -s1 + s2]
	for i in 4:
		var j = (i + 1) % 4
		for v in [a + c[i], b + c[i], b + c[j], a + c[i], b + c[j], a + c[j]]:
			st.add_vertex(v)
