extends Node3D

var tool_active := false

var bush_lines = []

const SAVE_PATH = "user://bush_lines.json"

@export var bush_spacing := 1.6

var preview_mesh := ImmediateMesh.new()
var preview_instance : MeshInstance3D

var preview_parent : Node3D

var bush_parent : Node3D
var camera : Camera3D

var painting := false
var last_paint_pos : Vector3
var distance_since_last := 0.0


func _ready():

	print("BushPainter ready")

	set_process_input(true)

	camera = get_viewport().get_camera_3d()

	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = preview_mesh
	add_child(preview_instance)

	bush_parent = Node3D.new()
	bush_parent.name = "Bushes"
	add_child(bush_parent)

	preview_parent = Node3D.new()
	preview_parent.name = "BushPreview"
	add_child(preview_parent)

	load_bush_lines()


func activate():
	print("Bush tool activated")
	tool_active = true


func deactivate():

	tool_active = false
	painting = false

	for c in preview_parent.get_children():
		c.queue_free()


func _input(event):

	if !tool_active:
		return

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_LEFT:

			if event.pressed:
				start_paint()
			else:
				stop_paint()

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			delete_bush()


func _process(delta):

	if !tool_active:
		return

	if painting:
		paint_step()

	draw_preview()


# -------------------------------------------------
# PAINTING SYSTEM
# -------------------------------------------------

func start_paint():

	var pos = get_crosshair_ground()

	if pos == null:
		return

	last_paint_pos = pos
	distance_since_last = 0
	painting = true

	create_bush(pos)
	bush_lines.append({
		"pos":[pos.x,pos.y,pos.z]
	})
	save_bush_lines()


func stop_paint():
	painting = false


func paint_step():

	var pos = get_crosshair_ground()

	if pos == null:
		return

	var dist = last_paint_pos.distance_to(pos)

	if dist < bush_spacing:
		return

	var dir = (pos - last_paint_pos).normalized()

	var steps = int(dist / bush_spacing)

	for i in range(steps):

		var p = last_paint_pos + dir * bush_spacing * (i + 1)

		p.x += randf_range(-0.35,0.35)
		p.z += randf_range(-0.35,0.35)

		create_bush(p)

		bush_lines.append({
			"pos":[p.x,p.y,p.z]
		})

	last_paint_pos = pos

	save_bush_lines()


# -------------------------------------------------
# PREVIEW
# -------------------------------------------------

func draw_preview():

	for c in preview_parent.get_children():
		c.queue_free()

	var mouse = get_crosshair_ground()

	if mouse == null:
		return

	var preview = build_preview_bush()
	preview.position = mouse

	preview_parent.add_child(preview)


func create_preview_bush():

	var bush = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = build_leaf_flake_bush_mesh(true)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	mesh_instance.material_override = mat

	bush.add_child(mesh_instance)

	return bush


func build_preview_bush():

	var bush = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = build_leaf_flake_bush_mesh(true)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	mesh_instance.material_override = mat

	bush.add_child(mesh_instance)

	return bush


# -------------------------------------------------
# BUSH GENERATION
# -------------------------------------------------

func create_bush(pos):

	var bush = StaticBody3D.new()
	bush.position = pos
	bush.rotation.y = randf() * TAU

	bush.collision_layer = 2
	bush.collision_mask = 1

	# Taller bushes overall, with more random variation
	var bush_scale = randf_range(1.05, 1.9)
	if randf() < 0.2:
		bush_scale = randf_range(1.9, 2.35)

	bush.scale = Vector3.ONE * bush_scale

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = build_leaf_flake_bush_mesh(false)

	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	mesh_instance.material_override = mat

	bush.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()

	shape.radius = 1.8
	collision.shape = shape
	collision.position = Vector3(0,1.1,0)

	bush.add_child(collision)

	bush_parent.add_child(bush)


func build_leaf_flake_bush_mesh(is_preview: bool) -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bush_style = randi() % 4

	var point_count = 180
	var width = 1.6
	var depth = 1.6
	var height = 1.9

	if bush_style == 0:
		# round and taller
		point_count = 180
		width = 1.5
		depth = 1.5
		height = 1.9
	elif bush_style == 1:
		# wider hedge-like
		point_count = 190
		width = 2.1
		depth = 1.5
		height = 1.5
	elif bush_style == 2:
		# scruffy tall
		point_count = 200
		width = 1.6
		depth = 1.6
		height = 2.2
	else:
		# compact but upright
		point_count = 170
		width = 1.3
		depth = 1.3
		height = 2.0

	# 3 darker random bush palettes
	var palette_a_dark = Color(0.05, 0.11, 0.04)
	var palette_a_light = Color(0.10, 0.20, 0.08)

	var palette_b_dark = Color(0.06, 0.13, 0.05)
	var palette_b_light = Color(0.12, 0.23, 0.09)

	var palette_c_dark = Color(0.04, 0.09, 0.03)
	var palette_c_light = Color(0.09, 0.17, 0.07)

	if is_preview:
		palette_a_dark = Color(0.08, 0.32, 0.08, 0.35)
		palette_a_light = Color(0.14, 0.48, 0.14, 0.35)

		palette_b_dark = Color(0.09, 0.36, 0.10, 0.35)
		palette_b_light = Color(0.16, 0.54, 0.16, 0.35)

		palette_c_dark = Color(0.07, 0.28, 0.07, 0.35)
		palette_c_light = Color(0.12, 0.42, 0.12, 0.35)

	var tint = Color(
		randf_range(0.72, 0.88),
		randf_range(0.72, 0.88),
		randf_range(0.72, 0.88),
		1.0 if !is_preview else 0.35
	)

	for i in range(point_count):

		var x = randf_range(-width, width)
		var z = randf_range(-depth, depth)

		var edge_x = abs(x) / max(width, 0.001)
		var edge_z = abs(z) / max(depth, 0.001)
		var edge = max(edge_x, edge_z)

		var max_y = lerp(height, height * 0.5, edge)
		var y = randf_range(0.18, max_y)

		if bush_style == 2:
			y += randf_range(-0.15, 0.35)
		elif bush_style == 3:
			y += randf_range(0.0, 0.22)

		var center = Vector3(x, y, z)

		var flake_count = 2
		var flake_size = randf_range(0.18, 0.30)

		if bush_style == 1:
			flake_count = 2
			flake_size = randf_range(0.17, 0.28)
		elif bush_style == 2:
			flake_count = 3
			flake_size = randf_range(0.16, 0.27)
		elif bush_style == 3:
			flake_count = 3
			flake_size = randf_range(0.18, 0.29)

		for j in range(flake_count):

			var palette_roll = randi() % 3

			var dark = palette_a_dark
			var light = palette_a_light

			if palette_roll == 1:
				dark = palette_b_dark
				light = palette_b_light
			elif palette_roll == 2:
				dark = palette_c_dark
				light = palette_c_light

			var leaf_color = Color(
				randf_range(dark.r, light.r) * tint.r,
				randf_range(dark.g, light.g) * tint.g,
				randf_range(dark.b, light.b) * tint.b,
				tint.a
			)

			add_leaf_flake(
				st,
				center + Vector3(
					randf_range(-0.08, 0.08),
					randf_range(-0.08, 0.08),
					randf_range(-0.08, 0.08)
				),
				flake_size,
				leaf_color
			)

	st.generate_normals()

	var mesh = st.commit()

	return mesh


func add_leaf_flake(st: SurfaceTool, center: Vector3, size: float, color: Color):

	var basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, randf() * TAU)
	basis = basis.rotated(Vector3.RIGHT, randf_range(-0.9, 0.9))
	basis = basis.rotated(Vector3.FORWARD, randf_range(-0.9, 0.9))

	var right = basis.x.normalized() * size
	var up = basis.y.normalized() * size * randf_range(0.65, 1.15)

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


# -------------------------------------------------
# SAVE / LOAD
# -------------------------------------------------

func save_bush_lines():

	var file = FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify(bush_lines))
	file.close()


func load_bush_lines():

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH,FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for entry in data:

		var p = entry["pos"]

		create_bush(Vector3(p[0],p[1],p[2]))

	bush_lines = data


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

	query.collision_mask = 1

	var result = space.intersect_ray(query)

	if result:
		return result.position

	return null


func delete_bush():

	var result = get_crosshair_raycast()

	if result.is_empty():
		return

	if !result.has("collider"):
		return

	var node = result.collider

	while node != null:

		if node.get_parent() == bush_parent:

			var pos = node.position

			node.queue_free()

			bush_lines = bush_lines.filter(func(b):
				return Vector3(b["pos"][0],b["pos"][1],b["pos"][2]).distance_to(pos) > 0.5
			)

			save_bush_lines()
			return

		node = node.get_parent()


func get_crosshair_raycast():

	var center = get_viewport().get_visible_rect().size / 2

	var ray_origin = camera.project_ray_origin(center)
	var ray_dir = camera.project_ray_normal(center)

	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 2000
	)

	query.collision_mask = 2

	return space.intersect_ray(query)
