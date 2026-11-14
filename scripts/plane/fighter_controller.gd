extends Node

var world: Node
var fighter_plane: CharacterBody2D
var flight_speed: float = 850.0
var visual_rotation_offset_degrees: float = 0.0


func setup(
	world_node: Node,
	fighter_node: CharacterBody2D,
	new_flight_speed: float,
	new_rotation_offset_degrees: float
) -> void:
	world = world_node
	fighter_plane = fighter_node
	flight_speed = new_flight_speed
	visual_rotation_offset_degrees = new_rotation_offset_degrees

	fighter_plane.velocity = Vector2.ZERO
	fighter_plane.hide()
	fighter_plane.set_physics_process(false)


func activate() -> void:
	if not is_instance_valid(fighter_plane):
		return

	fighter_plane.global_position = world.plane.global_position
	fighter_plane.velocity = Vector2.ZERO
	fighter_plane.show()
	fighter_plane.set_physics_process(true)


func deactivate() -> void:
	if not is_instance_valid(fighter_plane):
		return

	fighter_plane.velocity = Vector2.ZERO
	fighter_plane.hide()
	fighter_plane.set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(fighter_plane) or not world.ultimate_active:
		return

	var input_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_direction.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_direction.x += 1.0

	input_direction = input_direction.normalized()
	fighter_plane.velocity = input_direction * flight_speed

	if input_direction != Vector2.ZERO:
		fighter_plane.rotation = input_direction.angle() + deg_to_rad(visual_rotation_offset_degrees)

	fighter_plane.move_and_slide()
	fighter_plane.global_position = world.bounds.clamp_position(fighter_plane.global_position)
