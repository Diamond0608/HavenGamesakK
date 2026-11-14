
extends CharacterBody2D

@export var flight_speed: float = 850.0
@export var shoot_radius: float = 65.0
@export var shoot_cooldown: float = 0.25
@export var visual_rotation_offset_degrees: float = 90.0

var world: Node
var can_shoot: bool = true


func _ready() -> void:
	world = get_parent()
	set_process(false)
	hide()


func _physics_process(_delta: float) -> void:
	if not world or not world.ultimate_active:
		velocity = Vector2.ZERO
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
	velocity = input_direction * flight_speed

	if velocity.length_squared() > 0.0:
		rotation = velocity.angle() + deg_to_rad(visual_rotation_offset_degrees)

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not world or not world.ultimate_active:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_fire_at_mouse()


func _fire_at_mouse() -> void:
	if not can_shoot:
		return

	can_shoot = false

	var target_position := get_global_mouse_position()
	world.try_shoot_aircraft(target_position, shoot_radius)

	await get_tree().create_timer(shoot_cooldown).timeout
	can_shoot = true


func activate() -> void:
	global_position = world.plane.global_position
	show()
	set_process(true)
	set_physics_process(true)


func deactivate() -> void:
	hide()
	velocity = Vector2.ZERO
	set_process(false)
	set_physics_process(false)
