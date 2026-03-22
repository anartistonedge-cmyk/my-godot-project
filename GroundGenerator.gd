extends Node3D

var ground_mesh : MeshInstance3D
var ground_collision : CollisionShape3D
var ground_visible := true


func _ready():

	var body = StaticBody3D.new()

	var mesh = PlaneMesh.new()
	mesh.size = Vector2(4000,4000)

	ground_mesh = MeshInstance3D.new()
	ground_mesh.mesh = mesh

	# LOWER THE GROUND SURFACE
	ground_mesh.position.y = -0.5

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.133, 0.286, 0.039, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	ground_mesh.material_override = mat

	ground_collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(4000,1,4000)

	ground_collision.shape = shape
	ground_collision.position.y = -0.5

	body.add_child(ground_mesh)
	body.add_child(ground_collision)

	add_child(body)


func _input(event):

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_DOWN:

			ground_visible = !ground_visible

			ground_mesh.visible = ground_visible
			ground_collision.disabled = !ground_visible
