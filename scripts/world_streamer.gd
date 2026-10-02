extends Node3D

# Endless road: child segments (each a road.tscn plus roadside content) leapfrog
# ahead once the camera has passed them. Also rebases the world toward the
# origin periodically so float precision never degrades on long runs.

signal rebased(shift: float)

@export var segment_length: float = 360.0
# road.tscn spans local z from +60 (near end) to -300 (far end).
@export var segment_far_end: float = -300.0
@export var recycle_margin: float = 10.0
@export var rebase_distance: float = 2000.0

var player: Node3D = null
var camera_rig: Node3D = null

func _ready():
	player = get_node_or_null("../PlayerTrotro")
	camera_rig = get_node_or_null("../CameraRig")

func _process(_delta: float):
	if not player:
		return
	var segments = get_children()
	if segments.is_empty():
		return

	# Recycle any segment whose far end is behind the camera (~6 m behind the trotro).
	var behind_z = player.position.z + 6.2 + recycle_margin
	for seg in segments:
		if seg.position.z + segment_far_end > behind_z:
			var farthest_z = seg.position.z
			for other in segments:
				farthest_z = minf(farthest_z, other.position.z)
			seg.position.z = farthest_z - segment_length
			# Fresh roadside for the recycled stretch so the street doesn't loop.
			for part in seg.get_children():
				if part.has_method("populate"):
					part.populate()
			# Forget gaps the camera has left behind, then give the stretch its own.
			pole_gaps = pole_gaps.filter(func(g): return g.y < behind_z)
			frontage_gaps = frontage_gaps.filter(func(g): return g.y < behind_z)
			apply_pole_gaps(seg)

	if player.position.z < -rebase_distance:
		rebase(rebase_distance)

# Stretches of the right-hand walkway kept clear of power poles (bus-stop pockets, the
# police checkpoint), as Vector2(near_z, far_z) in world space. A stretch that's built or
# recycled later picks up the gaps that fall inside it.
var pole_gaps: Array = []

func clear_poles(near_z: float, far_z: float):
	pole_gaps.append(Vector2(near_z, far_z))
	for seg in get_children():
		apply_pole_gaps(seg)

func apply_pole_gaps(seg: Node3D):
	var road = seg.get_node_or_null("Road")
	if road == null or not road.has_method("set_pole_gaps"):
		return
	var local: Array = []
	for g in pole_gaps:
		var ln = g.x - seg.position.z
		var lf = g.y - seg.position.z
		if lf < road.NEAR_END and ln > road.FAR_END:
			local.append(Vector2(ln, lf))
	road.set_pole_gaps(local)

# Stretches of roadside frontage given to a fitter's building, as Vector3(near_z, far_z,
# side) in world space: the random roadside buildings, props and stalls stay out of them.
var frontage_gaps: Array = []

func clear_frontage(near_z: float, far_z: float, side: float):
	frontage_gaps.append(Vector3(near_z, far_z, side))
	# Clear what is already standing there.
	for seg in get_children():
		var roadside = seg.get_node_or_null("Roadside")
		if roadside == null:
			continue
		for c in roadside.get_children():
			if not (c is Node3D) or signf(c.position.x) != side or absf(c.position.x) > 16.0:
				continue # other side of the road, or a tree far behind the frontage
			var cn = seg.position.z + c.get_meta("near_z", c.position.z)
			var cf = cn - c.get_meta("len", 3.0)
			if cn > far_z and cf < near_z:
				c.queue_free()

func frontage_cleared(side: float, z: float) -> bool:
	for g in frontage_gaps:
		if g.z == side and z <= g.x and z >= g.y:
			return true
	return false

func rebase(shift: float):
	for i in pole_gaps.size():
		pole_gaps[i] += Vector2(shift, shift)
	for i in frontage_gaps.size():
		frontage_gaps[i] += Vector3(shift, shift, 0.0)
	player.position.z += shift
	for seg in get_children():
		seg.position.z += shift
	if camera_rig:
		var cam = camera_rig.get_node_or_null("Camera3D")
		if cam:
			cam.global_position.z += shift
	rebased.emit(shift)
