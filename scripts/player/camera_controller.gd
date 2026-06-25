class_name CameraController
extends Camera3D

## Camera settings — exported for tuning.
@export var mouse_sensitivity: float = 0.002
@export var min_pitch: float = -80.0
@export var max_pitch: float = 80.0

var _pitch: float = 0.0
var _yaw: float = 0.0

@onready var _pivot: Node3D = get_parent()


func _ready() -> void:
	var is_auth: bool = is_multiplayer_authority()
	set_process(is_auth)
	set_process_unhandled_input(is_auth)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		# Yaw rotates the pivot (orbits camera around player).
		# Pitch rotates the camera itself (look up/down).
		_pivot.rotation.y = _yaw
		rotation.x = _pitch
