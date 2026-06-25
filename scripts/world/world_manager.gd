class_name WorldManager
extends Node

@export var player_scene: PackedScene

@onready var _players: Node3D = %Players


func _ready() -> void:
	_players.add_to_group("players")
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.multiplayer_peer != null:
		var my_id: int = MultiplayerManager.get_my_id()
		for peer_id: int in multiplayer.get_peers():
			if peer_id != my_id:
				print("[WM:%d] _ready: spawning remote peer %d" % [my_id, peer_id])
				_spawn_player(peer_id)


func spawn_initial_players() -> void:
	var my_id: int = MultiplayerManager.get_my_id()
	if my_id != 0:
		print("[WM:%d] spawn_initial_players: spawning local player" % my_id)
		var player := _spawn_player(my_id)
		if player:
			_place_player_on_terrain(player)
			print("[WM:%d] spawn_initial_players: placed at %s" % [my_id, str(player.global_position)])
			var ns: NetworkSync = player.get_node_or_null("NetworkSync")
			if ns:
				ns.send_initial_sync()
				print("[WM:%d] spawn_initial_players: sent initial_sync" % my_id)


func _on_peer_connected(peer_id: int) -> void:
	print("[WM:%d] _on_peer_connected: peer %d, current state=%s" % [MultiplayerManager.get_my_id(), peer_id, GameStateController.State.find_key(GameStateController.get_state())])
	var player := _spawn_player(peer_id)
	if player and GameStateController.get_state() == GameStateController.State.PLAYING:
		var ns: NetworkSync = player.get_node_or_null("NetworkSync")
		if ns:
			ns.enable_sync()
			print("[WM:%d] _on_peer_connected: enabled sync for late-joining peer %d" % [MultiplayerManager.get_my_id(), peer_id])


func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)


func _spawn_player(peer_id: int) -> Node3D:
	if _players.get_node_or_null(_player_name(peer_id)):
		print("[WM:%d] _spawn_player(%d) skipped: already exists" % [MultiplayerManager.get_my_id(), peer_id])
		return null
	print("[WM:%d] _spawn_player(%d): instantiating player" % [MultiplayerManager.get_my_id(), peer_id])
	var player: Node3D = player_scene.instantiate()
	player.name = _player_name(peer_id)
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player)
	print("[WM:%d] _spawn_player(%d): added to tree, authority=%d" % [MultiplayerManager.get_my_id(), peer_id, peer_id])
	if peer_id == MultiplayerManager.get_my_id():
		player.player_wrapped.connect(_on_local_player_wrapped)
	return player


func _on_local_player_wrapped() -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm:
		cm.rewrap_remote_players()


func _place_player_on_terrain(player: Node3D) -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm == null or cm.get_world_data() == null:
		return
	var spawn_x: float = float(cm.get_world_data().chunk_size) * 0.5
	var spawn_z: float = float(cm.get_world_data().chunk_size) * 0.5
	var terrain_y: float = cm.get_terrain_height(spawn_x, spawn_z)
	player.global_position = Vector3(spawn_x, terrain_y + 1.0, spawn_z)


func _despawn_player(peer_id: int) -> void:
	print("[WM:%d] _despawn_player(%d)" % [MultiplayerManager.get_my_id(), peer_id])
	var player := _players.get_node_or_null(_player_name(peer_id))
	if player:
		player.queue_free()


func _player_name(peer_id: int) -> String:
	return "Player_%d" % peer_id
