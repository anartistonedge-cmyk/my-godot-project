extends Node3D

@export var plot_expand := 2.5

func _ready():

	print("Generating plots from buildings...")

	var meshes = get_tree().get_nodes_in_group("distance_objects")

	for m in meshes:

		if m is MeshInstance3D:
			create_plot(m)



func create_plot(building:MeshInstance3D):

	if building.mesh == null:
		return

	var aabb = building.mesh.get_aabb()

	var size = aabb.size
	var pos = building.global_transform.origin

	size.x += plot_expand * 2
	size.z += plot_expand * 2

	var mesh = PlaneMesh.new()
	mesh.size = Vector2(size.x, size.z)

	var mi = MeshInstance3D.new()
	mi.mesh = mesh

	mi.position = Vector3(
		pos.x,
		0.05,
		pos.z
	)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4,0.4,0.4)

	mi.material_override = mat

	add_child(mi)
