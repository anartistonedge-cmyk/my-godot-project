extends Node

const SAVE_PATH = "user://trees.json"


func save_trees(tree_container):

	var data = []

	for tree in tree_container.get_children():

		var tree_type = "oak"
		var tree_scale = 1.0
		var tree_rotation = tree.rotation.y

		if tree.has_meta("tree_type"):
			tree_type = str(tree.get_meta("tree_type"))

		if tree.has_meta("tree_scale"):
			tree_scale = float(tree.get_meta("tree_scale"))

		if tree.has_meta("tree_rotation"):
			tree_rotation = float(tree.get_meta("tree_rotation"))

		data.append({
			"x": tree.position.x,
			"z": tree.position.z,
			"type": tree_type,
			"scale": tree_scale,
			"rotation": tree_rotation
		})

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	print("Trees saved:", data.size())


func load_trees(tree_container, tree_generator):

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	for tree in data:

		tree_generator.create_tree(
			tree_container,
			tree["x"],
			tree["z"],
			tree
		)

	print("Trees loaded:", data.size())
