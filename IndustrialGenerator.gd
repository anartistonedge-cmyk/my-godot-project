extends Node

var roof_generator

func _ready():
	roof_generator = preload("res://RoofGenerator.gd").new()


func create_industrial(st, points, height):

	for i in range(points.size()):

		var next = (i + 1) % points.size()

		var p1 = points[i]
		var p2 = points[next]

		var b1 = p1
		var b2 = p2
		var t1 = p1 + Vector3.UP * height
		var t2 = p2 + Vector3.UP * height

		st.add_vertex(b1)
		st.add_vertex(b2)
		st.add_vertex(t2)

		st.add_vertex(b1)
		st.add_vertex(t2)
		st.add_vertex(t1)

	roof_generator.create_flat_roof(st, points, height)
