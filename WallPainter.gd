extends Node3D

var tool_active := false
var wall_points = []

@export var panel_spacing := 4.0
@export var wall_height := 1.8
@export var post_snap_distance := 2.0

var preview_mesh := ImmediateMesh.new()
var preview_instance : MeshInstance3D

var wall_parent : Node3D
var camera : Camera3D

var brick_material : StandardMaterial3D

var snap_highlight_mat : StandardMaterial3D
var snapped_post = null

var original_materials := {}

const SAVE_PATH = "user://walls.json"

var wall_data = []
var loading_walls := false

# -------------------------------------------------
# BUILDING DELETE TOOL
# -------------------------------------------------

var building_delete_mode := false


func _ready():

	camera = get_viewport().get_camera_3d()

	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = preview_mesh
	add_child(preview_instance)

	wall_parent = Node3D.new()
	wall_parent.name = "Walls"
	add_child(wall_parent)

	# CREATE MATERIAL FIRST
	brick_material = StandardMaterial3D.new()

	var tex = preload("res://brick.jpg")

	brick_material.albedo_texture = tex
	brick_material.roughness = 1.0

	# This controls brick size globally
	brick_material.uv1_scale = Vector3(4, 2, 1)

	# THEN LOAD WALLS
	load_walls()

	snap_highlight_mat = StandardMaterial3D.new()
	snap_highlight_mat.albedo_color = Color(1,0.8,0.2)
	snap_highlight_mat.emission_enabled = true
	snap_highlight_mat.emission = Color(1,0.8,0.2)
	snap_highlight_mat.emission_energy = 2


func activate():
	tool_active = true
	wall_points.clear()


func deactivate():
	tool_active = false
	wall_points.clear()
	building_delete_mode = false
	preview_mesh.clear_surfaces()
	clear_post_highlight()


func _input(event):

	if !tool_active:
		return

	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_LEFT:

			if building_delete_mode:
				delete_building_at_crosshair()
				return

			var pos = get_crosshair_ground()

			if pos == null:
				return

			var post = get_nearby_post(pos)
			if post != null:
				pos = post.position

			wall_points.append(pos)

			if wall_points.size() == 2:

				create_wall_line(wall_points[0], wall_points[1])
				wall_points.clear()

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_DELETE:
			delete_wall_piece()

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_B:
			building_delete_mode = !building_delete_mode
			wall_points.clear()
			preview_mesh.clear_surfaces()
			clear_post_highlight()

			if building_delete_mode:
				print("Building delete mode ON")
			else:
				print("Building delete mode OFF")

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_1 \
		or event.keycode == KEY_2 \
		or event.keycode == KEY_3 \
		or event.keycode == KEY_4 \
		or event.keycode == KEY_5 \
		or event.keycode == KEY_6 \
		or event.keycode == KEY_7:
			deactivate()


func _process(delta):

	if !tool_active:
		return

	draw_preview()


# -------------------------------------------------
# PREVIEW
# -------------------------------------------------

func draw_preview():

	preview_mesh.clear_surfaces()

	if building_delete_mode:
		clear_post_highlight()
		return

	var mouse = get_crosshair_ground()

	if mouse == null:
		clear_post_highlight()
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

	# snap + highlight
	if post != null:

		mouse = post.position

		if post.get_child_count() > 0:

			var mesh = post.get_child(0)

			if !original_materials.has(mesh):
				original_materials[mesh] = mesh.material_override

			mesh.material_override = snap_highlight_mat

	if wall_points.size() == 0:
		return

	preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	preview_mesh.surface_add_vertex(wall_points[0] + Vector3.UP * 0.1)
	preview_mesh.surface_add_vertex(mouse + Vector3.UP * 0.1)

	preview_mesh.surface_end()


func clear_post_highlight():

	if snapped_post != null and is_instance_valid(snapped_post):

		if snapped_post.get_child_count() > 0:

			var mesh = snapped_post.get_child(0)

			if original_materials.has(mesh):
				mesh.material_override = original_materials[mesh]
				original_materials.erase(mesh)

	snapped_post = null


# -------------------------------------------------
# SAVE / LOAD
# -------------------------------------------------

func save_walls():

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(wall_data))
	file.close()


func load_walls():

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	wall_data = data
	loading_walls = true

	for piece in wall_data:

		if piece["type"] == "post":

			spawn_post(
				Vector3(piece["x"], piece["y"], piece["z"]),
				piece["rot"]
			)

		if piece["type"] == "panel":

			spawn_panel(
				Vector3(piece["x"], piece["y"], piece["z"]),
				piece["rot"],
				piece["width"]
			)

	loading_walls = false


# -------------------------------------------------
# WALL GENERATION
# -------------------------------------------------

func create_wall_line(a: Vector3, b: Vector3):

	var dist = a.distance_to(b)
	var dir = (b - a).normalized()

	var posts = []
	var travelled := 0.0

	while travelled + panel_spacing < dist:

		var pos = a + dir * travelled

		var post = create_post(pos, dir)
		posts.append(post)

		travelled += panel_spacing

	var last_post = create_post(b, dir)
	posts.append(last_post)

	for i in range(posts.size() - 1):

		var p1 = posts[i].position
		var p2 = posts[i + 1].position

		create_panel_between(p1, p2, dir)


# -------------------------------------------------
# POSTS
# -------------------------------------------------

func create_post(pos, dir):

	var existing = get_nearby_post(pos)
	if existing != null:
		return existing

	var post = StaticBody3D.new()
	post.position = pos
	post.rotation.y = atan2(dir.x, dir.z) + PI / 2

	var mesh_instance = MeshInstance3D.new()

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.6, wall_height + 0.2, 0.6)

	mesh_instance.mesh = mesh
	mesh_instance.position.y = (wall_height + 0.2) * 0.5

	mesh_instance.material_override = brick_material

	post.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = mesh.size
	collision.shape = shape
	collision.position.y = mesh_instance.position.y

	post.add_child(collision)

	wall_parent.add_child(post)

	if !loading_walls:

		wall_data.append({
			"type": "post",
			"x": pos.x,
			"y": pos.y,
			"z": pos.z,
			"rot": post.rotation.y
		})

		save_walls()

	return post


func spawn_post(pos, rot):

	var post = StaticBody3D.new()
	post.position = pos
	post.rotation.y = rot

	var mesh_instance = MeshInstance3D.new()

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.6, wall_height + 0.2, 0.6)

	mesh_instance.mesh = mesh
	mesh_instance.position.y = (wall_height + 0.2) * 0.5

	mesh_instance.material_override = brick_material

	post.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = mesh.size
	collision.shape = shape
	collision.position.y = mesh_instance.position.y

	post.add_child(collision)

	wall_parent.add_child(post)


# -------------------------------------------------
# PANELS
# -------------------------------------------------

func create_panel_between(p1, p2, dir):

	var width = p1.distance_to(p2)

	var panel_pos = (p1 + p2) * 0.5

	var panel = StaticBody3D.new()

	panel.position = panel_pos
	panel.rotation.y = atan2(dir.x, dir.z) + PI / 2

	var mesh_instance = MeshInstance3D.new()

	var mesh = BoxMesh.new()
	mesh.size = Vector3(width, wall_height, 0.45)

	mesh_instance.mesh = mesh
	mesh_instance.position.y = wall_height * 0.5

	mesh_instance.material_override = brick_material

	panel.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = mesh.size
	collision.shape = shape
	collision.position = mesh_instance.position

	panel.add_child(collision)

	wall_parent.add_child(panel)

	if !loading_walls:

		wall_data.append({
			"type": "panel",
			"x": panel_pos.x,
			"y": panel_pos.y,
			"z": panel_pos.z,
			"rot": panel.rotation.y,
			"width": width
		})

		save_walls()


func spawn_panel(pos, rot, width):

	var panel = StaticBody3D.new()
	panel.position = pos
	panel.rotation.y = rot

	var mesh_instance = MeshInstance3D.new()

	var mesh = BoxMesh.new()
	mesh.size = Vector3(width, wall_height, 0.45)

	mesh_instance.mesh = mesh
	mesh_instance.position.y = wall_height * 0.5

	mesh_instance.material_override = brick_material

	panel.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()

	shape.size = mesh.size
	collision.shape = shape
	collision.position = mesh_instance.position

	panel.add_child(collision)

	wall_parent.add_child(panel)


# -------------------------------------------------
# HELPERS
# -------------------------------------------------

func get_nearby_post(pos: Vector3):

	for child in wall_parent.get_children():

		if child.position.distance_to(pos) < post_snap_distance:
			return child

	return null


func delete_wall_piece():

	var result = get_crosshair_hit()
	if result == null:
		return

	var node = result.collider

	while node != null:

		if node.get_parent() == wall_parent:

			var pos = node.position

			for i in range(wall_data.size()):

				var p = wall_data[i]

				var saved_pos = Vector3(p["x"], p["y"], p["z"])

				if saved_pos.distance_to(pos) < 0.5:
					wall_data.remove_at(i)
					break

			node.queue_free()
			save_walls()
			return

		node = node.get_parent()


func get_building_generator():

	var world = get_tree().current_scene

	if world == null:
		print("No current scene")
		return null

	if !("BuildingGenerator" in world):
		print("World does not expose BuildingGenerator")
		return null

	var generator = world.BuildingGenerator

	if generator == null:
		print("World BuildingGenerator is null")
		return null

	return generator


func delete_building_at_crosshair():

	var generator = get_building_generator()

	if generator == null:
		print("Building generator reference missing")
		return

	if !generator.has_method("exclude_building"):
		print("Building generator does not have exclude_building()")
		return

	var result = get_crosshair_hit()
	if result == null:
		print("No hit")
		return

	if !result.has("collider"):
		print("No collider in hit result")
		return

	var node = result.collider

	while node != null:

		print("Hit node: ", node.name)

		if node.has_meta("building_id"):
			var building_id = str(node.get_meta("building_id"))
			print("Excluding building: ", building_id)
			generator.exclude_building(building_id)
			return

		node = node.get_parent()

	print("No building_id found on hit node chain")


# -------------------------------------------------
# RAYCAST
# -------------------------------------------------

func get_crosshair_ground():

	var center = get_viewport().get_visible_rect().size / 2

	var ray_origin = camera.project_ray_origin(center)
	var ray_dir = camera.project_ray_normal(center)

	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 2000
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
