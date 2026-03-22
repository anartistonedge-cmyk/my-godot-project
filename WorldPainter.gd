extends Node3D

# -------------------------------------------------
# TOOL MODE
# -------------------------------------------------

var tool = "trees"
var terrain_color = Color(0.1,0.8,0.1)

# -------------------------------------------------
# TREE BRUSH SETTINGS
# -------------------------------------------------

@export var brush_radius := 12.0
@export var tree_density := 0.008
@export var tree_spacing := 4.0
@export var tree_spawn_cooldown := 0.12
@export var single_tree_min_spacing := 3.0

var tree_spawn_timer := 0.0

@export var edge_snap_distance := 2.0

@export var patch_subdivisions := 10

var painting := false
var brush_visual : MeshInstance3D

var terrain_noise := FastNoiseLite.new()

# -------------------------------------------------
# TERRAIN PATCH SYSTEM
# -------------------------------------------------

var grass_points = []
var grass_patches = []
var editing_patch = null

var snap_dot : MeshInstance3D
var snap_edge : MeshInstance3D

var snap_position = null
var snap_edge_a = null
var snap_edge_b = null

@export var grass_density := 40.0

var preview_mesh := ImmediateMesh.new()
var preview_instance

var marker_nodes = []

const SAVE_PATH = "user://terrain_patches.json"

# -------------------------------------------------
# REFERENCES
# -------------------------------------------------

var camera : Camera3D
@onready var player = get_node("../CharacterBody3D")

@onready var TreeGenerator = preload("res://TreeGenerator.gd").new()
@onready var TreeSaveManager = preload("res://TreeSaveManager.gd").new()

# -------------------------------------------------
# TOOL LABEL UI
# -------------------------------------------------

var tool_ui_layer : CanvasLayer
var tool_label : Label
var tool_label_timer := 0.0
var tool_label_duration := 1.8

# -------------------------------------------------
# READY
# -------------------------------------------------

func _ready():

	camera = get_viewport().get_camera_3d()

	create_brush_visual()
	create_snap_visuals()
	create_tool_label_ui()

	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = preview_mesh
	add_child(preview_instance)

	load_patches()

	preview_instance.visible = false

	print(get_children())

	terrain_noise.seed = randi()
	terrain_noise.frequency = 0.035
	terrain_noise.fractal_octaves = 3
	terrain_noise.fractal_gain = 0.5

	show_tool_name("Tree Tool")

# -------------------------------------------------
# INPUT
# -------------------------------------------------

func _input(event):

	if event is InputEventMouseButton:

		if tool == "trees":

			# start painting
			if event.button_index == MOUSE_BUTTON_LEFT:
				painting = event.pressed

			# scroll size
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				brush_radius += 2
				update_brush_size()

			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				brush_radius = max(0.5, brush_radius - 2)
				update_brush_size()

	# -------------------------------------------------
	# TOOL SWITCHING
	# -------------------------------------------------

	if event is InputEventKey and event.pressed:

		# TREE TOOL
		if event.keycode == KEY_1:
			deactivate_bush_tool()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			tool = "trees"
			painting = false
			if brush_visual:
				brush_visual.show()
			show_tool_name("Tree Tool")

		# GRASS TOOLS
		if event.keycode == KEY_2:
			deactivate_bush_tool()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			tool = "grass"
			if brush_visual:
				brush_visual.hide()
			terrain_color = Color(0.012,0.212,0.012,1.0)
			show_tool_name("Dark Grass Patch")

		if event.keycode == KEY_3:
			deactivate_bush_tool()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			tool = "grass"
			if brush_visual:
				brush_visual.hide()
			terrain_color = Color(0.288,0.527,0.094,1.0)
			change_patch_type(terrain_color)
			show_tool_name("Green Grass Patch")

		if event.keycode == KEY_4:
			deactivate_bush_tool()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			tool = "grass"
			if brush_visual:
				brush_visual.hide()
			terrain_color = Color(0.55,0.35,0.2)
			change_patch_type(terrain_color)
			show_tool_name("Dirt Patch")

		if event.keycode == KEY_5:
			deactivate_bush_tool()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			tool = "grass"

			if brush_visual:
				brush_visual.hide()

			# gravel patch color
			terrain_color = Color(0.45,0.45,0.45)

			change_patch_type(terrain_color)
			show_tool_name("Gravel Patch")

		# COMPLETE PATCH
		if event.keycode == KEY_ENTER and tool == "grass":
			create_patch(terrain_color)

		# DELETE PATCH
		if event.keycode == KEY_DELETE:
			delete_patch()

		# BUSH TOOL
		if event.keycode == KEY_6:
			tool = "bush"
			if brush_visual:
				brush_visual.hide()
			$FencePainter.deactivate()
			$WallPainter.deactivate()
			get_node("BushPainter").activate()
			show_tool_name("Bush Tool")

		# FENCE TOOL
		if event.keycode == KEY_7:
			tool = "fence"
			if brush_visual:
				brush_visual.hide()
			get_node("FencePainter").activate()
			$WallPainter.deactivate()
			deactivate_bush_tool()
			show_tool_name("Fence Tool")

		# WALL TOOL
		if event.keycode == KEY_8:
			tool = "wall"
			if brush_visual:
				brush_visual.hide()
			$WallPainter.activate()
			$FencePainter.deactivate()
			deactivate_bush_tool()
			show_tool_name("Wall Tool")

	# -------------------------------------------------
	# GRASS POINT PLACEMENT
	# -------------------------------------------------

	if event is InputEventMouseButton and tool == "grass" and event.pressed:

		if event.button_index == MOUSE_BUTTON_LEFT:

			var pos = get_crosshair_ground()
			pos = get_snap_to_edges(pos)

			if !would_self_intersect(pos):

				grass_points.append(pos)
				create_marker(pos)

			else:
				print("Invalid shape: edges would intersect")

		if event.button_index == MOUSE_BUTTON_RIGHT:

			if grass_points.size() > 0:
				grass_points.remove_at(grass_points.size() - 1)
				remove_last_marker()

# -------------------------------------------------
# PROCESS
# -------------------------------------------------

func create_snap_visuals():

	# Snap dot
	snap_dot = MeshInstance3D.new()
	snap_dot.mesh = SphereMesh.new()
	snap_dot.scale = Vector3.ONE * 0.3

	var dot_mat = StandardMaterial3D.new()
	dot_mat.albedo_color = Color(1,0,0)
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	snap_dot.material_override = dot_mat
	add_child(snap_dot)
	snap_dot.visible = false


	# Snap edge highlight
	snap_edge = MeshInstance3D.new()
	snap_edge.mesh = ImmediateMesh.new()

	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(1,0.6,0)
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.no_depth_test = true

	snap_edge.material_override = edge_mat
	add_child(snap_edge)
	snap_edge.visible = false

func _process(delta):

	if tree_spawn_timer > 0.0:
		tree_spawn_timer -= delta

	if brush_visual == null:
		return

	update_tool_label(delta)

	if tool == "grass":

		var pos = get_crosshair_ground()

		if pos != null:
			get_snap_to_edges(pos)

	update_snap_visuals()

	if tool == "trees":

		brush_visual.visible = true

		var pos = get_crosshair_ground()

		if pos != null:
			brush_visual.global_position = pos + Vector3(0,0.05,0)

		process_tree_brush()

	else:
		painting = false
		brush_visual.visible = false

	if tool == "grass":
		preview_instance.visible = true
		draw_preview()
	else:
		preview_instance.visible = false

func can_place_tree(tree_container, pos: Vector3, min_dist: float) -> bool:

	for tree in tree_container.get_children():
		if tree.global_position.distance_to(pos) < min_dist:
			return false

	return true

# -------------------------------------------------
# TOOL LABEL UI
# -------------------------------------------------

func create_tool_label_ui():

	tool_ui_layer = CanvasLayer.new()
	add_child(tool_ui_layer)

	tool_label = Label.new()
	tool_label.text = ""
	tool_label.visible = false
	tool_label.position = Vector2(20, 20)

	tool_label.add_theme_font_size_override("font_size", 26)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	tool_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	tool_label.add_theme_constant_override("shadow_offset_x", 2)
	tool_label.add_theme_constant_override("shadow_offset_y", 2)

	tool_ui_layer.add_child(tool_label)

func show_tool_name(name):

	if tool_label == null:
		return

	tool_label.text = "Tool: " + name
	tool_label.visible = true
	tool_label.modulate.a = 1.0
	tool_label_timer = tool_label_duration

func update_tool_label(delta):

	if tool_label == null:
		return

	if tool_label_timer > 0.0:
		tool_label_timer -= delta

		if tool_label_timer <= 0.0:
			tool_label.visible = false
		elif tool_label_timer < 0.4:
			tool_label.modulate.a = tool_label_timer / 0.4

# -------------------------------------------------
# PATCH CREATION
# -------------------------------------------------

func update_snap_visuals():

	if snap_position == null:
		snap_dot.visible = false
		snap_edge.visible = false
		return

	# show snap dot
	snap_dot.visible = true
	snap_dot.global_position = snap_position + Vector3(0,0.1,0)

	# draw edge highlight
	if snap_edge_a != null and snap_edge_b != null:

		var mesh = ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)

		mesh.surface_add_vertex(snap_edge_a + Vector3(0,0.05,0))
		mesh.surface_add_vertex(snap_edge_b + Vector3(0,0.05,0))

		mesh.surface_end()

		snap_edge.mesh = mesh
		snap_edge.visible = true

func create_patch(color):

	if grass_points.size() < 3:
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# -------------------------------------------------
	# Calculate patch center
	# -------------------------------------------------

	var center = Vector3.ZERO
	for p in grass_points:
		center += p
	center /= grass_points.size()

	var max_dist = 0.0
	for p in grass_points:
		max_dist = max(max_dist, p.distance_to(center))

	# -------------------------------------------------
	# Proper polygon triangulation
	# -------------------------------------------------

	var poly2d = PackedVector2Array()

	for p in grass_points:
		poly2d.append(Vector2(p.x, p.z))

	# Ensure polygon winding is correct
	if Geometry2D.is_polygon_clockwise(poly2d):

		poly2d.reverse()
		grass_points.reverse()

	# Now triangulate
	var indices = Geometry2D.triangulate_polygon(poly2d)

	# Cancel if triangulation failed
	if indices.size() < 3:
		print("Invalid polygon shape, patch cancelled")
		return

	# -------------------------------------------------
	# Subdivide each triangle
	# -------------------------------------------------

	for i in range(0, indices.size(), 3):

		var a = grass_points[indices[i]]
		var b = grass_points[indices[i+1]]
		var c = grass_points[indices[i+2]]

		for u in range(patch_subdivisions):
			for v in range(patch_subdivisions - u):

				var fu = float(u) / patch_subdivisions
				var fv = float(v) / patch_subdivisions
				var fu2 = float(u + 1) / patch_subdivisions
				var fv2 = float(v + 1) / patch_subdivisions

				var p1 = a * (1.0 - fu - fv) + b * fu + c * fv
				var p2 = a * (1.0 - fu2 - fv) + b * fu2 + c * fv
				var p3 = a * (1.0 - fu - fv2) + b * fu + c * fv2
				var p4 = a * (1.0 - fu2 - fv2) + b * fu2 + c * fv2

				p1 += Vector3.UP * 0.02
				p2 += Vector3.UP * 0.02
				p3 += Vector3.UP * 0.02
				p4 += Vector3.UP * 0.02

				# Edge detection (keep borders flat)
				var p1_edge = (u == 0 or v == 0 or u + v == patch_subdivisions)
				var p2_edge = (u + 1 == 0 or v == 0 or u + 1 + v == patch_subdivisions)
				var p3_edge = (u == 0 or v + 1 == 0 or u + v + 1 == patch_subdivisions)
				var p4_edge = (u + 1 == 0 or v + 1 == 0 or u + 1 + v + 1 == patch_subdivisions)

				if !p1_edge:
					p1 = bump_vertex(p1, center, max_dist)

				if !p2_edge:
					p2 = bump_vertex(p2, center, max_dist)

				if !p3_edge:
					p3 = bump_vertex(p3, center, max_dist)

				if !p4_edge:
					p4 = bump_vertex(p4, center, max_dist)

				# First triangle
				st.set_uv(Vector2(p1.x, p1.z) * 0.15)
				st.add_vertex(p1)

				st.set_uv(Vector2(p2.x, p2.z) * 0.15)
				st.add_vertex(p2)

				st.set_uv(Vector2(p3.x, p3.z) * 0.15)
				st.add_vertex(p3)

				# Second triangle
				if v < patch_subdivisions - u - 1:

					st.set_uv(Vector2(p3.x, p3.z) * 0.15)
					st.add_vertex(p3)

					st.set_uv(Vector2(p2.x, p2.z) * 0.15)
					st.add_vertex(p2)

					st.set_uv(Vector2(p4.x, p4.z) * 0.15)
					st.add_vertex(p4)

	st.generate_normals()

	var mesh = st.commit()

	var body = StaticBody3D.new()

	var mi = MeshInstance3D.new()
	mi.mesh = mesh

	var mat = StandardMaterial3D.new()

	# Gravel texture
	if color == Color(0.45,0.45,0.45):

		var tex = load("res://gravel.jpg")
		mat.albedo_texture = tex
		mat.albedo_color = Color(0.75,0.75,0.75)
		mat.uv1_scale = Vector3(2,2,1)

	else:
		mat.albedo_color = color

	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	mi.material_override = mat

	body.add_child(mi)

	var shape = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)

	add_child(body)

	body.set_meta("border_points", grass_points.duplicate())
	grass_patches.append(body)

	if color == Color(0.288,0.527,0.094,1.0):
		generate_grass_for_patch(body, mesh)

	save_patches()

	clear_markers()
	grass_points.clear()


func bump_vertex(v, center, max_dist):

	var dist = v.distance_to(center)
	var edge = clamp(dist / max_dist, 0.0, 1.0)

	# Lock vertices near the edges so the patch outline stays identical
	if edge > 0.92:
		return v

	# Smooth falloff toward edges
	var edge_falloff = pow(1.0 - edge, 3.0)

	var noise_height = terrain_noise.get_noise_2d(v.x, v.z)

	# convert noise from -1..1 → 0..1
	noise_height = (noise_height + 1.0) * 0.5

	var bump = pow(noise_height, 2.0) * 3.0 * edge_falloff

	return v + Vector3(0, bump, 0)

# -------------------------------------------------
# PATCH EDITING
# -------------------------------------------------

func get_snap_to_edges(pos):

	snap_position = null
	snap_edge_a = null
	snap_edge_b = null

	var best_dist = edge_snap_distance

	for patch in grass_patches:

		if !patch.has_meta("border_points"):
			continue

		var points = patch.get_meta("border_points")

		for i in range(points.size()):

			var a = points[i]
			var b = points[(i + 1) % points.size()]

			best_dist = check_edge(a, b, pos, best_dist)

	if snap_position != null:
		return snap_position

	return pos

func check_edge(a, b, pos, best_dist):

	var ab = b - a
	var t = (pos - a).dot(ab) / ab.length_squared()
	t = clamp(t, 0.0, 1.0)

	var closest = a + ab * t
	var dist = pos.distance_to(closest)

	if dist < best_dist:

		snap_position = closest
		snap_edge_a = a
		snap_edge_b = b

		return dist

	return best_dist

func change_patch_type(new_color):

	var hit = raycast()

	if !hit:
		return

	if !(hit.collider in grass_patches):
		return

	var body = hit.collider
	var mi = body.get_child(0)

	mi.material_override.albedo_color = new_color

	for child in body.get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()

	if new_color == Color(0.288,0.527,0.094,1.0):
		generate_grass_for_patch(body,mi.mesh)

	save_patches()

# -------------------------------------------------
# LOAD / SAVE
# -------------------------------------------------

func load_patches():

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH,FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for patch_data in data:

		var verts = patch_data["verts"]
		var color_data = patch_data["color"]
		var color = Color(color_data[0],color_data[1],color_data[2],color_data[3])

		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for v in verts:
			st.add_vertex(Vector3(v[0],v[1] + 0.02,v[2]))

		st.generate_normals()

		var mesh = st.commit()

		var body = StaticBody3D.new()

		var mi = MeshInstance3D.new()
		mi.mesh = mesh

		var mat = StandardMaterial3D.new()

		# restore gravel texture
		if color == Color(0.45,0.45,0.45):

			var tex = load("res://gravel.jpg")
			mat.albedo_texture = tex
			mat.albedo_color = Color(0.75,0.75,0.75)
			mat.uv1_scale = Vector3(2,2,1)

		else:
			mat.albedo_color = color

		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

		mi.material_override = mat

		body.add_child(mi)

		var shape = CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)

		add_child(body)

		# restore border points for snapping
		if patch_data.has("border"):
			var border_points = []
			for p in patch_data["border"]:
				border_points.append(Vector3(p[0],p[1],p[2]))
			body.set_meta("border_points", border_points)

		grass_patches.append(body)

		if color == Color(0.288,0.527,0.094,1.0):
			generate_grass_for_patch(body,mesh)

func save_patches():

	var data = []

	for patch in grass_patches:

		var mi = patch.get_child(0)
		var mesh = mi.mesh
		var color = mi.material_override.albedo_color

		var arrays = mesh.surface_get_arrays(0)
		var verts = arrays[Mesh.ARRAY_VERTEX]

		var vert_arr = []

		for v in verts:
			vert_arr.append([v.x,v.y,v.z])

		var border = patch.get_meta("border_points")

		var border_arr = []

		if border != null:
			for p in border:
				border_arr.append([p.x,p.y,p.z])

		data.append({
			"verts":vert_arr,
			"border":border_arr,
			"color":[color.r,color.g,color.b,color.a]
		})

	var file = FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# -------------------------------------------------
# GRASS GENERATION
# -------------------------------------------------

func generate_grass_for_patch(body,mesh):

	var arrays_mesh = mesh.surface_get_arrays(0)
	var verts_mesh = arrays_mesh[Mesh.ARRAY_VERTEX]

	var tri_count = verts_mesh.size()/3
	var blade_count = tri_count*grass_density

	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = blade_count

	var blade_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	var verts = PackedVector3Array()
	var indices = PackedInt32Array()

	var width = 0.03
	var height = 1.0

	verts.append(Vector3(-width,0,0))
	verts.append(Vector3(width,0,0))
	verts.append(Vector3(0,height,0))

	verts.append(Vector3(0,0,-width))
	verts.append(Vector3(0,0,width))
	verts.append(Vector3(0,height,0))

	indices.append_array([0,1,2,3,4,5])

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices

	blade_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

	multimesh.mesh = blade_mesh

	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.extra_cull_margin = 10

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.288,0.527,0.094,1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0

	mmi.material_override = mat

	for i in range(blade_count):

		var tri = randi()%tri_count

		var a = verts_mesh[tri*3]
		var b = verts_mesh[tri*3+1]
		var c = verts_mesh[tri*3+2]

		var r1 = randf()
		var r2 = randf()

		if r1+r2>1.0:
			r1 = 1.0-r1
			r2 = 1.0-r2

		var pos = a+(b-a)*r1+(c-a)*r2

		var blade_height = randf_range(0.7,1.3)

		var t = Transform3D()

		var rot_y = randf()*TAU
		var tilt_x = deg_to_rad(randf_range(-25,25))
		var tilt_z = deg_to_rad(randf_range(-25,25))

		var basis = Basis()
		basis = basis.rotated(Vector3.UP,rot_y)
		basis = basis.rotated(Vector3.RIGHT,tilt_x)
		basis = basis.rotated(Vector3.FORWARD,tilt_z)

		t.basis = basis.scaled(Vector3.ONE*blade_height)
		t.origin = pos+Vector3.UP*0.02

		multimesh.set_instance_transform(i,t)

	body.add_child(mmi)

# -------------------------------------------------
# TREE TOOL
# -------------------------------------------------

func process_tree_brush():

	if !painting:
		return

	if tree_spawn_timer > 0.0:
		return

	var pos = get_crosshair_ground()

	if pos == null:
		return

	var tree_container = get_parent().get_node_or_null("Trees")

	if tree_container == null:
		return

	# -------------------------------------------------
	# SINGLE TREE MODE (tiny brush)
	# -------------------------------------------------

	if brush_radius <= 1.0:

		if !can_place_tree(tree_container, pos, single_tree_min_spacing):
			return

		TreeGenerator.create_tree(
			tree_container,
			pos.x,
			pos.z,
			null
		)

		TreeSaveManager.save_trees(tree_container)
		tree_spawn_timer = tree_spawn_cooldown
		return


	# -------------------------------------------------
	# NORMAL TREE PAINTING
	# -------------------------------------------------

	var area = PI * brush_radius * brush_radius
	var tree_count = int(area * tree_density)

	var created := false

	for i in range(tree_count):

		var angle = randf() * TAU
		var dist = sqrt(randf()) * brush_radius

		var offset = Vector3(
			cos(angle) * dist,
			0,
			sin(angle) * dist
		)

		var tree_pos = pos + offset

		if !can_place_tree(tree_container, tree_pos, tree_spacing):
			continue

		TreeGenerator.create_tree(
			tree_container,
			tree_pos.x,
			tree_pos.z,
			null
		)

		created = true

	if created:
		TreeSaveManager.save_trees(tree_container)
		tree_spawn_timer = tree_spawn_cooldown

# -------------------------------------------------
# DELETE / EDIT
# -------------------------------------------------

func delete_patch():

	var hit = raycast()

	if hit and hit.collider in grass_patches:
		hit.collider.queue_free()
		grass_patches.erase(hit.collider)
		save_patches()

func toggle_edit_mode():

	var hit = raycast()

	if hit and hit.collider in grass_patches:
		editing_patch = hit.collider

# -------------------------------------------------
# MARKERS
# -------------------------------------------------

func create_marker(pos):

	var marker = MeshInstance3D.new()
	marker.mesh = SphereMesh.new()

	marker.position = pos+Vector3.UP*0.1

	add_child(marker)

	marker_nodes.append(marker)

func remove_last_marker():

	if marker_nodes.size()==0:
		return

	var m = marker_nodes.pop_back()
	m.queue_free()

func clear_markers():

	for m in marker_nodes:
		m.queue_free()

	marker_nodes.clear()

func draw_preview():

	preview_mesh.clear_surfaces()

	var pts = grass_points.duplicate()

	var mouse_pos = get_crosshair_ground()
	if mouse_pos != null:
		pts.append(mouse_pos)

	if pts.size() < 3:
		return

	# Convert to 2D polygon
	var poly2d = PackedVector2Array()
	for p in pts:
		poly2d.append(Vector2(p.x, p.z))

	# Ensure correct winding
	if Geometry2D.is_polygon_clockwise(poly2d):
		poly2d.reverse()
		pts.reverse()

	# Triangulate
	var indices = Geometry2D.triangulate_polygon(poly2d)

	if indices.size() < 3:
		return

	# Draw filled preview
	preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(0, indices.size(), 3):

		var a = pts[indices[i]]
		var b = pts[indices[i+1]]
		var c = pts[indices[i+2]]

		preview_mesh.surface_add_vertex(a + Vector3.UP * 0.02)
		preview_mesh.surface_add_vertex(b + Vector3.UP * 0.02)
		preview_mesh.surface_add_vertex(c + Vector3.UP * 0.02)

	preview_mesh.surface_end()

	# Draw outline
	preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	for p in pts:
		preview_mesh.surface_add_vertex(p + Vector3.UP * 0.05)

	preview_mesh.surface_end()

# -------------------------------------------------
# BRUSH VISUAL
# -------------------------------------------------

func create_brush_visual():

	brush_visual = MeshInstance3D.new()

	var mesh = ImmediateMesh.new()

	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var segments = 64

	for i in range(segments + 1):

		var angle = (i / float(segments)) * TAU

		var x = cos(angle)
		var z = sin(angle)

		mesh.surface_add_vertex(Vector3(x, 0.05, z))

	mesh.surface_end()

	brush_visual.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1,1,1) # white
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	brush_visual.material_override = mat

	add_child(brush_visual)

	update_brush_size()

	brush_visual.hide()

func update_brush_size():

	if brush_visual == null:
		return

	brush_visual.scale = Vector3(brush_radius,1,brush_radius)

# -------------------------------------------------
# RAYCAST
# -------------------------------------------------

func raycast():

	var center = get_viewport().get_visible_rect().size/2

	var ray_origin = camera.project_ray_origin(center)
	var ray_dir = camera.project_ray_normal(center)

	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir*2000
	)

	return space.intersect_ray(query)

func get_crosshair_ground():

	var result = raycast()

	if result:
		return result.position

	return null

func deactivate_bush_tool():

	if has_node("BushPainter"):
		get_node("BushPainter").deactivate()

func segments_intersect(a1, a2, b1, b2):

	var d1 = direction(a1, a2, b1)
	var d2 = direction(a1, a2, b2)
	var d3 = direction(b1, b2, a1)
	var d4 = direction(b1, b2, a2)

	if d1 * d2 < 0 and d3 * d4 < 0:
		return true

	return false


func direction(a, b, c):

	return (c.x - a.x) * (b.z - a.z) - (b.x - a.x) * (c.z - a.z)

func would_self_intersect(new_point):

	if grass_points.size() < 2:
		return false

	var last = grass_points[grass_points.size() - 1]

	for i in range(grass_points.size() - 2):

		var a = grass_points[i]
		var b = grass_points[i + 1]

		if segments_intersect(a, b, last, new_point):
			return true

	return false
