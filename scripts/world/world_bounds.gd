extends RefCounted
class_name WorldBounds


var rect: Rect2


func _init(bounds: Rect2) -> void:
	rect = bounds


func is_valid() -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0


func clamp_position(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, rect.position.x, rect.end.x),
		clampf(position.y, rect.position.y, rect.end.y)
	)
