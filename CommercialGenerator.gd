extends Node

var building_cache = []
var cache_loaded = false

var st := SurfaceTool.new()
var building_mesh_instance : MeshInstance3D

var residential
var industrial
var commercial


func begin(parent):

	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	building_mesh_instance = MeshInstance3D.new()
	parent.add_child(building_mesh_instance)

	# load generators
	residential = preload("res://ResidentialGenerator.gd").new()
	industrial = preload("res://IndustrialGenerator.gd").new()
	commercial = preload("res://CommercialGenerator.gd").new()


func create_building(parent, el, nodes, geo, roads):

	if cache_loaded:
		return

	var points = []

	for n in el["nodes"]:

		var node = nodes.get(n)
		if node == null:
			node = nodes.get(str(n))

		if node == null:
			continue

		var p = geo.convert_coords(node["lat"], node["lon"])
		points.append(p)

	if points.size() < 3:
		return

	points = ensure_counter_clockwise(points)

	var height = 6.0
	var levels = 2

	if el.has("tags") and el["tags"].has("building:levels"):
		levels = int(el["tags"]["building:levels"])

	height = levels * 3.4

	var building_type = "residential"

	if el.has("tags") and el["tags"].has("building"):
		building_type = el["tags"]["building"]

	# SEND TO CORRECT GENERATOR
	if building_type in ["industrial","warehouse","factory"]:

		height = levels * 4.8
		industrial.create_industrial(st, points, height)

	elif building_type in ["retail","commercial","supermarket"]:

		height = levels * 4.2
		commercial.create_building(st, points, height)

	else:

		residential.create_house(st, points, height)

	building_cache.append({
		"points": points,
		"height": height
	})


func ensure_counter_clockwise(points):

	var sum = 0.0

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		sum += (p2.x - p1.x) * (p2.z + p1.z)

	if sum > 0:
		points.reverse()

	return points


func commit_mesh():

	st.generate_normals()
	st.index()

	var mesh = st.commit()

	var mat = StandardMaterial3D.new()

	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)

	building_mesh_instance.mesh = mesh


func finish_generation():

	commit_mesh()
