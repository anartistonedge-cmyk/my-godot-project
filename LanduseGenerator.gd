extends Node

var TreeGenerator = preload("res://TreeGenerator.gd").new()


func create_landuse(parent, el, nodes, geo):

	if not el.has("tags"):
		return

	if not el["tags"].has("landuse") and not el["tags"].has("leisure"):
		return

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

	var color = get_landuse_color(el["tags"])

	create_surface(parent, points, color)

	# Spawn vegetation
	if should_spawn_trees(el["tags"]):
		spawn_trees(parent, points, geo)


# -------------------------
# CREATE LAND SURFACE
# -------------------------

func create_surface(parent, points, color):

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(1, points.size() - 1):

		var p0 = Vector3(points[0].x, 0.0, points[0].z)
		var p1 = Vector3(points[i].x, 0.0, points[i].z)
		var p2 = Vector3(points[i + 1].x, 0.0, points[i + 1].z)

		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)

	st.generate_normals()

	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color

	mesh.material_override = mat
	mesh.position.y = -0.02

	parent.add_child(mesh)


# -------------------------
# TREE SPAWNING
# -------------------------

func spawn_trees(parent, points, geo):

	if TreeGenerator == null:
		return

	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF

	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.z)
		max_z = max(max_z, p.z)

	var tree_count = clamp(points.size() * 3, 5, 80)

	for i in range(tree_count):

		var x = randf_range(min_x, max_x)
		var z = randf_range(min_z, max_z)

		TreeGenerator.create_tree(parent, x, z, geo)


# -------------------------
# SHOULD THIS AREA HAVE TREES
# -------------------------

func should_spawn_trees(tags):

	if tags.has("landuse"):

		match tags["landuse"]:

			"grass", "meadow", "farmland", "forest":
				return true

	if tags.has("leisure"):

		match tags["leisure"]:

			"park":
				return true

	return false


# -------------------------
# LANDUSE COLOR TYPES
# -------------------------

func get_landuse_color(tags):

	if tags.has("landuse"):

		match tags["landuse"]:

			"industrial":
				return Color(0.35, 0.35, 0.35)

			"commercial":
				return Color(0.40, 0.40, 0.40)

			"residential":
				return Color(0.45, 0.70, 0.45)

			"farmland":
				return Color(0.60, 0.70, 0.40)

			"meadow":
				return Color(0.55, 0.80, 0.45)

			"grass":
				return Color(0.45, 0.75, 0.40)

			"forest":
				return Color(0.30, 0.60, 0.30)

	if tags.has("leisure"):

		match tags["leisure"]:

			"park":
				return Color(0.35, 0.70, 0.35)

			"pitch":
				return Color(0.30, 0.75, 0.30)

			"playground":
				return Color(0.40, 0.80, 0.40)

	return Color(0.50, 0.80, 0.50)
