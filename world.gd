extends Node

const PlaneMovement = preload("res://scripts/plane/plane_movement.gd")
const WorldBounds = preload("res://scripts/world/world_bounds.gd")

@export var world_bounds: Rect2 = Rect2(
	Vector2(-808, -488),
	Vector2(1381, 890)
)

@export var initial_speed: float = 100.0
@export var initial_direction: Vector2 = Vector2.RIGHT
@export var max_speed: float = 20000.0

@export var plane_path: NodePath = ^"CharacterBody2"

var plane: CharacterBody2D
var current_speed: float
var direction: Vector2
var bounds: RefCounted


func _ready() -> void:
	plane = get_node_or_null(plane_path) as CharacterBody2D

	if plane == null:
		push_error("World: Plane not found at plane_path: " + str(plane_path))
		set_physics_process(false)
		return

	bounds = WorldBounds.new(world_bounds)

	if not bounds.is_valid():
		push_error("World: world_bounds must have a positive width and height.")
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
	var result: Dictionary = PlaneMovement.advance(
		plane.global_position,
		direction,
		current_speed,
		delta,
		world_bounds,
		max_speed
	)

	plane.global_position = result.position
	direction = result.direction
	current_speed = result.speed

	if result.bounces > 0:
		plane.rotation += PI * float(result.bounces)
