
extends Node

@export var world_bounds: Rect2 = Rect2(
	Vector2(-808, -488),
	Vector2(1381, 890)
)

@export var initial_speed: float = 100.0
@export var initial_direction: Vector2 = Vector2.RIGHT

@export var plane_path: NodePath = ^"CharacterBody2"

var plane: CharacterBody2D
var current_speed: float
var direction: Vector2


func _ready() -> void:
	plane = get_node(plane_path) as CharacterBody2D

	current_speed = initial_speed
	direction = initial_direction.normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT


func _physics_process(delta: float) -> void:
	var next_position = plane.global_position + direction * current_speed * delta

	var hit_x = (
		next_position.x < world_bounds.position.x
		or next_position.x > world_bounds.end.x
	)

	var hit_y = (
		next_position.y < world_bounds.position.y
		or next_position.y > world_bounds.end.y
	)

	if hit_x or hit_y:
		direction = -direction
		current_speed *= 2.0
		plane.rotation += PI

	next_position.x = clampf(
		next_position.x,
		world_bounds.position.x,
		world_bounds.end.x
	)

	next_position.y = clampf(
		next_position.y,
		world_bounds.position.y,
		world_bounds.end.y
	)

	plane.global_position = next_position
