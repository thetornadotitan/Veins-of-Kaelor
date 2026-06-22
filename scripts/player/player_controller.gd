class_name PlayerController
extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_multiplier: float = 2.0

var camera_yaw: float = 0.0

signal player_wrapped

@onready var _visuals: DirectionalSpriteStack = %VisualController


func _ready() -> void:
	add_to_group("ghostable")
	set_physics_process(is_multiplayer_authority())
	if _visuals and is_multiplayer_authority():
		_visuals.initialize_default_styles()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_movement()
	move_and_slide()
	var did_wrap: bool = _wrap_world_coordinates()
	_update_camera_yaw()
	_sync_transform_if_needed()
	if did_wrap:
		player_wrapped.emit()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		velocity.y -= gravity * gravity_multiplier * delta


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


func _update_camera_yaw() -> void:
	var pivot := get_node_or_null("CameraPivot")
	if pivot:
		camera_yaw = pivot.rotation.y


func _handle_movement() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_yaw: float = 0.0
	var pivot := get_node_or_null("CameraPivot")
	if pivot:
		move_yaw = pivot.rotation.y
	var forward := Vector3(0, 0, -1).rotated(Vector3.UP, move_yaw)
	var right := Vector3(1, 0, 0).rotated(Vector3.UP, move_yaw)
	var direction := (-forward * input_dir.y + right * input_dir.x).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if direction.length() > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)


func _sync_transform_if_needed() -> void:
	if (
		is_multiplayer_authority()
		and multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and not multiplayer.get_peers().is_empty()
	):
		rpc("sync_transform", global_transform.origin, camera_yaw)


func _get_world_data() -> WorldData:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm:
		return cm.get_world_data()
	return null


func _get_local_authority_position() -> Vector3:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child.global_position
	return Vector3.ZERO


@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, yaw: float) -> void:
	if not is_multiplayer_authority():
		var wd := _get_world_data()
		if wd:
			var ref: Vector3 = _get_local_authority_position()
			pos = TorusUtils.wrap_vector3_near(pos, ref, wd)
		global_transform.origin = pos
		camera_yaw = yaw


@rpc("authority", "reliable")
func initial_sync(pos: Vector3, yaw: float) -> void:
	if not is_multiplayer_authority():
		var wd := _get_world_data()
		if wd:
			var ref: Vector3 = _get_local_authority_position()
			pos = TorusUtils.wrap_vector3_near(pos, ref, wd)
		global_transform.origin = pos
		camera_yaw = yaw


@rpc("authority", "reliable")
func equip_item(slot: String, style: String) -> void:
	if not _visuals:
		return
	_visuals.equip_item(slot, style)
	rpc("sync_equipment", _visuals.equipped_styles)


@rpc("any_peer", "reliable")
func sync_equipment(styles: Dictionary) -> void:
	if not _visuals:
		return
	var dup: Dictionary[String, String] = {}
	for key: String in styles:
		dup[key] = str(styles[key])
	_visuals.equipped_styles = dup


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F2:
				_randomize_equipment()


func _randomize_equipment() -> void:
	var slots: Array[String] = ["chest", "legs", "hands", "head"]
	var slot: String = slots[randi() % slots.size()]
	var sheet_id: String = _visuals.SHEET_MAP.get(slot, "")
	if sheet_id == "":
		return
	var sheet: SheetData = SpriteDatabaseLoader.get_sheet(sheet_id)
	if not sheet:
		return
	var style_list: Array[String] = []
	for s: String in sheet.styles:
		style_list.append(s)
	if style_list.is_empty():
		return
	var random_style: String = style_list[randi() % style_list.size()]
	rpc("equip_item", slot, random_style)


func _wrap_world_coordinates() -> bool:
	var chunk_manager: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if chunk_manager == null or chunk_manager.get_world_data() == null:
		return false
	var wd: WorldData = chunk_manager.get_world_data()
	var world_size_x: float = wd.world_size_x
	var world_size_z: float = wd.world_size_z
	var pos := global_position
	var wrapped := false
	if pos.x < 0.0:
		pos.x += world_size_x
		wrapped = true
	elif pos.x >= world_size_x:
		pos.x -= world_size_x
		wrapped = true
	if pos.z < 0.0:
		pos.z += world_size_z
		wrapped = true
	elif pos.z >= world_size_z:
		pos.z -= world_size_z
		wrapped = true
	if wrapped:
		global_position = pos
	return wrapped


func get_canonical_position() -> Vector3:
	return global_position


func create_ghost() -> Node3D:
	var ghost := GhostPlayer.new()
	ghost.source = self
	return ghost
