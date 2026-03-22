extends Node3D

@export var player: Node3D
@export var render_distance := 220.0
@export var disable_collision_distance := 150.0

func _process(delta):

	if player == null:
		return

	var player_pos = player.global_position

	for obj in get_tree().get_nodes_in_group("distance_objects"):

		var dist = obj.global_position.distance_to(player_pos)

		# Hide far objects
		obj.visible = dist < render_distance

		# Optional physics optimisation
		if obj.has_node("CollisionShape3D"):

			var col = obj.get_node("CollisionShape3D")
			col.disabled = dist > disable_collision_distance
