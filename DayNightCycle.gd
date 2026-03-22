extends Node3D

@export var sun_path: NodePath
@export var moon_path: NodePath
@export var sun_visual_path: NodePath
@export var moon_visual_path: NodePath
@export var world_environment_path: NodePath
@export var orbit_center_path: NodePath
@export var star_dome_path: NodePath

@export var cycle_length_minutes: float = 30.0
@export_range(0.0, 24.0, 0.1) var start_time_hours: float = 12.0
@export var cycle_enabled: bool = true

@export var sun_max_energy: float = 2.2
@export var moon_max_energy: float = 0.35

@export var day_ambient_energy: float = 1.0
@export var night_ambient_energy: float = 0.15

@export var sky_distance: float = 800.0

@export var east_west_rotation_degrees: float = -90.0
@export_range(-45.0, 45.0, 0.1) var sun_path_tilt_degrees: float = 20.0

@export var star_rotation_speed_degrees: float = 0.4
@export var star_max_emission: float = 0.6
@export var star_max_alpha: float = 1.0

@export var print_time_debug: bool = false

var time_of_day_hours: float = 12.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sun_visual: Node3D
var moon_visual: Node3D
var world_environment: WorldEnvironment
var orbit_center: Node3D
var star_dome: Node3D
var star_mesh: MeshInstance3D

var _last_printed_minute: int = -1

func _ready():
	sun = get_node_or_null(sun_path)
	moon = get_node_or_null(moon_path)
	sun_visual = get_node_or_null(sun_visual_path)
	moon_visual = get_node_or_null(moon_visual_path)
	world_environment = get_node_or_null(world_environment_path)
	orbit_center = get_node_or_null(orbit_center_path)
	star_dome = get_node_or_null(star_dome_path)

	if star_dome:
		star_mesh = find_first_mesh_instance(star_dome)
		setup_star_material()

	if orbit_center == null:
		print("DayNightCycle: Orbit center path not assigned or not found")
	if sun == null:
		print("DayNightCycle: Sun path not assigned or not found")
	if moon == null:
		print("DayNightCycle: Moon path not assigned or not found")
	if world_environment == null:
		print("DayNightCycle: WorldEnvironment path not assigned or not found")
	if star_dome and star_mesh == null:
		print("DayNightCycle: Star dome found, but no MeshInstance3D was found under it")

	time_of_day_hours = start_time_hours
	update_cycle_visuals()

	if print_time_debug:
		print("DayNightCycle: started at ", get_time_string())

func _process(delta):
	if cycle_enabled and cycle_length_minutes > 0.0:
		var day_seconds: float = cycle_length_minutes * 60.0
		var hours_per_second: float = 24.0 / day_seconds
		time_of_day_hours += delta * hours_per_second

		if time_of_day_hours >= 24.0:
			time_of_day_hours -= 24.0

	update_cycle_visuals()
	update_star_dome_transform(delta)

	if print_time_debug:
		var current_minute: int = int(time_of_day_hours * 60.0)
		if current_minute != _last_printed_minute:
			_last_printed_minute = current_minute
			print("DayNightCycle time: ", get_time_string())

func update_cycle_visuals():
	var t: float = time_of_day_hours / 24.0

	# 6:00 sunrise, 12:00 noon, 18:00 sunset, 0:00 midnight
	var sun_angle: float = (t * 360.0) - 90.0
	var moon_angle: float = sun_angle + 180.0

	var sun_height: float = sin(deg_to_rad(sun_angle))
	var moon_height: float = sin(deg_to_rad(moon_angle))

	var sun_visible: float = clampf(sun_height, 0.0, 1.0)
	var moon_visible: float = clampf(moon_height, 0.0, 1.0)

	# Softer sunrise/sunset transitions
	sun_visible = smoothstep(0.0, 1.0, sun_visible)
	moon_visible = smoothstep(0.0, 1.0, moon_visible)

	var sun_dir: Vector3 = build_celestial_direction(sun_angle)
	var moon_dir: Vector3 = build_celestial_direction(moon_angle)

	update_light_directions(sun_dir, moon_dir)
	update_visual_positions(sun_dir, moon_dir)

	if sun:
		sun.light_energy = sun_max_energy * sun_visible
		var sunrise_sunset_tint := Color(1.0, 0.72, 0.5)
		var midday_tint := Color(1.0, 0.98, 0.92)
		sun.light_color = sunrise_sunset_tint.lerp(midday_tint, sun_visible)

	if moon:
		moon.light_energy = moon_max_energy * moon_visible
		moon.light_color = Color(0.65, 0.75, 1.0)

	update_visual_brightness(sun_visible, moon_visible)
	update_environment(sun_visible)

func build_celestial_direction(angle_degrees: float) -> Vector3:
	var dir := Vector3(0, 0, -1)
	# Main arc
	dir = dir.rotated(Vector3.RIGHT, deg_to_rad(angle_degrees))
	# Tilt arc
	dir = dir.rotated(Vector3.FORWARD, deg_to_rad(sun_path_tilt_degrees))
	# Turn arc east-west
	dir = dir.rotated(Vector3.UP, deg_to_rad(east_west_rotation_degrees))
	return dir.normalized()

func update_light_directions(sun_dir: Vector3, moon_dir: Vector3):
	if sun:
		sun.look_at(sun.global_position - sun_dir, Vector3.UP)
	if moon:
		moon.look_at(moon.global_position - moon_dir, Vector3.UP)

func update_visual_positions(sun_dir: Vector3, moon_dir: Vector3):
	var center: Vector3 = Vector3.ZERO
	if orbit_center:
		center = orbit_center.global_position
	if sun_visual:
		sun_visual.global_position = center + (sun_dir * sky_distance)
	if moon_visual:
		moon_visual.global_position = center + (moon_dir * sky_distance)

func update_visual_brightness(sun_visible: float, moon_visible: float):
	if sun_visual:
		set_visual_alpha_and_emission(sun_visual, max(sun_visible, 0.08), 1.0)
	if moon_visual:
		set_visual_alpha_and_emission(moon_visual, max(moon_visible, 0.08), 0.6)

func update_environment(day_amount: float):
	if world_environment == null or world_environment.environment == null:
		return

	var env := world_environment.environment

	env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, day_amount)
	var night_ambient := Color(0.02, 0.02, 0.08)
	var day_ambient := Color(1.0, 1.0, 1.0)
	env.ambient_light_color = night_ambient.lerp(day_ambient, day_amount)
	env.background_energy_multiplier = lerpf(0.05, 1.0, day_amount)

	if env.volumetric_fog_enabled:
		var fog_night := Color(0.03, 0.04, 0.08)
		var fog_day := Color(0.7, 0.8, 1.0)
		env.volumetric_fog_albedo = fog_night.lerp(fog_day, day_amount)

	if env.sky and env.sky.sky_material:
		var sky_mat = env.sky.sky_material
		if sky_mat is ProceduralSkyMaterial:
			var day_top := Color(0.22, 0.5, 1.0)
			var night_top := Color(0.01, 0.01, 0.05)
			var day_horizon := Color(0.65, 0.78, 1.0)
			var night_horizon := Color(0.02, 0.02, 0.08)
			var sunrise_band_1: float = clampf(1.0 - abs(day_amount - 0.15) * 8.0, 0.0, 1.0)
			var sunrise_band_2: float = clampf(1.0 - abs(day_amount - 0.85) * 8.0, 0.0, 1.0)
			var sunrise_amount: float = clampf(sunrise_band_1 + sunrise_band_2, 0.0, 1.0)
			var sunrise_horizon := Color(1.0, 0.55, 0.35)
			var sky_top_color: Color = night_top.lerp(day_top, day_amount)
			var sky_horizon_color: Color = night_horizon.lerp(day_horizon, day_amount)
			sky_horizon_color = sky_horizon_color.lerp(sunrise_horizon, sunrise_amount * 0.6)
			sky_mat.sky_top_color = sky_top_color
			sky_mat.sky_horizon_color = sky_horizon_color

	# Stars fade in at night: always enabled, fade via alpha/emission
	var night_amount: float = 1.0 - day_amount
	night_amount = clampf(night_amount, 0.0, 1.0)

	# Smooth fade across entire night/day cycle
	var star_fade: float = smoothstep(0.0, 1.0, night_amount)

	if star_dome:
		# Keep the dome always visible; rely on alpha fade
		star_dome.visible = true

	if star_mesh and star_mesh.material_override is StandardMaterial3D:
		var mat := star_mesh.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		var c := mat.albedo_color
		c.a = star_fade * star_max_alpha
		mat.albedo_color = c
		mat.emission_energy_multiplier = lerpf(0.0, star_max_emission, star_fade)

func update_star_dome_transform(delta: float):
	if star_dome == null:
		return
	var center: Vector3 = Vector3.ZERO
	if orbit_center:
		center = orbit_center.global_position
	star_dome.global_position = center
	star_dome.rotate_y(deg_to_rad(star_rotation_speed_degrees * delta))

func set_visual_alpha_and_emission(node: Node3D, alpha_value: float, emission_multiplier: float):
	var mesh_instance := find_first_mesh_instance(node)
	if mesh_instance == null:
		return
	if mesh_instance.material_override is StandardMaterial3D:
		var mat := mesh_instance.material_override as StandardMaterial3D
		var c := mat.albedo_color
		c.a = clampf(alpha_value, 0.0, 1.0)
		mat.albedo_color = c
		mat.emission_energy_multiplier = max(alpha_value * emission_multiplier, 0.05)

func find_first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := find_first_mesh_instance(child)
		if found:
			return found
	return null

func setup_star_material():
	if star_mesh == null:
		return
	if star_mesh.material_override is StandardMaterial3D:
		var mat := star_mesh.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_FRONT

func set_time_hours(new_time: float):
	time_of_day_hours = fposmod(new_time, 24.0)
	update_cycle_visuals()
	if print_time_debug:
		print("DayNightCycle: set time to ", get_time_string())

func set_cycle_length_minutes(new_minutes: float):
	cycle_length_minutes = max(new_minutes, 0.1)
	if print_time_debug:
		print("DayNightCycle: cycle length set to ", cycle_length_minutes, " minutes")

func get_time_string() -> String:
	var hours: int = int(time_of_day_hours)
	var minutes: int = int((time_of_day_hours - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]
