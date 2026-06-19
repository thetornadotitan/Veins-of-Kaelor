class_name WorldManager
extends Node

@export var player_scene: PackedScene

@onready var _players: Node3D = %Players


func _ready() -> void:
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	# Host spawns its own player (ID 1) immediately.
	# Clients need to spawn their local player once their ID is known.
	if MultiplayerManager.is_host():
		_spawn_player(1)
	elif MultiplayerManager.get_my_id() != 0:
		# Client has already received its ID before the world loaded.
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
	print("[WorldManager] Spawned player for peer %d (total: %d)" % [peer_id, _players.get_child_count()])


func _despawn_player(peer_id: int) -> void:
	var player := _players.get_node_or_null(_player_name(peer_id))
	if player:
		player.queue_free()
		print("[WorldManager] Despawned player for peer %d" % peer_id)


func _player_name(peer_id: int) -> String:
	return "Player_%d" % peer_id
