# Individual building generator
# Residential buildings now spawn as simple grey foundations with a visible front marker

var chunk_manager
var chunks_parent
var world_parent

const CACHE_PATH := "user://buildings_cache.json"
const EXCLUDE_PATH := "user://excluded_buildings.json"
const CACHE_VERSION := 25
const CHUNK_SIZE := 200.0

const ROAD_SURFACE_MARGIN := 1.2
const PATH_SURFACE_MARGIN := 0.8
const CURB_SURFACE_MARGIN := 0.3
const PUSHBACK_PASSES := 3
const PLOT_EXPAND := 3.0
const BLOCK_SEARCH_MARGIN := 10.0

const BUILDING_SPACING_MARGIN := 1.2
const BUILDING_PUSHBACK_PASSES := 4

const ACCESS_REQUIRED_MAX_DISTANCE := 22.0
const FOUNDATION_HEIGHT := 0.12
const FOUNDATION_SIDE_INSET := 0.35
const FOUNDATION_FRONT_INSET := 0.45
const FOUNDATION_BACK_INSET := 0.55

const FRONT_MARKER_HEIGHT := 0.22
const FRONT_MARKER_WIDTH := 1.2
const FRONT_MARKER_DEPTH := 0.22

const RESIDENTIAL_TYPES := [
	"house",
	"residential",
	"detached",
	"semidetached_house",
	"semidetached",
	"terrace",
	"terraced_house",
	"terraced",
	"row_house",
	"yes"
]

var cache_loaded := false

# Saved building data by ID
var building_data := {}

# Spawned building nodes by ID
var building_nodes := {}

# Excluded building IDs
var excluded_building_ids := {}

var default_wall_material : StandardMaterial3D
var residential_wall_material : StandardMaterial3D
var plot_material : StandardMaterial3D
var front_marker_material : StandardMaterial3D


func begin(parent):

	world_parent = parent
	chunk_manager = parent.get_node("ChunkManager")
	chunks_parent = parent.get_node("Chunks")

	setup_materials()
	load_excluded_buildings()


func setup_materials():

	if default_wall_material != null:
		return

	default_wall_material = StandardMaterial3D.new()
	default_wall_material.albedo_color = Color(0.65, 0.65, 0.65, 1.0)

	residential_wall_material = StandardMaterial3D.new()
	residential_wall_material.albedo_color = Color(0.62, 0.62, 0.62, 1.0)
	residential_wall_material.roughness = 1.0
	residential_wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	plot_material = StandardMaterial3D.new()
	plot_material.albedo_color = Color(0.22, 0.22, 0.22, 1.0)
	plot_material.roughness = 1.0

	front_marker_material = StandardMaterial3D.new()
	front_marker_material.albedo_color = Color(0.9, 0.15, 0.1, 1.0)
	front_marker_material.emission_enabled = true
	front_marker_material.emission = Color(0.9, 0.15, 0.1, 1.0)
	front_marker_material.emission_energy_multiplier = 1.2
	front_marker_material.roughness = 0.8


func get_chunk_coords(pos: Vector3) -> Vector2i:

	var cx = int(floor(pos.x / CHUNK_SIZE))
	var cz = int(floor(pos.z / CHUNK_SIZE))

	return Vector2i(cx, cz)


func get_chunk_node(coords: Vector2i) -> Node3D:

	var name = "chunk_%d_%d" % [coords.x, coords.y]

	if chunks_parent.has_node(name):
		return chunks_parent.get_node(name)

	var chunk = Node3D.new()
	chunk.name = name

	chunks_parent.add_child(chunk)

	chunk.add_to_group("distance_objects")
	chunk_manager.register_object(chunk)

	return chunk


func try_load_cached_buildings(parent) -> bool:

	begin(parent)

	if !FileAccess.file_exists(CACHE_PATH):
		return false

	print("Building cache found. Loading...")

	var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return false

	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return false

	if !data.has("version") or data["version"] != CACHE_VERSION:
		print("Cache outdated. Regenerating buildings.")
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

			if fixed_points.size() < 3:
				continue

			var height = float(b.get("height", 6.0))
			var type = str(b.get("type", "residential"))
			var spawn_config = b.get("spawn_config", {"mode": "skip"})

			if !is_residential_building(type, {"building": type}):
				continue

			if str(spawn_config.get("mode", "")) != "foundation":
				continue

			var saved = {
				"id": id,
				"points": fixed_points,
				"height": height,
				"type": type,
				"spawn_config": spawn_config
			}

			building_data[id] = saved
			spawn_building_from_data(saved)

	print("Loaded cached buildings: ", building_data.size())

	cache_loaded = true
	return true


func create_building(parent, el, nodes, geo, roads):

	if cache_loaded:
		return

	if !el.has("id"):
		return

	var building_id := str(el["id"])

	if building_data.has(building_id):
		return

	if is_building_excluded(building_id):
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

	var pushback_data = get_surface_pushback_data(parent)

	var nearby_road_blocks = get_nearby_blocks(points, pushback_data["road_blocks"], BLOCK_SEARCH_MARGIN)
	var nearby_path_blocks = get_nearby_blocks(points, pushback_data["path_blocks"], BLOCK_SEARCH_MARGIN)
	var nearby_curb_blocks = get_nearby_blocks(points, pushback_data["curb_blocks"], BLOCK_SEARCH_MARGIN)

	var local_pushback_data = {
		"road_blocks": nearby_road_blocks,
		"path_blocks": nearby_path_blocks,
		"curb_blocks": nearby_curb_blocks,
		"road_margin": pushback_data["road_margin"],
		"path_margin": pushback_data["path_margin"],
		"curb_margin": pushback_data["curb_margin"]
	}

	points = apply_surface_block_pushback(points, local_pushback_data, PUSHBACK_PASSES)
	points = apply_building_spacing_pushback(points, BUILDING_SPACING_MARGIN, BUILDING_PUSHBACK_PASSES)

	points = remove_duplicate_points(points)

	if points.size() < 3:
		return

	var height := 6.0
	var levels := 2
	var type := "residential"
	var tags := {}

	if el.has("tags") and el["tags"] is Dictionary:
		tags = el["tags"]

	if tags.has("building:levels"):
		levels = max(1, int(tags["building:levels"]))

	height = levels * 3.8

	if tags.has("building"):
		type = str(tags["building"])

	var spawn_config = choose_spawn_config(building_id, points, height, type, tags, roads, nodes, geo, parent)

	if str(spawn_config.get("mode", "")) == "skip":
		return

	var saved = {
		"id": building_id,
		"points": points,
		"height": height,
		"type": type,
		"spawn_config": spawn_config
	}

	building_data[building_id] = saved
	spawn_building_from_data(saved)


func choose_spawn_config(building_id: String, points: Array, height: float, type: String, tags: Dictionary, roads, nodes, geo, parent) -> Dictionary:

	if is_residential_building(type, tags):
		var access_data = get_nearest_access_data_for_plot(points, roads, nodes, geo, parent)

		if access_data.is_empty():
			return {"mode": "skip"}

		if float(access_data.get("distance", INF)) > ACCESS_REQUIRED_MAX_DISTANCE:
			return {"mode": "skip"}

		return {
			"mode": "foundation",
			"front_kind": access_data.get("kind", "road"),
			"road_facing_angle_degrees": access_data["facing_angle_degrees"],
			"road_tangent_angle_degrees": access_data["tangent_angle_degrees"],
			"road_anchor_point": access_data["closest_point"]
		}

	return {"mode": "skip"}


func spawn_building_from_data(data: Dictionary):

	var id := str(data["id"])
	var points = data["points"]
	var height = float(data["height"])
	var type = str(data["type"])
	var spawn_config = data.get("spawn_config", {"mode": "skip"})

	if points.size() < 3:
		return

	if str(spawn_config.get("mode", "")) != "foundation":
		return

	if !is_residential_building(type, {"building": type}):
		return

	if building_nodes.has(id):
		if is_instance_valid(building_nodes[id]):
			building_nodes[id].queue_free()
		building_nodes.erase(id)

	var center = get_polygon_center(points)
	var coords = get_chunk_coords(center)
	var chunk = get_chunk_node(coords)

	var root = Node3D.new()
	root.name = "Building_%s" % id
	root.set_meta("building_id", id)
	root.set_meta("building_type", type)
	root.set_meta("building_height", height)
	root.add_to_group("generated_buildings")

	chunk.add_child(root)

	var foundation_instance = MeshInstance3D.new()
	foundation_instance.name = "Foundation"
	foundation_instance.mesh = build_residential_foundation_mesh(points, spawn_config)
	foundation_instance.visible = false
	root.add_child(foundation_instance)

	var front_marker = create_residential_front_marker(points, spawn_config)
	if front_marker != null:
		front_marker.visible = false
		root.add_child(front_marker)

	building_nodes[id] = root


func build_residential_foundation_mesh(points: Array, spawn_config: Dictionary) -> ArrayMesh:

	var rect_points = get_residential_foundation_rect(points, spawn_config)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if rect_points.size() == 4:
		var y_off = Vector3(0, FOUNDATION_HEIGHT, 0)

		st.add_vertex(rect_points[0] + y_off)
		st.add_vertex(rect_points[2] + y_off)
		st.add_vertex(rect_points[1] + y_off)

		st.add_vertex(rect_points[0] + y_off)
		st.add_vertex(rect_points[3] + y_off)
		st.add_vertex(rect_points[2] + y_off)

	st.generate_normals()
	st.index()

	var mesh = st.commit()

	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, residential_wall_material)

	return mesh


func create_residential_front_marker(points: Array, spawn_config: Dictionary) -> Node3D:

	var rect_points = get_residential_foundation_rect(points, spawn_config)
	if rect_points.size() != 4:
		return null

	var front_left: Vector3 = rect_points[3]
	var front_right: Vector3 = rect_points[2]
	var back_left: Vector3 = rect_points[0]

	var front_edge = front_right - front_left
	front_edge.y = 0.0

	var side_depth = front_left - back_left
	side_depth.y = 0.0

	# Do not show marker if the foundation is too small to be meaningful
	if front_edge.length() < 1.0 or side_depth.length() < 1.0:
		return null

	var front_center: Vector3 = (front_left + front_right) * 0.5
	var width = min(FRONT_MARKER_WIDTH, front_edge.length() * 0.6)

	var mesh = BoxMesh.new()
	mesh.size = Vector3(width, FRONT_MARKER_HEIGHT, FRONT_MARKER_DEPTH)

	var marker = MeshInstance3D.new()
	marker.name = "FrontMarker"
	marker.mesh = mesh
	marker.material_override = front_marker_material

	marker.position = front_center + Vector3(0, FOUNDATION_HEIGHT + FRONT_MARKER_HEIGHT * 0.5, 0)

	var yaw = atan2(front_edge.x, front_edge.z)
	marker.rotation.y = yaw

	return marker


func get_residential_foundation_rect(points: Array, spawn_config: Dictionary) -> Array:

	var center = get_polygon_center(points)

	var width_axis := Vector3.RIGHT
	var depth_axis := Vector3.FORWARD

	if spawn_config.has("road_facing_angle_degrees"):
		var facing_angle = float(spawn_config.get("road_facing_angle_degrees", 0.0))
		depth_axis = Vector3(
			sin(deg_to_rad(facing_angle)),
			0,
			cos(deg_to_rad(facing_angle))
		).normalized()

	if depth_axis.length() < 0.001:
		depth_axis = Vector3.FORWARD

	# Force a true perpendicular width axis so foundations stay rectangular
	width_axis = Vector3(-depth_axis.z, 0, depth_axis.x).normalized()

	if width_axis.length() < 0.001:
		width_axis = Vector3.RIGHT

	var min_w := INF
	var max_w := -INF
	var min_d := INF
	var max_d := -INF

	for p in points:
		var rel = p - center
		var w = rel.dot(width_axis)
		var d = rel.dot(depth_axis)

		min_w = min(min_w, w)
		max_w = max(max_w, w)
		min_d = min(min_d, d)
		max_d = max(max_d, d)

	min_w += FOUNDATION_SIDE_INSET
	max_w -= FOUNDATION_SIDE_INSET
	min_d += FOUNDATION_BACK_INSET
	max_d -= FOUNDATION_FRONT_INSET

	var width = max_w - min_w
	var depth = max_d - min_d

	# Stop tiny or collapsed plots from turning into weird shapes
	var min_foundation_width := 2.2
	var min_foundation_depth := 2.2

	if width < min_foundation_width:
		var mid_w = (min_w + max_w) * 0.5
		min_w = mid_w - min_foundation_width * 0.5
		max_w = mid_w + min_foundation_width * 0.5

	if depth < min_foundation_depth:
		var mid_d = (min_d + max_d) * 0.5
		min_d = mid_d - min_foundation_depth * 0.5
		max_d = mid_d + min_foundation_depth * 0.5

	var p0 = center + width_axis * min_w + depth_axis * min_d
	var p1 = center + width_axis * max_w + depth_axis * min_d
	var p2 = center + width_axis * max_w + depth_axis * max_d
	var p3 = center + width_axis * min_w + depth_axis * max_d

	return [p0, p1, p2, p3]


func get_nearest_access_data_for_plot(points: Array, roads, nodes, geo, parent) -> Dictionary:

	var road_data = get_nearest_road_data_for_plot(points, roads, nodes, geo)
	var path_data = get_nearest_path_data_for_plot(points, parent)

	if road_data.is_empty() and path_data.is_empty():
		return {}

	if road_data.is_empty():
		return path_data

	if path_data.is_empty():
		return road_data

	var road_dist = float(road_data.get("distance", INF))
	var path_dist = float(path_data.get("distance", INF))

	if path_dist < road_dist:
		return path_data

	return road_data


func get_nearest_road_data_for_plot(points: Array, roads, nodes, geo) -> Dictionary:

	var probes := []
	var center = get_polygon_center(points)

	probes.append(center)

	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		probes.append((a + b) * 0.5)

	var best_data := {}
	var best_score := INF

	for probe in probes:
		var road_data: Dictionary = get_nearest_road_data(probe, roads, nodes, geo)
		var dist = float(road_data.get("distance", INF))

		if dist < best_score:
			best_score = dist
			best_data = road_data.duplicate()

	if best_data.is_empty():
		return get_nearest_road_data(center, roads, nodes, geo)

	return best_data


func get_nearest_path_data_for_plot(points: Array, parent) -> Dictionary:

	var center = get_polygon_center(points)
	var probes := [center]

	var surface_data = get_surface_pushback_data(parent)
	var path_blocks: Array = surface_data.get("path_blocks", [])

	var best_dist: float = INF
	var best_closest: Vector3 = center
	var best_tangent: Vector3 = Vector3.RIGHT

	for probe in probes:
		for block in path_blocks:
			var a: Vector3 = block["a"]
			var b: Vector3 = block["b"]
			var c: Vector3 = block["c"]
			var d: Vector3 = block["d"]

			var closest = get_closest_point_on_quad_edges_xz(probe, a, b, c, d)
			var dist = probe.distance_to(closest)

			if dist < best_dist:
				best_dist = dist
				best_closest = closest

				var ab = b - a
				ab.y = 0.0
				var bc = c - b
				bc.y = 0.0

				best_tangent = ab.normalized()
				if bc.length() > ab.length():
					best_tangent = bc.normalized()

	if best_dist == INF:
		return {}

	var facing = best_closest - center
	facing.y = 0.0

	if facing.length() < 0.001:
		facing = Vector3(0, 0, -1)
	else:
		facing = facing.normalized()

	if best_tangent.length() < 0.001:
		best_tangent = Vector3(-facing.z, 0, facing.x).normalized()

	return {
		"kind": "path",
		"closest_point": best_closest,
		"tangent": best_tangent,
		"facing": facing,
		"distance": best_dist,
		"tangent_angle_degrees": rad_to_deg(atan2(best_tangent.x, best_tangent.z)),
		"facing_angle_degrees": rad_to_deg(atan2(facing.x, facing.z))
	}


func get_nearest_road_data(center: Vector3, roads, nodes, geo) -> Dictionary:

	var best_dist := INF
	var best_closest := center
	var best_tangent := Vector3(1, 0, 0)

	for road in roads:
		if !road.has("nodes"):
			continue

		var road_nodes = road["nodes"]

		for i in range(road_nodes.size() - 1):

			var n1 = nodes.get(road_nodes[i])
			if n1 == null:
				n1 = nodes.get(str(road_nodes[i]))

			var n2 = nodes.get(road_nodes[i + 1])
			if n2 == null:
				n2 = nodes.get(str(road_nodes[i + 1]))

			if n1 == null or n2 == null:
				continue

			var a = geo.convert_coords(n1["lat"], n1["lon"])
			var b = geo.convert_coords(n2["lat"], n2["lon"])

			var closest = closest_point_on_segment_xz(center, a, b)
			var dist = center.distance_to(closest)

			if dist < best_dist:
				best_dist = dist
				best_closest = closest

				var tangent = b - a
				tangent.y = 0.0
				if tangent.length() > 0.001:
					best_tangent = tangent.normalized()

	var facing = best_closest - center
	facing.y = 0.0

	if facing.length() < 0.001:
		facing = Vector3(0, 0, -1)
	else:
		facing = facing.normalized()

	if best_tangent.length() < 0.001:
		best_tangent = Vector3(-facing.z, 0, facing.x).normalized()

	return {
		"kind": "road",
		"closest_point": best_closest,
		"tangent": best_tangent,
		"facing": facing,
		"distance": best_dist,
		"tangent_angle_degrees": rad_to_deg(atan2(best_tangent.x, best_tangent.z)),
		"facing_angle_degrees": rad_to_deg(atan2(facing.x, facing.z))
	}


func is_residential_building(type: String, tags: Dictionary) -> bool:

	if type in RESIDENTIAL_TYPES:
		return true

	if tags.has("building") and str(tags["building"]) in RESIDENTIAL_TYPES:
		return true

	if tags.has("house"):
		return true

	return false


func get_surface_pushback_data(parent) -> Dictionary:

	var road_blocks := []
	var path_blocks := []
	var curb_blocks := []

	var better = null

	if parent != null and "BetterRoadGenerator" in parent:
		better = parent.BetterRoadGenerator

	if better != null:

		if "road_quads" in better and better.road_quads is Array:
			for block in better.road_quads:
				road_blocks.append(block)

		if "path_candidates" in better and better.path_candidates is Array:
			for block in better.path_candidates:
				path_blocks.append(block)

		if "curb_candidates" in better and better.curb_candidates is Array:
			for block in better.curb_candidates:
				curb_blocks.append(block)

	return {
		"road_blocks": road_blocks,
		"path_blocks": path_blocks,
		"curb_blocks": curb_blocks,
		"road_margin": ROAD_SURFACE_MARGIN,
		"path_margin": PATH_SURFACE_MARGIN,
		"curb_margin": CURB_SURFACE_MARGIN
	}


func get_nearby_blocks(points: Array, blocks: Array, extra_margin: float) -> Array:

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF

	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.z)
		max_z = max(max_z, p.z)

	min_x -= extra_margin
	max_x += extra_margin
	min_z -= extra_margin
	max_z += extra_margin

	var nearby := []

	for block in blocks:

		var a: Vector3 = block["a"]
		var b: Vector3 = block["b"]
		var c: Vector3 = block["c"]
		var d: Vector3 = block["d"]

		var block_min_x: float = min(a.x, min(b.x, min(c.x, d.x)))
		var block_max_x: float = max(a.x, max(b.x, max(c.x, d.x)))
		var block_min_z: float = min(a.z, min(b.z, min(c.z, d.z)))
		var block_max_z: float = max(a.z, max(b.z, max(c.z, d.z)))

		if block_max_x < min_x:
			continue
		if block_min_x > max_x:
			continue
		if block_max_z < min_z:
			continue
		if block_min_z > max_z:
			continue

		nearby.append(block)

	return nearby


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
			"type": b["type"],
			"spawn_config": b.get("spawn_config", {"mode": "skip"})
		})

	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		print("Failed to save buildings cache.")
		return

	file.store_string(JSON.stringify(save_data))
	file.close()

	print("Buildings cached: ", save_data["buildings"].size())


func delete_building(building_id, save_immediately := true):

	var id := str(building_id)

	if building_nodes.has(id):
		var node = building_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
		building_nodes.erase(id)

	if building_data.has(id):
		building_data.erase(id)
		print("Deleted building: ", id)

	if save_immediately:
		save_buildings()


func exclude_building(building_id, save_immediately := true):

	var id := str(building_id)

	excluded_building_ids[id] = true
	delete_building(id, false)

	if save_immediately:
		save_excluded_buildings()
		save_buildings()

	print("Excluded building: ", id)


func unexclude_building(building_id, save_immediately := true):

	var id := str(building_id)

	if excluded_building_ids.has(id):
		excluded_building_ids.erase(id)

	if save_immediately:
		save_excluded_buildings()

	print("Unexcluded building: ", id)


func replace_building_with_scene(building_id, scene: PackedScene, save_delete := true):

	var id := str(building_id)

	if !building_data.has(id):
		print("Building not found for replacement: ", id)
		return null

	var old_data = building_data[id]
	var center = get_polygon_center(old_data["points"])
	var coords = get_chunk_coords(center)
	var chunk = get_chunk_node(coords)

	delete_building(id, save_delete)

	var instance = scene.instantiate()
	instance.name = "Replacement_%s" % id
	instance.position = center
	chunk.add_child(instance)

	return instance


func building_exists(building_id) -> bool:

	return building_data.has(str(building_id))


func is_building_excluded(building_id) -> bool:

	return excluded_building_ids.has(str(building_id))


func get_building_node(building_id):

	var id := str(building_id)

	if building_nodes.has(id):
		return building_nodes[id]

	return null


func get_building_center(building_id) -> Vector3:

	var id := str(building_id)

	if !building_data.has(id):
		return Vector3.ZERO

	return get_polygon_center(building_data[id]["points"])


func get_all_building_ids() -> Array:

	return building_data.keys()


func get_all_excluded_building_ids() -> Array:

	return excluded_building_ids.keys()


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

	print("Loaded excluded buildings: ", excluded_building_ids.size())


func save_excluded_buildings():

	var data = {
		"excluded_ids": []
	}

	for id in excluded_building_ids.keys():
		data["excluded_ids"].append(id)

	var file = FileAccess.open(EXCLUDE_PATH, FileAccess.WRITE)
	if file == null:
		print("Failed to save excluded buildings.")
		return

	file.store_string(JSON.stringify(data))
	file.close()

	print("Saved excluded buildings: ", excluded_building_ids.size())


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


func get_check_points(points: Array) -> Array:

	var checks := []

	for p in points:
		checks.append(p)

	for i in range(points.size()):
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		checks.append((a + b) * 0.5)

	checks.append(get_polygon_center(points))

	return checks


func get_plot_alignment_data(points: Array) -> Dictionary:

	var center = get_polygon_center(points)

	var longest_len := 0.0
	var forward := Vector3.FORWARD

	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		var edge = b - a
		edge.y = 0.0

		var len = edge.length()
		if len > longest_len:
			longest_len = len
			forward = edge.normalized()

	if forward.length() < 0.001:
		forward = Vector3(0, 0, -1)

	var right = Vector3(-forward.z, 0, forward.x).normalized()

	var min_f := INF
	var max_f := -INF
	var min_r := INF
	var max_r := -INF

	for p in points:
		var rel = p - center
		var f = rel.dot(forward)
		var r = rel.dot(right)

		min_f = min(min_f, f)
		max_f = max(max_f, f)
		min_r = min(min_r, r)
		max_r = max(max_r, r)

	var length = max_f - min_f
	var depth = max_r - min_r

	return {
		"center": center,
		"forward": forward,
		"right": right,
		"length": max(length, 0.1),
		"depth": max(depth, 0.1),
		"angle_degrees": rad_to_deg(atan2(forward.x, forward.z))
	}


func get_plot_data_for_model_axes(points: Array, road_data: Dictionary) -> Dictionary:

	var center = get_polygon_center(points)

	var width_axis: Vector3 = road_data["tangent"]
	var depth_axis: Vector3 = road_data["facing"]

	if width_axis.length() < 0.001 or depth_axis.length() < 0.001:
		var fallback = get_plot_alignment_data(points)
		width_axis = fallback["forward"]
		depth_axis = fallback["right"]

	var min_w := INF
	var max_w := -INF
	var min_d := INF
	var max_d := -INF

	for p in points:
		var rel = p - center
		var w = rel.dot(width_axis)
		var d = rel.dot(depth_axis)

		min_w = min(min_w, w)
		max_w = max(max_w, w)
		min_d = min(min_d, d)
		max_d = max(max_d, d)

	return {
		"center": center,
		"width": max(max_w - min_w, 0.1),
		"depth": max(max_d - min_d, 0.1)
	}


func point_in_triangle_xz(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:

	var p2 = Vector2(p.x, p.z)
	var a2 = Vector2(a.x, a.z)
	var b2 = Vector2(b.x, b.z)
	var c2 = Vector2(c.x, c.z)

	var v0 = c2 - a2
	var v1 = b2 - a2
	var v2 = p2 - a2

	var dot00 = v0.dot(v0)
	var dot01 = v0.dot(v1)
	var dot02 = v0.dot(v2)
	var dot11 = v1.dot(v1)
	var dot12 = v1.dot(v2)

	var denom = dot00 * dot11 - dot01 * dot01

	if abs(denom) < 0.000001:
		return false

	var inv_denom = 1.0 / denom
	var u = (dot11 * dot02 - dot01 * dot12) * inv_denom
	var v = (dot00 * dot12 - dot01 * dot02) * inv_denom

	return u >= -0.0001 and v >= -0.0001 and (u + v) <= 1.0001


func point_in_quad_xz(p: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:

	return point_in_triangle_xz(p, a, b, c) or point_in_triangle_xz(p, a, c, d)


func point_near_block_bounds_xz(p: Vector3, block: Dictionary, margin: float) -> bool:

	var a: Vector3 = block["a"]
	var b: Vector3 = block["b"]
	var c: Vector3 = block["c"]
	var d: Vector3 = block["d"]

	var min_x: float = min(a.x, min(b.x, min(c.x, d.x))) - margin
	var max_x: float = max(a.x, max(b.x, max(c.x, d.x))) + margin
	var min_z: float = min(a.z, min(b.z, min(c.z, d.z))) - margin
	var max_z: float = max(a.z, max(b.z, max(c.z, d.z))) + margin

	return (
		p.x >= min_x and p.x <= max_x
		and p.z >= min_z and p.z <= max_z
	)


func closest_point_on_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> Vector3:

	var ab = b - a
	ab.y = 0.0

	var ap = point - a
	ap.y = 0.0

	if ab.length_squared() <= 0.000001:
		return Vector3(a.x, point.y, a.z)

	var t = ap.dot(ab) / ab.length_squared()
	t = clamp(t, 0.0, 1.0)

	var closest = a + ab * t
	closest.y = point.y

	return closest


func get_closest_point_on_quad_edges_xz(point: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector3:

	var best = closest_point_on_segment_xz(point, a, b)
	var best_dist = point.distance_to(best)

	var edges = [
		[b, c],
		[c, d],
		[d, a]
	]

	for edge in edges:
		var cp = closest_point_on_segment_xz(point, edge[0], edge[1])
		var dist = point.distance_to(cp)
		if dist < best_dist:
			best = cp
			best_dist = dist

	return best


func get_block_push_vector(point: Vector3, building_center: Vector3, block: Dictionary, clearance: float) -> Vector3:

	if !point_near_block_bounds_xz(point, block, clearance):
		return Vector3.ZERO

	var a: Vector3 = block["a"]
	var b: Vector3 = block["b"]
	var c: Vector3 = block["c"]
	var d: Vector3 = block["d"]

	var inside = point_in_quad_xz(point, a, b, c, d)

	var nearest_point = closest_point_on_segment_xz(point, a, b)
	var nearest_dist = point.distance_to(nearest_point)

	var edges = [
		[a, b],
		[b, c],
		[c, d],
		[d, a]
	]

	for edge in edges:
		var cp = closest_point_on_segment_xz(point, edge[0], edge[1])
		var dist = point.distance_to(cp)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest_point = cp

	if !inside and nearest_dist >= clearance:
		return Vector3.ZERO

	var push_amount := 0.0

	if inside:
		push_amount = clearance + nearest_dist
	else:
		push_amount = clearance - nearest_dist

	var block_center = (a + b + c + d) * 0.25
	var dir = building_center - block_center
	dir.y = 0.0

	if dir.length() < 0.001:
		dir = point - nearest_point
		dir.y = 0.0

	if dir.length() < 0.001:
		var edge_dir = b - a
		edge_dir.y = 0.0

		if edge_dir.length() < 0.001:
			return Vector3.ZERO

		edge_dir = edge_dir.normalized()
		dir = Vector3(-edge_dir.z, 0, edge_dir.x)

	if dir.length() < 0.001:
		return Vector3.ZERO

	return dir.normalized() * push_amount


func apply_surface_block_pushback(points: Array, pushback_data: Dictionary, max_passes: int) -> Array:

	var moved_points := []
	for p in points:
		moved_points.append(p)

	var road_blocks: Array = pushback_data.get("road_blocks", [])
	var path_blocks: Array = pushback_data.get("path_blocks", [])
	var curb_blocks: Array = pushback_data.get("curb_blocks", [])

	var road_margin: float = float(pushback_data.get("road_margin", ROAD_SURFACE_MARGIN))
	var path_margin: float = float(pushback_data.get("path_margin", PATH_SURFACE_MARGIN))
	var curb_margin: float = float(pushback_data.get("curb_margin", CURB_SURFACE_MARGIN))

	for push_pass in range(max_passes):

		var check_points = get_check_points(moved_points)
		var building_center = get_polygon_center(moved_points)

		var total_push := Vector3.ZERO
		var push_count := 0
		var max_single_push := 0.0
		var had_overlap := false

		for block in road_blocks:
			for p in check_points:
				var push_vec = get_block_push_vector(p, building_center, block, road_margin)

				if push_vec.length() > 0.0001:
					had_overlap = true
					total_push += push_vec
					push_count += 1
					max_single_push = max(max_single_push, push_vec.length())

		for block in path_blocks:
			for p in check_points:
				var push_vec = get_block_push_vector(p, building_center, block, path_margin)

				if push_vec.length() > 0.0001:
					had_overlap = true
					total_push += push_vec
					push_count += 1
					max_single_push = max(max_single_push, push_vec.length())

		for block in curb_blocks:
			for p in check_points:
				var push_vec = get_block_push_vector(p, building_center, block, curb_margin)

				if push_vec.length() > 0.0001:
					had_overlap = true
					total_push += push_vec
					push_count += 1
					max_single_push = max(max_single_push, push_vec.length())

		if !had_overlap:
			break

		if push_count == 0:
			break

		var final_push = total_push / float(push_count)
		final_push.y = 0.0

		if final_push.length() < 0.0001:
			break

		if final_push.length() > max_single_push:
			final_push = final_push.normalized() * max_single_push

		for i in range(moved_points.size()):
			moved_points[i] += final_push

	return moved_points


func apply_building_spacing_pushback(points: Array, spacing_margin: float, max_passes: int) -> Array:

	var moved_points := []
	for p in points:
		moved_points.append(p)

	for push_pass in range(max_passes):

		var my_bounds = get_points_bounds_xz(moved_points)
		var my_center = get_polygon_center(moved_points)

		var had_overlap := false
		var total_push := Vector3.ZERO
		var push_count := 0

		for other_id in building_data.keys():
			var other = building_data[other_id]
			if !other.has("points"):
				continue

			var other_points: Array = other["points"]
			if other_points.size() < 3:
				continue

			var other_bounds = get_points_bounds_xz(other_points)

			var expand = spacing_margin
			var min_x_a = my_bounds["min_x"] - expand
			var max_x_a = my_bounds["max_x"] + expand
			var min_z_a = my_bounds["min_z"] - expand
			var max_z_a = my_bounds["max_z"] + expand

			var min_x_b = other_bounds["min_x"]
			var max_x_b = other_bounds["max_x"]
			var min_z_b = other_bounds["min_z"]
			var max_z_b = other_bounds["max_z"]

			var overlap_x = min(max_x_a, max_x_b) - max(min_x_a, min_x_b)
			var overlap_z = min(max_z_a, max_z_b) - max(min_z_a, min_z_b)

			if overlap_x > 0.0 and overlap_z > 0.0:
				had_overlap = true

				var other_center = get_polygon_center(other_points)
				var dir = my_center - other_center
				dir.y = 0.0

				var push_vec := Vector3.ZERO

				if abs(dir.x) >= abs(dir.z):
					var sign_x = 1.0 if dir.x >= 0.0 else -1.0
					push_vec = Vector3(sign_x * (overlap_x + 0.05), 0, 0)
				else:
					var sign_z = 1.0 if dir.z >= 0.0 else -1.0
					push_vec = Vector3(0, 0, sign_z * (overlap_z + 0.05))

				total_push += push_vec
				push_count += 1

		if !had_overlap or push_count == 0:
			break

		var final_push = total_push / float(push_count)
		final_push.y = 0.0

		if final_push.length() < 0.0001:
			break

		for i in range(moved_points.size()):
			moved_points[i] += final_push

	return moved_points


func get_points_bounds_xz(points: Array) -> Dictionary:

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF

	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.z)
		max_z = max(max_z, p.z)

	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z
	}
