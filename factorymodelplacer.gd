extends Node3D

const SAVE_PATH: String = "user://factory_model_edits.json"

@export var industrial_parent_path: NodePath
@export var spawned_models_parent_path: NodePath

@export var peppermill_wrapper: PackedScene
@export var warehouse1_wrapper: PackedScene
@export var warehouse2_wrapper: PackedScene

@export var peppermill_expected_size: Vector2 = Vector2(36.0, 22.0)
@export var warehouse1_expected_size: Vector2 = Vector2(22.0, 14.0)
@export var warehouse2_expected_size: Vector2 = Vector2(48.0, 28.0)

@export var size_tolerance: float = 4.0
@export var area_tolerance_ratio: float = 0.30
@export var aspect_tolerance: float = 0.35
@export var fill_tolerance: float = 0.30

@export var peppermill_expected_fill: float = 0.78
@export var warehouse1_expected_fill: float = 0.95
@export var warehouse2_expected_fill: float = 0.95

@export var model_y_offset: float = 0.02
@export var auto_spawn_on_ready: bool = true
@export var clear_spawned_models_on_ready: bool = true
@export var hide_source_buildings_when_model_spawned: bool = true

@export var rotate_speed: float = 0.012
@export var scale_step: float = 0.03
@export var min_scale: float = 0.05
@export var max_scale: float = 6.0
@export var move_snap: float = 0.0
@export var selection_pixel_radius: float = 120.0
@export var auto_fit_scale_padding: float = 0.92
@export var move_drag_speed: float = 0.06

@export var random_spawn_distance: float = 18.0

@export var tool_nodes_to_disable: Array[NodePath] = []

var industrial_parent: Node3D
var spawned_models_parent: Node3D
var camera: Camera3D

var model_defs: Array = []
var placed_entries: Array = []
var saved_edits: Dictionary = {}
var random_spawn_counter: int = 0

var factory_edit_mode: bool = false
var selected_index: int = -1
var drag_mode: String = ""

var ui_layer: CanvasLayer
var ui_panel: Panel
var ui_label: Label

var selection_box: MeshInstance3D


func _ready() -> void:
	randomize()

	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)

	industrial_parent = get_node_or_null(industrial_parent_path) as Node3D
	spawned_models_parent = get_node_or_null(spawned_models_parent_path) as Node3D

	if spawned_models_parent == null:
		spawned_models_parent = Node3D.new()
		spawned_models_parent.name = "SpawnedFactoryModels"
		add_child(spawned_models_parent)

	camera = get_viewport().get_camera_3d()

	_build_model_defs()
	_create_ui()
	_create_selection_box()
	_load_saved_edits()
	_rebuild_random_spawn_counter_from_save()

	if clear_spawned_models_on_ready:
		for child in spawned_models_parent.get_children():
			child.queue_free()

	if auto_spawn_on_ready:
		call_deferred("_spawn_all_models")


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	_update_ui()
	_update_selection_box()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_toggle_factory_edit_mode()
			get_viewport().set_input_as_handled()
			return

	if not factory_edit_mode:
		return

	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_from_mouse(event.position)

			if selected_index != -1:
				if Input.is_key_pressed(KEY_R):
					drag_mode = "rotate"
				elif Input.is_key_pressed(KEY_M):
					drag_mode = "move"

		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if drag_mode != "":
				_save_all_edits()
			drag_mode = ""

	if event is InputEventMouseMotion:
		if drag_mode == "rotate":
			_rotate_selected(event.relative.x)
		elif drag_mode == "move":
			_move_selected_by_mouse_delta(event.relative)

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_cycle_selected_model()
			KEY_BRACKETRIGHT:
				_scale_selected(scale_step)
			KEY_BRACKETLEFT:
				_scale_selected(-scale_step)
			KEY_L:
				_spawn_random_model_in_front()
			KEY_K:
				_delete_selected_model()


func _unhandled_input(_event: InputEvent) -> void:
	if factory_edit_mode:
		get_viewport().set_input_as_handled()


func _build_model_defs() -> void:
	model_defs.clear()

	model_defs.append({
		"name": "peppermill",
		"scene": peppermill_wrapper,
		"size": peppermill_expected_size,
		"fill": peppermill_expected_fill
	})

	model_defs.append({
		"name": "warehouse1",
		"scene": warehouse1_wrapper,
		"size": warehouse1_expected_size,
		"fill": warehouse1_expected_fill
	})

	model_defs.append({
		"name": "warehouse2",
		"scene": warehouse2_wrapper,
		"size": warehouse2_expected_size,
		"fill": warehouse2_expected_fill
	})


func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	ui_panel = Panel.new()
	ui_panel.position = Vector2(16, 16)
	ui_panel.size = Vector2(640, 320)
	ui_layer.add_child(ui_panel)

	ui_label = Label.new()
	ui_label.position = Vector2(12, 10)
	ui_label.size = Vector2(616, 296)
	ui_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_panel.add_child(ui_label)

	ui_panel.visible = false


func _create_selection_box() -> void:
	selection_box = MeshInstance3D.new()

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	selection_box.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.1, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	selection_box.material_override = mat
	selection_box.visible = false

	add_child(selection_box)


func _spawn_all_models() -> void:
	placed_entries.clear()

	if industrial_parent == null:
		push_warning("FactoryModelPlacer: industrial_parent_path is not set correctly.")
		return

	for child in industrial_parent.get_children():
		var root: Node3D = child as Node3D
		if root == null:
			continue

		if not root.name.begins_with("Industrial_"):
			continue

		var building_id: String = str(root.get_meta("building_id", ""))
		if building_id == "":
			continue

		var shape_info: Dictionary = _analyze_industrial_root(root)
		if shape_info.is_empty():
			continue

		var compatible: Array = _get_compatible_model_indices(shape_info)
		if compatible.is_empty():
			continue

		var chosen_index: int = int(compatible[0])

		if saved_edits.has(building_id):
			var saved: Variant = saved_edits[building_id]
			if saved is Dictionary:
				var saved_dict: Dictionary = saved
				if bool(saved_dict.get("hidden", false)):
					continue

				var saved_name: String = str(saved_dict.get("model_name", ""))
				var saved_idx: int = _get_model_index_by_name(saved_name)
				if saved_idx != -1 and compatible.has(saved_idx):
					chosen_index = saved_idx

		var placed: Dictionary = _spawn_model_for_building(root, building_id, shape_info, compatible, chosen_index)
		if placed.is_empty():
			continue

		placed_entries.append(placed)

	_spawn_saved_random_models()


func _spawn_model_for_building(root: Node3D, building_id: String, shape_info: Dictionary, compatible: Array, chosen_index: int) -> Dictionary:
	if chosen_index < 0 or chosen_index >= model_defs.size():
		return {}

	var def: Dictionary = model_defs[chosen_index]
	var scene: PackedScene = def.get("scene", null) as PackedScene
	if scene == null:
		return {}

	var instance: Node = scene.instantiate()
	var model_root: Node3D = instance as Node3D
	if model_root == null:
		if instance != null:
			instance.queue_free()
		return {}

	spawned_models_parent.add_child(model_root)

	var centre: Vector3 = shape_info.get("center_3d", Vector3.ZERO)
	var angle: float = float(shape_info.get("angle", 0.0))
	var target_size: Vector2 = shape_info.get("size", Vector2.ZERO)

	model_root.global_position = centre
	model_root.rotation.y = angle

	var auto_scale: float = _get_auto_fit_scale(model_root, target_size)
	model_root.scale = Vector3.ONE * auto_scale

	_snap_model_to_ground(model_root)
	model_root.global_position.y += model_y_offset

	if saved_edits.has(building_id):
		var saved: Variant = saved_edits[building_id]
		if saved is Dictionary:
			var saved_dict: Dictionary = saved

			if saved_dict.has("position"):
				var p: Variant = saved_dict["position"]
				if p is Array and p.size() == 3:
					model_root.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))

			if saved_dict.has("rotation_y"):
				model_root.rotation.y = float(saved_dict["rotation_y"])

			if saved_dict.has("scale"):
				var s: float = float(saved_dict["scale"])
				model_root.scale = Vector3.ONE * clampf(s, min_scale, max_scale)

			_snap_model_to_ground(model_root)
			model_root.global_position.y += model_y_offset

	model_root.set_meta("building_id", building_id)
	model_root.set_meta("model_name", str(def.get("name", "")))
	model_root.set_meta("shape_size_x", float(target_size.x))
	model_root.set_meta("shape_size_z", float(target_size.y))
	model_root.set_meta("is_random_spawn", false)

	var entry: Dictionary = {
		"building_id": building_id,
		"building_root": root,
		"instance": model_root,
		"shape_info": shape_info,
		"compatible": compatible
	}

	_update_linked_building_visibility(entry)

	return entry


func _spawn_saved_random_models() -> void:
	for building_id in saved_edits.keys():
		var id_str: String = str(building_id)
		var saved: Variant = saved_edits[id_str]

		if not (saved is Dictionary):
			continue

		var saved_dict: Dictionary = saved

		if not bool(saved_dict.get("is_random_spawn", false)):
			continue

		var model_name: String = str(saved_dict.get("model_name", ""))
		var model_index: int = _get_model_index_by_name(model_name)
		if model_index == -1:
			continue

		var def: Dictionary = model_defs[model_index]
		var scene: PackedScene = def.get("scene", null) as PackedScene
		if scene == null:
			continue

		var instance: Node = scene.instantiate()
		var model_root: Node3D = instance as Node3D
		if model_root == null:
			if instance != null:
				instance.queue_free()
			continue

		spawned_models_parent.add_child(model_root)

		model_root.set_meta("building_id", id_str)
		model_root.set_meta("model_name", model_name)
		model_root.set_meta("is_random_spawn", true)

		model_root.global_position = Vector3.ZERO
		model_root.rotation = Vector3.ZERO
		model_root.scale = Vector3.ONE

		if saved_dict.has("position"):
			var p: Variant = saved_dict["position"]
			if p is Array and p.size() == 3:
				model_root.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))

		if saved_dict.has("rotation_y"):
			model_root.rotation.y = float(saved_dict["rotation_y"])

		if saved_dict.has("scale"):
			var s: float = float(saved_dict["scale"])
			model_root.scale = Vector3.ONE * clampf(s, min_scale, max_scale)

		_snap_model_to_ground(model_root)
		model_root.global_position.y += model_y_offset

		var entry: Dictionary = {
			"building_id": id_str,
			"building_root": null,
			"instance": model_root,
			"shape_info": {},
			"compatible": _get_available_model_indices()
		}

		placed_entries.append(entry)


func _spawn_random_model_in_front() -> void:
	if camera == null:
		return

	var available_indices: Array = _get_available_model_indices()
	if available_indices.is_empty():
		return

	var chosen_index: int = int(available_indices[randi() % available_indices.size()])
	var def: Dictionary = model_defs[chosen_index]
	var scene: PackedScene = def.get("scene", null) as PackedScene
	if scene == null:
		return

	var instance: Node = scene.instantiate()
	var model_root: Node3D = instance as Node3D
	if model_root == null:
		if instance != null:
			instance.queue_free()
		return

	spawned_models_parent.add_child(model_root)

	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var spawn_pos: Vector3 = camera.global_position + forward * random_spawn_distance
	spawn_pos.y = 0.0

	model_root.global_position = spawn_pos
	model_root.rotation.y = atan2(forward.x, forward.z)
	model_root.scale = Vector3.ONE

	_snap_model_to_ground(model_root)
	model_root.global_position.y += model_y_offset

	random_spawn_counter += 1
	var random_id: String = "random_%d" % random_spawn_counter

	model_root.set_meta("building_id", random_id)
	model_root.set_meta("model_name", str(def.get("name", "")))
	model_root.set_meta("is_random_spawn", true)

	var entry: Dictionary = {
		"building_id": random_id,
		"building_root": null,
		"instance": model_root,
		"shape_info": {},
		"compatible": available_indices.duplicate()
	}

	placed_entries.append(entry)
	selected_index = placed_entries.size() - 1

	_save_all_edits()


func _delete_selected_model() -> void:
	if selected_index < 0 or selected_index >= placed_entries.size():
		return

	var entry: Dictionary = placed_entries[selected_index]
	var inst: Node3D = entry.get("instance", null) as Node3D
	var building_root: Node3D = entry.get("building_root", null) as Node3D
	var building_id: String = str(entry.get("building_id", ""))

	if inst != null and is_instance_valid(inst):
		inst.queue_free()

	if building_root != null and is_instance_valid(building_root):
		building_root.visible = true

	if saved_edits.has(building_id):
		saved_edits.erase(building_id)

	placed_entries.remove_at(selected_index)
	selected_index = -1
	selection_box.visible = false

	_save_all_edits()


func _get_available_model_indices() -> Array:
	var out: Array = []

	for i in range(model_defs.size()):
		var def: Dictionary = model_defs[i]
		var scene: PackedScene = def.get("scene", null) as PackedScene
		if scene != null:
			out.append(i)

	return out


func _rebuild_random_spawn_counter_from_save() -> void:
	random_spawn_counter = 0

	for key in saved_edits.keys():
		var id_str: String = str(key)
		if not id_str.begins_with("random_"):
			continue

		var suffix := id_str.trim_prefix("random_")
		if suffix.is_valid_int():
			random_spawn_counter = max(random_spawn_counter, int(suffix))


func _analyze_industrial_root(root: Node3D) -> Dictionary:
	var roof: MeshInstance3D = root.get_node_or_null("Roof") as MeshInstance3D
	if roof == null:
		return _analyze_from_merged_mesh_aabb(root)

	var roof_mesh: Mesh = roof.mesh
	if roof_mesh == null or roof_mesh.get_surface_count() == 0:
		return _analyze_from_merged_mesh_aabb(root)

	var roof_points: PackedVector2Array = _extract_unique_roof_points_2d(roof_mesh)
	if roof_points.size() < 3:
		return _analyze_from_merged_mesh_aabb(root)

	var hull: PackedVector2Array = Geometry2D.convex_hull(roof_points)
	if hull.size() < 3:
		return _analyze_from_merged_mesh_aabb(root)

	var center_2d: Vector2 = _average_points_2d(hull)
	var angle: float = _get_principal_axis_angle(hull, center_2d)
	var obb: Dictionary = _get_oriented_bounds(hull, center_2d, angle)

	var size: Vector2 = obb.get("size", Vector2.ZERO)
	var hull_area: float = absf(_polygon_area(hull))
	var bbox_area: float = maxf(size.x * size.y, 0.001)
	var fill_ratio: float = hull_area / bbox_area

	var height: float = float(root.get_meta("building_height", 0.0))
	var center_3d: Vector3 = Vector3(center_2d.x, height * 0.5, center_2d.y)

	return {
		"center_3d": center_3d,
		"center_2d": center_2d,
		"angle": angle,
		"size": size,
		"fill_ratio": fill_ratio,
		"hull_area": hull_area,
		"bbox_area": bbox_area
	}


func _analyze_from_merged_mesh_aabb(root: Node3D) -> Dictionary:
	var aabb: AABB = _get_combined_mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return {}

	var size: Vector2 = Vector2(absf(aabb.size.x), absf(aabb.size.z))
	var center: Vector3 = aabb.position + aabb.size * 0.5

	return {
		"center_3d": center,
		"center_2d": Vector2(center.x, center.z),
		"angle": 0.0,
		"size": size,
		"fill_ratio": 1.0,
		"hull_area": size.x * size.y,
		"bbox_area": size.x * size.y
	}


func _extract_unique_roof_points_2d(mesh: Mesh) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()

	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return out

	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if verts == null:
		return out

	for v in verts:
		if v is Vector3:
			var p2: Vector2 = Vector2(v.x, v.z)
			if not _packed_vector2_array_has_near(out, p2, 0.05):
				out.append(p2)

	return out


func _packed_vector2_array_has_near(arr: PackedVector2Array, point: Vector2, tolerance: float) -> bool:
	for p in arr:
		if p.distance_to(point) <= tolerance:
			return true
	return false


func _average_points_2d(points: PackedVector2Array) -> Vector2:
	var c: Vector2 = Vector2.ZERO
	for p in points:
		c += p
	return c / maxf(1.0, float(points.size()))


func _get_principal_axis_angle(points: PackedVector2Array, center: Vector2) -> float:
	if points.size() < 2:
		return 0.0

	var xx: float = 0.0
	var zz: float = 0.0
	var xz: float = 0.0

	for p in points:
		var d: Vector2 = p - center
		xx += d.x * d.x
		zz += d.y * d.y
		xz += d.x * d.y

	if absf(xz) < 0.0001 and absf(xx - zz) < 0.0001:
		return 0.0

	return 0.5 * atan2(2.0 * xz, xx - zz)


func _get_oriented_bounds(points: PackedVector2Array, center: Vector2, angle: float) -> Dictionary:
	var axis_x: Vector2 = Vector2(cos(angle), sin(angle))
	var axis_z: Vector2 = Vector2(-sin(angle), cos(angle))

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for p in points:
		var d: Vector2 = p - center
		var px: float = d.dot(axis_x)
		var pz: float = d.dot(axis_z)

		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
		min_z = minf(min_z, pz)
		max_z = maxf(max_z, pz)

	return {
		"size": Vector2(max_x - min_x, max_z - min_z),
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z
	}


func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0

	var sum: float = 0.0
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y

	return sum * 0.5


func _get_combined_mesh_aabb(root: Node3D) -> AABB:
	var found: bool = false
	var combined: AABB = AABB()

	var stack: Array = [root]

	while stack.size() > 0:
		var node: Variant = stack.pop_back()

		if node is MeshInstance3D and node.mesh != null:
			var local_aabb: AABB = node.mesh.get_aabb()
			var global_aabb: AABB = _transform_aabb(local_aabb, node.global_transform)

			if not found:
				combined = global_aabb
				found = true
			else:
				combined = combined.merge(global_aabb)

		if node is Node3D:
			for child in node.get_children():
				if child is Node3D:
					stack.append(child)

	if found:
		return combined

	return AABB()


func _get_combined_local_aabb(root: Node3D) -> AABB:
	var found: bool = false
	var combined: AABB = AABB()

	for child in root.get_children():
		var child_3d: Node3D = child as Node3D
		if child_3d == null:
			continue

		var child_aabb: AABB = _get_node_local_aabb_recursive(child_3d)
		if child_aabb.size == Vector3.ZERO:
			continue

		var transformed: AABB = _transform_aabb(child_aabb, child_3d.transform)

		if not found:
			combined = transformed
			found = true
		else:
			combined = combined.merge(transformed)

	if found:
		return combined

	return AABB()


func _get_node_local_aabb_recursive(node: Node3D) -> AABB:
	var found: bool = false
	var combined: AABB = AABB()

	if node is MeshInstance3D and node.mesh != null:
		combined = node.mesh.get_aabb()
		found = true

	for child in node.get_children():
		var child_3d: Node3D = child as Node3D
		if child_3d == null:
			continue

		var child_aabb: AABB = _get_node_local_aabb_recursive(child_3d)
		if child_aabb.size == Vector3.ZERO:
			continue

		var transformed: AABB = _transform_aabb(child_aabb, child_3d.transform)

		if not found:
			combined = transformed
			found = true
		else:
			combined = combined.merge(transformed)

	if found:
		return combined

	return AABB()


func _get_auto_fit_scale(model_root: Node3D, target_size: Vector2) -> float:
	if target_size.x <= 0.001 or target_size.y <= 0.001:
		return 1.0

	var local_aabb: AABB = _get_combined_local_aabb(model_root)
	if local_aabb.size == Vector3.ZERO:
		return 1.0

	var model_size_x: float = absf(local_aabb.size.x)
	var model_size_z: float = absf(local_aabb.size.z)

	if model_size_x <= 0.001 or model_size_z <= 0.001:
		return 1.0

	var scale_x: float = target_size.x / model_size_x
	var scale_z: float = target_size.y / model_size_z

	var fit_scale: float = minf(scale_x, scale_z) * auto_fit_scale_padding
	fit_scale = maxf(fit_scale, 0.01)
	fit_scale = minf(fit_scale, max_scale)

	return fit_scale


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]

	var min_v: Vector3 = xform * corners[0]
	var max_v: Vector3 = min_v

	for i in range(1, corners.size()):
		var p: Vector3 = xform * corners[i]
		min_v = min_v.min(p)
		max_v = max_v.max(p)

	return AABB(min_v, max_v - min_v)


func _get_compatible_model_indices(shape_info: Dictionary) -> Array:
	var matches: Array = []

	var actual_size: Vector2 = shape_info.get("size", Vector2.ZERO)
	var actual_fill: float = float(shape_info.get("fill_ratio", 1.0))

	for i in range(model_defs.size()):
		var def: Dictionary = model_defs[i]
		var expected_size: Vector2 = def.get("size", Vector2.ZERO)
		var expected_fill: float = float(def.get("fill", 1.0))

		var score: float = _get_match_score(actual_size, actual_fill, expected_size, expected_fill)
		if score >= 0.0:
			matches.append({
				"index": i,
				"score": score
			})

	matches.sort_custom(_sort_matches)

	var out: Array = []
	for m in matches:
		if m is Dictionary:
			out.append(int(m.get("index", -1)))

	return out


func _sort_matches(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		return float(a.get("score", INF)) < float(b.get("score", INF))
	return false


func _get_match_score(actual_size: Vector2, actual_fill: float, expected_size: Vector2, expected_fill: float) -> float:
	var actual_sorted: Vector2 = _sort_vec2(actual_size)
	var expected_sorted: Vector2 = _sort_vec2(expected_size)

	var dx: float = absf(actual_sorted.x - expected_sorted.x)
	var dz: float = absf(actual_sorted.y - expected_sorted.y)

	if dx > size_tolerance or dz > size_tolerance:
		return -1.0

	var actual_area: float = maxf(actual_sorted.x * actual_sorted.y, 0.001)
	var expected_area: float = maxf(expected_sorted.x * expected_sorted.y, 0.001)
	var area_ratio_diff: float = absf(actual_area - expected_area) / expected_area

	if area_ratio_diff > area_tolerance_ratio:
		return -1.0

	var actual_aspect: float = actual_sorted.y / maxf(actual_sorted.x, 0.001)
	var expected_aspect: float = expected_sorted.y / maxf(expected_sorted.x, 0.001)
	var aspect_diff: float = absf(actual_aspect - expected_aspect)

	if aspect_diff > aspect_tolerance:
		return -1.0

	var fill_diff: float = absf(actual_fill - expected_fill)
	if fill_diff > fill_tolerance:
		return -1.0

	return dx + dz + (area_ratio_diff * 15.0) + (aspect_diff * 10.0) + (fill_diff * 8.0)


func _sort_vec2(v: Vector2) -> Vector2:
	if v.x <= v.y:
		return v
	return Vector2(v.y, v.x)


func _get_model_index_by_name(name: String) -> int:
	for i in range(model_defs.size()):
		var def: Dictionary = model_defs[i]
		if str(def.get("name", "")) == name:
			return i
	return -1


func _toggle_factory_edit_mode() -> void:
	factory_edit_mode = not factory_edit_mode
	drag_mode = ""

	ui_panel.visible = factory_edit_mode
	_set_other_tools_enabled(not factory_edit_mode)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not factory_edit_mode:
		selected_index = -1
		selection_box.visible = false


func _set_other_tools_enabled(enabled: bool) -> void:
	for path in tool_nodes_to_disable:
		var node: Node = get_node_or_null(path)
		if node == null:
			continue

		node.set_process_input(enabled)
		node.set_process_unhandled_input(enabled)
		node.set_process(enabled)

		if node is Node3D:
			node.set_physics_process(enabled)


func _update_ui() -> void:
	if ui_label == null or not factory_edit_mode:
		return

	var selected_name: String = "None"
	var selected_scale: String = "-"
	var selected_rot: String = "-"
	var selected_pos: String = "-"
	var selected_building: String = "-"

	if selected_index >= 0 and selected_index < placed_entries.size():
		var entry: Dictionary = placed_entries[selected_index]
		var inst: Node3D = entry.get("instance", null) as Node3D

		if inst != null and is_instance_valid(inst):
			selected_name = str(inst.get_meta("model_name", "Unknown"))
			selected_scale = str(round(inst.scale.x * 100.0) / 100.0)
			selected_rot = str(round(rad_to_deg(inst.rotation.y) * 10.0) / 10.0) + "°"
			selected_pos = "(%.2f, %.2f, %.2f)" % [inst.global_position.x, inst.global_position.y, inst.global_position.z]
			selected_building = str(entry.get("building_id", "-"))

	ui_label.text = (
		"FACTORY EDIT MODE\n\n" +
		"P = exit factory edit mode\n" +
		"Left Click = select model nearest screen centre\n" +
		"Hold R + drag = rotate model\n" +
		"Hold M + drag = move model on ground\n" +
		"C = cycle through matching models\n" +
		"L = spawn random model\n" +
		"K = delete selected model\n" +
		"] = scale up slightly\n" +
		"[ = scale down slightly\n\n" +
		"Selected building ID: " + selected_building + "\n" +
		"Selected model: " + selected_name + "\n" +
		"Scale: " + selected_scale + "    Rotation: " + selected_rot + "\n" +
		"Position: " + selected_pos
	)


func _select_from_mouse(_mouse_pos: Vector2) -> void:
	if camera == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var best_index: int = -1
	var best_dist: float = selection_pixel_radius

	for i in range(placed_entries.size()):
		var entry: Dictionary = placed_entries[i]
		var inst: Node3D = entry.get("instance", null) as Node3D

		if inst == null or not is_instance_valid(inst):
			continue

		var aabb: AABB = _get_combined_mesh_aabb(inst)
		if aabb.size == Vector3.ZERO:
			continue

		var world_center: Vector3 = aabb.position + aabb.size * 0.5

		if camera.is_position_behind(world_center):
			continue

		var screen_pos: Vector2 = camera.unproject_position(world_center)
		var dist: float = screen_pos.distance_to(screen_center)

		if dist < best_dist:
			best_dist = dist
			best_index = i

	selected_index = best_index


func _update_selection_box() -> void:
	if not factory_edit_mode:
		selection_box.visible = false
		return

	if selected_index < 0 or selected_index >= placed_entries.size():
		selection_box.visible = false
		return

	var entry: Dictionary = placed_entries[selected_index]
	var inst: Node3D = entry.get("instance", null) as Node3D

	if inst == null or not is_instance_valid(inst):
		selection_box.visible = false
		return

	var aabb: AABB = _get_combined_mesh_aabb(inst)
	if aabb.size == Vector3.ZERO:
		selection_box.visible = false
		return

	selection_box.visible = true
	selection_box.global_position = aabb.position + aabb.size * 0.5
	selection_box.scale = aabb.size
	selection_box.rotation = Vector3.ZERO


func _rotate_selected(mouse_delta_x: float) -> void:
	if selected_index < 0 or selected_index >= placed_entries.size():
		return

	var entry: Dictionary = placed_entries[selected_index]
	var inst: Node3D = entry.get("instance", null) as Node3D
	if inst == null or not is_instance_valid(inst):
		return

	inst.rotate_y(-mouse_delta_x * rotate_speed)

	_snap_model_to_ground(inst)
	inst.global_position.y += model_y_offset


func _move_selected_by_mouse_delta(relative: Vector2) -> void:
	if selected_index < 0 or selected_index >= placed_entries.size():
		return

	var entry: Dictionary = placed_entries[selected_index]
	var inst: Node3D = entry.get("instance", null) as Node3D
	if inst == null or not is_instance_valid(inst):
		return

	if camera == null:
		return

	var cam_basis: Basis = camera.global_transform.basis

	var right: Vector3 = cam_basis.x
	right.y = 0.0
	if right.length() <= 0.0001:
		return
	right = right.normalized()

	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	if forward.length() <= 0.0001:
		return
	forward = forward.normalized()

	var move: Vector3 = (right * relative.x + forward * -relative.y) * move_drag_speed
	inst.global_position += move

	if move_snap > 0.0:
		inst.global_position.x = snappedf(inst.global_position.x, move_snap)
		inst.global_position.z = snappedf(inst.global_position.z, move_snap)

	_snap_model_to_ground(inst)
	inst.global_position.y += model_y_offset

	_update_linked_building_visibility(entry)


func _scale_selected(amount: float) -> void:
	if selected_index < 0 or selected_index >= placed_entries.size():
		return

	var entry: Dictionary = placed_entries[selected_index]
	var inst: Node3D = entry.get("instance", null) as Node3D
	if inst == null or not is_instance_valid(inst):
		return

	var s: float = clampf(inst.scale.x + amount, min_scale, max_scale)
	inst.scale = Vector3.ONE * s

	_snap_model_to_ground(inst)
	inst.global_position.y += model_y_offset

	_update_linked_building_visibility(entry)

	_save_all_edits()


func _cycle_selected_model() -> void:
	if selected_index < 0 or selected_index >= placed_entries.size():
		return

	var entry: Dictionary = placed_entries[selected_index]
	var compatible: Array = entry.get("compatible", [])
	if compatible.is_empty():
		return

	var old_inst: Node3D = entry.get("instance", null) as Node3D
	if old_inst == null or not is_instance_valid(old_inst):
		return

	var current_name: String = str(old_inst.get_meta("model_name", ""))
	var current_idx: int = _get_model_index_by_name(current_name)

	var current_compatible_pos: int = compatible.find(current_idx)
	if current_compatible_pos == -1:
		current_compatible_pos = 0

	var next_pos: int = (current_compatible_pos + 1) % compatible.size()
	var next_index: int = int(compatible[next_pos])

	var def: Dictionary = model_defs[next_index]
	var scene: PackedScene = def.get("scene", null) as PackedScene
	if scene == null:
		return

	var new_inst_node: Node = scene.instantiate()
	var new_root: Node3D = new_inst_node as Node3D
	if new_root == null:
		if new_inst_node != null:
			new_inst_node.queue_free()
		return

	var old_pos: Vector3 = old_inst.global_position
	var old_rot: Vector3 = old_inst.rotation
	var old_scale: Vector3 = old_inst.scale
	var building_id: String = str(entry.get("building_id", ""))
	var is_random_spawn: bool = bool(old_inst.get_meta("is_random_spawn", false))

	old_inst.queue_free()

	spawned_models_parent.add_child(new_root)

	new_root.global_position = old_pos
	new_root.rotation = old_rot
	new_root.scale = old_scale
	new_root.set_meta("building_id", building_id)
	new_root.set_meta("model_name", str(def.get("name", "")))
	new_root.set_meta("is_random_spawn", is_random_spawn)

	_snap_model_to_ground(new_root)
	new_root.global_position.y += model_y_offset

	entry["instance"] = new_root
	placed_entries[selected_index] = entry
	_update_linked_building_visibility(entry)

	_save_all_edits()


func _snap_model_to_ground(model_root: Node3D) -> void:
	var aabb: AABB = _get_combined_mesh_aabb(model_root)
	if aabb.size == Vector3.ZERO:
		return

	var bottom_y: float = aabb.position.y
	model_root.global_position.y -= bottom_y


func _model_overlaps_building(model_root: Node3D, building_root: Node3D) -> bool:
	var model_aabb: AABB = _get_combined_mesh_aabb(model_root)
	var building_aabb: AABB = _get_combined_mesh_aabb(building_root)

	if model_aabb.size == Vector3.ZERO or building_aabb.size == Vector3.ZERO:
		return false

	var padding: float = 0.5

	var model_min_x: float = model_aabb.position.x - padding
	var model_max_x: float = model_aabb.position.x + model_aabb.size.x + padding
	var model_min_z: float = model_aabb.position.z - padding
	var model_max_z: float = model_aabb.position.z + model_aabb.size.z + padding

	var building_min_x: float = building_aabb.position.x
	var building_max_x: float = building_aabb.position.x + building_aabb.size.x
	var building_min_z: float = building_aabb.position.z
	var building_max_z: float = building_aabb.position.z + building_aabb.size.z

	var overlap_x: bool = model_max_x >= building_min_x and model_min_x <= building_max_x
	var overlap_z: bool = model_max_z >= building_min_z and model_min_z <= building_max_z

	return overlap_x and overlap_z


func _update_linked_building_visibility(entry: Dictionary) -> void:
	var inst: Node3D = entry.get("instance", null) as Node3D
	var building_root: Node3D = entry.get("building_root", null) as Node3D

	if building_root == null or not is_instance_valid(building_root):
		return

	if inst == null or not is_instance_valid(inst):
		building_root.visible = true
		return

	if hide_source_buildings_when_model_spawned:
		building_root.visible = not _model_overlaps_building(inst, building_root)
	else:
		building_root.visible = true


func _load_saved_edits() -> void:
	saved_edits.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if data is Dictionary and data.has("models") and data["models"] is Dictionary:
		saved_edits = data["models"]


func _save_all_edits() -> void:
	var out: Dictionary = {
		"models": {}
	}

	for entry_var in placed_entries:
		if not (entry_var is Dictionary):
			continue

		var entry: Dictionary = entry_var
		var inst: Node3D = entry.get("instance", null) as Node3D
		if inst == null or not is_instance_valid(inst):
			continue

		var building_id: String = str(entry.get("building_id", ""))
		out["models"][building_id] = {
			"model_name": str(inst.get_meta("model_name", "")),
			"position": [inst.global_position.x, inst.global_position.y, inst.global_position.z],
			"rotation_y": inst.rotation.y,
			"scale": inst.scale.x,
			"is_random_spawn": bool(inst.get_meta("is_random_spawn", false))
		}

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("FactoryModelPlacer: could not save factory edits.")
		return

	file.store_string(JSON.stringify(out))
	file.close()

	saved_edits = out["models"]


func respawn_all() -> void:
	for child in spawned_models_parent.get_children():
		child.queue_free()

	if industrial_parent != null and is_instance_valid(industrial_parent):
		for child in industrial_parent.get_children():
			var root: Node3D = child as Node3D
			if root != null:
				root.visible = true

	placed_entries.clear()
	call_deferred("_spawn_all_models")


func clear_saved_factory_edits() -> void:
	saved_edits.clear()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	respawn_all()
