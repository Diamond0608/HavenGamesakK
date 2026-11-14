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

	# The scene's legacy fighter script also handled movement/input.
	# Remove it so this controller is the single owner of fighter behaviour.
	fighter_plane.set_script(null)

	var fighter_sprite := fighter_plane.get_node_or_null("Sprite2D") as Sprite2D
	if fighter_sprite != null:
		fighter_sprite.position = Vector2.ZERO

	var fighter_collision := fighter_plane.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if fighter_collision != null:
		fighter_collision.position = Vector2.ZERO
		fighter_collision.rotation = 0.0
		fighter_collision.scale = Vector2.ONE
		if fighter_collision.shape is RectangleShape2D:
			fighter_collision.shape = fighter_collision.shape.duplicate()
			(fighter_collision.shape as RectangleShape2D).size = Vector2(60, 50)

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
