extends Node

const TREE_BIRCH := "birch"
const TREE_OAK := "oak"
const TREE_ALDER := "alder"


func create_tree(parent: Node3D, x: float, z: float, data):

	var tree = Node3D.new()
	tree.position = Vector3(x, 0, z)

	var tree_type := TREE_OAK
	var tree_scale := 1.0
	var tree_rotation := randf() * TAU

	if data != null and typeof(data) == TYPE_DICTIONARY:

		if data.has("type"):
			tree_type = str(data["type"])
		else:
			tree_type = random_tree_type()

		if data.has("scale"):
			tree_scale = float(data["scale"])
		else:
			tree_scale = random_tree_scale()

		if data.has("rotation"):
			tree_rotation = float(data["rotation"])

	else:
		tree_type = random_tree_type()
		tree_scale = random_tree_scale()

	tree.set_meta("tree_type", tree_type)
	tree.set_meta("tree_scale", tree_scale)
	tree.set_meta("tree_rotation", tree_rotation)

	tree.rotation.y = tree_rotation
	tree.scale = Vector3.ONE * tree_scale

	match tree_type:
		TREE_BIRCH:
			create_birch(tree)
		TREE_ALDER:
			create_alder(tree)
		_:
			create_oak(tree)

	parent.add_child(tree)
	return tree


func random_tree_type() -> String:
	var roll = randi() % 3
	if roll == 0:
		return TREE_BIRCH
	elif roll == 1:
		return TREE_OAK
	return TREE_ALDER


func random_tree_scale() -> float:
	if randf() < 0.2:
		return randf_range(1.45, 2.0)

	return randf_range(0.9, 1.35)


# -------------------------------------------------
# TREE TYPES
# -------------------------------------------------

func create_birch(tree):

	var trunk_height = randf_range(8.5, 11.5)
	var trunk_radius = randf_range(0.13, 0.18)

	create_trunk(
		tree,
		trunk_height,
		trunk_radius,
		Color(0.84, 0.84, 0.81),
		Color(0.18, 0.18, 0.18),
		true
	)

	var branch_tips = create_branch_set(
		tree,
		trunk_height,
		trunk_radius,
		6,
		Color(0.66, 0.66, 0.64),
		Vector2(0.58, 0.95),
		Vector2(1.8, 3.1),
		Vector2(14.0, 28.0),
		"birch"
	)

	create_leaf_flake_canopy(
		tree,
		trunk_height,
		trunk_radius,
		branch_tips,
		[
			{
				"dark": Color(0.09, 0.20, 0.08),
				"light": Color(0.16, 0.30, 0.12)
			},
			{
				"dark": Color(0.12, 0.24, 0.10),
				"light": Color(0.18, 0.34, 0.14)
			}
		],
		"birch"
	)


func create_oak(tree):

	var trunk_height = randf_range(5.8, 7.4)
	var trunk_radius = randf_range(0.34, 0.5)

	create_trunk(
		tree,
		trunk_height,
		trunk_radius,
		Color(0.28, 0.18, 0.1),
		Color(0.18, 0.12, 0.08),
		false
	)

	var branch_tips = create_branch_set(
		tree,
		trunk_height,
		trunk_radius,
		10,
		Color(0.25, 0.17, 0.09),
		Vector2(0.4, 0.86),
		Vector2(2.6, 4.8),
		Vector2(30.0, 54.0),
		"oak"
	)

	create_leaf_flake_canopy(
		tree,
		trunk_height,
		trunk_radius,
		branch_tips,
		[
			{
				"dark": Color(0.07, 0.16, 0.06),
				"light": Color(0.14, 0.26, 0.10)
			},
			{
				"dark": Color(0.09, 0.19, 0.07),
				"light": Color(0.16, 0.30, 0.11)
			}
		],
		"oak"
	)


func create_alder(tree):

	var trunk_height = randf_range(7.2, 9.4)
	var trunk_radius = randf_range(0.18, 0.26)

	create_trunk(
		tree,
		trunk_height,
		trunk_radius,
		Color(0.42, 0.28, 0.16),
		Color(0.24, 0.17, 0.1),
		false
	)

	var branch_tips = create_branch_set(
		tree,
		trunk_height,
		trunk_radius,
		7,
		Color(0.34, 0.23, 0.14),
		Vector2(0.5, 0.92),
		Vector2(1.9, 3.4),
		Vector2(22.0, 38.0),
		"alder"
	)

	create_leaf_flake_canopy(
		tree,
		trunk_height,
		trunk_radius,
		branch_tips,
		[
			{
				"dark": Color(0.08, 0.18, 0.07),
				"light": Color(0.15, 0.28, 0.11)
			},
			{
				"dark": Color(0.10, 0.21, 0.08),
				"light": Color(0.18, 0.32, 0.13)
			}
		],
		"alder"
	)


# -------------------------------------------------
# TRUNK
# -------------------------------------------------

func create_trunk(tree, height, radius, base_color, dark_color, birch_style := false):

	var trunk = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = radius * 0.72
	mesh.bottom_radius = radius
	mesh.radial_segments = 10
	mesh.rings = 4

	trunk.mesh = mesh
	trunk.position.y = height * 0.5
	trunk.rotation.z = deg_to_rad(randf_range(-2.5, 2.5))
	trunk.rotation.x = deg_to_rad(randf_range(-2.0, 2.0))

	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = 1.0
	trunk.material_override = mat
	tree.add_child(trunk)

	if birch_style:
		for i in range(randi_range(5, 8)):
			var scar = MeshInstance3D.new()
			var scar_mesh = BoxMesh.new()
			scar_mesh.size = Vector3(
				randf_range(radius * 0.25, radius * 0.45),
				randf_range(0.08, 0.14),
				0.02
			)
			scar.mesh = scar_mesh
			scar.position = Vector3(
				randf_range(-radius * 0.3, radius * 0.3),
				randf_range(height * 0.15, height * 0.95),
				radius * 0.82
			)

			var scar_mat = StandardMaterial3D.new()
			scar_mat.albedo_color = dark_color
			scar_mat.roughness = 1.0
			scar.material_override = scar_mat
			tree.add_child(scar)


# -------------------------------------------------
# BRANCHES
# -------------------------------------------------

func create_branch_set(
	tree,
	trunk_height,
	trunk_radius,
	branch_count,
	color,
	height_range: Vector2,
	length_range: Vector2,
	angle_range: Vector2,
	style: String
) -> Array:

	var tips := []

	for i in range(branch_count):

		var yaw = randf() * TAU
		var pitch = deg_to_rad(randf_range(angle_range.x, angle_range.y))
		var branch_length = randf_range(length_range.x, length_range.y)

		if style == "oak":
			pitch = deg_to_rad(randf_range(34.0, 58.0))
		elif style == "birch":
			pitch = deg_to_rad(randf_range(12.0, 24.0))
		else:
			pitch = deg_to_rad(randf_range(20.0, 36.0))

		var start_y = trunk_height * randf_range(height_range.x, height_range.y)

		var start_pos = Vector3(
			cos(yaw) * trunk_radius * 0.72,
			start_y,
			sin(yaw) * trunk_radius * 0.72
		)

		var dir = Vector3(
			cos(yaw) * cos(pitch),
			sin(pitch),
			sin(yaw) * cos(pitch)
		).normalized()

		var end_pos = start_pos + dir * branch_length

		create_branch_mesh(
			tree,
			start_pos,
			end_pos,
			lerp(trunk_radius * 0.38, trunk_radius * 0.22, float(i) / max(1.0, float(branch_count - 1))),
			color
		)

		tips.append(end_pos)

		if randf() < 0.7:
			var split_yaw = yaw + randf_range(-0.7, 0.7)
			var split_pitch = pitch + deg_to_rad(randf_range(-10.0, 10.0))
			var split_len = branch_length * randf_range(0.35, 0.55)

			var split_dir = Vector3(
				cos(split_yaw) * cos(split_pitch),
				sin(split_pitch),
				sin(split_yaw) * cos(split_pitch)
			).normalized()

			var split_start = start_pos.lerp(end_pos, randf_range(0.45, 0.7))
			var split_end = split_start + split_dir * split_len

			create_branch_mesh(
				tree,
				split_start,
				split_end,
				trunk_radius * 0.14,
				color
			)

			tips.append(split_end)

	return tips


func create_branch_mesh(tree, start_pos: Vector3, end_pos: Vector3, radius: float, color):

	var branch = MeshInstance3D.new()
	var mesh = CylinderMesh.new()

	var dir = end_pos - start_pos
	var length = dir.length()

	mesh.height = length
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.radial_segments = 6
	mesh.rings = 2

	branch.mesh = mesh
	branch.position = (start_pos + end_pos) * 0.5
	branch.transform.basis = basis_from_y(dir.normalized())

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	branch.material_override = mat

	tree.add_child(branch)


func basis_from_y(y_dir: Vector3) -> Basis:

	var up = y_dir.normalized()
	var helper = Vector3.FORWARD

	if abs(up.dot(helper)) > 0.95:
		helper = Vector3.RIGHT

	var right = helper.cross(up).normalized()
	var forward = right.cross(up).normalized()

	return Basis(right, up, forward)


# -------------------------------------------------
# LEAF FLAKE CANOPY
# -------------------------------------------------

func create_leaf_flake_canopy(tree, trunk_height, trunk_radius, branch_tips, color_sets: Array, style: String):

	var leaf_points := []
	var highest_tip_y: float = trunk_height

	for tip in branch_tips:
		if tip.y > highest_tip_y:
			highest_tip_y = tip.y

	if style == "birch" or style == "alder":
		var leader_top = highest_tip_y + randf_range(0.6, 1.1)

		create_branch_mesh(
			tree,
			Vector3(0, trunk_height, 0),
			Vector3(
				randf_range(-0.12, 0.12),
				leader_top,
				randf_range(-0.12, 0.12)
			),
			trunk_radius * 0.36,
			Color(0.32, 0.22, 0.14)
		)

		branch_tips.append(Vector3(0, leader_top, 0))

	for tip in branch_tips:

		var spray_count = 20
		var spread = 1.0
		var vertical = 0.7

		if style == "oak":
			spray_count = 34
			spread = 2.1
			vertical = 1.15
		elif style == "birch":
			spray_count = 18
			spread = 0.8
			vertical = 1.4
		else:
			spray_count = 22
			spread = 1.0
			vertical = 1.1

		for i in range(spray_count):
			var offset = Vector3(
				randf_range(-spread, spread),
				randf_range(-vertical, vertical),
				randf_range(-spread, spread)
			)

			var p = tip + offset

			if style == "birch":
				p.x *= 0.82
				p.z *= 0.82

			leaf_points.append(p)

	var fill_count = 50
	var center_spread = 1.0

	if style == "oak":
		fill_count = 95
		center_spread = 2.0
	elif style == "birch":
		fill_count = 35
		center_spread = 0.7
	else:
		fill_count = 55
		center_spread = 0.95

	for i in range(fill_count):

		var y = randf_range(trunk_height * 0.72, highest_tip_y)
		leaf_points.append(Vector3(
			randf_range(-center_spread, center_spread),
			y,
			randf_range(-center_spread, center_spread)
		))

	create_leaf_flake_mesh(tree, leaf_points, color_sets, style)


func create_leaf_flake_mesh(tree, points: Array, color_sets: Array, style: String):

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tree_tint = Color(
		randf_range(0.72, 0.88),
		randf_range(0.72, 0.88),
		randf_range(0.72, 0.88)
	)

	for p in points:

		var flake_count = 2
		var flake_size = 0.28

		if style == "oak":
			flake_count = 3
			flake_size = randf_range(0.24, 0.38)
		elif style == "birch":
			flake_count = 2
			flake_size = randf_range(0.18, 0.3)
		else:
			flake_count = 2
			flake_size = randf_range(0.2, 0.32)

		for i in range(flake_count):

			var chosen_set = color_sets[randi() % color_sets.size()]
			var dark_color: Color = chosen_set["dark"]
			var light_color: Color = chosen_set["light"]

			var leaf_color = Color(
				randf_range(dark_color.r, light_color.r),
				randf_range(dark_color.g, light_color.g),
				randf_range(dark_color.b, light_color.b)
			)

			leaf_color = Color(
				leaf_color.r * tree_tint.r * 0.82,
				leaf_color.g * tree_tint.g * 0.82,
				leaf_color.b * tree_tint.b * 0.82,
				1.0
			)

			add_leaf_flake(
				st,
				p + Vector3(
					randf_range(-0.12, 0.12),
					randf_range(-0.12, 0.12),
					randf_range(-0.12, 0.12)
				),
				flake_size,
				leaf_color
			)

	st.generate_normals()

	var mesh = st.commit()
	var canopy = MeshInstance3D.new()
	canopy.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	canopy.material_override = mat

	tree.add_child(canopy)


func add_leaf_flake(st: SurfaceTool, center: Vector3, size: float, color: Color):

	var basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, randf() * TAU)
	basis = basis.rotated(Vector3.RIGHT, randf_range(-0.8, 0.8))
	basis = basis.rotated(Vector3.FORWARD, randf_range(-0.8, 0.8))

	var right = basis.x.normalized() * size
	var up = basis.y.normalized() * size * randf_range(0.7, 1.2)

	var p1 = center - right - up
	var p2 = center + right - up
	var p3 = center + right + up
	var p4 = center - right + up

	st.set_color(color)

	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)

	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p4)

	st.add_vertex(p3)
	st.add_vertex(p2)
	st.add_vertex(p1)

	st.add_vertex(p4)
	st.add_vertex(p3)
	st.add_vertex(p1)
