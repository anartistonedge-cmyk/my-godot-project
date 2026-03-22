extends Node3D

var tool_active := false

var fence_points = []

@export var panel_spacing := 4.0
@export var fence_height := 3.6
@export var post_snap_distance := 1.0

var preview_mesh := ImmediateMesh.new()
var preview_instance : MeshInstance3D

var fence_parent : Node3D

var camera : Camera3D

var snap_highlight_mat : StandardMaterial3D
var snapped_post = null
var fence_mat : StandardMaterial3D

var original_materials := {}

const SAVE_PATH = "user://fences.json"

var fence_data = []

var loading_fences := false

var deleted_pieces = []

var piece_id_counter := 0

func _ready():

	camera = get_viewport().get_camera_3d()

	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = preview_mesh
	add_child(preview_instance)

	fence_parent = Node3D.new()
	fence_parent.name = "Fences"
	add_child(fence_parent)

	piece_id_counter = 0
	load_fences()

	snap_highlight_mat = StandardMaterial3D.new()
	snap_highlight_mat.albedo_color = Color(1,0.8,0.2)
	snap_highlight_mat.emission_enabled = true
	snap_highlight_mat.emission = Color(1,0.8,0.2)
	snap_highlight_mat.emission_energy = 2

	fence_mat = StandardMaterial3D.new()
	fence_mat.albedo_color = Color(0.55, 0.35, 0.2)
	fence_mat.roughness = 1.0

func activate():
	tool_active = true
	fence_points.clear()


func deactivate():
	tool_active = false
	fence_points.clear()
	preview_mesh.clear_surfaces()


func _input(event):

	if !tool_active:
		return

	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_LEFT:

			var pos = get_crosshair_ground()

			if pos == null:
				return

			var post = get_nearby_post(pos)
			if post != null:
				pos = post.position

			fence_points.append(pos)

			if fence_points.size() == 2:

				create_fence_line(fence_points[0], fence_points[1])
				fence_points.clear()

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_DELETE:
			delete_fence_piece()

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_1 \
		or event.keycode == KEY_2 \
		or event.keycode == KEY_3 \
		or event.keycode == KEY_4 \
		or event.keycode == KEY_5 \
		or event.keycode == KEY_6 \
		or event.keycode == KEY_F:

			deactivate()
			return

	if !tool_active:
		return

func _process(delta):

	if !tool_active:
		return

	draw_preview()


# -------------------------------------------------
# PREVIEW LINE
# -------------------------------------------------

func draw_preview():

	preview_mesh.clear_surfaces()

	var mouse = get_crosshair_ground()

	if mouse == null:
		return

	var post = get_nearby_post(mouse)

	# reset previous highlight
	if snapped_post != null and snapped_post != post:
		if snapped_post.get_child_count() > 0:
			var mesh = snapped_post.get_child(0)

			if original_materials.has(mesh):
				mesh.material_override = original_materials[mesh]
				original_materials.erase(mesh)

	snapped_post = post

	# snap cursor to post and highlight it
	if post != null:
		mouse = post.position
		if post.get_child_count() > 0:
			var mesh = post.get_child(0)

			if !original_materials.has(mesh):
				original_materials[mesh] = mesh.material_override

			mesh.material_override = snap_highlight_mat

	# if we haven't placed the first point yet,
	# just show the highlight and stop here
	if fence_points.size() == 0:
		return

	# draw preview line
	preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	preview_mesh.surface_add_vertex(fence_points[0] + Vector3.UP * 0.1)
	preview_mesh.surface_add_vertex(mouse + Vector3.UP * 0.1)

	preview_mesh.surface_end()


# -------------------------------------------------
# FENCE GENERATION
# -------------------------------------------------

func save_fences():

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(fence_data))
	file.close()

func load_fences():

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	fence_data = data

	for piece in fence_data:

		# Skip invalid entries from old save formats
		if typeof(piece) != TYPE_DICTIONARY:
			continue

		if !piece.has("type"):
			continue

		# Spawn posts
		if piece["type"] == "post":

			if piece.has("x") and piece.has("y") and piece.has("z") and piece.has("rot"):
				spawn_post(
					Vector3(piece["x"], piece["y"], piece["z"]),
					piece["rot"]
				)

		# Spawn panels
		if piece["type"] == "panel":

			if piece.has("x") and piece.has("y") and piece.has("z") and piece.has("rot") and piece.has("width"):
				spawn_panel(
					Vector3(piece["x"], piece["y"], piece["z"]),
					piece["rot"],
					piece["width"]
				)

func spawn_post(pos, rot):

	var post = StaticBody3D.new()
	post.position = pos
	post.rotation.y = rot

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = create_post_mesh()
	mesh_instance.position.y = (fence_height + 0.2) * 0.5
	post.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.2, fence_height + 0.2, 0.2)

	collision.shape = shape
	collision.position.y = (fence_height + 0.2) * 0.5
	post.add_child(collision)

	fence_parent.add_child(post)

func spawn_panel(pos, rot, width):

	var panel = StaticBody3D.new()
	panel.position = pos
	panel.rotation.y = rot

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = create_panel_mesh()
	mesh_instance.scale.x = width / panel_spacing

	mesh_instance.position.y = 0

	# THIS IS THE MISSING PART
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_instance.material_override = mat

	panel.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = Vector3(width, fence_height, 0.1)
	collision.shape = shape
	collision.position.y = fence_height * 0.5

	panel.add_child(collision)

	fence_parent.add_child(panel)

func is_deleted(id):

	return id in deleted_pieces

func create_fence_line(a:Vector3, b:Vector3):

	var line_index: int = fence_data.size()

	if !loading_fences:
		fence_data.append({
			"a":[a.x,a.y,a.z],
			"b":[b.x,b.y,b.z]
		})
		save_fences()
	else:
		# when loading, use the existing index
		line_index = fence_data.find({
			"a":[a.x,a.y,a.z],
			"b":[b.x,b.y,b.z]
		})

	var dist = a.distance_to(b)
	var dir = (b - a).normalized()

	var posts = []
	var local_piece_id = 0

	var travelled := 0.0

	while travelled + panel_spacing < dist:

		var pos = a + dir * travelled

		var piece_id = str(line_index) + "_" + str(local_piece_id)
		var post = create_post(pos, dir, piece_id)
		local_piece_id += 1

		if post != null:
			posts.append(post)

		travelled += panel_spacing


	var last_regular_pos = a + dir * travelled
	var piece_id = str(line_index) + "_" + str(local_piece_id)
	var last_post = create_post(last_regular_pos, dir, piece_id)
	local_piece_id += 1

	if last_post != null:
		posts.append(last_post)


	var piece_id2 = str(line_index) + "_" + str(local_piece_id)
	var end_post = create_post(b, dir, piece_id2)
	local_piece_id += 1

	if end_post != null:
		posts.append(end_post)


	for i in range(posts.size() - 1):

		var p1 = posts[i].position
		var p2 = posts[i+1].position

		var piece_id3 = str(line_index) + "_" + str(local_piece_id)
		create_panel_between(p1, p2, dir, piece_id3)
		local_piece_id += 1


func create_post(pos, dir, id):

	if is_deleted(id):
		return null

	var existing = get_nearby_post(pos)
	if existing != null:
		return existing

	var post = StaticBody3D.new()
	post.position = pos
	post.rotation.y = atan2(dir.x, dir.z) + PI/2

	post.set_meta("piece_id", id)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = create_post_mesh()
	mesh_instance.position.y = (fence_height + 0.2) * 0.5
	post.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.2, fence_height + 0.2, 0.2)

	collision.shape = shape
	collision.position.y = (fence_height + 0.2) * 0.5
	post.add_child(collision)

	fence_parent.add_child(post)

	# SAVE POST
	if !loading_fences:
		fence_data.append({
			"type":"post",
			"x":pos.x,
			"y":pos.y,
			"z":pos.z,
			"rot":post.rotation.y
		})
		save_fences()

	return post

func create_panel_between(p1, p2, dir, id):

	if is_deleted(id):
		return

	var panel_pos = (p1 + p2) * 0.5

	var panel = StaticBody3D.new()
	panel.set_meta("piece_id", id)

	var width = min(panel_spacing, p1.distance_to(p2))

	panel.position = panel_pos
	panel.rotation.y = atan2(dir.x, dir.z) + PI/2

	var mesh_instance = MeshInstance3D.new()

	var mesh = create_panel_mesh()
	mesh_instance.mesh = mesh

	mesh_instance.scale.x = width / panel_spacing
	mesh_instance.position.y = 0

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0

	mesh_instance.material_override = mat
	panel.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = Vector3(width, fence_height, 0.1)
	collision.shape = shape
	collision.position.y = fence_height * 0.5

	panel.add_child(collision)

	fence_parent.add_child(panel)

	if !loading_fences:
		fence_data.append({
			"type":"panel",
			"x":panel_pos.x,
			"y":panel_pos.y,
			"z":panel_pos.z,
			"rot":panel.rotation.y,
			"width":width
		})
		save_fences()

func get_nearby_post(pos:Vector3):

	for child in fence_parent.get_children():

		if child.position.distance_to(pos) < post_snap_distance:
			return child

	return null


# -------------------------------------------------
# PANEL MESH
# -------------------------------------------------

func create_panel_mesh():

	var wood_colors = [
		Color(0.07, 0.053, 0.036, 1.0),
		Color(0.101, 0.081, 0.057, 1.0),
		Color(0.096, 0.078, 0.054, 1.0)
	]

	var mesh = ArrayMesh.new()

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var slat_width := 0.35
	var slat_depth := 0.05
	var overlap := 0.12

	var usable_width := panel_spacing
	var step := slat_width - overlap

	var count := int(usable_width / step) + 1

	var start_x := -usable_width * 0.5 + slat_width * 0.5

	for i in range(count):

		var x := start_x + i * step

		var col = wood_colors[randi() % wood_colors.size()]
		st.set_color(col)

		add_box(st, Vector3(x, 0, 0), Vector3(slat_width, fence_height, slat_depth))

	st.generate_normals()

	return st.commit()

func add_box(st, pos:Vector3, size:Vector3):

	var angle = deg_to_rad(10)

	var hx = size.x * 0.5
	var hy = size.y * 0.5
	var hz = size.z * 0.5

	var corners = [
		Vector3(-hx,-hy,-hz),
		Vector3(hx,-hy,-hz),
		Vector3(hx,hy,-hz),
		Vector3(-hx,hy,-hz),

		Vector3(-hx,-hy,hz),
		Vector3(hx,-hy,hz),
		Vector3(hx,hy,hz),
		Vector3(-hx,hy,hz)
	]

	# rotate and place slat
	for i in range(corners.size()):
		corners[i] = corners[i].rotated(Vector3.UP, angle)
		corners[i] += pos + Vector3(0,hy,0)

	var faces = [
		[0,1,2,3],
		[5,4,7,6],
		[4,0,3,7],
		[1,5,6,2],
		[3,2,6,7],
		[4,5,1,0]
	]

	for f in faces:

		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[1]])
		st.add_vertex(corners[f[2]])

		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[2]])
		st.add_vertex(corners[f[3]])

func create_post_mesh():

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.25, fence_height + 0.2, 0.25)

	return mesh


# -------------------------------------------------
# RAYCAST
# -------------------------------------------------

func get_crosshair_ground():

	var center = get_viewport().get_visible_rect().size/2

	var ray_origin = camera.project_ray_origin(center)
	var ray_dir = camera.project_ray_normal(center)

	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir*2000
	)

	var result = space.intersect_ray(query)

	if result:
		return result.position

	return null


func get_crosshair_hit():

	var center = get_viewport().get_visible_rect().size / 2

	var ray_origin = camera.project_ray_origin(center)
	var ray_dir = camera.project_ray_normal(center)

	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 2000
	)

	return space.intersect_ray(query)

func delete_fence_piece():

	var result = get_crosshair_hit()
	if result.is_empty():
		return

	var node = result.collider

	while node != null:

		if node.get_parent() == fence_parent:

			var pos = node.position
			var remove_index := -1

			for i in range(fence_data.size()):

				var p = fence_data[i]

				if typeof(p) != TYPE_DICTIONARY:
					continue

				if !p.has("x") or !p.has("y") or !p.has("z"):
					continue

				var saved_pos = Vector3(p["x"], p["y"], p["z"])

				if saved_pos.distance_to(pos) < 0.5:
					remove_index = i
					break

			if remove_index != -1:
				fence_data.remove_at(remove_index)

			node.queue_free()
			save_fences()
			return

		node = node.get_parent()
