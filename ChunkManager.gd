extends Node3D

@export var player : Node3D

const CHUNK_SIZE = 200.0
const VIEW_DISTANCE = 2   # chunks

var chunks = {}

func get_chunk_coords(pos: Vector3) -> Vector2i:
	var x = floor(pos.x / CHUNK_SIZE)
	var z = floor(pos.z / CHUNK_SIZE)
	return Vector2i(x, z)


func register_object(obj):
	var chunk = get_chunk_coords(obj.global_position)

	if !chunks.has(chunk):
		chunks[chunk] = []

	chunks[chunk].append(obj)


func _process(delta):
	if player == null:
		return

	var player_chunk = get_chunk_coords(player.global_position)

	for c in chunks.keys():
		var dist = player_chunk.distance_to(c)

		for obj in chunks[c]:
			if obj != null and is_instance_valid(obj):
				obj.visible = dist <= VIEW_DISTANCE
