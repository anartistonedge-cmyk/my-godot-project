extends Node


func create_road(parent, el, nodes, geo, ROAD_WIDTH, PAVEMENT_WIDTH, PAVEMENT_HEIGHT, roads, road_names):

	# -------------------------
	# CARPARK AREA DETECTION
	# -------------------------
	if el.has("tags") and el["tags"].has("amenity") and el["tags"]["amenity"] == "parking":
		create_carpark(parent, el, nodes, geo)
		return

	# -------------------------
	# PARKING AISLE DETECTION
	# -------------------------
	if el.has("tags") and el["tags"].has("service") and el["tags"]["service"] == "parking_aisle":
		create_parking_aisle(parent, el, nodes, geo)
		return

	if el["nodes"].size() < 2:
		return

	var road_name = ""

	if el.has("tags") and el["tags"].has("name"):
		road_name = el["tags"]["name"]

	var points = []

	for n in el["nodes"]:

		var node = nodes.get(n)

		if node == null:
			node = nodes.get(str(n))

		if node == null:
			continue

		points.append(geo.convert_coords(node["lat"], node["lon"]))

	points = smooth_points(points)
	create_outer_ground(parent, points, ROAD_WIDTH)

	create_shoulder(parent, points, ROAD_WIDTH)

	var road_st = SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half = ROAD_WIDTH / 2

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var l1 = p1 + perp * half
		var r1 = p1 - perp * half
		var l2 = p2 + perp * half
		var r2 = p2 - perp * half

		# triangle 1
		road_st.add_vertex(l1)
		road_st.add_vertex(r1)
		road_st.add_vertex(r2)

		# triangle 2
		road_st.add_vertex(l1)
		road_st.add_vertex(r2)
		road_st.add_vertex(l2)

		roads.append([p1, p2])

		road_names.append({
			"p1": p1,
			"p2": p2,
			"name": road_name
		})

	road_st.generate_normals()

	var road = MeshInstance3D.new()
	road.mesh = road_st.commit()
	road.position.y = 0.04

	var road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.004, 0.004, 0.004, 1.0)

	road.material_override = road_mat

	parent.add_child(road)



func create_shoulder(parent, points, ROAD_WIDTH):

	var shoulder_width = ROAD_WIDTH + 6.0
	var half = shoulder_width / 2

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var l1 = p1 + perp * half
		var r1 = p1 - perp * half
		var l2 = p2 + perp * half
		var r2 = p2 - perp * half

		st.add_vertex(l1)
		st.add_vertex(r1)
		st.add_vertex(r2)

		st.add_vertex(l1)
		st.add_vertex(r2)
		st.add_vertex(l2)

	st.generate_normals()

	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.133, 0.133, 0.133, 1.0)

	mesh.material_override = mat
	mesh.position.y = 0.0

	parent.add_child(mesh)

func create_outer_ground(parent, points, ROAD_WIDTH):

	var outer_width = ROAD_WIDTH + 21.0
	var half = outer_width / 2

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var l1 = p1 + perp * half
		var r1 = p1 - perp * half
		var l2 = p2 + perp * half
		var r2 = p2 - perp * half

		st.add_vertex(l1)
		st.add_vertex(r1)
		st.add_vertex(r2)

		st.add_vertex(l1)
		st.add_vertex(r2)
		st.add_vertex(l2)

	st.generate_normals()

	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.102, 0.102, 0.102, 1.0)

	mesh.material_override = mat
	mesh.position.y = -0.02

	parent.add_child(mesh)

func create_carpark(parent, el, nodes, geo):

	var points = []

	for n in el["nodes"]:

		var node = nodes.get(n)

		if node == null:
			node = nodes.get(str(n))

		if node == null:
			continue

		points.append(geo.convert_coords(node["lat"], node["lon"]))

	if points.size() < 3:
		return

	var center = Vector3.ZERO

	for p in points:
		center += p

	center /= points.size()

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(points.size()):

		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]

		st.add_vertex(center)
		st.add_vertex(p1)
		st.add_vertex(p2)

	st.generate_normals()

	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20,0.20,0.20)

	mesh.material_override = mat
	mesh.position.y = 0.02

	parent.add_child(mesh)



func create_parking_aisle(parent, el, nodes, geo):

	var points = []

	for n in el["nodes"]:

		var node = nodes.get(n)

		if node == null:
			node = nodes.get(str(n))

		if node == null:
			continue

		points.append(geo.convert_coords(node["lat"], node["lon"]))

	if points.size() < 2:
		return

	var width = 12.0

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var l1 = p1 + perp * width
		var r1 = p1 - perp * width
		var l2 = p2 + perp * width
		var r2 = p2 - perp * width

		st.add_vertex(l1)
		st.add_vertex(r1)
		st.add_vertex(r2)

		st.add_vertex(l1)
		st.add_vertex(r2)
		st.add_vertex(l2)

	st.generate_normals()

	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20,0.20,0.20)

	mesh.material_override = mat
	mesh.position.y = 0.02

	parent.add_child(mesh)



func smooth_points(points):

	if points.size() < 4:
		return points

	var smooth = []
	smooth.append(points[0])

	var segments = 6

	for i in range(points.size() - 3):

		var p0 = points[i]
		var p1 = points[i+1]
		var p2 = points[i+2]
		var p3 = points[i+3]

		for j in range(segments):

			var t = float(j) / segments
			var t2 = t * t
			var t3 = t2 * t

			var point = 0.5 * (
				(2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			)

			smooth.append(point)

	smooth.append(points[-2])
	smooth.append(points[-1])

	return smooth
