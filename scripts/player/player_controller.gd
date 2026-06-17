class_name PlayerController
extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_multiplier: float = 2.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	set_physics_process(is_multiplayer_authority())


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement()
	move_and_slide()
	# Sync transform if this peer owns the player and the session is active
	if (
		is_multiplayer_authority()
		and multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and not multiplayer.get_peers().is_empty()
	):
		rpc("sync_transform", global_transform.origin, rotation.y)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= gravity * gravity_multiplier * delta

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

func _handle_movement() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Get yaw from the camera pivot (our parent's rotation).
	var camera_yaw: float = 0.0
	var pivot := get_node_or_null("CameraPivot")
	if pivot:
		camera_yaw = pivot.rotation.y
	var forward := Vector3(0, 0, -1).rotated(Vector3.UP, camera_yaw)
	var right := Vector3(1, 0, 0).rotated(Vector3.UP, camera_yaw)
	var direction := (-forward * input_dir.y + right * input_dir.x).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if direction.length() > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if _mesh:
			_mesh.rotation.y = atan2(direction.x, direction.z) + camera_yaw
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, rot_y: float) -> void:
	if not is_multiplayer_authority():
		global_transform.origin = pos
		rotation.y = rot_y
