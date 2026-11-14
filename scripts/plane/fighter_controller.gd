extends Node

var world
var fighter_plane: CharacterBody2D

var flight_speed: float = 850.0
var shoot_radius: float = 65.0
var shoot_cooldown: float = 0.25
var visual_rotation_offset_degrees: float = 0.0

var shoot_cooldown_left: float = 0.0


func setup(
	world_node: Node,
	fighter_node: CharacterBody2D,
	new_flight_speed: float,
	new_shoot_radius: float,
	new_shoot_cooldown: float,
	new_rotation_offset_degrees: float
) -> void:
	world = world_node
	fighter_plane = fighter_node
	flight_speed = new_flight_speed
	shoot_radius = new_shoot_radius
	shoot_cooldown = new_shoot_cooldown
	visual_rotation_offset_degrees = new_rotation_offset_degrees

	fighter_plane.hide()
	fighter_plane.set_physics_process(false)


func activate() -> void:
	if not is_instance_valid(fighter_plane):
		return

	fighter_plane.global_position = world.plane.global_position
	fighter_plane.velocity = Vector2.ZERO
	fighter_plane.show()
	fighter_plane.set_physics_process(true)
	shoot_cooldown_left = 0.0


func deactivate() -> void:
	if not is_instance_valid(fighter_plane):
		return

	fighter_plane.velocity = Vector2.ZERO
	fighter_plane.hide()
	fighter_plane.set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not world.ultimate_active or not is_instance_valid(fighter_plane):
		return

	shoot_cooldown_left = maxf(0.0, shoot_cooldown_left - delta)

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


func _unhandled_input(event: InputEvent) -> void:
	if not world.ultimate_active or not is_instance_valid(fighter_plane):
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if shoot_cooldown_left > 0.0:
			return

		shoot_cooldown_left = shoot_cooldown
		world.try_shoot_aircraft(fighter_plane.get_global_mouse_position(), shoot_radius)
