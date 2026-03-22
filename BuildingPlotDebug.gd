extends Node3D

@export var plot_height := 0.05
@export var chunk_size := 200.0

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame
	create_chunk_plots()

func create_chunk_plots():
	var chunks = get_node("Chunks")

	for chunk in chunks.get_children():

		var mesh := PlaneMesh.new()
		mesh.size = Vector2(chunk_size, chunk_size)

		var mi := MeshInstance3D.new()
		mi.mesh = mesh

		mi.rotation_degrees.x = -90

		mi.global_position = chunk.global_position
		mi.global_position.y = plot_height

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45,0.45,0.45)

		mi.material_override = mat

		add_child(mi)
