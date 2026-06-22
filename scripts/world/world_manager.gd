class_name WorldManager
extends Node

@export var player_scene: PackedScene

@onready var _players: Node3D = %Players


func _ready() -> void:
	_players.add_to_group("players")
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	print("[WorldManager] _ready: is_host=%s my_id=%d" % [MultiplayerManager.is_host(), MultiplayerManager.get_my_id()])
	if MultiplayerManager.is_host():
		_spawn_player(1)
	elif MultiplayerManager.get_my_id() != 0:
		_spawn_player(MultiplayerManager.get_my_id())


func _on_connection_succeeded() -> void:
	if not MultiplayerManager.is_host() and MultiplayerManager.get_my_id() != 0:
		_spawn_player(MultiplayerManager.get_my_id())


func _on_peer_connected(peer_id: int) -> void:
	print("[WorldManager] Peer %d connected" % peer_id)
	_spawn_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[WorldManager] Peer %d disconnected" % peer_id)
	_despawn_player(peer_id)


func _spawn_player(peer_id: int) -> void:
	if _players.get_node_or_null(_player_name(peer_id)):
		return
	var player: Node3D = player_scene.instantiate()
	player.name = _player_name(peer_id)
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player)
	if peer_id == MultiplayerManager.get_my_id():
		_place_player_on_terrain(player)
		player.player_wrapped.connect(_on_local_player_wrapped)
	print("[WorldManager] Spawned player for peer %d (total: %d)" % [peer_id, _players.get_child_count()])


func _on_local_player_wrapped() -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm:
		cm.rewrap_remote_players()


func _place_player_on_terrain(player: Node3D) -> void:
	_place_player_on_terrain_deferred.call_deferred(player)


func _place_player_on_terrain_deferred(player: Node3D) -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm == null or cm.get_world_data() == null:
		push_warning("[WorldManager] No ChunkManager found after deferral, player stays at origin")
		return
	var spawn_x: float = float(cm.get_world_data().chunk_size) * 0.5
	var spawn_z: float = float(cm.get_world_data().chunk_size) * 0.5
	var terrain_y: float = cm.get_terrain_height(spawn_x, spawn_z)
	player.global_position = Vector3(spawn_x, terrain_y + 1.0, spawn_z)
	print("[WorldManager] Placed player at (%.1f, %.1f, %.1f)" % [spawn_x, terrain_y + 1.0, spawn_z])
	var pc: PlayerController = player as PlayerController
	if pc and pc.is_multiplayer_authority():
		pc.rpc("initial_sync", player.global_position, pc.camera_yaw)


func _despawn_player(peer_id: int) -> void:
	var player := _players.get_node_or_null(_player_name(peer_id))
	if player:
		player.queue_free()
		print("[WorldManager] Despawned player for peer %d" % peer_id)


func _player_name(peer_id: int) -> String:
	return "Player_%d" % peer_id
