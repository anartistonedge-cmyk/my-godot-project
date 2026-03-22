extends Control

@onready var player = get_tree().get_root().get_node_or_null("World/CharacterBody3D")
@onready var world_node = get_tree().get_root().get_node_or_null("World")

var road_system = null
var map_scale := 0.5


func _ready():
	if world_node != null:
		road_system = find_road_system(world_node)


func find_road_system(node: Node):

	if node == null:
		return null

	if "road_quads" in node:
		return node

	for child in node.get_children():
		var found = find_road_system(child)
		if found != null:
			return found

	return null


func _process(delta):
	queue_redraw()


func _draw():

	if player == null:
		return

	var center = Vector2(size.x / 2, size.y / 2)
	var player_pos = player.global_position

	# First try the saved road point chains from maploader.gd
	if world_node != null:
		var roads = world_node.get("roads")

		if roads != null and roads.size() > 0:

			for road in roads:

				if road == null or road.size() < 2:
					continue

				for i in range(road.size() - 1):

					var p1 = road[i]
					var p2 = road[i + 1]

					var a = Vector2(p1.x - player_pos.x, p1.z - player_pos.z) * map_scale
					var b = Vector2(p2.x - player_pos.x, p2.z - player_pos.z) * map_scale

					draw_line(center + a, center + b, Color.WHITE, 2)

			draw_circle(center, 5, Color.RED)
			return

	# Fallback to BetterRoadGenerator road_quads
	if road_system != null:
		var quads = road_system.get("road_quads")

		if quads != null and quads.size() > 0:
			for quad in quads:

				if !quad.has("a") or !quad.has("b") or !quad.has("c") or !quad.has("d"):
					continue

				var start_mid = (quad["a"] + quad["b"]) * 0.5
				var end_mid = (quad["d"] + quad["c"]) * 0.5

				var a = Vector2(start_mid.x - player_pos.x, start_mid.z - player_pos.z) * map_scale
				var b = Vector2(end_mid.x - player_pos.x, end_mid.z - player_pos.z) * map_scale

				draw_line(center + a, center + b, Color.WHITE, 2)

	draw_circle(center, 5, Color.RED)
