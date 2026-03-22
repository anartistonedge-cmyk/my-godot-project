extends Node3D

const MAP_CACHE_PATH = "user://parsed_map_cache.json"

const CENTER_LAT = 52.68363
const CENTER_LON = -1.94049
const METERS_PER_DEGREE = 111320.0
const SCALE = 1.0

const ROAD_WIDTH = 8.0
const PAVEMENT_WIDTH = 1.6
const PAVEMENT_HEIGHT = 0.16

var nodes = {}
var node_use_count = {}

var roads = []
var road_names = []
var road_segments = []

@onready var GeoUtils = preload("res://GeoUtils.gd").new()
@onready var OSMParser = preload("res://OSMParser.gd").new()
@onready var RoadGenerator = preload("res://RoadGenerator.gd").new()
@onready var BetterRoadGenerator = preload("res://BetterRoadGenerator.gd").new()
@onready var BuildingGenerator = preload("res://BuildingGenerator.gd").new()
@onready var IndustrialBuildingGenerator = preload("res://IndustrialBuildingGenerator.gd").new()
@onready var GroundGenerator = preload("res://GroundGenerator.gd").new()
@onready var TreeGenerator = preload("res://TreeGenerator.gd").new()
@onready var TreeSaveManager = preload("res://TreeSaveManager.gd").new()


func _ready():

	randomize()

	add_child(GroundGenerator)

	# -------- Tree systems --------
	add_child(TreeGenerator)
	add_child(TreeSaveManager)
	# ------------------------------

	GeoUtils.CENTER_LAT = CENTER_LAT
	GeoUtils.CENTER_LON = CENTER_LON
	GeoUtils.METERS_PER_DEGREE = METERS_PER_DEGREE
	GeoUtils.SCALE = SCALE

	var map_data

	# -------------------------
	# LOAD PARSED CACHE
	# -------------------------

	if FileAccess.file_exists(MAP_CACHE_PATH):

		print("Loading cached parsed map")

		var file = FileAccess.open(MAP_CACHE_PATH, FileAccess.READ)
		var json = JSON.parse_string(file.get_as_text())
		file.close()

		map_data = json

	else:

		print("Parsing OSM map for first time")

		map_data = OSMParser.load_map("res://ws7.json")

		var file = FileAccess.open(MAP_CACHE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(map_data))
		file.close()

		print("Saved parsed map cache")


	nodes = map_data["nodes"]
	node_use_count = map_data["node_use_count"]

	roads.clear()
	road_names.clear()

	# -------------------------
	# JUNCTION DETECTION (IMPROVED)
	# -------------------------

	var junction_points = []

	for node_id in node_use_count:

		# A real junction is typically used by 3+ road segments
		if node_use_count[node_id] >= 3:

			var node = nodes.get(node_id)

			if node == null:
				node = nodes.get(str(node_id))

			if node == null:
				continue

			var pos = GeoUtils.convert_coords(node["lat"], node["lon"])
			junction_points.append(pos)

	print("Detected junctions:", junction_points.size())

	# Send junctions to road generator
	BetterRoadGenerator.set_junction_points(junction_points)

	# -------------------------
	# BUILDING SYSTEM SETUP
	# -------------------------

	var buildings_loaded = BuildingGenerator.try_load_cached_buildings(self)
	var industrial_buildings_loaded = IndustrialBuildingGenerator.try_load_cached_buildings(self)

	if !buildings_loaded:
		BuildingGenerator.begin(self)

	if !industrial_buildings_loaded:
		IndustrialBuildingGenerator.begin(self)

	var tree_container = get_node("Trees")

	# -------------------------
	# START ROAD GENERATION
	# -------------------------

	BetterRoadGenerator.begin()

	for el in map_data["elements"]:

		if not el.has("tags"):
			continue

		var tags = el["tags"]

		# -------------------------
		# ROADS
		# -------------------------

		if tags.has("highway") and tags["highway"] in [
			"motorway",
			"primary",
			"secondary",
			"tertiary",
			"unclassified",
			"residential",
			"service"
		]:

			var points = []

			for n in el["nodes"]:

				var node = nodes.get(n)

				if node == null:
					node = nodes.get(str(n))

				if node == null:
					continue

				points.append(
					GeoUtils.convert_coords(node["lat"], node["lon"])
				)

			# Skip broken roads
			if points.size() < 2:
				continue

			# Save roads for minimap
			roads.append(points)

			var road_name = ""
			if tags.has("name"):
				road_name = tags["name"]
			else:
				road_name = "Unnamed Road"

			road_names.append(road_name)

			# Save individual road segments for road name lookup
			for i in range(points.size() - 1):
				road_segments.append({
					"p1": points[i],
					"p2": points[i + 1],
					"name": road_name
				})

			BetterRoadGenerator.add_road(points, ROAD_WIDTH)

			continue

		# -------------------------
		# BUILDINGS
		# -------------------------

		if tags.has("building"):

			if !buildings_loaded:
				BuildingGenerator.create_building(
					self,
					el,
					nodes,
					GeoUtils,
					roads
				)

			if !industrial_buildings_loaded:
				IndustrialBuildingGenerator.create_building(
					self,
					el,
					nodes,
					GeoUtils
				)

			continue

		# -------------------------
		# LANDUSE
		# -------------------------



	# -------------------------
	# FINISH ROAD MESH
	# -------------------------

	BetterRoadGenerator.finish(self)

	# -------------------------
	# FINALISE BUILDING MESH
	# -------------------------

	if !buildings_loaded:
		BuildingGenerator.finish_generation()

	if !industrial_buildings_loaded:
		IndustrialBuildingGenerator.finish_generation()

	# -------------------------
	# LOAD SAVED TREES
	# -------------------------

	TreeSaveManager.load_trees(tree_container, TreeGenerator)
