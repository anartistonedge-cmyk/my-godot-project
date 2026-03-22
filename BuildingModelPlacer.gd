extends Node3D

# -------------------------------------------------
# BUILDING MODEL PLACER
# Godot 4.6.1
#
# Spawns wrapper scenes onto existing generated plots.
# Each generated building root should contain:
# - Foundation
# - FrontMarker
#
# Each wrapper scene should contain:
# - Node3D root
# - model
# - FrontMarker
# -------------------------------------------------

@export var foundations_parent_path : NodePath
@export var spawned_models_parent_path : NodePath

# Wrapper scenes - drag these in through the Inspector
@export var newhouse_wrapper : PackedScene
@export var terrace_wrapper : PackedScene
@export var housev1_wrapper : PackedScene
@export var housev2_wrapper : PackedScene
@export var housev3_wrapper : PackedScene
@export var housev4_wrapper : PackedScene
@export var bung1_wrapper : PackedScene
@export var bung2_wrapper : PackedScene
@export var bung3_wrapper : PackedScene
@export var garage_wrapper : PackedScene

@export var model_y_offset := 0.08
@export var model_scale := 0.5
@export var clear_before_rebuild := true
@export var auto_rebuild_on_ready := true
@export var startup_delay_seconds := 1.0

# Overlap avoidance
@export var avoid_overlaps := true
@export var overlap_padding := 1.0
@export var lateral_nudge_step := 1.0
@export var lateral_nudge_attempts := 8

# Try different models if overlap happens
@export var try_alternative_models_on_overlap := true

# Terrace grouping
@export var terrace_base_weight := 1
@export var terrace_group_bonus_weight := 4
@export var terrace_neighbor_distance := 14.0
@export var terrace_row_depth_tolerance := 4.0
@export var terrace_max_in_row := 4

# Garage preference
@export var prefer_garage_on_small_foundations := true
@export var garage_small_foundation_max_width := 7.0
@export var garage_small_foundation_max_depth := 10.0
@export var garage_small_foundation_max_area := 55.0
@export var garage_small_plot_weight := 3

const META_BUILDING_ID := "building_id"
const META_BUILDING_KIND := "building_kind"
const META_MODEL_PATH := "model_path"
const META_IS_TERRACE := "is_terrace"
const META_IS_FLATS := "is_flats"

const SAVE_PATH := "user://building_model_layout.json"
const DELETED_MODELS_SAVE_PATH := "user://deleted_building_models.json"
const SAVE_VERSION := 4

const DELETE_TOGGLE_KEY := KEY_PERIOD
const DELETE_MOUSE_BUTTON := MOUSE_BUTTON_RIGHT
const DELETE_RAY_DISTANCE := 600.0

var foundations_parent : Node = null
var spawned_models_parent : Node3D = null
var spawned_models := {}

var saved_layout := {}
var deleted_building_ids := {}
var layout_dirty := false

var delete_mode := false
var delete_mode_canvas : CanvasLayer = null
var delete_mode_label : Label = null


func _ready():
	randomize()

	foundations_parent = get_node_or_null(foundations_parent_path)
	spawned_models_parent = get_node_or_null(spawned_models_parent_path)

	if foundations_parent == null:
		push_error("BuildingModelPlacer: foundations_parent_path is not set correctly.")
		return

	if spawned_models_parent == null:
		spawned_models_parent = Node3D.new()
		spawned_models_parent.name = "SpawnedBuildingModels"
		add_child(spawned_models_parent)

	_load_layout_from_disk()
	_load_deleted_buildings()
	_setup_delete_mode_ui()
	_update_delete_mode_ui()
	set_process_unhandled_input(true)

	if auto_rebuild_on_ready:
		call_deferred("_delayed_startup_rebuild")


func _delayed_startup_rebuild():
	if startup_delay_seconds > 0.0:
		await get_tree().create_timer(startup_delay_seconds).timeout

	rebuild_models()


# -------------------------------------------------
# MAIN
# -------------------------------------------------
func rebuild_models():
	if foundations_parent == null:
		push_error("BuildingModelPlacer: No foundations parent found.")
		return

	if clear_before_rebuild:
		clear_spawned_models()

	spawned_models.clear()
	layout_dirty = false

	var foundation_nodes : Array = []
	_collect_foundations(foundations_parent, foundation_nodes)

	print("BuildingModelPlacer: foundations found = ", foundation_nodes.size())

	for foundation in foundation_nodes:
		_spawn_model_for_foundation(foundation)

	if layout_dirty:
		_save_layout_to_disk()


func clear_spawned_models():
	if spawned_models_parent == null:
		return

	for child in spawned_models_parent.get_children():
		child.queue_free()


# -------------------------------------------------
# FOUNDATION SEARCH
# -------------------------------------------------
func _collect_foundations(node: Node, out_array: Array):
	for child in node.get_children():
		if child is MeshInstance3D and child.name == "Foundation":
			out_array.append(child)

		_collect_foundations(child, out_array)


# -------------------------------------------------
# SPAWNING
# -------------------------------------------------
func _spawn_model_for_foundation(foundation: Node):
	if not (foundation is Node3D):
		return

	var foundation_3d := foundation as Node3D
	var building_root := foundation_3d.get_parent()

	if building_root == null or not (building_root is Node3D):
		return

	var building_id := _get_building_id(building_root)

	# Permanently removed model slots should stay empty
	if deleted_building_ids.has(building_id):
		return

	if spawned_models.has(building_id):
		return

	var source_front_marker := _find_source_front_marker(building_root)
	if source_front_marker == null:
		return

	# Try loading saved layout first
	if _spawn_from_saved_layout(building_id):
		return

	var preferred_scene := _choose_scene_for_foundation(foundation_3d)
	if preferred_scene == null:
		return

	var candidate_scenes := _get_candidate_scenes_for_foundation(foundation_3d)
	if candidate_scenes.is_empty():
		return

	var try_order := _build_scene_try_order(preferred_scene, candidate_scenes)

	var chosen_model : Node3D = null
	var chosen_scene : PackedScene = null

	var smallest_model : Node3D = null
	var smallest_scene : PackedScene = null
	var smallest_area := INF

	for scene in try_order:
		var model := _instantiate_and_place_scene(scene, source_front_marker)
		if model == null:
			continue

		_set_wrapper_type_meta(model, scene)

		var footprint_area := _get_model_footprint_area(model)
		if footprint_area < smallest_area:
			if smallest_model != null and smallest_model != model and smallest_model.get_parent() != null:
				smallest_model.queue_free()

			smallest_model = model
			smallest_scene = scene
			smallest_area = footprint_area

		var fits := true

		if try_alternative_models_on_overlap:
			if _model_overlaps_anything(model):
				if avoid_overlaps:
					_resolve_overlap_by_side_shift(model, source_front_marker)

				if _model_overlaps_anything(model):
					fits = false

		elif avoid_overlaps:
			_resolve_overlap_by_side_shift(model, source_front_marker)

		if fits:
			chosen_model = model
			chosen_scene = scene
			break
		else:
			if model != smallest_model and model.get_parent() != null:
				model.queue_free()

	# If chosen model still overlaps, try converting this plot to a garage
	if chosen_model != null and chosen_scene != garage_wrapper and garage_wrapper != null:
		if _model_overlaps_anything(chosen_model):
			if chosen_model.get_parent() != null:
				chosen_model.queue_free()

			chosen_model = null
			chosen_scene = null

			var garage_model := _instantiate_and_place_scene(garage_wrapper, source_front_marker)
			if garage_model != null:
				_set_wrapper_type_meta(garage_model, garage_wrapper)

				if avoid_overlaps:
					_resolve_overlap_by_side_shift(garage_model, source_front_marker)

				if not _model_overlaps_anything(garage_model):
					chosen_model = garage_model
					chosen_scene = garage_wrapper
				else:
					var garage_area := _get_model_footprint_area(garage_model)
					if garage_area < smallest_area:
						if smallest_model != null and smallest_model != garage_model and smallest_model.get_parent() != null:
							smallest_model.queue_free()

						smallest_model = garage_model
						smallest_scene = garage_wrapper
						smallest_area = garage_area
					else:
						if garage_model.get_parent() != null:
							garage_model.queue_free()

	# If nothing fit, fall back to garage once more
	if chosen_model == null and garage_wrapper != null:
		var garage_model_2 := _instantiate_and_place_scene(garage_wrapper, source_front_marker)
		if garage_model_2 != null:
			_set_wrapper_type_meta(garage_model_2, garage_wrapper)

			if avoid_overlaps:
				_resolve_overlap_by_side_shift(garage_model_2, source_front_marker)

			if not _model_overlaps_anything(garage_model_2):
				chosen_model = garage_model_2
				chosen_scene = garage_wrapper
			else:
				var garage_area_2 := _get_model_footprint_area(garage_model_2)
				if garage_area_2 < smallest_area:
					if smallest_model != null and smallest_model != garage_model_2 and smallest_model.get_parent() != null:
						smallest_model.queue_free()

					smallest_model = garage_model_2
					smallest_scene = garage_wrapper
					smallest_area = garage_area_2
				else:
					if garage_model_2.get_parent() != null:
						garage_model_2.queue_free()

	if chosen_model == null:
		if smallest_model == null:
			return

		chosen_model = smallest_model
		chosen_scene = smallest_scene

	if smallest_model != null and smallest_model != chosen_model and smallest_model.get_parent() != null:
		smallest_model.queue_free()

	chosen_model.set_meta(META_BUILDING_ID, building_id)
	_set_wrapper_type_meta(chosen_model, chosen_scene)

	spawned_models[building_id] = chosen_model
	_save_building_to_memory(building_id, chosen_model, chosen_scene)
	layout_dirty = true


func _spawn_from_saved_layout(building_id: String) -> bool:
	if deleted_building_ids.has(building_id):
		return true

	if not saved_layout.has(building_id):
		return false

	var entry = saved_layout[building_id]
	if typeof(entry) != TYPE_DICTIONARY:
		return false

	var scene_key := str(entry.get("scene_key", ""))
	var scene := _get_scene_from_key(scene_key)
	if scene == null:
		return false

	var instance = scene.instantiate()
	if instance == null:
		return false

	if not (instance is Node3D):
		instance.queue_free()
		return false

	var model := instance as Node3D
	spawned_models_parent.add_child(model)

	model.global_position = Vector3(
		float(entry.get("pos_x", 0.0)),
		float(entry.get("pos_y", 0.0)),
		float(entry.get("pos_z", 0.0))
	)

	model.global_rotation = Vector3(
		float(entry.get("rot_x", 0.0)),
		float(entry.get("rot_y", 0.0)),
		float(entry.get("rot_z", 0.0))
	)

	model.scale = Vector3(
		float(entry.get("scale_x", model_scale)),
		float(entry.get("scale_y", model_scale)),
		float(entry.get("scale_z", model_scale))
	)

	model.set_meta(META_BUILDING_ID, building_id)

	var wrapper_type := str(entry.get("wrapper_type", "house"))
	model.set_meta("wrapper_type", wrapper_type)

	spawned_models[building_id] = model
	return true


func _instantiate_and_place_scene(scene: PackedScene, source_front_marker: Node3D) -> Node3D:
	if scene == null:
		return null

	var instance = scene.instantiate()
	if instance == null:
		return null

	if not (instance is Node3D):
		instance.queue_free()
		push_warning("BuildingModelPlacer: spawned scene is not a Node3D.")
		return null

	var model := instance as Node3D
	spawned_models_parent.add_child(model)
	_place_model_using_front_markers(model, source_front_marker)

	return model


func _set_wrapper_type_meta(model: Node3D, scene: PackedScene):
	if scene == terrace_wrapper:
		model.set_meta("wrapper_type", "terrace")
	elif scene == garage_wrapper:
		model.set_meta("wrapper_type", "garage")
	else:
		model.set_meta("wrapper_type", "house")


func _build_scene_try_order(preferred_scene: PackedScene, candidate_scenes: Array[PackedScene]) -> Array[PackedScene]:
	var ordered : Array[PackedScene] = []

	if preferred_scene != null:
		ordered.append(preferred_scene)

	var remaining : Array[PackedScene] = []
	for scene in candidate_scenes:
		if scene == null:
			continue
		if scene == preferred_scene:
			continue
		remaining.append(scene)

	_shuffle_packed_scene_array(remaining)

	for scene in remaining:
		ordered.append(scene)

	return ordered


func _shuffle_packed_scene_array(arr: Array[PackedScene]):
	for i in range(arr.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var temp := arr[i]
		arr[i] = arr[j]
		arr[j] = temp


# -------------------------------------------------
# DELETE MODE
# -------------------------------------------------
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == DELETE_TOGGLE_KEY:
			delete_mode = !delete_mode
			_update_delete_mode_ui()
			print("Building model delete mode: ", delete_mode)
			get_viewport().set_input_as_handled()
			return

	if not delete_mode:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == DELETE_MOUSE_BUTTON:
			_try_delete_building_looked_at()
			get_viewport().set_input_as_handled()


func _try_delete_building_looked_at():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		print("BuildingModelPlacer: no active camera found for delete mode.")
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_center).normalized()

	var best_model: Node3D = null
	var best_distance := INF

	for child in spawned_models_parent.get_children():
		if not (child is Node3D):
			continue

		var model := child as Node3D
		var aabb: AABB = _get_world_aabb_for_node(model)
		if aabb.size == Vector3.ZERO:
			continue

		var hit_distance: float = _ray_intersects_aabb_distance(ray_origin, ray_dir, aabb)
		if hit_distance >= 0.0 and hit_distance <= DELETE_RAY_DISTANCE and hit_distance < best_distance:
			best_distance = hit_distance
			best_model = model

	if best_model == null:
		print("BuildingModelPlacer: delete mode hit nothing.")
		return

	var building_id := str(best_model.get_meta(META_BUILDING_ID, ""))
	if building_id == "":
		print("BuildingModelPlacer: looked-at model has no building id.")
		return

	_delete_building_model(building_id)


func _delete_building_model(building_id: String):
	if spawned_models.has(building_id):
		var model = spawned_models[building_id]
		if is_instance_valid(model):
			model.queue_free()
		spawned_models.erase(building_id)

	deleted_building_ids[building_id] = true

	if saved_layout.has(building_id):
		saved_layout.erase(building_id)

	_save_deleted_buildings()
	_save_layout_to_disk()

	print("BuildingModelPlacer: deleted model for building ", building_id)


func _ray_intersects_aabb_distance(ray_origin: Vector3, ray_dir: Vector3, aabb: AABB) -> float:
	var min_v: Vector3 = aabb.position
	var max_v: Vector3 = aabb.position + aabb.size

	var tmin := -INF
	var tmax := INF

	# X axis
	if absf(ray_dir.x) < 0.00001:
		if ray_origin.x < min_v.x or ray_origin.x > max_v.x:
			return -1.0
	else:
		var tx1: float = (min_v.x - ray_origin.x) / ray_dir.x
		var tx2: float = (max_v.x - ray_origin.x) / ray_dir.x
		tmin = maxf(tmin, minf(tx1, tx2))
		tmax = minf(tmax, maxf(tx1, tx2))

	# Y axis
	if absf(ray_dir.y) < 0.00001:
		if ray_origin.y < min_v.y or ray_origin.y > max_v.y:
			return -1.0
	else:
		var ty1: float = (min_v.y - ray_origin.y) / ray_dir.y
		var ty2: float = (max_v.y - ray_origin.y) / ray_dir.y
		tmin = maxf(tmin, minf(ty1, ty2))
		tmax = minf(tmax, maxf(ty1, ty2))

	# Z axis
	if absf(ray_dir.z) < 0.00001:
		if ray_origin.z < min_v.z or ray_origin.z > max_v.z:
			return -1.0
	else:
		var tz1: float = (min_v.z - ray_origin.z) / ray_dir.z
		var tz2: float = (max_v.z - ray_origin.z) / ray_dir.z
		tmin = maxf(tmin, minf(tz1, tz2))
		tmax = minf(tmax, maxf(tz1, tz2))

	if tmax < 0.0:
		return -1.0

	if tmin > tmax:
		return -1.0

	if tmin >= 0.0:
		return tmin

	return tmax


func _setup_delete_mode_ui():
	delete_mode_canvas = CanvasLayer.new()
	delete_mode_canvas.name = "BuildingDeleteModeUI"
	add_child(delete_mode_canvas)

	delete_mode_label = Label.new()
	delete_mode_label.name = "DeleteModeLabel"
	delete_mode_label.text = ""
	delete_mode_label.visible = false
	delete_mode_label.position = Vector2(18, 18)
	delete_mode_label.size = Vector2(900, 120)
	delete_mode_label.z_index = 100

	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "Sans"])

	theme.set_default_font(font)
	theme.set_font_size("font_size", "Label", 20)
	delete_mode_label.theme = theme

	delete_mode_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
	delete_mode_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	delete_mode_label.add_theme_constant_override("shadow_offset_x", 2)
	delete_mode_label.add_theme_constant_override("shadow_offset_y", 2)

	delete_mode_canvas.add_child(delete_mode_label)


func _update_delete_mode_ui():
	if delete_mode_label == null:
		return

	if delete_mode:
		delete_mode_label.visible = true
		delete_mode_label.text = "BUILDING DELETE MODE ON\nToggle: .    Delete looked-at model: Right Click"
	else:
		delete_mode_label.visible = false


# -------------------------------------------------
# SAVE / LOAD
# -------------------------------------------------
func _get_building_id(building_root: Node3D) -> String:
	if building_root.has_meta(META_BUILDING_ID):
		return str(building_root.get_meta(META_BUILDING_ID))
	return str(building_root.get_path())


func _get_scene_key_from_scene(scene: PackedScene) -> String:
	if scene == newhouse_wrapper:
		return "newhouse"
	if scene == terrace_wrapper:
		return "terrace"
	if scene == housev1_wrapper:
		return "housev1"
	if scene == housev2_wrapper:
		return "housev2"
	if scene == housev3_wrapper:
		return "housev3"
	if scene == housev4_wrapper:
		return "housev4"
	if scene == bung1_wrapper:
		return "bung1"
	if scene == bung2_wrapper:
		return "bung2"
	if scene == bung3_wrapper:
		return "bung3"
	if scene == garage_wrapper:
		return "garage"
	return ""


func _get_scene_from_key(scene_key: String) -> PackedScene:
	match scene_key:
		"newhouse":
			return newhouse_wrapper
		"terrace":
			return terrace_wrapper
		"housev1":
			return housev1_wrapper
		"housev2":
			return housev2_wrapper
		"housev3":
			return housev3_wrapper
		"housev4":
			return housev4_wrapper
		"bung1":
			return bung1_wrapper
		"bung2":
			return bung2_wrapper
		"bung3":
			return bung3_wrapper
		"garage":
			return garage_wrapper
		_:
			return null


func _save_building_to_memory(building_id: String, model: Node3D, scene: PackedScene):
	var scene_key := _get_scene_key_from_scene(scene)
	if scene_key == "":
		return

	saved_layout[building_id] = {
		"scene_key": scene_key,
		"wrapper_type": str(model.get_meta("wrapper_type", "house")),
		"pos_x": model.global_position.x,
		"pos_y": model.global_position.y,
		"pos_z": model.global_position.z,
		"rot_x": model.global_rotation.x,
		"rot_y": model.global_rotation.y,
		"rot_z": model.global_rotation.z,
		"scale_x": model.scale.x,
		"scale_y": model.scale.y,
		"scale_z": model.scale.z
	}


func _save_layout_to_disk():
	var data = {
		"version": SAVE_VERSION,
		"buildings": saved_layout
	}

	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("BuildingModelPlacer: could not save layout to " + SAVE_PATH)
		return

	file.store_string(json_text)
	file.close()
	print("BuildingModelPlacer: saved model layout to ", SAVE_PATH)


func _load_layout_from_disk():
	saved_layout.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("BuildingModelPlacer: could not open layout save file.")
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_warning("BuildingModelPlacer: failed to parse layout save file.")
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return

	if int(data.get("version", -1)) != SAVE_VERSION:
		print("BuildingModelPlacer: layout save version mismatch, ignoring old save.")
		return

	var buildings = data.get("buildings", {})
	if typeof(buildings) == TYPE_DICTIONARY:
		saved_layout = buildings
		print("BuildingModelPlacer: loaded saved model layout entries = ", saved_layout.size())


func _load_deleted_buildings():
	deleted_building_ids.clear()

	if not FileAccess.file_exists(DELETED_MODELS_SAVE_PATH):
		return

	var file := FileAccess.open(DELETED_MODELS_SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("BuildingModelPlacer: could not open deleted models save file.")
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_warning("BuildingModelPlacer: failed to parse deleted models save file.")
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return

	var ids = data.get("deleted_ids", [])
	if typeof(ids) == TYPE_ARRAY:
		for id in ids:
			deleted_building_ids[str(id)] = true

	print("BuildingModelPlacer: loaded deleted building ids = ", deleted_building_ids.size())


func _save_deleted_buildings():
	var data = {
		"deleted_ids": deleted_building_ids.keys()
	}

	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(DELETED_MODELS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("BuildingModelPlacer: could not save deleted models file.")
		return

	file.store_string(json_text)
	file.close()


# -------------------------------------------------
# PLACEMENT
# -------------------------------------------------
func _place_model_using_front_markers(model: Node3D, source_front_marker: Node3D):
	model.global_position = Vector3.ZERO
	model.global_rotation = Vector3.ZERO
	model.scale = Vector3.ONE * model_scale

	model.global_rotation.y = source_front_marker.global_rotation.y + PI
	model.global_position.y = source_front_marker.global_position.y + model_y_offset

	var wrapper_front_marker := _find_wrapper_front_marker(model)
	if wrapper_front_marker == null:
		push_warning("BuildingModelPlacer: wrapper has no FrontMarker: " + model.name)
		model.global_position.x = source_front_marker.global_position.x
		model.global_position.z = source_front_marker.global_position.z
		return

	var delta := source_front_marker.global_position - wrapper_front_marker.global_position
	model.global_position += delta


func _resolve_overlap_by_side_shift(model: Node3D, source_front_marker: Node3D):
	if not _model_overlaps_anything(model):
		return

	var original_position := model.global_position

	var right := model.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	if right.length() < 0.001:
		return

	for i in range(1, lateral_nudge_attempts + 1):
		var offset_amount := lateral_nudge_step * float(i)

		model.global_position = original_position + right * offset_amount
		if not _model_overlaps_anything(model):
			return

		model.global_position = original_position - right * offset_amount
		if not _model_overlaps_anything(model):
			return

	model.global_position = original_position


# -------------------------------------------------
# OVERLAP CHECKING
# -------------------------------------------------
func _model_overlaps_anything(model: Node3D) -> bool:
	var model_aabb := _get_world_aabb_for_node(model)
	if model_aabb.size == Vector3.ZERO:
		return false

	var model_center := model_aabb.position + model_aabb.size * 0.5

	for other in spawned_models_parent.get_children():
		if other == model:
			continue
		if not (other is Node3D):
			continue

		var other_3d := other as Node3D

		if model_center.distance_to(other_3d.global_position) > 8.0:
			continue

		var other_aabb := _get_world_aabb_for_node(other_3d)
		if other_aabb.size == Vector3.ZERO:
			continue

		if _aabb_intersects_xz(model_aabb, other_aabb, overlap_padding):
			return true

	return false


func _get_model_footprint_area(model: Node3D) -> float:
	var aabb := _get_world_aabb_for_node(model)
	if aabb.size == Vector3.ZERO:
		return INF

	return aabb.size.x * aabb.size.z


func _get_world_aabb_for_node(root: Node3D) -> AABB:
	var found := false
	var combined := AABB()

	for mesh_instance in _collect_mesh_instances(root):
		var local_aabb := mesh_instance.get_aabb()
		var world_aabb := _transform_aabb(mesh_instance.global_transform, local_aabb)

		if not found:
			combined = world_aabb
			found = true
		else:
			combined = combined.merge(world_aabb)

	if not found:
		return AABB()

	return combined


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result : Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)

	for child in node.get_children():
		result.append_array(_collect_mesh_instances(child))

	return result


func _transform_aabb(transform: Transform3D, aabb: AABB) -> AABB:
	var corners = [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z)
	]

	var first_point: Vector3 = transform * corners[0]
	var min_v: Vector3 = first_point
	var max_v: Vector3 = first_point

	for i in range(1, corners.size()):
		var p: Vector3 = transform * corners[i]
		min_v.x = min(min_v.x, p.x)
		min_v.y = min(min_v.y, p.y)
		min_v.z = min(min_v.z, p.z)
		max_v.x = max(max_v.x, p.x)
		max_v.y = max(max_v.y, p.y)
		max_v.z = max(max_v.z, p.z)

	return AABB(min_v, max_v - min_v)


func _aabb_intersects_xz(a: AABB, b: AABB, padding: float = 0.0) -> bool:
	var a_min_x := a.position.x - padding
	var a_max_x := a.position.x + a.size.x + padding
	var a_min_z := a.position.z - padding
	var a_max_z := a.position.z + a.size.z + padding

	var b_min_x := b.position.x - padding
	var b_max_x := b.position.x + b.size.x + padding
	var b_min_z := b.position.z - padding
	var b_max_z := b.position.z + b.size.z + padding

	var overlap_x := a_min_x < b_max_x and a_max_x > b_min_x
	var overlap_z := a_min_z < b_max_z and a_max_z > b_min_z

	return overlap_x and overlap_z


# -------------------------------------------------
# MARKER FINDING
# -------------------------------------------------
func _find_source_front_marker(building_root: Node) -> Node3D:
	if building_root.has_node("FrontMarker"):
		var marker = building_root.get_node("FrontMarker")
		if marker is Node3D:
			return marker as Node3D

	for child in building_root.get_children():
		if child.name == "FrontMarker" and child is Node3D:
			return child as Node3D

	return null


func _find_wrapper_front_marker(model: Node) -> Node3D:
	if model.has_node("FrontMarker"):
		var marker = model.get_node("FrontMarker")
		if marker is Node3D:
			return marker as Node3D

	return _find_wrapper_front_marker_recursive(model)


func _find_wrapper_front_marker_recursive(node: Node) -> Node3D:
	if node.name == "FrontMarker" and node is Node3D:
		return node as Node3D

	for child in node.get_children():
		var result = _find_wrapper_front_marker_recursive(child)
		if result != null:
			return result

	return null


# -------------------------------------------------
# TERRACE GROUPING
# -------------------------------------------------
func _get_terrace_run_for_plot(source_front_marker: Node3D) -> int:
	var right := source_front_marker.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	if right.length() < 0.001:
		return 0

	var forward := -source_front_marker.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	if forward.length() < 0.001:
		return 0

	var candidate_pos := source_front_marker.global_position

	var left_offsets: Array[float] = []
	var right_offsets: Array[float] = []

	for child in spawned_models_parent.get_children():
		if not (child is Node3D):
			continue

		var model: Node3D = child as Node3D

		if model.get_meta("wrapper_type", "") != "terrace":
			continue

		var delta: Vector3 = model.global_position - candidate_pos
		var depth_offset: float = absf(delta.dot(forward))

		if depth_offset > terrace_row_depth_tolerance:
			continue

		var side_offset: float = delta.dot(right)
		var abs_side: float = absf(side_offset)

		if abs_side > terrace_neighbor_distance:
			continue

		if side_offset < 0.0:
			left_offsets.append(abs_side)
		else:
			right_offsets.append(abs_side)

	var left_count := _count_contiguous_side_neighbors(left_offsets)
	var right_count := _count_contiguous_side_neighbors(right_offsets)

	return left_count + 1 + right_count


func _count_contiguous_side_neighbors(offsets: Array[float]) -> int:
	if offsets.is_empty():
		return 0

	offsets.sort()

	var count := 0
	var last_offset := 0.0
	var max_gap := terrace_neighbor_distance * 0.55

	for offset in offsets:
		if count == 0:
			count = 1
			last_offset = offset
		elif offset - last_offset <= max_gap:
			count += 1
			last_offset = offset
		else:
			break

	return count


# -------------------------------------------------
# MODEL CHOICE
# -------------------------------------------------
func _get_candidate_scenes_for_foundation(foundation: Node3D) -> Array[PackedScene]:
	var building_root := foundation.get_parent()

	var building_kind := ""
	var is_flats := false

	if building_root != null and building_root.has_meta("building_type"):
		building_kind = str(building_root.get_meta("building_type")).to_lower()

	if foundation.has_meta(META_BUILDING_KIND):
		building_kind = str(foundation.get_meta(META_BUILDING_KIND)).to_lower()

	if foundation.has_meta(META_IS_FLATS):
		is_flats = bool(foundation.get_meta(META_IS_FLATS))

	var candidates : Array[PackedScene] = []

	if is_flats or building_kind == "flats" or building_kind == "apartments":
		if newhouse_wrapper != null:
			candidates.append(newhouse_wrapper)
		if garage_wrapper != null:
			candidates.append(garage_wrapper)
		return candidates

	var source_front_marker := _find_source_front_marker(building_root)
	var terrace_run := 0

	if source_front_marker != null and terrace_wrapper != null:
		terrace_run = _get_terrace_run_for_plot(source_front_marker)

	if newhouse_wrapper != null:
		candidates.append(newhouse_wrapper)

	if terrace_wrapper != null and terrace_run < terrace_max_in_row:
		candidates.append(terrace_wrapper)

	if housev1_wrapper != null:
		candidates.append(housev1_wrapper)
	if housev2_wrapper != null:
		candidates.append(housev2_wrapper)
	if housev3_wrapper != null:
		candidates.append(housev3_wrapper)
	if housev4_wrapper != null:
		candidates.append(housev4_wrapper)
	if bung1_wrapper != null:
		candidates.append(bung1_wrapper)
	if bung2_wrapper != null:
		candidates.append(bung2_wrapper)
	if bung3_wrapper != null:
		candidates.append(bung3_wrapper)

	if garage_wrapper != null:
		candidates.append(garage_wrapper)

	return candidates


func _choose_scene_for_foundation(foundation: Node3D) -> PackedScene:
	var building_root := foundation.get_parent()

	var building_kind := ""
	var is_flats := false

	if building_root != null and building_root.has_meta("building_type"):
		building_kind = str(building_root.get_meta("building_type")).to_lower()

	if foundation.has_meta(META_BUILDING_KIND):
		building_kind = str(foundation.get_meta(META_BUILDING_KIND)).to_lower()

	if foundation.has_meta(META_IS_FLATS):
		is_flats = bool(foundation.get_meta(META_IS_FLATS))

	if is_flats or building_kind == "flats" or building_kind == "apartments":
		var flat_pool : Array[PackedScene] = []
		if newhouse_wrapper != null:
			flat_pool.append(newhouse_wrapper)
		if garage_wrapper != null:
			flat_pool.append(garage_wrapper)

		if not flat_pool.is_empty():
			return _pick_random_scene(flat_pool)
		return null

	var source_front_marker := _find_source_front_marker(building_root)
	var terrace_run := 0

	if source_front_marker != null and terrace_wrapper != null:
		terrace_run = _get_terrace_run_for_plot(source_front_marker)

	var residential_pool : Array[PackedScene] = []

	# Small foundations get garage in the natural pool
	if prefer_garage_on_small_foundations and garage_wrapper != null and _is_small_foundation(foundation):
		for i in range(garage_small_plot_weight):
			residential_pool.append(garage_wrapper)

	if newhouse_wrapper != null:
		residential_pool.append(newhouse_wrapper)

	if terrace_wrapper != null:
		var terrace_weight := terrace_base_weight

		if terrace_run > 0 and terrace_run < terrace_max_in_row:
			terrace_weight += terrace_group_bonus_weight

		if terrace_run < terrace_max_in_row:
			for i in range(terrace_weight):
				residential_pool.append(terrace_wrapper)

	if housev1_wrapper != null:
		residential_pool.append(housev1_wrapper)
	if housev2_wrapper != null:
		residential_pool.append(housev2_wrapper)
	if housev3_wrapper != null:
		residential_pool.append(housev3_wrapper)
	if housev4_wrapper != null:
		residential_pool.append(housev4_wrapper)
	if bung1_wrapper != null:
		residential_pool.append(bung1_wrapper)
	if bung2_wrapper != null:
		residential_pool.append(bung2_wrapper)
	if bung3_wrapper != null:
		residential_pool.append(bung3_wrapper)

	if not residential_pool.is_empty():
		return _pick_random_scene(residential_pool)

	return null


func _is_small_foundation(foundation: Node3D) -> bool:
	var size: Vector2 = _get_foundation_size_xz(foundation)
	if size == Vector2.ZERO:
		return false

	var width: float = minf(size.x, size.y)
	var depth: float = maxf(size.x, size.y)
	var area: float = size.x * size.y

	if width <= garage_small_foundation_max_width:
		return true
	if depth <= garage_small_foundation_max_depth:
		return true
	if area <= garage_small_foundation_max_area:
		return true

	return false


func _get_foundation_size_xz(foundation: Node3D) -> Vector2:
	var aabb: AABB = _get_world_aabb_for_single_node(foundation)
	if aabb.size == Vector3.ZERO:
		return Vector2.ZERO

	return Vector2(absf(aabb.size.x), absf(aabb.size.z))


func _get_world_aabb_for_single_node(node: Node3D) -> AABB:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		return _transform_aabb(mesh_node.global_transform, mesh_node.get_aabb())

	return _get_world_aabb_for_node(node)


func _pick_random_scene(scene_array: Array[PackedScene]) -> PackedScene:
	if scene_array.is_empty():
		return null

	var valid_scenes : Array[PackedScene] = []

	for scene in scene_array:
		if scene != null:
			valid_scenes.append(scene)

	if valid_scenes.is_empty():
		return null

	return valid_scenes[randi() % valid_scenes.size()]
