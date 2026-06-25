class_name NetworkSync
extends Node

var _entity: CharacterBody3D
var _sync_enabled: bool = false
var _initial_sync_sent: bool = false


func _ready() -> void:
	var parent := get_parent()
	if parent is CharacterBody3D:
		_entity = parent as CharacterBody3D


func enable_sync() -> void:
	_sync_enabled = true
	print("[NS:%d] enable_sync on %s" % [MultiplayerManager.get_my_id(), get_parent().name if get_parent() else "?"])


func disable_sync() -> void:
	_sync_enabled = false
	print("[NS:%d] disable_sync on %s" % [MultiplayerManager.get_my_id(), get_parent().name if get_parent() else "?"])


func send_initial_sync() -> void:
	if _entity == null or not _entity.is_multiplayer_authority():
		return
	if not _is_connected():
		print("[NS:%d] send_initial_sync on %s skipped: not connected" % [MultiplayerManager.get_my_id(), get_parent().name if get_parent() else "?"])
		return
	print("[NS:%d] send_initial_sync on %s pos=%s yaw=%.2f" % [MultiplayerManager.get_my_id(), get_parent().name, str(_entity.global_transform.origin), _entity.camera_yaw])
	rpc("initial_sync", _entity.global_transform.origin, _entity.camera_yaw)
	_initial_sync_sent = true


func _physics_process(_delta: float) -> void:
	if not _sync_enabled or _entity == null:
		return
	if not _entity.is_multiplayer_authority():
		return
	if not _is_connected():
		return
	rpc("sync_transform", _entity.global_transform.origin, _entity.camera_yaw)


func _is_connected() -> bool:
	return (
		multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and not multiplayer.get_peers().is_empty()
	)


@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, yaw: float) -> void:
	if _entity == null or _entity.is_multiplayer_authority():
		return
	var wd := _get_world_data()
	if wd:
		var ref: Vector3 = _get_local_authority_position()
		pos = TorusUtils.wrap_vector3_near(pos, ref, wd)
	_entity.global_transform.origin = pos
	_entity.camera_yaw = yaw


@rpc("authority", "reliable")
func initial_sync(pos: Vector3, yaw: float) -> void:
	if _entity == null or _entity.is_multiplayer_authority():
		return
	var wd := _get_world_data()
	if wd:
		var ref: Vector3 = _get_local_authority_position()
		pos = TorusUtils.wrap_vector3_near(pos, ref, wd)
	_entity.global_transform.origin = pos
	_entity.camera_yaw = yaw


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
