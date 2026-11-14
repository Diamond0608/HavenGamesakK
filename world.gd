extends Node

const PlaneMovementScript = preload("res://scripts/plane/plane_movement.gd")
const WorldBoundsScript = preload("res://scripts/world/world_bounds.gd")

@export var initial_speed: float = 600.0
@export var initial_direction: Vector2 = Vector2.RIGHT
@export var max_speed: float = 10000.0

@export var plane_path: NodePath = ^"CharacterBody2D"
@export var tile_map_path: NodePath = ^"TileMapLayer2"

@export var min_pitch: float = 0.8
@export var max_pitch: float = 2.0
@export var min_volume: float = 0.1

# The aircraft artwork faces up by default, so rotate it 90 degrees
# clockwise to align its nose with a movement direction of Vector2.RIGHT.
@export var plane_visual_rotation_offset_degrees: float = 90.0

# Progressive traffic spawning. The first extra plane appears after 10 seconds.
@export var initial_spawn_interval: float = 10.0
@export var spawn_interval_reduction: float = 1.0
@export var spawn_interval_reduction_every: float = 30.0
@export var minimum_spawn_interval: float = 2.0
@export var spawn_margin: float = 48.0

@export_group("Fighter Ultimate")
@export var fighter_plane_path: NodePath = ^"fighterplane"
@export var fighter_flight_speed: float = 850.0
@export var fighter_shoot_radius: float = 65.0
@export var fighter_shoot_cooldown: float = 0.25
@export var ultimate_duration: float = 20.0
@export var fighter_visual_rotation_offset_degrees: float = 0.0

const FighterControllerScript = preload("res://scripts/plane/fighter_controller.gd")

var fighter_controller: Node
var ultimate_active: bool = false
var ultimate_time_left: float = 0.0

var plane: CharacterBody2D
var world_bounds: Rect2
var bounds: WorldBounds

# Each entry stores the independent movement state for one aircraft.
var aircraft: Array[Dictionary] = []

var elapsed_game_time: float = 0.0
var spawn_clock: float = 0.0


func _ready() -> void:
	plane = get_node_or_null(plane_path) as CharacterBody2D

	if plane == null:
		push_error("World: Plane not found at plane_path: " + str(plane_path))
		set_physics_process(false)
		return

	var tile_map := get_node_or_null(tile_map_path) as TileMapLayer

	if tile_map == null:
		push_error("World: TileMapLayer not found at tile_map_path: " + str(tile_map_path))
		set_physics_process(false)
		return

	if tile_map.tile_set == null:
		push_error("World: TileMapLayer has no TileSet.")
		set_physics_process(false)
		return

	var used_rect: Rect2i = tile_map.get_used_rect()

	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		push_error("World: TileMapLayer has no used cells.")
		set_physics_process(false)
		return

	# map_to_local() returns cell centres. Move half a tile outward
	# to get the actual outer edges of the used map area.
	var half_tile_size := Vector2(tile_map.tile_set.tile_size) * 0.5
	var top_left_local := tile_map.map_to_local(used_rect.position) - half_tile_size
	var bottom_right_local := tile_map.map_to_local(used_rect.end) - half_tile_size

	# Convert the TileMapLayer's local coordinates into world coordinates,
	# because aircraft are moved using global_position.
	var top_left_global := tile_map.to_global(top_left_local)
	var bottom_right_global := tile_map.to_global(bottom_right_local)

	var bounds_min := Vector2(
		minf(top_left_global.x, bottom_right_global.x),
		minf(top_left_global.y, bottom_right_global.y)
	)
	var bounds_max := Vector2(
		maxf(top_left_global.x, bottom_right_global.x),
		maxf(top_left_global.y, bottom_right_global.y)
	)

	world_bounds = Rect2(bounds_min, bounds_max - bounds_min)
	bounds = WorldBoundsScript.new(world_bounds)

	print("World: calculated map bounds (global): ", world_bounds)

	if not bounds.is_valid():
		push_error("World: calculated map bounds are invalid.")
		set_physics_process(false)
		return

	if initial_speed <= 0.0 or max_speed <= 0.0:
		push_error("World: initial_speed and max_speed must be greater than zero.")
		set_physics_process(false)
		return

	if initial_spawn_interval <= 0.0 or minimum_spawn_interval <= 0.0:
		push_error("World: spawn intervals must be greater than zero.")
		set_physics_process(false)
		return

	if spawn_interval_reduction_every <= 0.0:
		push_error("World: spawn_interval_reduction_every must be greater than zero.")
		set_physics_process(false)
		return

	var first_direction := initial_direction.normalized()
	if first_direction == Vector2.ZERO:
		first_direction = Vector2.RIGHT

	plane.global_position = bounds.clamp_position(plane.global_position)
	plane.rotation = _rotation_for_direction(first_direction)
	_register_aircraft(plane, first_direction, minf(initial_speed, max_speed))
	_setup_fighter_controller()


func _process(delta: float) -> void:
	if not ultimate_active:
		return

	ultimate_time_left -= delta
	if ultimate_time_left <= 0.0:
		_end_ultimate()


func _physics_process(delta: float) -> void:
	# Freeze traffic progression and spawning during the fighter deployment.
	# Existing aircraft continue flying normally.
	if not ultimate_active:
		elapsed_game_time += delta
		spawn_clock += delta

	_update_aircraft(delta)

	if not ultimate_active:
		_try_spawn_aircraft()


func _unhandled_input(event: InputEvent) -> void:
	# Temporary test control. Landing-count unlocks will be connected later.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_activate_ultimate()


func _setup_fighter_controller() -> void:
	var fighter_plane := get_node_or_null(fighter_plane_path) as CharacterBody2D
	if fighter_plane == null:
		push_warning("World: fighterplane not found at fighter_plane_path: " + str(fighter_plane_path))
		return

	fighter_controller = FighterControllerScript.new()
	add_child(fighter_controller)
	fighter_controller.setup(
		self,
		fighter_plane,
		fighter_flight_speed,
		fighter_shoot_radius,
		fighter_shoot_cooldown,
		fighter_visual_rotation_offset_degrees
	)


func _activate_ultimate() -> void:
	if ultimate_active or fighter_controller == null:
		return

	ultimate_active = true
	ultimate_time_left = ultimate_duration
	fighter_controller.activate()
	print("Fighter deployed! ", ultimate_duration, " seconds.")


func _end_ultimate() -> void:
	ultimate_active = false
	ultimate_time_left = 0.0

	if fighter_controller != null:
		fighter_controller.deactivate()

	print("Fighter deployment ended. Normal traffic spawning resumed.")


func try_shoot_aircraft(target_position: Vector2, shoot_radius: float) -> void:
	if not ultimate_active:
		return

	var closest_index := -1
	var closest_distance := shoot_radius

	for i in range(aircraft.size()):
		var state: Dictionary = aircraft[i]
		var target_plane := state["plane"] as CharacterBody2D

		if not is_instance_valid(target_plane) or target_plane == plane:
			continue

		var distance := target_plane.global_position.distance_to(target_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = i

	if closest_index == -1:
		return

	var target_state: Dictionary = aircraft[closest_index]
	var target_plane := target_state["plane"] as CharacterBody2D
	aircraft.remove_at(closest_index)
	target_plane.queue_free()
	print("Arcade intercept! Remaining traffic: ", aircraft.size())


func _register_aircraft(new_plane: CharacterBody2D, start_direction: Vector2, start_speed: float) -> void:
	var movement_audio := new_plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D

	if movement_audio == null:
		push_warning("World: AudioStreamPlayer2D not found inside " + new_plane.name + ".")

	elif not movement_audio.playing:
		movement_audio.play()

	aircraft.append({
		"plane": new_plane,
		"direction": start_direction.normalized(),
		"speed": start_speed,
		"audio": movement_audio
	})


func _update_aircraft(delta: float) -> void:
	for i in range(aircraft.size()):
		var state: Dictionary = aircraft[i]
		var aircraft_node := state["plane"] as CharacterBody2D

		if not is_instance_valid(aircraft_node):
			continue

		var result: Dictionary = PlaneMovementScript.advance(
			aircraft_node.global_position,
			state["direction"],
			state["speed"],
			delta,
			world_bounds,
			max_speed
		)

		aircraft_node.global_position = result["position"]
		state["direction"] = result["direction"]
		state["speed"] = result["speed"]

		# Derive the visual heading from the current travel direction. This
		# keeps the sprite aligned after every 180-degree boundary bounce.
		aircraft_node.rotation = _rotation_for_direction(state["direction"])

		_update_movement_audio(state["audio"], state["speed"])
		aircraft[i] = state


func _try_spawn_aircraft() -> void:
	var interval := _get_current_spawn_interval()

	if spawn_clock < interval:
		return

	spawn_clock = 0.0
	_spawn_aircraft()


func _get_current_spawn_interval() -> float:
	var reduction_steps := floori(elapsed_game_time / spawn_interval_reduction_every)
	var interval := initial_spawn_interval - float(reduction_steps) * spawn_interval_reduction
	return maxf(minimum_spawn_interval, interval)


func _spawn_aircraft() -> void:
	# Duplicate the existing plane node so its sprite, collision shape and
	# audio stream stay identical to the aircraft already in the scene.
	var new_plane := plane.duplicate() as CharacterBody2D

	if new_plane == null:
		push_error("World: Could not duplicate the existing plane.")
		return

	new_plane.name = "Aircraft_%02d" % (aircraft.size() + 1)

	# Only the original aircraft should control the shared camera.
	var camera := new_plane.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false

	# The world controls movement and audio for every aircraft. Remove any
	# legacy movement script from duplicated audio nodes to avoid two movers.
	var movement_audio := new_plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	if movement_audio != null:
		movement_audio.set_script(null)

	get_parent().add_child(new_plane)

	var margin_x := minf(spawn_margin, world_bounds.size.x * 0.25)
	var margin_y := minf(spawn_margin, world_bounds.size.y * 0.25)
	var min_x := world_bounds.position.x + margin_x
	var max_x := world_bounds.end.x - margin_x
	var min_y := world_bounds.position.y + margin_y
	var max_y := world_bounds.end.y - margin_y

	var spawn_position := Vector2(
		randf_range(min_x, max_x) if min_x <= max_x else world_bounds.get_center().x,
		randf_range(min_y, max_y) if min_y <= max_y else world_bounds.get_center().y
	)

	var angle := randf_range(0.0, TAU)
	var direction := Vector2.RIGHT.rotated(angle)

	new_plane.global_position = spawn_position
	new_plane.rotation = _rotation_for_direction(direction)

	_register_aircraft(new_plane, direction, minf(initial_speed, max_speed))

	print(
		"World: spawned aircraft ",
		new_plane.name,
		" | active aircraft: ",
		aircraft.size(),
		" | next interval: ",
		_get_current_spawn_interval()
	)


func _update_movement_audio(audio: AudioStreamPlayer2D, current_speed: float) -> void:
	if audio == null or max_speed <= 0.0:
		return

	var speed_ratio: float = clampf(current_speed / max_speed, 0.0, 1.0)
	audio.pitch_scale = lerpf(min_pitch, max_pitch, speed_ratio)
	audio.volume_db = linear_to_db(lerpf(min_volume, 1.0, speed_ratio))



func _rotation_for_direction(travel_direction: Vector2) -> float:
	return travel_direction.angle() + deg_to_rad(plane_visual_rotation_offset_degrees)
