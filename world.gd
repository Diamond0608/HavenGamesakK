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

var plane: CharacterBody2D
var movement_audio: AudioStreamPlayer2D
var current_speed: float
var direction: Vector2
var world_bounds: Rect2
var bounds
var route_line: Line2D
var route_confirmed: bool = false
var plane_art_angle_offset: float = 0.0
var route_points: Array[Vector2] = []
var route_index: int = 0
var is_drawing_route: bool = false
var route_trace_moved: bool = false
var plane_landed: bool = false
var active_runway: CollisionShape2D
var runway_entry_side: float = 0.0
var runway_entry_x: float = 0.0
var runway_entry_y: float = 0.0
var runway_travel_sign: float = 0.0
var runway_entry_angle: float = 0.0
var runway_line_slope: float = 0.0
const ROUTE_POINT_SPACING: float = 18.0
const PLANE_TAP_RADIUS: float = 48.0
const RUNWAY_ENTRY_MARGIN: float = 24.0
const RUNWAY_HEADING_TOLERANCE: float = 0.10
const RUNWAY_TRACK_TOLERANCE: float = 6.0


func _ready() -> void:
	plane = get_node_or_null(plane_path) as CharacterBody2D

	if plane == null:
		push_error("World: Plane not found at plane_path: " + str(plane_path))
		set_physics_process(false)
		return

	movement_audio = plane.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D

	if movement_audio == null:
		push_warning("World: AudioStreamPlayer2D not found inside CharacterBody2D.")

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
	# because the plane is moved using global_position.
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

	current_speed = minf(initial_speed, max_speed)
	direction = initial_direction.normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	plane.global_position = bounds.clamp_position(plane.global_position)

	if movement_audio and not movement_audio.playing:
		movement_audio.play()

	_setup_route_ui()
	plane_art_angle_offset = plane.global_rotation


func _physics_process(delta: float) -> void:
	if plane_landed:
		return

	if route_confirmed:
		_follow_drawn_route(delta)
		_update_movement_audio()
		return

	var result: Dictionary = PlaneMovementScript.advance(
		plane.global_position,
		direction,
		current_speed,
		delta,
		world_bounds,
		max_speed
	)

	plane.global_position = result["position"]
	direction = result["direction"]
	current_speed = result["speed"]

	plane.global_rotation = direction.angle() + plane_art_angle_offset

	_update_movement_audio()


func _update_movement_audio() -> void:
	if movement_audio == null or max_speed <= 0.0:
		return

	var speed_ratio: float = clampf(current_speed / max_speed, 0.0, 1.0)
	movement_audio.pitch_scale = lerpf(min_pitch, max_pitch, speed_ratio)
	movement_audio.volume_db = linear_to_db(lerpf(min_volume, 1.0, speed_ratio))


func _setup_route_ui() -> void:
	route_line = Line2D.new()
	route_line.name = "RoutePreview"
	route_line.width = route_line_width
	route_line.default_color = route_line_color
	route_line.z_index = 100
	add_child(route_line)
	route_line.hide()


func _input(event: InputEvent) -> void:
	if plane_landed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var world_mouse := _viewport_to_world(event.position)
		if event.pressed:
			if _is_tapping_plane(event.position):
				_reset_route()
				_start_route_trace(plane.global_position)
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


func _is_tapping_plane(viewport_position: Vector2) -> bool:
	var plane_viewport_position := get_viewport().get_canvas_transform() * plane.global_position
	return plane_viewport_position.distance_to(viewport_position) <= PLANE_TAP_RADIUS


func _start_route_trace(world_position: Vector2) -> void:
	route_confirmed = false
	route_points.clear()
	route_points.append(plane.global_position)
	active_runway = null
	if world_position.distance_to(plane.global_position) >= ROUTE_POINT_SPACING:
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
	if route_points[-1].distance_to(world_position) < ROUTE_POINT_SPACING:
		return
	var bounded_position: Vector2 = bounds.clamp_position(world_position)
	route_points.append(bounded_position)
	route_line.add_point(bounded_position)


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
	route_confirmed = true
	route_index = 1
	active_runway = null
	route_line.hide()


func _follow_drawn_route(delta: float) -> void:
	var distance_left := current_speed * delta
	while route_index < route_points.size() and distance_left > 0.0:
		var target := route_points[route_index]
		var offset := target - plane.global_position
		var distance := offset.length()
		if distance <= distance_left:
			if distance > 0.0:
				direction = offset / distance
				plane.global_rotation = direction.angle() + plane_art_angle_offset
			plane.global_position = target
			distance_left -= distance
			route_index += 1
			if _update_runway_traversal():
				return
			continue
		direction = offset / distance
		plane.global_position += direction * distance_left
		plane.global_rotation = direction.angle() + plane_art_angle_offset
		if _update_runway_traversal():
			return
		distance_left = 0.0
	if route_index >= route_points.size():
		if route_points.size() >= 2:
			direction = (route_points[-1] - route_points[-2]).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.RIGHT
		route_confirmed = false
		active_runway = null


func _update_runway_traversal() -> bool:
	if active_runway == null:
		var entered_runway := _get_runway_at_position(plane.global_position)
		if entered_runway == null:
			return false
		var entered_point := entered_runway.to_local(plane.global_position)
		var entered_half_size := (entered_runway.shape as RectangleShape2D).size * 0.5
		if absf(entered_point.x) < entered_half_size.x - RUNWAY_ENTRY_MARGIN:
			return false
		runway_entry_side = signf(entered_point.x)
		runway_travel_sign = -runway_entry_side
		var entry_local_direction := entered_runway.global_transform.basis_xform_inv(direction).normalized()
		if entry_local_direction.x * runway_travel_sign <= 0.0 or absf(entry_local_direction.y) > 0.2:
			return false
		active_runway = entered_runway
		runway_entry_x = entered_point.x
		runway_entry_y = entered_point.y
		runway_entry_angle = entry_local_direction.angle()
		runway_line_slope = entry_local_direction.y / entry_local_direction.x
		return false

	var local_position := active_runway.to_local(plane.global_position)
	var half_size := (active_runway.shape as RectangleShape2D).size * 0.5
	var current_local_direction := active_runway.global_transform.basis_xform_inv(direction).normalized()
	var expected_y := runway_entry_y + (local_position.x - runway_entry_x) * runway_line_slope
	var heading_change := absf(wrapf(current_local_direction.angle() - runway_entry_angle, -PI, PI))
	var crossed_full_runway := (local_position.x * runway_travel_sign) >= half_size.x
	if crossed_full_runway:
		if absf(local_position.y - expected_y) <= RUNWAY_TRACK_TOLERANCE and absf(expected_y) <= half_size.y and heading_change <= RUNWAY_HEADING_TOLERANCE and current_local_direction.x * runway_travel_sign > 0.0:
			_finish_landing()
			return true
		active_runway = null
		return false

	var still_on_runway := _get_runway_at_position(plane.global_position) == active_runway
	var straight_and_centered := (
		current_local_direction.x * runway_travel_sign > 0.0
		and heading_change <= RUNWAY_HEADING_TOLERANCE
		and absf(local_position.y - expected_y) <= RUNWAY_TRACK_TOLERANCE
		and absf(expected_y) <= half_size.y
	)
	if not still_on_runway or not straight_and_centered:
		active_runway = null
	return false


func _get_runway_at_position(world_position: Vector2) -> CollisionShape2D:
	for runway in find_children("*", "Area2D", true, false):
		if not runway.name.to_lower().contains("airport"):
			continue
		if not runway.has_node("CollisionShape2D"):
			continue
		var runway_shape := runway.get_node("CollisionShape2D") as CollisionShape2D
		if runway_shape.disabled or not runway_shape.shape is RectangleShape2D:
			continue
		var shape_point := runway_shape.to_local(world_position)
		var half_size := (runway_shape.shape as RectangleShape2D).size * 0.5
		if absf(shape_point.x) <= half_size.x and absf(shape_point.y) <= half_size.y:
			return runway_shape
	return null


func _finish_landing() -> void:
	plane_landed = true
	route_confirmed = false
	is_drawing_route = false
	route_line.hide()
	plane.hide()
	if movement_audio:
		movement_audio.stop()
