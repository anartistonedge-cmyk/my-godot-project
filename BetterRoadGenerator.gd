extends Node

const DATA_CACHE_PATH := "user://better_road_generator_cache.json"
const ROAD_MESH_CACHE_PATH := "user://better_road_mesh_cache.res"
const PATH_MESH_CACHE_PATH := "user://better_path_mesh_cache.res"
const CURB_MESH_CACHE_PATH := "user://better_curb_mesh_cache.res"
const MATERIAL_CACHE_PATH := "user://better_road_materials_cache.json"
const CACHE_VERSION := 3


var road_surface := SurfaceTool.new()
var path_surface := SurfaceTool.new()
var curb_surface := SurfaceTool.new()

var ROAD_HEIGHT = 0.35
var PATH_HEIGHT = 0.42
var PATH_WIDTH = 2.5
var PATH_OFFSET = 0.0
var PATH_THICKNESS = 0.18

var CURB_WIDTH = 0.18
var CURB_HEIGHT = 0.07

var SNAP_DISTANCE = 0.1
var ROAD_CHECK_DISTANCE = 4.0
var JUNCTION_CHECK_DISTANCE = 8.0

var PATH_SUBDIVISIONS = 4
var ROAD_EDGE_PADDING = 0.04
var PATH_Z_FIGHT_OFFSET = 0.01

var path_nodes = []
var road_points = []
var junction_points = []

# Full road surface quads with bounding boxes
var road_quads = []

# Store path/curb candidates until all roads are known
var curb_candidates = []
var path_candidates = []

# Editable path segments
var path_segments = []

var cache_loaded := false
var mesh_cache_loaded := false
var rng := RandomNumberGenerator.new()

var cached_road_mesh : Mesh = null
var cached_path_mesh : Mesh = null
var cached_curb_mesh : Mesh = null

var road_color := Color(0.08, 0.08, 0.08, 1.0)
var curb_color := Color(0.252, 0.252, 0.252, 1.0)
var path_color := Color(0.102, 0.102, 0.102, 1.0)


func begin():

	rng.randomize()

	road_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	path_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	curb_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	path_nodes.clear()
	road_points.clear()
	junction_points.clear()
	road_quads.clear()
	curb_candidates.clear()
	path_candidates.clear()
	path_segments.clear()

	cached_road_mesh = null
	cached_path_mesh = null
	cached_curb_mesh = null

	mesh_cache_loaded = load_mesh_cache()
	cache_loaded = load_data_cache()



# ------------------------------------------------
# CREATE EDITABLE SEGMENT
# ------------------------------------------------
func create_path_segment(start_pos:Vector3, end_pos:Vector3):

	var seg = {
		"start": start_pos,
		"end": end_pos
	}

	path_segments.append(seg)



# ------------------------------------------------
# SLIDE SEGMENT END
# ------------------------------------------------
func slide_segment_end(index:int, new_pos:Vector3):

	if index >= path_segments.size():
		return

	path_segments[index]["end"] = new_pos
	rebuild_paths()



func slide_segment_start(index:int, new_pos:Vector3):

	if index >= path_segments.size():
		return

	path_segments[index]["start"] = new_pos
	rebuild_paths()



# ------------------------------------------------
# SPLIT SEGMENT
# ------------------------------------------------
func split_segment(index:int, split_pos:Vector3):

	if index >= path_segments.size():
		return

	var seg = path_segments[index]

	var segA = {
		"start": seg["start"],
		"end": split_pos
	}

	var segB = {
		"start": split_pos,
		"end": seg["end"]
	}

	path_segments.remove_at(index)

	path_segments.append(segA)
	path_segments.append(segB)

	rebuild_paths()



# ------------------------------------------------
# REBUILD PATHS AFTER EDIT
# ------------------------------------------------
func rebuild_paths():

	path_surface.clear()
	path_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	path_nodes.clear()

	var trimmed_blocks = []

	for seg in path_segments:

		var a = seg["start"]
		var b = seg["end"]

		var dir = (b - a).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		var li = a + perp * (CURB_WIDTH + PATH_OFFSET)
		var lo = a + perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)

		var ri = b + perp * (CURB_WIDTH + PATH_OFFSET)
		var ro = b + perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)

		li.y = PATH_HEIGHT
		lo.y = PATH_HEIGHT
		ri.y = PATH_HEIGHT
		ro.y = PATH_HEIGHT

		var trimmed = trim_block_against_roads(li, lo, ro, ri)

		if trimmed["valid"]:
			trimmed["z_offset"] = 0.0
			trimmed_blocks.append(trimmed)

	resolve_path_block_z_fighting(trimmed_blocks)

	for block in trimmed_blocks:
		var ta = snap_point(block["a"])
		var tb = snap_point(block["b"])
		var tc = snap_point(block["c"])
		var td = snap_point(block["d"])

		add_path_block(path_surface, ta, tb, tc, td, block["z_offset"])



# ------------------------------------------------
# MERGE / DETECT JUNCTIONS
# ------------------------------------------------
func set_junction_points(points):

	junction_points.clear()

	var counts = {}

	for p in points:

		var key = Vector3(
			round(p.x * 10.0) / 10.0,
			0,
			round(p.z * 10.0) / 10.0
		)

		if not counts.has(key):
			counts[key] = 1
		else:
			counts[key] += 1

	for key in counts.keys():

		if counts[key] >= 3:
			junction_points.append(key)



func snap_point(p:Vector3) -> Vector3:

	for existing in path_nodes:
		if p.distance_to(existing) < SNAP_DISTANCE:
			return existing

	path_nodes.append(p)
	return p



# ------------------------------------------------
# FULL ROAD SURFACE DETECTION
# ------------------------------------------------
func point_in_triangle_xz(p:Vector3, a:Vector3, b:Vector3, c:Vector3) -> bool:

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



func point_in_quad_xz(p:Vector3, a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> bool:

	return point_in_triangle_xz(p, a, b, c) or point_in_triangle_xz(p, a, c, d)



func point_inside_quad_bounds_xz(p:Vector3, quad:Dictionary) -> bool:

	return (
		p.x >= quad["min_x"]
		and p.x <= quad["max_x"]
		and p.z >= quad["min_z"]
		and p.z <= quad["max_z"]
	)



func path_overlaps_road(p:Vector3) -> bool:

	for quad in road_quads:

		if not point_inside_quad_bounds_xz(p, quad):
			continue

		if point_in_quad_xz(p, quad["a"], quad["b"], quad["c"], quad["d"]):
			return true

	return false



func near_junction(p:Vector3) -> bool:

	for j in junction_points:
		if p.distance_to(j) < JUNCTION_CHECK_DISTANCE:
			return true

	return false



func block_sample_points(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> Array:

	var samples = []
	var ts = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

	for t in ts:
		var inner = a.lerp(d, t)
		var outer = b.lerp(c, t)
		var mid = (inner + outer) * 0.5
		var q1 = inner.lerp(mid, 0.5)
		var q3 = mid.lerp(outer, 0.5)

		samples.append(inner)
		samples.append(q1)
		samples.append(mid)
		samples.append(q3)
		samples.append(outer)

	return samples



func block_overlaps_road(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> bool:

	var samples = block_sample_points(a, b, c, d)

	for p in samples:
		if path_overlaps_road(p):
			return true

	return false



func cross_section_overlaps_road(a:Vector3, b:Vector3, c:Vector3, d:Vector3, t:float) -> bool:

	var inner = a.lerp(d, t)
	var outer = b.lerp(c, t)
	var mid = (inner + outer) * 0.5
	var q1 = inner.lerp(mid, 0.5)
	var q3 = mid.lerp(outer, 0.5)

	if path_overlaps_road(inner):
		return true
	if path_overlaps_road(q1):
		return true
	if path_overlaps_road(mid):
		return true
	if path_overlaps_road(q3):
		return true
	if path_overlaps_road(outer):
		return true

	return false



func curb_cross_section_overlaps_road(a:Vector3, b:Vector3, c:Vector3, d:Vector3, t:float) -> bool:

	var inner = a.lerp(d, t)
	var outer = b.lerp(c, t)

	var s1 = inner.lerp(outer, 0.35)
	var s2 = inner.lerp(outer, 0.7)
	var s3 = outer

	if path_overlaps_road(s1):
		return true
	if path_overlaps_road(s2):
		return true
	if path_overlaps_road(s3):
		return true

	return false



func find_trim_t_from_start(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> float:

	if not cross_section_overlaps_road(a, b, c, d, 0.0):
		return 0.0

	if cross_section_overlaps_road(a, b, c, d, 1.0):
		return 1.0

	var lo = 0.0
	var hi = 1.0

	for i in range(14):
		var mid = (lo + hi) * 0.5

		if cross_section_overlaps_road(a, b, c, d, mid):
			lo = mid
		else:
			hi = mid

	return hi



func find_trim_t_from_end(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> float:

	if not cross_section_overlaps_road(a, b, c, d, 1.0):
		return 1.0

	if cross_section_overlaps_road(a, b, c, d, 0.0):
		return 0.0

	var lo = 0.0
	var hi = 1.0

	for i in range(14):
		var mid = (lo + hi) * 0.5

		if cross_section_overlaps_road(a, b, c, d, mid):
			hi = mid
		else:
			lo = mid

	return lo



func find_curb_trim_t_from_start(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> float:

	if not curb_cross_section_overlaps_road(a, b, c, d, 0.0):
		return 0.0

	if curb_cross_section_overlaps_road(a, b, c, d, 1.0):
		return 1.0

	var lo = 0.0
	var hi = 1.0

	for i in range(14):
		var mid = (lo + hi) * 0.5

		if curb_cross_section_overlaps_road(a, b, c, d, mid):
			lo = mid
		else:
			hi = mid

	return hi



func find_curb_trim_t_from_end(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> float:

	if not curb_cross_section_overlaps_road(a, b, c, d, 1.0):
		return 1.0

	if curb_cross_section_overlaps_road(a, b, c, d, 0.0):
		return 0.0

	var lo = 0.0
	var hi = 1.0

	for i in range(14):
		var mid = (lo + hi) * 0.5

		if curb_cross_section_overlaps_road(a, b, c, d, mid):
			hi = mid
		else:
			lo = mid

	return lo



func trim_block_against_roads(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> Dictionary:

	var start_t = find_trim_t_from_start(a, b, c, d)
	var end_t = find_trim_t_from_end(a, b, c, d)

	var push = 0.006
	start_t = clamp(start_t + push, 0.0, 1.0)
	end_t = clamp(end_t - push, 0.0, 1.0)

	if start_t >= end_t:
		return {
			"valid": false
		}

	var na = a.lerp(d, start_t)
	var nb = b.lerp(c, start_t)
	var nc = b.lerp(c, end_t)
	var nd = a.lerp(d, end_t)

	var start_mid = (na + nb) * 0.5
	var end_mid = (nd + nc) * 0.5

	if start_mid.distance_to(end_mid) < 0.05:
		return {
			"valid": false
		}

	if block_overlaps_road(na, nb, nc, nd):
		return {
			"valid": false
		}

	if near_junction(start_mid) and near_junction(end_mid):
		return {
			"valid": false
		}

	return {
		"valid": true,
		"a": na,
		"b": nb,
		"c": nc,
		"d": nd
	}



func trim_curb_block_against_roads(a:Vector3, b:Vector3, c:Vector3, d:Vector3) -> Dictionary:

	var start_t = find_curb_trim_t_from_start(a, b, c, d)
	var end_t = find_curb_trim_t_from_end(a, b, c, d)

	var push = 0.003
	start_t = clamp(start_t + push, 0.0, 1.0)
	end_t = clamp(end_t - push, 0.0, 1.0)

	if start_t >= end_t:
		return {
			"valid": false
		}

	var na = a.lerp(d, start_t)
	var nb = b.lerp(c, start_t)
	var nc = b.lerp(c, end_t)
	var nd = a.lerp(d, end_t)

	var start_mid = (na + nb) * 0.5
	var end_mid = (nd + nc) * 0.5

	if start_mid.distance_to(end_mid) < 0.02:
		return {
			"valid": false
		}

	if near_junction(start_mid) and near_junction(end_mid):
		return {
			"valid": false
		}

	return {
		"valid": true,
		"a": na,
		"b": nb,
		"c": nc,
		"d": nd
	}



# ------------------------------------------------
# PATH vs PATH Z-FIGHTING
# ------------------------------------------------
func get_path_block_samples(block:Dictionary) -> Array:

	var a = block["a"]
	var b = block["b"]
	var c = block["c"]
	var d = block["d"]

	var samples = []
	var ts = [0.2, 0.5, 0.8]

	for t in ts:
		var inner = a.lerp(d, t)
		var outer = b.lerp(c, t)
		var mid = (inner + outer) * 0.5
		var q1 = inner.lerp(mid, 0.5)
		var q3 = mid.lerp(outer, 0.5)

		samples.append(q1)
		samples.append(mid)
		samples.append(q3)

	return samples



func path_block_bounds_overlap(block_a:Dictionary, block_b:Dictionary) -> bool:

	var min_ax = min(block_a["a"].x, block_a["b"].x, block_a["c"].x, block_a["d"].x)
	var max_ax = max(block_a["a"].x, block_a["b"].x, block_a["c"].x, block_a["d"].x)
	var min_az = min(block_a["a"].z, block_a["b"].z, block_a["c"].z, block_a["d"].z)
	var max_az = max(block_a["a"].z, block_a["b"].z, block_a["c"].z, block_a["d"].z)

	var min_bx = min(block_b["a"].x, block_b["b"].x, block_b["c"].x, block_b["d"].x)
	var max_bx = max(block_b["a"].x, block_b["b"].x, block_b["c"].x, block_b["d"].x)
	var min_bz = min(block_b["a"].z, block_b["b"].z, block_b["c"].z, block_b["d"].z)
	var max_bz = max(block_b["a"].z, block_b["b"].z, block_b["c"].z, block_b["d"].z)

	if max_ax < min_bx or max_bx < min_ax:
		return false

	if max_az < min_bz or max_bz < min_az:
		return false

	return true



func path_blocks_overlap(block_a:Dictionary, block_b:Dictionary) -> bool:

	if not path_block_bounds_overlap(block_a, block_b):
		return false

	var samples_a = get_path_block_samples(block_a)
	for p in samples_a:
		if point_in_quad_xz(p, block_b["a"], block_b["b"], block_b["c"], block_b["d"]):
			return true

	var samples_b = get_path_block_samples(block_b)
	for p in samples_b:
		if point_in_quad_xz(p, block_a["a"], block_a["b"], block_a["c"], block_a["d"]):
			return true

	return false



func resolve_path_block_z_fighting(blocks:Array):

	for i in range(blocks.size()):
		for j in range(i + 1, blocks.size()):
			if path_blocks_overlap(blocks[i], blocks[j]):
				if rng.randi_range(0, 1) == 0:
					blocks[i]["z_offset"] = PATH_Z_FIGHT_OFFSET
				else:
					blocks[j]["z_offset"] = PATH_Z_FIGHT_OFFSET



func store_candidate_block(target:Array, a:Vector3, b:Vector3, c:Vector3, d:Vector3):

	target.append({
		"a": a,
		"b": b,
		"c": c,
		"d": d
	})



func build_deferred_curbs_and_paths():

	path_surface.clear()
	curb_surface.clear()

	path_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	curb_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	path_nodes.clear()

	for item in curb_candidates:
		var trimmed_curb = trim_curb_block_against_roads(item["a"], item["b"], item["c"], item["d"])

		if trimmed_curb["valid"]:
			add_curb_block(
				curb_surface,
				trimmed_curb["a"],
				trimmed_curb["b"],
				trimmed_curb["c"],
				trimmed_curb["d"]
			)

	var trimmed_path_blocks = []

	for item in path_candidates:
		var trimmed_path = trim_block_against_roads(item["a"], item["b"], item["c"], item["d"])

		if trimmed_path["valid"]:
			trimmed_path["z_offset"] = 0.0
			trimmed_path_blocks.append(trimmed_path)

	resolve_path_block_z_fighting(trimmed_path_blocks)

	for block in trimmed_path_blocks:
		var ta = snap_point(block["a"])
		var tb = snap_point(block["b"])
		var tc = snap_point(block["c"])
		var td = snap_point(block["d"])

		add_path_block(path_surface, ta, tb, tc, td, block["z_offset"])



func add_road(points, width):

	if mesh_cache_loaded:
		return

	if points.size() < 2:
		return

	var half = width * 0.5

	var left_points = []
	var right_points = []

	for i in range(points.size()):

		var p = points[i]
		road_points.append(p)

		var dir = Vector3.ZERO

		if i == 0:
			dir = (points[i + 1] - p).normalized()

		elif i == points.size() - 1:
			dir = (p - points[i - 1]).normalized()

		else:
			var forward = (points[i + 1] - p).normalized()
			var backward = (p - points[i - 1]).normalized()
			dir = (forward + backward).normalized()

		var perp = Vector3(-dir.z, 0, dir.x)

		var left = p + perp * half
		var right = p - perp * half

		left.y += ROAD_HEIGHT
		right.y += ROAD_HEIGHT

		left_points.append(left)
		right_points.append(right)


	for i in range(points.size() - 1):

		var l1 = left_points[i]
		var r1 = right_points[i]
		var l2 = left_points[i + 1]
		var r2 = right_points[i + 1]

		if l1.distance_to(l2) < 0.3:
			continue

		add_quad(road_surface, l1, r1, r2, l2)

		var min_x = min(l1.x, r1.x, r2.x, l2.x) - ROAD_EDGE_PADDING
		var max_x = max(l1.x, r1.x, r2.x, l2.x) + ROAD_EDGE_PADDING
		var min_z = min(l1.z, r1.z, r2.z, l2.z) - ROAD_EDGE_PADDING
		var max_z = max(l1.z, r1.z, r2.z, l2.z) + ROAD_EDGE_PADDING

		road_quads.append({
			"a": l1,
			"b": r1,
			"c": r2,
			"d": l2,
			"min_x": min_x,
			"max_x": max_x,
			"min_z": min_z,
			"max_z": max_z
		})

		var dir = (points[i + 1] - points[i]).normalized()
		var perp = Vector3(-dir.z, 0, dir.x)

		for s in range(PATH_SUBDIVISIONS):

			var t1 = float(s) / PATH_SUBDIVISIONS
			var t2 = float(s + 1) / PATH_SUBDIVISIONS

			var sl1 = l1.lerp(l2, t1)
			var sl2 = l1.lerp(l2, t2)
			var sr1 = r1.lerp(r2, t1)
			var sr2 = r1.lerp(r2, t2)

			# CURB LEFT
			var curb_i1 = sl1
			var curb_o1 = sl1 + perp * CURB_WIDTH
			var curb_i2 = sl2
			var curb_o2 = sl2 + perp * CURB_WIDTH

			curb_i1.y = ROAD_HEIGHT
			curb_i2.y = ROAD_HEIGHT
			curb_o1.y = ROAD_HEIGHT + CURB_HEIGHT
			curb_o2.y = ROAD_HEIGHT + CURB_HEIGHT

			store_candidate_block(curb_candidates, curb_i1, curb_o1, curb_o2, curb_i2)

			# PATH LEFT
			var li1 = sl1 + perp * (CURB_WIDTH + PATH_OFFSET)
			var lo1 = sl1 + perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)
			var li2 = sl2 + perp * (CURB_WIDTH + PATH_OFFSET)
			var lo2 = sl2 + perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)

			li1.y = PATH_HEIGHT
			lo1.y = PATH_HEIGHT
			li2.y = PATH_HEIGHT
			lo2.y = PATH_HEIGHT

			store_candidate_block(path_candidates, li1, lo1, lo2, li2)

			# CURB RIGHT
			var curb_ri1 = sr1
			var curb_ro1 = sr1 - perp * CURB_WIDTH
			var curb_ri2 = sr2
			var curb_ro2 = sr2 - perp * CURB_WIDTH

			curb_ri1.y = ROAD_HEIGHT
			curb_ri2.y = ROAD_HEIGHT
			curb_ro1.y = ROAD_HEIGHT + CURB_HEIGHT
			curb_ro2.y = ROAD_HEIGHT + CURB_HEIGHT

			store_candidate_block(curb_candidates, curb_ri1, curb_ro1, curb_ro2, curb_ri2)

			# PATH RIGHT
			var ri1 = sr1 - perp * (CURB_WIDTH + PATH_OFFSET)
			var ro1 = sr1 - perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)
			var ri2 = sr2 - perp * (CURB_WIDTH + PATH_OFFSET)
			var ro2 = sr2 - perp * (CURB_WIDTH + PATH_OFFSET + PATH_WIDTH)

			ri1.y = PATH_HEIGHT
			ro1.y = PATH_HEIGHT
			ri2.y = PATH_HEIGHT
			ro2.y = PATH_HEIGHT

			store_candidate_block(path_candidates, ri1, ro1, ro2, ri2)



func add_quad(st, a, b, c, d):

	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)



func add_path_block(st, a, b, c, d, y_offset:float = 0.0):

	var top_y = PATH_HEIGHT + y_offset
	var bottom_y = top_y - PATH_THICKNESS

	var a1 = Vector3(a.x, top_y, a.z)
	var b1 = Vector3(b.x, top_y, b.z)
	var c1 = Vector3(c.x, top_y, c.z)
	var d1 = Vector3(d.x, top_y, d.z)

	var a2 = Vector3(a.x, bottom_y, a.z)
	var b2 = Vector3(b.x, bottom_y, b.z)
	var c2 = Vector3(c.x, bottom_y, c.z)
	var d2 = Vector3(d.x, bottom_y, d.z)

	add_quad(st, a1, b1, c1, d1)
	add_quad(st, d2, c2, b2, a2)

	add_quad(st, a1, d1, d2, a2)
	add_quad(st, b1, a1, a2, b2)
	add_quad(st, c1, b1, b2, c2)
	add_quad(st, d1, c1, c2, d2)



func add_curb_block(st, a, b, c, d):

	var bottom_y = ROAD_HEIGHT

	var a2 = Vector3(a.x, bottom_y, a.z)
	var b2 = Vector3(b.x, bottom_y, b.z)
	var c2 = Vector3(c.x, bottom_y, c.z)
	var d2 = Vector3(d.x, bottom_y, d.z)

	add_quad(st, a, b, c, d)
	add_quad(st, d2, c2, b2, a2)

	add_quad(st, a, d, d2, a2)
	add_quad(st, b, a, a2, b2)
	add_quad(st, c, b, b2, c2)
	add_quad(st, d, c, c2, d2)



# ------------------------------------------------
# CACHE HELPERS
# ------------------------------------------------
func vec3_to_data(v:Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func data_to_vec3(d:Dictionary) -> Vector3:
	return Vector3(float(d["x"]), float(d["y"]), float(d["z"]))


func color_to_data(c:Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


func data_to_color(d:Dictionary) -> Color:
	return Color(float(d["r"]), float(d["g"]), float(d["b"]), float(d["a"]))


func block_to_data(block:Dictionary) -> Dictionary:
	return {
		"a": vec3_to_data(block["a"]),
		"b": vec3_to_data(block["b"]),
		"c": vec3_to_data(block["c"]),
		"d": vec3_to_data(block["d"])
	}


func data_to_block(data:Dictionary) -> Dictionary:
	return {
		"a": data_to_vec3(data["a"]),
		"b": data_to_vec3(data["b"]),
		"c": data_to_vec3(data["c"]),
		"d": data_to_vec3(data["d"])
	}


func road_quad_to_data(quad:Dictionary) -> Dictionary:
	return {
		"a": vec3_to_data(quad["a"]),
		"b": vec3_to_data(quad["b"]),
		"c": vec3_to_data(quad["c"]),
		"d": vec3_to_data(quad["d"]),
		"min_x": quad["min_x"],
		"max_x": quad["max_x"],
		"min_z": quad["min_z"],
		"max_z": quad["max_z"]
	}


func data_to_road_quad(data:Dictionary) -> Dictionary:
	return {
		"a": data_to_vec3(data["a"]),
		"b": data_to_vec3(data["b"]),
		"c": data_to_vec3(data["c"]),
		"d": data_to_vec3(data["d"]),
		"min_x": float(data["min_x"]),
		"max_x": float(data["max_x"]),
		"min_z": float(data["min_z"]),
		"max_z": float(data["max_z"])
	}


func save_data_cache():

	var root = {
		"version": CACHE_VERSION,
		"road_quads": [],
		"curb_candidates": [],
		"path_candidates": [],
		"junction_points": [],
		"path_segments": []
	}

	for quad in road_quads:
		root["road_quads"].append(road_quad_to_data(quad))

	for block in curb_candidates:
		root["curb_candidates"].append(block_to_data(block))

	for block in path_candidates:
		root["path_candidates"].append(block_to_data(block))

	for p in junction_points:
		root["junction_points"].append(vec3_to_data(p))

	for seg in path_segments:
		root["path_segments"].append({
			"start": vec3_to_data(seg["start"]),
			"end": vec3_to_data(seg["end"])
		})

	var json_text = JSON.stringify(root)

	var file = FileAccess.open(DATA_CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json_text)
		file.close()


func load_data_cache() -> bool:

	if not FileAccess.file_exists(DATA_CACHE_PATH):
		return false

	var file = FileAccess.open(DATA_CACHE_PATH, FileAccess.READ)
	if file == null:
		return false

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_text)

	if err != OK:
		return false

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		return false

	if !data.has("version") or int(data["version"]) != CACHE_VERSION:
		return false

	if typeof(data) != TYPE_DICTIONARY:
		return false

	if data.has("road_quads"):
		for quad_data in data["road_quads"]:
			road_quads.append(data_to_road_quad(quad_data))

	if data.has("curb_candidates"):
		for block_data in data["curb_candidates"]:
			curb_candidates.append(data_to_block(block_data))

	if data.has("path_candidates"):
		for block_data in data["path_candidates"]:
			path_candidates.append(data_to_block(block_data))

	if data.has("junction_points"):
		for point_data in data["junction_points"]:
			junction_points.append(data_to_vec3(point_data))

	if data.has("path_segments"):
		for seg_data in data["path_segments"]:
			path_segments.append({
				"start": data_to_vec3(seg_data["start"]),
				"end": data_to_vec3(seg_data["end"])
			})

	return road_quads.size() > 0


func save_material_cache():

	var root = {
		"road_color": color_to_data(road_color),
		"curb_color": color_to_data(curb_color),
		"path_color": color_to_data(path_color)
	}

	var json_text = JSON.stringify(root)
	var file = FileAccess.open(MATERIAL_CACHE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json_text)
		file.close()


func load_material_cache():

	if not FileAccess.file_exists(MATERIAL_CACHE_PATH):
		return

	var file = FileAccess.open(MATERIAL_CACHE_PATH, FileAccess.READ)
	if file == null:
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_text)

	if err != OK:
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return

	if data.has("road_color"):
		road_color = data_to_color(data["road_color"])
	if data.has("curb_color"):
		curb_color = data_to_color(data["curb_color"])
	if data.has("path_color"):
		path_color = data_to_color(data["path_color"])


func save_mesh_cache(road_mesh:Mesh, curb_mesh:Mesh, path_mesh:Mesh):

	ResourceSaver.save(road_mesh, ROAD_MESH_CACHE_PATH)
	ResourceSaver.save(curb_mesh, CURB_MESH_CACHE_PATH)
	ResourceSaver.save(path_mesh, PATH_MESH_CACHE_PATH)
	save_material_cache()


func load_mesh_cache() -> bool:

	if not FileAccess.file_exists(ROAD_MESH_CACHE_PATH):
		return false
	if not FileAccess.file_exists(CURB_MESH_CACHE_PATH):
		return false
	if not FileAccess.file_exists(PATH_MESH_CACHE_PATH):
		return false

	cached_road_mesh = load(ROAD_MESH_CACHE_PATH)
	cached_curb_mesh = load(CURB_MESH_CACHE_PATH)
	cached_path_mesh = load(PATH_MESH_CACHE_PATH)

	if cached_road_mesh == null or cached_curb_mesh == null or cached_path_mesh == null:
		cached_road_mesh = null
		cached_curb_mesh = null
		cached_path_mesh = null
		return false

	load_material_cache()
	return true


func clear_mesh_cache():
	if FileAccess.file_exists(ROAD_MESH_CACHE_PATH):
		DirAccess.remove_absolute(ROAD_MESH_CACHE_PATH)
	if FileAccess.file_exists(CURB_MESH_CACHE_PATH):
		DirAccess.remove_absolute(CURB_MESH_CACHE_PATH)
	if FileAccess.file_exists(PATH_MESH_CACHE_PATH):
		DirAccess.remove_absolute(PATH_MESH_CACHE_PATH)
	if FileAccess.file_exists(MATERIAL_CACHE_PATH):
		DirAccess.remove_absolute(MATERIAL_CACHE_PATH)



# ------------------------------------------------
# JUNCTION DEBUG
# ------------------------------------------------
func draw_junction_debug(parent):

	for j in junction_points:

		var mesh = TorusMesh.new()
		mesh.inner_radius = JUNCTION_CHECK_DISTANCE
		mesh.outer_radius = JUNCTION_CHECK_DISTANCE + 0.1

		var m = MeshInstance3D.new()
		m.mesh = mesh
		m.position = j
		m.position.y += 1.2

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0)
		mat.emission_enabled = true
		mat.emission = Color(1, 0, 0)

		m.material_override = mat
		parent.add_child(m)



func finish(parent):

	var road_mesh : Mesh
	var path_mesh : Mesh
	var curb_mesh : Mesh

	if mesh_cache_loaded:
		road_mesh = cached_road_mesh
		path_mesh = cached_path_mesh
		curb_mesh = cached_curb_mesh
	else:
		build_deferred_curbs_and_paths()

		road_surface.generate_normals()
		path_surface.generate_normals()
		curb_surface.generate_normals()

		road_mesh = road_surface.commit()
		path_mesh = path_surface.commit()
		curb_mesh = curb_surface.commit()

		save_data_cache()
		save_mesh_cache(road_mesh, curb_mesh, path_mesh)

	var roads = MeshInstance3D.new()
	roads.mesh = road_mesh

	var road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = road_color
	road_mat.roughness = 1.0

	roads.material_override = road_mat
	parent.add_child(roads)

	var curbs = MeshInstance3D.new()
	curbs.mesh = curb_mesh

	var curb_mat = StandardMaterial3D.new()
	curb_mat.albedo_color = curb_color
	curb_mat.roughness = 1.0

	curbs.material_override = curb_mat
	parent.add_child(curbs)

	var paths = MeshInstance3D.new()
	paths.mesh = path_mesh

	var path_mat = StandardMaterial3D.new()
	path_mat.albedo_color = path_color
	path_mat.roughness = 1.0
	path_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	paths.material_override = path_mat
	parent.add_child(paths)

	draw_junction_debug(parent)
