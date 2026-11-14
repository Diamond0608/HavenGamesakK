
extends Area2D

signal destination_clicked(destination: Area2D)


func _ready() -> void:
	input_pickable = true


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			destination_clicked.emit(self)
