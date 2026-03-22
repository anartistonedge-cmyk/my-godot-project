extends Node

func load_map(path):

	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	var data = JSON.parse_string(text)

	var nodes = {}
	var node_use_count = {}

	for el in data["elements"]:
		if el["type"] == "node":
			nodes[el["id"]] = el

	for el in data["elements"]:

		if el["type"] != "way":
			continue

		if not el.has("tags"):
			continue

		if not el["tags"].has("highway"):
			continue

		for n in el["nodes"]:

			if not node_use_count.has(n):
				node_use_count[n] = 0

			node_use_count[n] += 1

	return {
		"elements": data["elements"],
		"nodes": nodes,
		"node_use_count": node_use_count
	}
