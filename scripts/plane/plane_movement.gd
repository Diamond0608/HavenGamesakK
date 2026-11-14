extends RefCounted


const MAX_BOUNCES_PER_FRAME: int = 64


static func advance(
	start_position: Vector2,
	start_direction: Vector2,
	start_speed: float,
	delta: float,
	bounds: Rect2,
	maximum_speed: float
) -> Dictionary:
	var position := start_position
	var direction := start_direction.normalized()
	var speed := minf(start_speed, maximum_speed)
	var time_left := maxf(delta, 0.0)
	var bounce_count := 0

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	if not bounds_is_valid(bounds) or speed <= 0.0 or maximum_speed <= 0.0:
		return {
			"position": position,
			"direction": direction,
			"speed": speed,
			"bounces": bounce_count
		}

	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)

	while time_left > 0.0 and bounce_count < MAX_BOUNCES_PER_FRAME:
		var time_to_x_edge := INF
		var time_to_y_edge := INF

		if direction.x > 0.0:
			time_to_x_edge = (bounds.end.x - position.x) / (direction.x * speed)
		elif direction.x < 0.0:
			time_to_x_edge = (bounds.position.x - position.x) / (direction.x * speed)

		if direction.y > 0.0:
			time_to_y_edge = (bounds.end.y - position.y) / (direction.y * speed)
		elif direction.y < 0.0:
			time_to_y_edge = (bounds.position.y - position.y) / (direction.y * speed)

		var time_to_edge := minf(time_to_x_edge, time_to_y_edge)

		if time_to_edge == INF or time_to_edge >= time_left:
			position += direction * speed * time_left
			time_left = 0.0
		else:
			position += direction * speed * time_to_edge
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.y = clampf(position.y, bounds.position.y, bounds.end.y)
			time_left -= time_to_edge
			direction = -direction
			speed = minf(speed * 2.0, maximum_speed)
			bounce_count += 1

	return {
		"position": position,
		"direction": direction,
		"speed": speed,
		"bounces": bounce_count
	}


static func bounds_is_valid(bounds: Rect2) -> bool:
	return bounds.size.x > 0.0 and bounds.size.y > 0.0
