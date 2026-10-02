@tool
extends SceneTree

func _init():
	print("--- Rebuilding with Recessed 3D Porch & Solid Materials ---")
	
	build_road_scene()
	build_trotro_scene()
	build_compound_house_scene()
	build_mosque_scene()
	build_world_scene()
	
	print("--- Complete ---")
	quit()

func set_owner_recursive(node: Node, root: Node):
	if node != root:
		node.owner = root
		# Instanced sub-scenes own their own children; re-owning them would
		# serialize every child a second time on top of the instance.
		if node.scene_file_path != "":
			return
	for child in node.get_children():
		set_owner_recursive(child, root)

func create_mat(tex_path: String, uv_scale: Vector3 = Vector3.ONE, roughness: float = 0.85) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	if tex_path != "":
		var tex = load(tex_path)
		mat.albedo_texture = tex
	mat.uv1_scale = uv_scale
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

# --- 1. ROAD & ROADSIDE ENVIRONMENT ---
func build_road_scene():
	var root = Node3D.new()
	root.name = "Road"
	
	var road_len = 360.0
	var road_z_center = -120.0
	
	# 3-Lane Asphalt Road
	var road_mesh = PlaneMesh.new()
	road_mesh.size = Vector2(11.0, road_len)
	road_mesh.orientation = PlaneMesh.FACE_Y
	var road_inst = MeshInstance3D.new()
	road_inst.name = "AsphaltRoad"
	road_inst.mesh = road_mesh
	road_inst.position = Vector3(0, 0.04, road_z_center)
	var road_mat = create_mat("res://assets/environment/road_3lane.png", Vector3(1.0, road_len / 12.0, 1.0), 0.88)
	road_inst.material_override = road_mat
	root.add_child(road_inst)
	
	# Concrete Curbs & Gutters
	var curb_mat = create_mat("res://assets/environment/curb_concrete.png", Vector3(1.0, road_len / 4.0, 1.0), 0.9)
	var gutter_mat = StandardMaterial3D.new()
	gutter_mat.albedo_color = Color(0.28, 0.25, 0.22)
	gutter_mat.roughness = 0.95
	gutter_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	for side in [-1.0, 1.0]:
		var curb_m = BoxMesh.new()
		curb_m.size = Vector3(0.4, 0.18, road_len)
		var curb_inst = MeshInstance3D.new()
		curb_inst.name = "Curb_" + ("Left" if side < 0 else "Right")
		curb_inst.mesh = curb_m
		curb_inst.position = Vector3(side * 5.7, 0.08, road_z_center)
		curb_inst.material_override = curb_mat
		root.add_child(curb_inst)
		
		var gut_m = BoxMesh.new()
		gut_m.size = Vector3(0.6, 0.10, road_len)
		var gut_inst = MeshInstance3D.new()
		gut_inst.name = "Gutter_" + ("Left" if side < 0 else "Right")
		gut_inst.mesh = gut_m
		gut_inst.position = Vector3(side * 6.2, 0.02, road_z_center)
		gut_inst.material_override = gutter_mat
		root.add_child(gut_inst)
	
	# Laterite Earth Shoulders extending 160m to horizon
	var earth_mat = create_mat("res://assets/environment/laterite_earth.png", Vector3(24.0, road_len / 8.0, 1.0), 0.95)
	for side in [-1.0, 1.0]:
		var earth_m = PlaneMesh.new()
		earth_m.size = Vector2(160.0, road_len)
		earth_m.orientation = PlaneMesh.FACE_Y
		var earth_inst = MeshInstance3D.new()
		earth_inst.name = "LateriteShoulder_" + ("Left" if side < 0 else "Right")
		earth_inst.mesh = earth_m
		earth_inst.position = Vector3(side * 86.5, 0.03, road_z_center)
		earth_inst.material_override = earth_mat
		root.add_child(earth_inst)
	
	# Utility / Electricity Poles along roadside
	var pole_wood_mat = StandardMaterial3D.new()
	pole_wood_mat.albedo_color = Color(0.36, 0.33, 0.30)
	pole_wood_mat.roughness = 0.92
	pole_wood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var crossarm_mat = StandardMaterial3D.new()
	crossarm_mat.albedo_color = Color(0.24, 0.22, 0.20)
	crossarm_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	for z_pos in range(35, -310, -35):
		var pole_holder = Node3D.new()
		pole_holder.name = "UtilityPole_%d" % int(abs(z_pos))
		pole_holder.position = Vector3(7.2, 0, z_pos)
		
		var pole_m = CylinderMesh.new()
		pole_m.top_radius = 0.12
		pole_m.bottom_radius = 0.16
		pole_m.height = 7.5
		pole_m.radial_segments = 8
		var pole_inst = MeshInstance3D.new()
		pole_inst.mesh = pole_m
		pole_inst.position = Vector3(0, 3.75, 0)
		pole_inst.material_override = pole_wood_mat
		pole_holder.add_child(pole_inst)
		
		var arm_m = BoxMesh.new()
		arm_m.size = Vector3(1.6, 0.12, 0.12)
		var arm_inst = MeshInstance3D.new()
		arm_inst.mesh = arm_m
		arm_inst.position = Vector3(0, 6.9, 0)
		arm_inst.material_override = crossarm_mat
		pole_holder.add_child(arm_inst)
		
		root.add_child(pole_holder)
		
	# Roadside Palm Trees
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.42, 0.34, 0.28)
	trunk_mat.roughness = 0.95
	trunk_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var palm_frond_mat = StandardMaterial3D.new()
	palm_frond_mat.albedo_color = Color(0.18, 0.45, 0.18)
	palm_frond_mat.roughness = 0.8
	palm_frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var palm_positions = [
		Vector3(-18.0, 0, 15.0),
		Vector3(-22.0, 0, -20.0),
		Vector3(-20.0, 0, -85.0),
		Vector3(-24.0, 0, -145.0),
		Vector3(19.0, 0, 20.0),
		Vector3(22.0, 0, -35.0),
		Vector3(24.0, 0, -150.0),
		Vector3(20.0, 0, -210.0)
	]
	for idx in range(palm_positions.size()):
		var p_pos = palm_positions[idx]
		var palm = Node3D.new()
		palm.name = "PalmTree_%d" % idx
		palm.position = p_pos
		
		var trunk_m = CylinderMesh.new()
		trunk_m.top_radius = 0.18
		trunk_m.bottom_radius = 0.32
		trunk_m.height = 7.0
		trunk_m.radial_segments = 7
		var trunk = MeshInstance3D.new()
		trunk.mesh = trunk_m
		trunk.position = Vector3(0, 3.5, 0)
		trunk.material_override = trunk_mat
		palm.add_child(trunk)
		
		for f_idx in range(6):
			var frond_m = PrismMesh.new()
			frond_m.size = Vector3(2.4, 0.15, 3.6)
			var frond = MeshInstance3D.new()
			frond.mesh = frond_m
			frond.position = Vector3(0, 7.0, 0)
			frond.rotation_degrees = Vector3(25, f_idx * 60.0, 0)
			frond.material_override = palm_frond_mat
			palm.add_child(frond)
			
		root.add_child(palm)
	
	set_owner_recursive(root, root)
	var scene = PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://scenes/road.tscn")
	print("Saved res://scenes/road.tscn")

# --- 2. PLAYER TROTRO SCENE ---
func build_trotro_scene():
	var root = Node3D.new()
	root.name = "PlayerTrotro"
	
	var script = load("res://scripts/player_trotro.gd")
	root.set_script(script)
	
	var shadow_mesh = QuadMesh.new()
	shadow_mesh.size = Vector2(2.4, 1.9)
	var shadow_inst = MeshInstance3D.new()
	shadow_inst.name = "ContactShadow"
	shadow_inst.mesh = shadow_mesh
	shadow_inst.rotation_degrees = Vector3(-90, 0, 0)
	shadow_inst.position = Vector3(0, 0.05, 0)
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_texture = load("res://assets/vehicles/player_trotro/shadow_blob.png")
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_inst.material_override = shadow_mat
	root.add_child(shadow_inst)
	
	var holder = Node3D.new()
	holder.name = "VisualHolder"
	
	var sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://assets/vehicles/player_trotro/player_trotro_rear.png")
	sprite.pixel_size = 0.00165
	sprite.position = Vector3(0, 0.98, 0)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.shaded = false
	holder.add_child(sprite)
	root.add_child(holder)
	
	set_owner_recursive(root, root)
	var scene = PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://scenes/player_trotro.tscn")
	print("Saved res://scenes/player_trotro.tscn")

# --- 3. GHANAIAN COMPOUND HOUSE SCENE ---
func build_compound_house_scene():
	var root = Node3D.new()
	root.name = "CompoundHouse"
	
	var ochre_wall = Color(0.78, 0.58, 0.20)
	var rust_wainscot = Color(0.58, 0.22, 0.14)
	var gutter_col = Color(0.24, 0.24, 0.26)
	
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = ochre_wall
	wall_mat.roughness = 0.92
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var wainscot_mat = StandardMaterial3D.new()
	wainscot_mat.albedo_color = rust_wainscot
	wainscot_mat.roughness = 0.92
	wainscot_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var gutter_mat = StandardMaterial3D.new()
	gutter_mat.albedo_color = gutter_col
	gutter_mat.roughness = 0.85
	gutter_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var plinth_mat = create_mat("res://assets/environment/curb_concrete.png", Vector3(3, 8, 1), 0.92)
	var roof_mat = create_mat("res://assets/buildings/compound_house/compound_roof.png", Vector3(14, 4, 1), 0.75)
	var side_wall_mat = create_mat("res://assets/buildings/compound_house/compound_side_wall.png", Vector3(1, 1, 1), 0.88)
	var front_facade_mat = create_mat("res://assets/buildings/compound_house/compound_front_facade.png", Vector3(1, 1, 1), 0.88)
	var boundary_wall_mat = create_mat("res://assets/buildings/compound_house/compound_boundary_wall.png", Vector3(2.5, 1, 1), 0.85)
	
	var porch_mat = StandardMaterial3D.new()
	porch_mat.albedo_texture = load("res://assets/buildings/compound_house/compound_porch_card.png")
	porch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	porch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	porch_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	porch_mat.roughness = 0.85
	
	var porch_side_mat = StandardMaterial3D.new()
	porch_side_mat.albedo_texture = load("res://assets/buildings/compound_house/compound_porch_side.png")
	porch_side_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	porch_side_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	porch_side_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	porch_side_mat.roughness = 0.85
	
	# 1. Foundation Plinth (Grounding base extending under house and porch)
	var plinth_m = BoxMesh.new()
	plinth_m.size = Vector3(6.2, 0.25, 17.6)
	var plinth_inst = MeshInstance3D.new()
	plinth_inst.name = "FoundationPlinth"
	plinth_inst.mesh = plinth_m
	plinth_inst.position = Vector3(0, 0.125, 0.4)
	plinth_inst.material_override = plinth_mat
	root.add_child(plinth_inst)
	
	# 2. Main Building Volumetric Core
	var core_m = BoxMesh.new()
	core_m.size = Vector3(5.4, 3.6, 16.0)
	var core_inst = MeshInstance3D.new()
	core_inst.name = "BuildingCore"
	core_inst.mesh = core_m
	core_inst.position = Vector3(0, 1.925, 0)
	core_inst.material_override = wall_mat
	root.add_child(core_inst)
	
	# 3. Long Side Wall (Facing Road, +X Face)
	# Rectified orthographic texture: 5 louvered windows, AC compressor, breaker box, breeze holes, downspout
	var side_quad_m = QuadMesh.new()
	side_quad_m.size = Vector2(16.0, 3.6)
	var side_quad = MeshInstance3D.new()
	side_quad.name = "RoadsideLongWall"
	side_quad.mesh = side_quad_m
	side_quad.position = Vector3(2.72, 1.925, 0)
	side_quad.rotation_degrees = Vector3(0, 90, 0)
	side_quad.material_override = side_wall_mat
	root.add_child(side_quad)
	
	# 4. Front End Building Surface (Facing Oncoming Traffic, +Z Face at Z = +8.02m)
	# Mapped with modular front facade: stucco wall, red wainscot, recessed front door, bedroom window with terracotta pots
	var front_quad_m = QuadMesh.new()
	front_quad_m.size = Vector2(5.4, 3.6)
	var front_quad = MeshInstance3D.new()
	front_quad.name = "FrontEndFacade"
	front_quad.mesh = front_quad_m
	front_quad.position = Vector3(0, 1.925, 8.02)
	front_quad.material_override = front_facade_mat
	root.add_child(front_quad)
	
	var coping_mat = StandardMaterial3D.new()
	coping_mat.albedo_color = Color(0.72, 0.58, 0.40)
	coping_mat.roughness = 0.90
	coping_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	# 5. Transparent Porch Architectural Card (Z = +8.65m, 0.63m in front of main facade)
	# Contains: porch roof awning, columns, turned balustrade, entrance steps, blue glazed flower pot, doorway
	var porch_card_m = QuadMesh.new()
	porch_card_m.size = Vector2(2.65, 3.6)
	var porch_card = MeshInstance3D.new()
	porch_card.name = "FrontPorchCard"
	porch_card.mesh = porch_card_m
	porch_card.position = Vector3(-1.35, 1.925, 8.65)
	porch_card.material_override = porch_mat
	root.add_child(porch_card)
	
	# 6. Shallow Side Return Card (Connecting front porch card to main wall)
	# Gives the porch 3D volume from oblique roadside passing angles
	var porch_side_m = QuadMesh.new()
	porch_side_m.size = Vector2(0.63, 3.6)
	var porch_side = MeshInstance3D.new()
	porch_side.name = "PorchSideReturn"
	porch_side.mesh = porch_side_m
	porch_side.position = Vector3(-0.025, 1.925, 8.335)
	porch_side.rotation_degrees = Vector3(0, 90, 0)
	porch_side.material_override = porch_side_mat
	root.add_child(porch_side)
	
	# 7. Grounding Step for Porch Card Entrance
	var step_m = BoxMesh.new()
	step_m.size = Vector3(2.2, 0.16, 0.6)
	var step_inst = MeshInstance3D.new()
	step_inst.name = "FrontEntranceStep"
	step_inst.mesh = step_m
	step_inst.position = Vector3(-1.35, 0.16, 8.65)
	step_inst.material_override = plinth_mat
	root.add_child(step_inst)
	
	# 8. Gables (Front and Rear Triangles)
	var front_gable_m = PrismMesh.new()
	front_gable_m.size = Vector3(5.4, 1.25, 0.15)
	var front_gable = MeshInstance3D.new()
	front_gable.name = "FrontGable"
	front_gable.mesh = front_gable_m
	front_gable.position = Vector3(0, 4.35, 8.01)
	front_gable.rotation_degrees = Vector3(0, 180, 0)
	front_gable.material_override = wall_mat
	root.add_child(front_gable)
	
	var rear_gable_m = PrismMesh.new()
	rear_gable_m.size = Vector3(5.4, 1.25, 0.15)
	var rear_gable = MeshInstance3D.new()
	rear_gable.name = "RearGable"
	rear_gable.mesh = rear_gable_m
	rear_gable.position = Vector3(0, 4.35, -8.01)
	rear_gable.material_override = wall_mat
	root.add_child(rear_gable)
	
	# 9. Pitched Corrugated Metal Roof (Extending over porch card)
	var roof_angle = 22.0
	var roof_len = 17.6
	var roof_slope_w = 3.4
	
	var slope_road = MeshInstance3D.new()
	slope_road.name = "RoofSlope_Roadside"
	var rsm = BoxMesh.new()
	rsm.size = Vector3(roof_slope_w, 0.08, roof_len)
	slope_road.mesh = rsm
	slope_road.position = Vector3(1.48, 4.38, 0.4)
	slope_road.rotation_degrees = Vector3(0, 0, -roof_angle)
	slope_road.material_override = roof_mat
	root.add_child(slope_road)
	
	var slope_back = MeshInstance3D.new()
	slope_back.name = "RoofSlope_Back"
	slope_back.mesh = rsm
	slope_back.position = Vector3(-1.48, 4.38, 0.4)
	slope_back.rotation_degrees = Vector3(0, 0, roof_angle)
	slope_back.material_override = roof_mat
	root.add_child(slope_back)
	
	# Roof Ridge Cap
	var ridge_m = BoxMesh.new()
	ridge_m.size = Vector3(0.28, 0.1, roof_len)
	var ridge_inst = MeshInstance3D.new()
	ridge_inst.name = "RoofRidge"
	ridge_inst.mesh = ridge_m
	ridge_inst.position = Vector3(0, 5.0, 0.4)
	ridge_inst.material_override = wainscot_mat
	root.add_child(ridge_inst)
	
	# Fascia Gutter Trim along Eaves
	var eave_m = BoxMesh.new()
	eave_m.size = Vector3(0.08, 0.16, roof_len)
	var eave_road = MeshInstance3D.new()
	eave_road.name = "EaveGutter_Road"
	eave_road.mesh = eave_m
	eave_road.position = Vector3(3.02, 3.78, 0.4)
	eave_road.material_override = gutter_mat
	root.add_child(eave_road)
	
	# 10. Roadside Perimeter Boundary Wall with Breeze-Blocks
	var wall_node = Node3D.new()
	wall_node.name = "CompoundPerimeterWall"
	wall_node.position = Vector3(4.2, 0, 0.4)
	
	var c_wall_m = BoxMesh.new()
	c_wall_m.size = Vector3(0.22, 1.1, 17.2)
	var c_wall = MeshInstance3D.new()
	c_wall.name = "PerimeterWallMesh"
	c_wall.mesh = c_wall_m
	c_wall.position = Vector3(0, 0.55, 0)
	c_wall.material_override = wall_mat
	wall_node.add_child(c_wall)
	
	var breeze_m = QuadMesh.new()
	breeze_m.size = Vector2(17.2, 1.1)
	var breeze_inst = MeshInstance3D.new()
	breeze_inst.name = "BreezeBlockDetail"
	breeze_inst.mesh = breeze_m
	breeze_inst.position = Vector3(0.12, 0.55, 0)
	breeze_inst.rotation_degrees = Vector3(0, 90, 0)
	breeze_inst.material_override = boundary_wall_mat
	wall_node.add_child(breeze_inst)
	
	for pz in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		var col_m = BoxMesh.new()
		col_m.size = Vector3(0.36, 1.3, 0.36)
		var col_inst = MeshInstance3D.new()
		col_inst.name = "WallPillar_%d" % int(pz * 10)
		col_inst.mesh = col_m
		col_inst.position = Vector3(0, 0.65, pz)
		col_inst.material_override = wainscot_mat
		wall_node.add_child(col_inst)
		
		var cap_m = PrismMesh.new()
		cap_m.size = Vector3(0.44, 0.18, 0.44)
		var cap_inst = MeshInstance3D.new()
		cap_inst.name = "WallPillarCap_%d" % int(pz * 10)
		cap_inst.mesh = cap_m
		cap_inst.position = Vector3(0, 1.39, pz)
		cap_inst.material_override = coping_mat
		wall_node.add_child(cap_inst)
		
	root.add_child(wall_node)
	
	set_owner_recursive(root, root)
	var scene = PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://scenes/compound_house.tscn")
	print("Saved res://scenes/compound_house.tscn")

# --- 4. GHANAIAN MOSQUE SCENE ---
func build_mosque_scene():
	var root = Node3D.new()
	root.name = "Mosque"
	
	var cream_stucco = Color(0.68, 0.62, 0.50)
	var mosque_green = Color(0.10, 0.38, 0.30)
	var gold_col = Color(0.96, 0.80, 0.24)
	
	var cream_mat = StandardMaterial3D.new()
	cream_mat.albedo_color = cream_stucco
	cream_mat.roughness = 0.90
	cream_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var green_trim_mat = StandardMaterial3D.new()
	green_trim_mat.albedo_color = mosque_green
	green_trim_mat.roughness = 0.85
	green_trim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var plinth_mat = create_mat("res://assets/environment/curb_concrete.png", Vector3(4, 10, 1), 0.92)
	var green_roof_mat = create_mat("res://assets/buildings/mosque/roof_green_corrugated.png", Vector3(18, 4, 1), 0.75)
	var porch_mat = create_mat("res://assets/buildings/mosque/mosque_front_facade_modular.png", Vector3(1, 1, 1), 0.85)
	var single_bay_mat = create_mat("res://assets/buildings/mosque/mosque_wall_bay_single.png", Vector3(1, 1, 1), 0.85)
	var hall_facade_mat = create_mat("res://assets/buildings/mosque/mosque_side_wall_modular.png", Vector3(1, 1, 1), 0.85)
	
	# Foundation Plinth
	var plinth_m = BoxMesh.new()
	plinth_m.size = Vector3(12.5, 0.25, 27.0)
	var plinth_inst = MeshInstance3D.new()
	plinth_inst.name = "FoundationPlinth"
	plinth_inst.mesh = plinth_m
	plinth_inst.position = Vector3(0, 0.125, 0)
	plinth_inst.material_override = plinth_mat
	root.add_child(plinth_inst)
	
	# Main Prayer Hall
	var hall_m = BoxMesh.new()
	hall_m.size = Vector3(9.5, 4.8, 18.0)
	var hall_inst = MeshInstance3D.new()
	hall_inst.name = "PrayerHallGeometry"
	hall_inst.mesh = hall_m
	hall_inst.position = Vector3(0, 2.65, -3.5)
	hall_inst.material_override = cream_mat
	root.add_child(hall_inst)
	
	# Road-facing facade (-X side): Single modular orthographic texture (5 window bays, pilasters, downspouts)
	var facade_m = QuadMesh.new()
	facade_m.size = Vector2(18.0, 4.8)
	var facade_inst = MeshInstance3D.new()
	facade_inst.name = "PrayerHallFacade"
	facade_inst.mesh = facade_m
	facade_inst.position = Vector3(-4.77, 2.65, -3.5)
	facade_inst.rotation_degrees = Vector3(0, -90, 0)
	facade_inst.material_override = hall_facade_mat
	root.add_child(facade_inst)
	
	# 3D Extruded Pilasters along roadside wall
	for pz in [-11.5, -7.8, -3.5, 0.8, 4.5]:
		var col_m = BoxMesh.new()
		col_m.size = Vector3(0.32, 4.8, 0.44)
		var col_inst = MeshInstance3D.new()
		col_inst.name = "Pilaster_%d" % int(pz * 10)
		col_inst.mesh = col_m
		col_inst.position = Vector3(-4.9, 2.65, pz)
		col_inst.material_override = green_trim_mat
		root.add_child(col_inst)
	
	# Back Wall (-Z end) Wainscot
	var back_wain_m = BoxMesh.new()
	back_wain_m.size = Vector3(9.5, 1.4, 0.15)
	var back_wain = MeshInstance3D.new()
	back_wain.mesh = back_wain_m
	back_wain.position = Vector3(0, 0.95, -12.5)
	back_wain.material_override = green_trim_mat
	root.add_child(back_wain)
	
	# Pitched Green Corrugated Roof
	var roof_angle = 20.0
	var roof_len = 19.5
	var roof_slope_w = 5.5
	
	var slope_road = MeshInstance3D.new()
	slope_road.name = "RoofSlope_Roadside"
	var rsm = BoxMesh.new()
	rsm.size = Vector3(roof_slope_w, 0.08, roof_len)
	slope_road.mesh = rsm
	slope_road.position = Vector3(-2.3, 5.7, -3.5)
	slope_road.rotation_degrees = Vector3(0, 0, roof_angle)
	slope_road.material_override = green_roof_mat
	root.add_child(slope_road)
	
	var slope_back = MeshInstance3D.new()
	slope_back.name = "RoofSlope_Back"
	slope_back.mesh = rsm
	slope_back.position = Vector3(2.3, 5.7, -3.5)
	slope_back.rotation_degrees = Vector3(0, 0, -roof_angle)
	slope_back.material_override = green_roof_mat
	root.add_child(slope_back)
	
	var ridge_m = BoxMesh.new()
	ridge_m.size = Vector3(0.35, 0.12, roof_len)
	var ridge_inst = MeshInstance3D.new()
	ridge_inst.name = "RoofRidge"
	ridge_inst.mesh = ridge_m
	ridge_inst.position = Vector3(0, 6.65, -3.5)
	ridge_inst.material_override = green_trim_mat
	root.add_child(ridge_inst)
	
	var gable_back_m = PrismMesh.new()
	gable_back_m.size = Vector3(9.5, 1.9, 0.2)
	var gable_back = MeshInstance3D.new()
	gable_back.name = "Gable_Back"
	gable_back.mesh = gable_back_m
	gable_back.position = Vector3(0, 6.0, -12.5)
	gable_back.material_override = cream_mat
	root.add_child(gable_back)
	
	# Front Entrance Pavilion (Facing oncoming traffic approach at Z = +7.5m)
	var pav_m = BoxMesh.new()
	pav_m.size = Vector3(10.5, 5.4, 6.0)
	var pav_inst = MeshInstance3D.new()
	pav_inst.name = "EntrancePavilion"
	pav_inst.mesh = pav_m
	pav_inst.position = Vector3(0, 2.95, 7.5)
	pav_inst.material_override = cream_mat
	root.add_child(pav_inst)
	
	var pav_front_wain_m = BoxMesh.new()
	pav_front_wain_m.size = Vector3(10.55, 1.4, 6.05)
	var pav_front_wain = MeshInstance3D.new()
	pav_front_wain.mesh = pav_front_wain_m
	pav_front_wain.position = Vector3(0, 0.95, 7.5)
	pav_front_wain.material_override = green_trim_mat
	root.add_child(pav_front_wain)
	
	var pav_facade_m = QuadMesh.new()
	pav_facade_m.size = Vector2(6.0, 5.4)
	var pav_facade = MeshInstance3D.new()
	pav_facade.name = "PavilionRoadFacade"
	pav_facade.mesh = pav_facade_m
	pav_facade.position = Vector3(-5.27, 2.95, 7.5)
	pav_facade.rotation_degrees = Vector3(0, -90, 0)
	pav_facade.material_override = single_bay_mat
	root.add_child(pav_facade)
	
	# Approach-facing front (+Z face): Textured with modular entrance portal
	var portal_m = QuadMesh.new()
	portal_m.size = Vector2(8.0, 5.2)
	var portal_inst = MeshInstance3D.new()
	portal_inst.name = "ApproachEntrancePortal"
	portal_inst.mesh = portal_m
	portal_inst.position = Vector3(1.15, 2.95, 10.56)
	portal_inst.material_override = porch_mat
	root.add_child(portal_inst)
	
	# Pavilion Parapet Trim
	var parapet_m = BoxMesh.new()
	parapet_m.size = Vector3(10.8, 0.45, 6.3)
	var parapet = MeshInstance3D.new()
	parapet.name = "PavilionParapet"
	parapet.mesh = parapet_m
	parapet.position = Vector3(0, 5.8, 7.5)
	parapet.material_override = green_trim_mat
	root.add_child(parapet)
	
	# Grand Central Dome
	var dome_node = Node3D.new()
	dome_node.name = "CentralDome"
	dome_node.position = Vector3(1.2, 5.9, 7.5)
	
	var drum_m = CylinderMesh.new()
	drum_m.top_radius = 2.4
	drum_m.bottom_radius = 2.4
	drum_m.height = 1.1
	drum_m.radial_segments = 8
	var drum_inst = MeshInstance3D.new()
	drum_inst.name = "Drum"
	drum_inst.mesh = drum_m
	drum_inst.position = Vector3(0, 0.55, 0)
	drum_inst.material_override = green_trim_mat
	dome_node.add_child(drum_inst)
	
	var dome_m = SphereMesh.new()
	dome_m.radius = 2.5
	dome_m.height = 3.2
	dome_m.radial_segments = 16
	dome_m.rings = 8
	var dome_inst = MeshInstance3D.new()
	dome_inst.name = "DomeHemisphere"
	dome_inst.mesh = dome_m
	dome_inst.position = Vector3(0, 2.2, 0)
	var dome_mat = StandardMaterial3D.new()
	dome_mat.albedo_color = Color(0.08, 0.42, 0.32)
	dome_mat.roughness = 0.35
	dome_mat.metallic = 0.20
	dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome_inst.material_override = dome_mat
	dome_node.add_child(dome_inst)
	
	var gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = gold_col
	gold_mat.metallic = 0.85
	gold_mat.roughness = 0.25
	gold_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var spire_m = CylinderMesh.new()
	spire_m.top_radius = 0.04
	spire_m.bottom_radius = 0.18
	spire_m.height = 1.4
	spire_m.radial_segments = 6
	var spire_inst = MeshInstance3D.new()
	spire_inst.name = "Spire"
	spire_inst.mesh = spire_m
	spire_inst.position = Vector3(0, 4.2, 0)
	spire_inst.material_override = gold_mat
	dome_node.add_child(spire_inst)
	
	var crescent_m = TorusMesh.new()
	crescent_m.inner_radius = 0.22
	crescent_m.outer_radius = 0.38
	var cres_inst = MeshInstance3D.new()
	cres_inst.name = "Crescent"
	cres_inst.mesh = crescent_m
	cres_inst.position = Vector3(0, 5.1, 0)
	cres_inst.rotation_degrees = Vector3(90, 0, 0)
	cres_inst.material_override = gold_mat
	dome_node.add_child(cres_inst)
	
	root.add_child(dome_node)
	
	# Iconic 17.5m Multi-Tiered Ghanaian Minaret Tower
	var minaret = Node3D.new()
	minaret.name = "MinaretTower"
	minaret.position = Vector3(-4.2, 0, 9.5)
	
	var t1_m = BoxMesh.new()
	t1_m.size = Vector3(2.5, 5.6, 2.5)
	var t1_inst = MeshInstance3D.new()
	t1_inst.name = "Tier1_Base"
	t1_inst.mesh = t1_m
	t1_inst.position = Vector3(0, 2.8, 0)
	t1_inst.material_override = cream_mat
	minaret.add_child(t1_inst)
	
	# Tier1 facade details (roadside -X and approach +Z) using single window bay
	var t1_facade_m = QuadMesh.new()
	t1_facade_m.size = Vector2(2.4, 4.0)
	
	var t1_app = MeshInstance3D.new()
	t1_app.name = "Tier1_ApproachFacade"
	t1_app.mesh = t1_facade_m
	t1_app.position = Vector3(0, 3.4, 1.28)
	t1_app.material_override = single_bay_mat
	minaret.add_child(t1_app)
	
	var t1_road = MeshInstance3D.new()
	t1_road.name = "Tier1_RoadFacade"
	t1_road.mesh = t1_facade_m
	t1_road.position = Vector3(-1.28, 3.4, 0)
	t1_road.rotation_degrees = Vector3(0, -90, 0)
	t1_road.material_override = single_bay_mat
	minaret.add_child(t1_road)
	
	var t1_wain_m = BoxMesh.new()
	t1_wain_m.size = Vector3(2.55, 1.4, 2.55)
	var t1_wain = MeshInstance3D.new()
	t1_wain.name = "Tier1_Wainscot"
	t1_wain.mesh = t1_wain_m
	t1_wain.position = Vector3(0, 0.7, 0)
	t1_wain.material_override = green_trim_mat
	minaret.add_child(t1_wain)
	
	var t1_cornice_m = BoxMesh.new()
	t1_cornice_m.size = Vector3(2.65, 0.35, 2.65)
	var t1_cornice = MeshInstance3D.new()
	t1_cornice.name = "Tier1_Cornice"
	t1_cornice.mesh = t1_cornice_m
	t1_cornice.position = Vector3(0, 5.7, 0)
	t1_cornice.material_override = green_trim_mat
	minaret.add_child(t1_cornice)
	
	var t2_m = CylinderMesh.new()
	t2_m.top_radius = 1.05
	t2_m.bottom_radius = 1.15
	t2_m.height = 6.8
	t2_m.radial_segments = 8
	var t2_inst = MeshInstance3D.new()
	t2_inst.name = "Tier2_Shaft"
	t2_inst.mesh = t2_m
	t2_inst.position = Vector3(0, 9.2, 0)
	t2_inst.material_override = cream_mat
	minaret.add_child(t2_inst)
	
	var min_tex_m = QuadMesh.new()
	min_tex_m.size = Vector2(2.1, 6.0)
	var min_tex_inst = MeshInstance3D.new()
	min_tex_inst.name = "MinaretRoadFretwork"
	min_tex_inst.mesh = min_tex_m
	min_tex_inst.position = Vector3(-1.18, 9.2, 0)
	min_tex_inst.rotation_degrees = Vector3(0, -90, 0)
	var min_tex_mat = create_mat("res://assets/buildings/mosque/mosque_minaret.png", Vector3(1, 1, 1), 0.85)
	min_tex_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	min_tex_inst.material_override = min_tex_mat
	minaret.add_child(min_tex_inst)
	
	var min_app_inst = MeshInstance3D.new()
	min_app_inst.name = "MinaretApproachFretwork"
	min_app_inst.mesh = min_tex_m
	min_app_inst.position = Vector3(0, 9.2, 1.18)
	min_app_inst.material_override = min_tex_mat
	minaret.add_child(min_app_inst)
	
	var balcony_m = CylinderMesh.new()
	balcony_m.top_radius = 1.7
	balcony_m.bottom_radius = 1.5
	balcony_m.height = 0.4
	balcony_m.radial_segments = 8
	var balcony_inst = MeshInstance3D.new()
	balcony_inst.name = "BalconyFloor"
	balcony_inst.mesh = balcony_m
	balcony_inst.position = Vector3(0, 12.7, 0)
	balcony_inst.material_override = green_trim_mat
	minaret.add_child(balcony_inst)
	
	var railing_m = CylinderMesh.new()
	railing_m.top_radius = 1.7
	railing_m.bottom_radius = 1.7
	railing_m.height = 0.8
	railing_m.radial_segments = 8
	var railing_inst = MeshInstance3D.new()
	railing_inst.name = "BalconyRailing"
	railing_inst.mesh = railing_m
	railing_inst.position = Vector3(0, 13.2, 0)
	railing_inst.material_override = green_trim_mat
	minaret.add_child(railing_inst)
	
	var lantern_m = CylinderMesh.new()
	lantern_m.top_radius = 0.95
	lantern_m.bottom_radius = 0.95
	lantern_m.height = 2.2
	lantern_m.radial_segments = 8
	var lantern_inst = MeshInstance3D.new()
	lantern_inst.name = "LanternCore"
	lantern_inst.mesh = lantern_m
	lantern_inst.position = Vector3(0, 14.3, 0)
	lantern_inst.material_override = cream_mat
	minaret.add_child(lantern_inst)
	
	var cupola_m = SphereMesh.new()
	cupola_m.radius = 1.15
	cupola_m.height = 2.0
	cupola_m.radial_segments = 12
	cupola_m.rings = 6
	var cupola_inst = MeshInstance3D.new()
	cupola_inst.name = "CupolaDome"
	cupola_inst.mesh = cupola_m
	cupola_inst.position = Vector3(0, 16.2, 0)
	cupola_inst.material_override = dome_mat
	minaret.add_child(cupola_inst)
	
	var m_spire_m = CylinderMesh.new()
	m_spire_m.top_radius = 0.03
	m_spire_m.bottom_radius = 0.12
	m_spire_m.height = 1.2
	m_spire_m.radial_segments = 6
	var m_spire = MeshInstance3D.new()
	m_spire.mesh = m_spire_m
	m_spire.position = Vector3(0, 17.6, 0)
	m_spire.material_override = gold_mat
	minaret.add_child(m_spire)
	
	var m_cres_m = TorusMesh.new()
	m_cres_m.inner_radius = 0.14
	m_cres_m.outer_radius = 0.24
	var m_cres = MeshInstance3D.new()
	m_cres.mesh = m_cres_m
	m_cres.position = Vector3(0, 18.3, 0)
	m_cres.rotation_degrees = Vector3(90, 0, 0)
	m_cres.material_override = gold_mat
	minaret.add_child(m_cres)
	
	root.add_child(minaret)
	
	set_owner_recursive(root, root)
	var scene = PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://scenes/mosque.tscn")
	print("Saved res://scenes/mosque.tscn")

# --- 5. WORLD COMPOSITION SCENE ---
func build_world_scene():
	var root = Node3D.new()
	root.name = "World"
	
	var world_script = load("res://scripts/world.gd")
	root.set_script(world_script)
	
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.54, 0.84)
	sky_mat.sky_horizon_color = Color(0.72, 0.65, 0.58)
	sky_mat.ground_bottom_color = Color(0.48, 0.18, 0.10)
	sky_mat.ground_horizon_color = Color(0.55, 0.28, 0.18)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	
	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = env
	root.add_child(env_node)
	
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-36, -40, 0)
	root.add_child(sun)
	
	var road_scene = load("res://scenes/road.tscn")
	var road = road_scene.instantiate()
	road.name = "Road"
	root.add_child(road)
	
	var house_scene = load("res://scenes/compound_house.tscn")
	var house = house_scene.instantiate()
	house.name = "CompoundHouse"
	house.position = Vector3(-13.5, 0, -45.0)
	root.add_child(house)
	
	var mosque_scene = load("res://scenes/mosque.tscn")
	var mosque = mosque_scene.instantiate()
	mosque.name = "Mosque"
	mosque.position = Vector3(15.0, 0, -105.0)
	root.add_child(mosque)
	
	var trotro_scene = load("res://scenes/player_trotro.tscn")
	var trotro = trotro_scene.instantiate()
	trotro.name = "PlayerTrotro"
	trotro.position = Vector3(0, 0, 15.0)
	root.add_child(trotro)
	
	var cam_rig = Node3D.new()
	cam_rig.name = "CameraRig"
	var cam_script = load("res://scripts/camera_controller.gd")
	cam_rig.set_script(cam_script)
	
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 60.0
	cam.position = Vector3(0, 2.3, 21.2)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam_rig.add_child(cam)
	root.add_child(cam_rig)
	
	var ui = CanvasLayer.new()
	ui.name = "UI"
	var label = Label.new()
	label.name = "ControlsHUD"
	label.text = "TROTRO RUSH 3D PROTOTYPE\n[1] Chase Cam  |  [2] Far View  |  [3] Medium View  |  [4] Passing View\n[W/Up] Accelerate  [S/Down] Brake  [A/D] Steer  [Space] Cruise Toggle  [P] Screenshot"
	label.position = Vector2(24, 20)
	ui.add_child(label)
	root.add_child(ui)
	
	set_owner_recursive(root, root)
	var scene = PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://scenes/world.tscn")
	print("Saved res://scenes/world.tscn")
