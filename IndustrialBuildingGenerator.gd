extends Node

# -------------------------------------------------
# INDUSTRIAL BUILDING GENERATOR
# Separate from residential generator
# Keeps exact OSM footprints for industrial buildings
# No chunk interaction
# -------------------------------------------------

var chunk_manager
var chunks_parent
var world_parent
var industrial_parent : Node3D

const CACHE_PATH := "user://industrial_buildings_cache.json"
const EXCLUDE_PATH := "user://excluded_industrial_buildings.json"
const CACHE_VERSION := 4
const CHUNK_SIZE := 200.0

const INDUSTRIAL_TYPES := [
	"industrial",
	"warehouse",
	"factory",
	"commercial",
	"retail",
	"supermarket"
]

var cache_loaded := false

# Saved building data by ID
var building_data := {}

# Spawned building nodes by ID
var building_nodes := {}

# Excluded building IDs
var excluded_building_ids := {}

var wall_material : StandardMaterial3D
var roof_material : StandardMaterial3D

var industrial_buildings_visible := true


func _ready():
	set_process_input(true)
	set_process_unhandled_input(true)
	print("IndustrialBuildingGenerator ready")


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			print("O pressed in IndustrialBuildingGenerator")
			toggle_industrial_buildings_visibility()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			print("O pressed in IndustrialBuildingGenerator (_unhandled_input)")
			toggle_industrial_buildings_visibility()


func begin(parent):

	world_parent = parent
	chunk_manager = parent.get_node("ChunkManager")
	chunks_parent = parent.get_node("Chunks")

	set_process_input(true)
	set_process_unhandled_input(true)

	setup_materials()
	ensure_industrial_parent()
	load_excluded_buildings()


func ensure_industrial_parent():

	if industrial_parent != null and is_instance_valid(industrial_parent):
		industrial_parent.visible = industrial_buildings_visible
		return

	if chunks_parent.has_node("IndustrialBuildings"):
		industrial_parent = chunks_parent.get_node("IndustrialBuildings")
		industrial_parent.visible = industrial_buildings_visible
		return

	industrial_parent = Node3D.new()
	industrial_parent.name = "IndustrialBuildings"
	industrial_parent.visible = industrial_buildings_visible
	chunks_parent.add_child(industrial_parent)


func setup_materials():

	if wall_material != null:
		return

	wall_material = StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.55, 0.55, 0.58, 1.0)
	wall_material.roughness = 1.0
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	roof_material = StandardMaterial3D.new()
	roof_material.albedo_color = Color(0.72, 0.72, 0.72, 1.0)
	roof_material.roughness = 1.0
	roof_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func get_chunk_coords(pos: Vector3) -> Vector2i:

	var cx = int(floor(pos.x / CHUNK_SIZE))
	var cz = int(floor(pos.z / CHUNK_SIZE))
	return Vector2i(cx, cz)


func try_load_cached_buildings(parent) -> bool:

	begin(parent)

	if !FileAccess.file_exists(CACHE_PATH):
		return false

	print("Industrial cache found. Loading...")

	var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return false

	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return false

	if !data.has("version") or data["version"] != CACHE_VERSION:
		print("Industrial cache outdated. Regenerating.")
		return false

	building_data.clear()
	building_nodes.clear()

	if data.has("buildings"):
		for b in data["buildings"]:

			if !b.has("id"):
				continue

			var id := str(b["id"])

			if is_building_excluded(id):
				continue

			var fixed_points := []

			for p in b["points"]:
				if p is Array and p.size() == 3:
					fixed_points.append(Vector3(p[0], p[1], p[2]))

			fixed_points = remove_duplicate_points(fixed_points)

			if fixed_points.size() < 3:
				continue

			var height = float(b.get("height", 8.0))
			var type = str(b.get("type", "industrial"))

			if !is_industrial_building(type, {"building": type}):
				continue

			var saved = {
				"id": id,
				"points": fixed_points,
				"height": height,
				"type": type
			}

			building_data[id] = saved
			spawn_building_from_data(saved)

	print("Loaded industrial buildings: ", building_data.size())

	cache_loaded = true
	return true


func create_building(parent, el, nodes, geo):

	if cache_loaded:
		return

	if !el.has("id"):
		return

	var building_id := str(el["id"])

	if building_data.has(building_id):
		return

	if is_building_excluded(building_id):
		return

	var tags := {}
	if el.has("tags") and el["tags"] is Dictionary:
		tags = el["tags"]

	var type := "industrial"
	if tags.has("building"):
		type = str(tags["building"])

	if !is_industrial_building(type, tags):
		return

	var points := []

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

	if points[0] != points[points.size() - 1]:
		points.append(points[0])

	points = remove_duplicate_points(points)

	if points.size() < 3:
		return

	points = ensure_counter_clockwise(points)

	var levels := 2
	if tags.has("building:levels"):
		levels = max(1, int(tags["building:levels"]))

	var height := levels * 4.8

	if type in ["retail", "commercial", "supermarket"]:
		height = levels * 4.2

	var saved = {
		"id": building_id,
		"points": points,
		"height": height,
		"type": type
	}

	building_data[building_id] = saved
	spawn_building_from_data(saved)


func spawn_building_from_data(data: Dictionary):

	var id := str(data["id"])
	var points = data["points"]
	var height = float(data["height"])
	var type = str(data["type"])

	if points.size() < 3:
		return

	if !is_industrial_building(type, {"building": type}):
		return

	if building_nodes.has(id):
		if is_instance_valid(building_nodes[id]):
			building_nodes[id].queue_free()
		building_nodes.erase(id)

	ensure_industrial_parent()

	var root = Node3D.new()
	root.name = "Industrial_%s" % id
	root.set_meta("building_id", id)
	root.set_meta("building_type", type)
	root.set_meta("building_height", height)
	root.add_to_group("generated_industrial_buildings")
	root.visible = industrial_buildings_visible

	industrial_parent.add_child(root)

	var wall_instance = MeshInstance3D.new()
	wall_instance.name = "Walls"
	wall_instance.mesh = build_wall_mesh(points, height)
	root.add_child(wall_instance)

	var roof_instance = MeshInstance3D.new()
	roof_instance.name = "Roof"
	roof_instance.mesh = build_roof_mesh(points, height)
	root.add_child(roof_instance)

	building_nodes[id] = root


func build_wall_mesh(points: Array, height: float) -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(points.size()):

		var next = (i + 1) % points.size()

		var p1 = points[i]
		var p2 = points[next]

		if p1.distance_to(p2) < 0.001:
			continue

		var b1 = p1
		var b2 = p2
		var t1 = p1 + Vector3.UP * height
		var t2 = p2 + Vector3.UP * height

		var width = b1.distance_to(b2)

		st.set_uv(Vector2(0, 0))
		st.add_vertex(b1)

		st.set_uv(Vector2(width, 0))
		st.add_vertex(b2)

		st.set_uv(Vector2(width, height))
		st.add_vertex(t2)

		st.set_uv(Vector2(0, 0))
		st.add_vertex(b1)

		st.set_uv(Vector2(width, height))
		st.add_vertex(t2)

		st.set_uv(Vector2(0, height))
		st.add_vertex(t1)

	st.generate_normals()
	st.index()

	var mesh = st.commit()

	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, wall_material)

	return mesh


func build_roof_mesh(points: Array, height: float) -> ArrayMesh:

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if points.size() < 3:
		return st.commit()

	var polygon_2d := PackedVector2Array()

	for p in points:
		polygon_2d.append(Vector2(p.x, p.z))

	var indices = Geometry2D.triangulate_polygon(polygon_2d)

	if indices.is_empty():
		return st.commit()

	for i in range(0, indices.size(), 3):
		var a = points[indices[i]]
		var b = points[indices[i + 1]]
		var c = points[indices[i + 2]]

		st.add_vertex(Vector3(a.x, height, a.z))
		st.add_vertex(Vector3(b.x, height, b.z))
		st.add_vertex(Vector3(c.x, height, c.z))

	st.generate_normals()
	st.index()

	var mesh = st.commit()

	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, roof_material)

	return mesh


func finish_generation():

	if !cache_loaded:
		save_buildings()


func save_buildings():

	var save_data = {
		"version": CACHE_VERSION,
		"buildings": []
	}

	for id in building_data.keys():

		var b = building_data[id]
		var pts := []

		for p in b["points"]:
			pts.append([p.x, p.y, p.z])

		save_data["buildings"].append({
			"id": b["id"],
			"points": pts,
			"height": b["height"],
			"type": b["type"]
		})

	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		print("Failed to save industrial buildings cache.")
		return

	file.store_string(JSON.stringify(save_data))
	file.close()

	print("Industrial buildings cached: ", save_data["buildings"].size())


func delete_building(building_id, save_immediately := true):

	var id := str(building_id)

	if building_nodes.has(id):
		var node = building_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
		building_nodes.erase(id)

	if building_data.has(id):
		building_data.erase(id)
		print("Deleted industrial building: ", id)

	if save_immediately:
		save_buildings()


func exclude_building(building_id, save_immediately := true):

	var id := str(building_id)

	excluded_building_ids[id] = true
	delete_building(id, false)

	if save_immediately:
		save_excluded_buildings()
		save_buildings()

	print("Excluded industrial building: ", id)


func building_exists(building_id) -> bool:
	return building_data.has(str(building_id))


func is_building_excluded(building_id) -> bool:
	return excluded_building_ids.has(str(building_id))


func get_building_node(building_id):

	var id := str(building_id)

	if building_nodes.has(id):
		return building_nodes[id]

	return null


func get_all_building_ids() -> Array:
	return building_data.keys()


func load_excluded_buildings():

	excluded_building_ids.clear()

	if !FileAccess.file_exists(EXCLUDE_PATH):
		return

	var file = FileAccess.open(EXCLUDE_PATH, FileAccess.READ)
	if file == null:
		return

	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	if data.has("excluded_ids"):
		for id in data["excluded_ids"]:
			excluded_building_ids[str(id)] = true

	print("Loaded excluded industrial buildings: ", excluded_building_ids.size())


func save_excluded_buildings():

	var data = {
		"excluded_ids": []
	}

	for id in excluded_building_ids.keys():
		data["excluded_ids"].append(id)

	var file = FileAccess.open(EXCLUDE_PATH, FileAccess.WRITE)
	if file == null:
		print("Failed to save excluded industrial buildings.")
		return

	file.store_string(JSON.stringify(data))
	file.close()

	print("Saved excluded industrial buildings: ", excluded_building_ids.size())


func is_industrial_building(type: String, tags: Dictionary) -> bool:

	if type in INDUSTRIAL_TYPES:
		return true

	if tags.has("building") and str(tags["building"]) in INDUSTRIAL_TYPES:
		return true

	if tags.has("landuse"):
		var landuse = str(tags["landuse"])
		if landuse in ["industrial", "commercial", "retail"]:
			return true

	return false


func remove_duplicate_points(points: Array) -> Array:

	var cleaned := []

	for p in points:
		if cleaned.size() == 0 or cleaned[-1] != p:
			cleaned.append(p)

	if cleaned.size() > 1 and cleaned[0] == cleaned[cleaned.size() - 1]:
		cleaned.remove_at(cleaned.size() - 1)

	return cleaned


func ensure_counter_clockwise(points):

	var sum = 0.0

	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		sum += (p2.x - p1.x) * (p2.z + p1.z)

	if sum > 0:
		points.reverse()

	return points


func get_polygon_center(points) -> Vector3:

	var center := Vector3.ZERO

	for p in points:
		center += p

	return center / max(1, points.size())


func toggle_industrial_buildings_visibility():

	industrial_buildings_visible = !industrial_buildings_visible

	if industrial_parent == null or not is_instance_valid(industrial_parent):
		ensure_industrial_parent()

	if industrial_parent != null and is_instance_valid(industrial_parent):
		industrial_parent.visible = industrial_buildings_visible

	for id in building_nodes.keys():
		var node = building_nodes[id]
		if is_instance_valid(node):
			node.visible = industrial_buildings_visible

	print("Industrial buildings visible: ", industrial_buildings_visible)


func set_industrial_buildings_visible(visible: bool):

	industrial_buildings_visible = visible

	if industrial_parent == null or not is_instance_valid(industrial_parent):
		ensure_industrial_parent()

	if industrial_parent != null and is_instance_valid(industrial_parent):
		industrial_parent.visible = industrial_buildings_visible

	for id in building_nodes.keys():
		var node = building_nodes[id]
		if is_instance_valid(node):
			node.visible = industrial_buildings_visible

	print("Industrial buildings visible: ", industrial_buildings_visible)
