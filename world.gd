extends Node

const PlaneMovementScript = preload("res://scripts/plane/plane_movement.gd")
const WorldBoundsScript = preload("res://scripts/world/world_bounds.gd")

@export var initial_speed: float = 100.0
@export var initial_direction: Vector2 = Vector2.RIGHT
@export var max_speed: float = 20000.0

@export var plane_path: NodePath = ^"CharacterBody2D"
@export var tile_map_path: NodePath = ^"TileMapLayer2"

var plane: CharacterBody2D
var current_speed: float
var direction: Vector2
var world_bounds: Rect2
var bounds


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


func _physics_process(delta: float) -> void:
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

	if result["bounces"] > 0:
		plane.rotation += PI * float(result["bounces"])
