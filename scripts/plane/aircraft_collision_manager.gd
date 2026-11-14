extends Node

var world: Node
var explosion_template: AnimatedSprite2D


func setup(world_node: Node, template: AnimatedSprite2D) -> void:
	world = world_node
	explosion_template = template


func check_collisions(aircraft: Array[Dictionary]) -> void:
	var first_index := 0
	while first_index < aircraft.size():
		var first_state: Dictionary = aircraft[first_index]
		var first_plane := first_state["plane"] as CharacterBody2D
		if not is_instance_valid(first_plane) or not first_plane.visible or bool(first_state.get("landed", false)):
			first_index += 1
			continue

		var second_index := first_index + 1
		var collision_handled := false
		while second_index < aircraft.size():
			var second_state: Dictionary = aircraft[second_index]
			var second_plane := second_state["plane"] as CharacterBody2D
			if not is_instance_valid(second_plane) or not second_plane.visible or bool(second_state.get("landed", false)):
				second_index += 1
				continue

			if _aircraft_overlap(first_plane, second_plane):
				var impact_position := (first_plane.global_position + second_plane.global_position) * 0.5
				world.call("_on_aircraft_collision", first_plane, second_plane, impact_position)
				aircraft.remove_at(second_index)
				aircraft.remove_at(first_index)
				first_plane.queue_free()
				second_plane.queue_free()
				_play_explosion(impact_position)
				collision_handled = true
				break
			second_index += 1
		if collision_handled:
			continue
		first_index += 1


func _aircraft_overlap(first_plane: CharacterBody2D, second_plane: CharacterBody2D) -> bool:
	var first_box := _get_collision_box(first_plane)
	var second_box := _get_collision_box(second_plane)
	if first_box.is_empty() or second_box.is_empty():
		return false

	var center_delta: Vector2 = second_box["center"] - first_box["center"]
	var axes: Array[Vector2] = [
		first_box["axis_x"], first_box["axis_y"],
		second_box["axis_x"], second_box["axis_y"]
	]
	for axis in axes:
		var distance := absf(center_delta.dot(axis))
		if distance > _projection_radius(first_box, axis) + _projection_radius(second_box, axis):
			return false
	return true


func _get_collision_box(aircraft_node: CharacterBody2D) -> Dictionary:
	var shape_node := aircraft_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.disabled or not shape_node.shape is RectangleShape2D:
		return {}

	var rectangle := shape_node.shape as RectangleShape2D
	var transform := shape_node.global_transform
	return {
		"center": shape_node.global_position,
		"axis_x": transform.x.normalized(),
		"axis_y": transform.y.normalized(),
		"half_width": rectangle.size.x * transform.x.length() * 0.5,
		"half_height": rectangle.size.y * transform.y.length() * 0.5
	}


func _projection_radius(box: Dictionary, axis: Vector2) -> float:
	var axis_x: Vector2 = box["axis_x"]
	var axis_y: Vector2 = box["axis_y"]
	return (
		float(box["half_width"]) * absf(axis.dot(axis_x))
		+ float(box["half_height"]) * absf(axis.dot(axis_y))
	)


func _play_explosion(world_position: Vector2) -> void:
	if explosion_template == null or explosion_template.sprite_frames == null:
		push_warning("Aircraft collision: assign a SpriteFrames resource to World/ExplosionTemplate.")
		return
	var animation_name := "explode"
	if not explosion_template.sprite_frames.has_animation(animation_name):
		animation_name = "default"
	if not explosion_template.sprite_frames.has_animation(animation_name):
		push_warning("Aircraft collision: ExplosionTemplate needs an 'explode' or 'default' animation.")
		return

	var explosion := explosion_template.duplicate() as AnimatedSprite2D
	explosion.sprite_frames.set_animation_loop(animation_name, false)
	world.add_child(explosion)
	explosion.global_position = world_position
	explosion.show()
	explosion.animation_finished.connect(explosion.queue_free)
	explosion.play(animation_name)
