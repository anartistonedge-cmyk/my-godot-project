extends Node

func create_smooth_road(parent, el, nodes, geo, ROAD_WIDTH):

	if el["nodes"].size() < 2:
		return

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

	# smooth road path
	points = smooth_points(points)

	build_road_mesh(parent, points, ROAD_WIDTH)



func build_road_mesh(parent, points, width):

	var half = width / 2.0

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var uv_distance = 0.0

	for i in range(points.size() - 1):

		var p1 = points[i]
		var p2 = points[i + 1]

		var dir = (p2 - p1).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var height = 2.0   # BIG height so we can see it clearly

		var l1 = p1 + perp * half + Vector3.UP * height
		var r1 = p1 - perp * half + Vector3.UP * height
		var l2 = p2 + perp * half + Vector3.UP * height
		var r2 = p2 - perp * half + Vector3.UP * height

		var segment_length = p1.distance_to(p2)

		var uv1 = uv_distance
		var uv2 = uv_distance + segment_length

		# triangle 1
		st.set_uv(Vector2(0, uv1))
		st.add_vertex(l1)

		st.set_uv(Vector2(1, uv1))
		st.add_vertex(r1)

		st.set_uv(Vector2(1, uv2))
		st.add_vertex(r2)

		# triangle 2
		st.set_uv(Vector2(0, uv1))
		st.add_vertex(l1)

		st.set_uv(Vector2(1, uv2))
		st.add_vertex(r2)

		st.set_uv(Vector2(0, uv2))
		st.add_vertex(l2)

		uv_distance += segment_length


	st.generate_normals()

	var mesh = st.commit()

	var road = MeshInstance3D.new()
	road.mesh = mesh
	road.position.y = 0.05

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1,0,1)
	mat.roughness = 1.0

	road.material_override = mat

	var container = parent.get_node_or_null("RoadsSmooth")

	if container == null:
		container = Node3D.new()
		container.name = "RoadsSmooth"
		parent.add_child(container)

	container.add_child(road)



func smooth_points(points):

	if points.size() < 4:
		return points

	var smooth = []
	smooth.append(points[0])

	var segments = 8

	for i in range(points.size() - 3):

		var p0 = points[i]
		var p1 = points[i + 1]
		var p2 = points[i + 2]
		var p3 = points[i + 3]

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

	smooth.append(points[-1])

	return smooth
