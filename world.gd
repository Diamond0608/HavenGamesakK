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
@export var route_line_color: Color = Color(1.0, 0.85, 0.2, 0.9)
@export var route_line_width: float = 12.0

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
@export var ultimate_duration: float = 20.0
@export var fighter_visual_rotation_offset_degrees: float = 0.0

const FighterControllerScript = preload("res://scripts/plane/fighter_controller.gd")

var fighter_controller
var ultimate_active: bool = false
var ultimate_time_left: float = 0.0
var total_landings: int = 0
var fighter_charges: int = 0

var plane: CharacterBody2D
var world_bounds: Rect2
var bounds: WorldBounds
var direction: Vector2 = Vector2.RIGHT
var current_speed: float = 600.0
var movement_audio: AudioStreamPlayer2D

# Each entry stores the independent movement state for one aircraft.
var aircraft: Array[Dictionary] = []

var elapsed_game_time: float = 0.0
var spawn_clock: float = 0.0

var route_line: Line2D
var route_confirmed: bool = false
var plane_art_angle_offset: float = 0.0
var route_plane: CharacterBody2D
var route_speed: float = 0.0
var route_direction: Vector2 = Vector2.RIGHT
var route_points: Array[Vector2] = []
var route_index: int = 0
var is_drawing_route: bool = false
var route_trace_moved: bool = false
var plane_landed: bool = false
const ROUTE_POINT_SPACING: float = 18.0
const PLANE_TAP_RADIUS: float = 48.0

# --- Runway landing gates ---------------------------------------------------
# Every runway has two "gate" boxes, one at each end. A plane lands when the
# same plane touches both gates of one runway within a short time. The allowed
# time depends on the plane's speed (gate distance / speed).
const RUNWAY_PATHS: Array[String] = [
	"AirportnewRemovebgPreview",
	"AirportnewRemovebgPreview2",
	"AircraftCarrierNewRemovebgPreview"
]
const GATE_DEPTH: float = 40.0              # thickness of auto-made gates, runway-local units
const GATE_TIME_MIN_FACTOR: float = 0.5     # faster than half the expected time = rejected
const GATE_TIME_MAX_FACTOR: float = 1.5     # slower than 1.5x the expected time = rejected
const GATE_TIME_SLACK: float = 0.1          # extra seconds of forgiveness
const LANDING_GRACE: float = 0.5            # seconds after the route ends that a landing can still count

var scoreboard_label: Label
var physics_clock: float = 0.0
var landing_window_until: float = 0.0
var runway_gates: Dictionary = {}           # runway Area2D -> Array of gate nodes
var gate_hits: Dictionary = {}              # runway Area2D -> {"gate": Node2D, "time": float}


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
	route_plane = plane
	plane.rotation = _rotation_for_direction(first_direction)
	direction = first_direction
	current_speed = minf(initial_speed, max_speed)
	plane_art_angle_offset = deg_to_rad(plane_visual_rotation_offset_degrees)
	movement_audio = plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	_register_aircraft(plane, first_direction, current_speed)
	_setup_route_ui()
	_setup_fighter_controller()
	_setup_runway_gates()
	_setup_scoreboard()


func _process(delta: float) -> void:
	_update_scoreboard()

	if not ultimate_active:
		return

	ultimate_time_left -= delta
	if ultimate_time_left <= 0.0:
		_end_ultimate()


func _physics_process(delta: float) -> void:
	physics_clock += delta

	# Freeze traffic progression and spawning during the fighter deployment.
	# Existing aircraft continue flying normally.
	if not ultimate_active:
		elapsed_game_time += delta
		spawn_clock += delta

	# Update traffic first; the primary aircraft is skipped by the generic
	# updater while it is following a route or has already landed.
	_update_aircraft(delta)

	if route_confirmed and is_instance_valid(route_plane):
		_follow_drawn_route(delta)
		var route_audio := route_plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
		_update_movement_audio(route_audio, route_speed)
		_sync_routed_aircraft_state()

	if not ultimate_active:
		_try_spawn_aircraft()


func _sync_primary_aircraft_state() -> void:
	if aircraft.is_empty():
		return

	var primary_state: Dictionary = aircraft[0]
	primary_state["direction"] = direction
	primary_state["speed"] = current_speed
	aircraft[0] = primary_state


func _sync_routed_aircraft_state() -> void:
	for i in range(aircraft.size()):
		var state: Dictionary = aircraft[i]
		if state["plane"] == route_plane:
			state["direction"] = route_direction
			state["speed"] = route_speed
			aircraft[i] = state
			if route_plane == plane:
				direction = route_direction
				current_speed = route_speed
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("activate_ultimate"):
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
		fighter_visual_rotation_offset_degrees
	)




func _activate_ultimate() -> void:
	if ultimate_active or fighter_controller == null or fighter_charges <= 0:
		return

	fighter_charges -= 1
	plane.global_rotation = direction.angle() + plane_art_angle_offset

	ultimate_active = true
	ultimate_time_left = ultimate_duration
	fighter_controller.activate()
	print("Fighter deployed! ", ultimate_duration, " seconds. Charges remaining: ", fighter_charges)


func _end_ultimate() -> void:
	ultimate_active = false
	ultimate_time_left = 0.0

	if fighter_controller != null:
		fighter_controller.deactivate()

	print("Fighter deployment ended. Normal traffic spawning resumed.")


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

		if bool(state.get("landed", false)) or (aircraft_node == route_plane and route_confirmed):
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

		if aircraft_node == plane:
			direction = state["direction"]
			current_speed = state["speed"]

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

	# duplicate() copies the template's visibility. Once the original plane
	# has landed it is hidden, so without this every new plane spawns invisible.
	new_plane.show()

	# Only the original aircraft should control the shared camera.
	var camera := new_plane.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false

	# The world controls movement and audio for every aircraft. Remove any
	# legacy movement script from duplicated audio nodes to avoid two movers.
	var movement_audio := new_plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	if movement_audio != null:
		movement_audio.set_script(null)

	add_child(new_plane)

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


func _setup_route_ui() -> void:
	route_line = Line2D.new()
	route_line.name = "RoutePreview"
	route_line.width = route_line_width
	route_line.default_color = route_line_color
	route_line.z_index = 100
	add_child(route_line)
	route_line.hide()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(route_plane) or _is_aircraft_landed(route_plane):
		route_plane = _first_active_aircraft()
	if route_plane == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var world_mouse := _viewport_to_world(event.position)
		if event.pressed:
			var clicked_plane := _plane_at_viewport_position(event.position)
			if clicked_plane != null:
				route_plane = clicked_plane
				_reset_route()
				_start_route_trace(route_plane.global_position)
				return
			_start_route_trace(world_mouse)
		elif is_drawing_route:
			_append_route_point(world_mouse)
			is_drawing_route = false
			if route_trace_moved and route_points.size() >= 2:
				_route_confirmed()
			else:
				_reset_route()
	elif event is InputEventMouseMotion and is_drawing_route:
		var previous_count := route_points.size()
		_append_route_point(_viewport_to_world(event.position))
		if route_points.size() > previous_count:
			route_trace_moved = true


func _viewport_to_world(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * viewport_position


func _plane_at_viewport_position(viewport_position: Vector2) -> CharacterBody2D:
	var closest_plane: CharacterBody2D
	var closest_distance := PLANE_TAP_RADIUS
	for state in aircraft:
		var candidate := state["plane"] as CharacterBody2D
		if not is_instance_valid(candidate) or not candidate.visible or bool(state.get("landed", false)):
			continue
		var screen_position := get_viewport().get_canvas_transform() * candidate.global_position
		var distance := screen_position.distance_to(viewport_position)
		if distance <= closest_distance:
			closest_plane = candidate
			closest_distance = distance
	return closest_plane


func _is_aircraft_landed(aircraft_node: CharacterBody2D) -> bool:
	for state in aircraft:
		if state["plane"] == aircraft_node:
			return bool(state.get("landed", false))
	return false


func _first_active_aircraft() -> CharacterBody2D:
	for state in aircraft:
		var candidate := state["plane"] as CharacterBody2D
		if is_instance_valid(candidate) and candidate.visible and not bool(state.get("landed", false)):
			return candidate
	return null


func _start_route_trace(world_position: Vector2) -> void:
	if not is_instance_valid(route_plane):
		route_plane = plane
	route_confirmed = false
	route_points.clear()
	route_points.append(route_plane.global_position)
	if world_position.distance_to(route_plane.global_position) >= ROUTE_POINT_SPACING:
		route_points.append(world_position)
	route_line.clear_points()
	for point in route_points:
		route_line.add_point(point)
	route_line.show()
	is_drawing_route = true
	route_trace_moved = false


func _append_route_point(world_position: Vector2) -> void:
	if route_points.is_empty():
		return

	var bounded_position: Vector2 = bounds.clamp_position(world_position)
	var previous_position: Vector2 = route_points[-1]
	var segment_length := previous_position.distance_to(bounded_position)

	if segment_length < ROUTE_POINT_SPACING:
		return

	# Mouse-motion events are not evenly spaced. Insert intermediate points
	# so quick cursor movement still produces a continuous route line.
	var spacing := 6.0
	var steps := maxi(1, ceili(segment_length / spacing))
	for step in range(1, steps + 1):
		var point := previous_position.lerp(bounded_position, float(step) / float(steps))
		route_points.append(point)
		route_line.add_point(point)


func _reset_route() -> void:
	route_confirmed = false
	is_drawing_route = false
	route_trace_moved = false
	route_points.clear()
	route_index = 0
	route_line.clear_points()
	route_line.hide()


func _route_confirmed() -> void:
	if route_points.size() < 2:
		return
	var selected_state := _get_aircraft_state(route_plane)
	if selected_state.is_empty():
		return
	route_confirmed = true
	route_index = 1
	gate_hits.clear()
	landing_window_until = INF
	route_speed = float(selected_state["speed"])
	route_direction = selected_state["direction"]
	route_line.hide()


func _get_aircraft_state(aircraft_node: CharacterBody2D) -> Dictionary:
	for state in aircraft:
		if state["plane"] == aircraft_node:
			return state
	return {}


func _follow_drawn_route(delta: float) -> void:
	var distance_left := route_speed * delta
	while route_index < route_points.size() and distance_left > 0.0:
		var target := route_points[route_index]
		var offset := target - route_plane.global_position
		var distance := offset.length()
		if distance <= distance_left:
			if distance > 0.0:
				route_direction = offset / distance
				route_plane.global_rotation = _rotation_for_direction(route_direction)
			route_plane.global_position = target
			distance_left -= distance
			route_index += 1
			continue
		route_direction = offset / distance
		route_plane.global_position += route_direction * distance_left
		route_plane.global_rotation = _rotation_for_direction(route_direction)
		distance_left = 0.0
	if route_index >= route_points.size():
		if route_points.size() >= 2:
			route_direction = (route_points[-1] - route_points[-2]).normalized()
			if route_direction == Vector2.ZERO:
				route_direction = Vector2.RIGHT
		route_confirmed = false
		# Area signals arrive after this function, so give the plane a moment
		# to still get credit if the route ends right on the second gate.
		landing_window_until = physics_clock + LANDING_GRACE


# Finds the two gate boxes of every runway. If you already made them in the
# editor (child Area2D nodes, or extra CollisionShape2D nodes next to the
# runway's main "CollisionShape2D"), those are used. Otherwise two are created.
func _setup_runway_gates() -> void:
	for runway_name in RUNWAY_PATHS:
		var runway := get_node_or_null(runway_name) as Area2D
		var main_shape := get_node_or_null(runway_name + "/CollisionShape2D") as CollisionShape2D
		if runway == null or main_shape == null or not main_shape.shape is RectangleShape2D:
			push_warning("World: could not set up gates for " + runway_name)
			continue

		var gates: Array[Node2D] = []
		var uses_shape_signal := false
		for child in runway.get_children():
			if child is Area2D:
				gates.append(child as Area2D)
			elif child is CollisionShape2D and child != main_shape:
				gates.append(child as CollisionShape2D)
				uses_shape_signal = true

		if gates.size() == 2:
			print("World: ", runway_name, " is using your 2 existing gate boxes: ", gates[0].name, ", ", gates[1].name)
		else:
			for gate in gates:
				push_warning("World: ignoring " + str(gate.name) + " on " + runway_name + " (need exactly 2 gate boxes).")
			gates = _create_runway_gates(runway, main_shape)
			uses_shape_signal = false
			print("World: ", runway_name, " had no usable gate boxes, created 2 automatically.")

		runway_gates[runway] = gates
		for gate in gates:
			if gate is Area2D:
				(gate as Area2D).body_entered.connect(_on_gate_body_entered.bind(runway, gate))
		if uses_shape_signal:
			runway.body_shape_entered.connect(_on_runway_shape_entered.bind(runway))


func _create_runway_gates(runway: Area2D, main_shape: CollisionShape2D) -> Array[Node2D]:
	var made: Array[Node2D] = []
	var runway_size := (main_shape.shape as RectangleShape2D).size
	# The runway's long side is its length. Airports are long on x, the
	# aircraft carrier is long on y.
	var along_y := runway_size.y > runway_size.x
	var length := runway_size.y if along_y else runway_size.x
	var width := runway_size.x if along_y else runway_size.y
	for side in [-1.0, 1.0]:
		var along_offset: float = side * (length - GATE_DEPTH) * 0.5
		var gate := Area2D.new()
		gate.name = "Gate_A" if side < 0.0 else "Gate_B"
		gate.input_pickable = false
		gate.position = main_shape.position + (Vector2(0.0, along_offset) if along_y else Vector2(along_offset, 0.0))
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, GATE_DEPTH) if along_y else Vector2(GATE_DEPTH, width)
		var gate_shape := CollisionShape2D.new()
		gate_shape.shape = rect
		gate.add_child(gate_shape)
		runway.add_child(gate)
		made.append(gate)
	return made


# Used when the gates are CollisionShape2D nodes sitting inside the runway Area2D.
func _on_runway_shape_entered(_body_rid: RID, body: Node2D, _body_shape_index: int, local_shape_index: int, runway: Area2D) -> void:
	var owner_id := runway.shape_find_owner(local_shape_index)
	var shape_node := runway.shape_owner_get_owner(owner_id) as Node2D
	if shape_node == null or not runway_gates.get(runway, []).has(shape_node):
		return
	_on_gate_body_entered(body, runway, shape_node)


func _on_gate_body_entered(body: Node2D, runway: Area2D, gate: Node2D) -> void:
	if body != route_plane or physics_clock > landing_window_until:
		return
	var previous: Dictionary = gate_hits.get(runway, {})
	if not previous.is_empty() and previous["gate"] != gate:
		var elapsed := physics_clock - float(previous["time"])
		var gate_distance := (previous["gate"] as Node2D).global_position.distance_to(gate.global_position)
		var expected := gate_distance / maxf(route_speed, 1.0)
		var in_window := (
			elapsed >= expected * GATE_TIME_MIN_FACTOR
			and elapsed <= expected * GATE_TIME_MAX_FACTOR + GATE_TIME_SLACK
		)
		print("Gate hit 2/2 on ", runway.name, " | elapsed: ", snappedf(elapsed, 0.001), "s | expected: ", snappedf(expected, 0.001), "s | accepted: ", in_window)
		if in_window:
			print("Landing accepted: ", route_plane.name, " on ", runway.name)
			gate_hits.clear()
			_finish_landing()
			return
	gate_hits[runway] = {"gate": gate, "time": physics_clock}


func _setup_scoreboard() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Scoreboard"
	layer.layer = 50
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 24.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14.0)
	panel.add_theme_stylebox_override("panel", style)

	scoreboard_label = Label.new()
	scoreboard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_label.add_theme_font_size_override("font_size", 28)
	panel.add_child(scoreboard_label)
	layer.add_child(panel)
	_update_scoreboard()


func _update_scoreboard() -> void:
	if scoreboard_label == null:
		return

	var planes_in_air := 0
	for state in aircraft:
		if is_instance_valid(state["plane"]) and not bool(state.get("landed", false)):
			planes_in_air += 1

	var seconds := int(elapsed_game_time)
	var text := "Landings: %d\nTime: %d:%02d\nPlanes in the air: %d\nFighter charges: %d" % [
		total_landings, seconds / 60, seconds % 60, planes_in_air, fighter_charges
	]
	if ultimate_active:
		text += "\nFIGHTER ACTIVE: %ds" % int(ceilf(ultimate_time_left))
	else:
		text += "\nNext fighter charge in: %d" % (10 - total_landings % 10)
	scoreboard_label.text = text


func _finish_landing() -> void:
	for i in range(aircraft.size()):
		var state: Dictionary = aircraft[i]
		if state["plane"] == route_plane:
			state["landed"] = true
			aircraft[i] = state
			break

	total_landings += 1
	if total_landings % 10 == 0:
		fighter_charges += 1
		print("Fighter ability unlocked! Total landings: ", total_landings, " | charges: ", fighter_charges)

	if route_plane == plane:
		plane_landed = true
	route_confirmed = false
	is_drawing_route = false
	route_line.hide()
	route_plane.hide()
	var route_audio := route_plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	if route_audio:
		route_audio.stop()
