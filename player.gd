extends CharacterBody3D

@onready var map_loader = get_parent()
@onready var road_label = get_tree().get_root().get_node("World/UI/RoadName")

@export var speed := 8.0
@export var mouse_sensitivity := 0.002

@export var max_step_height := 0.9
@export var step_check_distance := 0.4
@export var step_up_speed := 4.5
@export var unstuck_distance := 1.2

const GRAVITY = 24.8
const JUMP_FORCE = 8.0

# Creative fly mode
var flying := false
var is_flying := false
var fly_speed := 20.0

var pitch := 0.0
var walk_speed = 8.0
var run_speed = 16.0
var current_speed = 8.0

const SAVE_PATH = "user://player_save.json"


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	load_player_state()


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_player_state()


func save_player_state():

	var save_data = {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"pitch": pitch,
		"flying": flying
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()


func load_player_state():

	if !FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	if data.has("position"):
		global_position = Vector3(
			data["position"][0],
			data["position"][1],
			data["position"][2]
		)

	if data.has("yaw"):
		rotation.y = data["yaw"]

	if data.has("pitch"):
		pitch = data["pitch"]
		$Camera3D.rotation.x = pitch

	if data.has("flying"):
		flying = data["flying"]
		is_flying = flying


func _input(event):

	# Toggle creative fly mode with F
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		flying = !flying
		is_flying = flying
		velocity.y = 0

	# Unstuck button
	if event is InputEventKey and event.pressed and event.keycode == KEY_U:
		try_unstuck()

	# Toggle industrial buildings visibility with O
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		toggle_industrial_buildings()

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -1.5, 1.5)

		$Camera3D.rotation.x = pitch


func _physics_process(delta):

	var input_dir = Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1

	if Input.is_action_pressed("move_back"):
		input_dir.z += 1

	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1

	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	# -----------------------------
	# CREATIVE FLIGHT MODE
	# -----------------------------
	if flying:

		if Input.is_action_pressed("jump"):
			velocity.y = fly_speed
		elif Input.is_action_pressed("ui_shift"):
			velocity.y = -fly_speed
		else:
			velocity.y = 0

		current_speed = fly_speed

	else:

		if not is_on_floor():
			velocity.y -= GRAVITY * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_FORCE

		if Input.is_action_pressed("ui_shift"):
			current_speed = run_speed
		else:
			current_speed = walk_speed

	input_dir = input_dir.normalized()
	var direction = transform.basis * input_dir

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if not flying:
		try_auto_step(delta)

	move_and_slide()

	if not flying:
		apply_floor_snap()

	update_road_name()


func try_auto_step(delta):

	if not is_on_floor():
		return

	var horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < 0.05:
		return

	var motion = horizontal_velocity.normalized() * step_check_distance

	# If nothing blocks us, no step needed
	if not test_move(global_transform, motion):
		return

	# Try the same motion from slightly higher up
	var raised_transform = global_transform.translated(Vector3.UP * max_step_height)

	# If still blocked when raised, obstacle is too tall
	if test_move(raised_transform, motion):
		return

	# Smooth step up instead of snapping the full height in one frame
	var step_amount = min(max_step_height, step_up_speed * delta)
	global_position.y += step_amount


func try_unstuck():

	var test_offsets = [
		Vector3(0, 0.6, 0),

		Vector3( unstuck_distance, 0.4, 0),
		Vector3(-unstuck_distance, 0.4, 0),
		Vector3(0, 0.4,  unstuck_distance),
		Vector3(0, 0.4, -unstuck_distance),

		Vector3( unstuck_distance, 0.6,  unstuck_distance),
		Vector3(-unstuck_distance, 0.6,  unstuck_distance),
		Vector3( unstuck_distance, 0.6, -unstuck_distance),
		Vector3(-unstuck_distance, 0.6, -unstuck_distance),

		Vector3(0, 1.2, 0)
	]

	for offset in test_offsets:
		var candidate = global_transform.translated(offset)

		if not test_move(candidate, Vector3.ZERO):
			global_position = candidate.origin
			velocity = Vector3.ZERO
			return


func update_road_name():

	if map_loader == null:
		road_label.text = ""
		return

	var roads = map_loader.get("road_segments")

	if roads == null or roads.size() == 0:
		road_label.text = ""
		return

	var closest_name = ""
	var closest_dist = 999999.0

	for r in roads:

		if typeof(r) != TYPE_DICTIONARY:
			continue

		if !r.has("p1") or !r.has("p2") or !r.has("name"):
			continue

		var p1 = r["p1"]
		var p2 = r["p2"]

		var mid = (p1 + p2) * 0.5
		var dist = global_position.distance_to(mid)

		if dist < closest_dist and r["name"] != "":
			closest_dist = dist
			closest_name = r["name"]

	if closest_dist < 30.0:
		road_label.text = closest_name
	else:
		road_label.text = ""


func toggle_industrial_buildings():

	var world = get_tree().get_root().get_node_or_null("World")
	if world == null:
		print("Industrial toggle failed: World node not found")
		return

	var chunks = world.get_node_or_null("Chunks")
	if chunks == null:
		print("Industrial toggle failed: Chunks node not found")
		return

	var industrial_buildings = chunks.get_node_or_null("IndustrialBuildings")
	if industrial_buildings == null:
		print("Industrial toggle failed: IndustrialBuildings node not found")
		return

	industrial_buildings.visible = !industrial_buildings.visible
	print("IndustrialBuildings visible: ", industrial_buildings.visible)
