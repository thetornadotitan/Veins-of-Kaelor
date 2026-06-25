extends Node

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()

@export var relay_port: int = 9080
@export var relay_address: String = "127.0.0.1"

var _ws_mp: WebSocketMultiplayerPeer = null
var _my_id: int = 0
var _is_host: bool = false
var _connected_peers: Dictionary = {}
var _connection_succeeded_emitted: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	if "--server" in OS.get_cmdline_user_args():
		_start_dedicated_server()


func _on_mp_peer_connected(peer_id: int) -> void:
	_connected_peers[peer_id] = true
	print("[MP:%d] multiplayer.peer_connected id=%d" % [_my_id, peer_id])
	peer_connected.emit(peer_id)


func _on_mp_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	print("[MP:%d] multiplayer.peer_disconnected id=%d" % [_my_id, peer_id])
	peer_disconnected.emit(peer_id)


func _start_dedicated_server() -> void:
	_is_host = true
	_ws_mp = WebSocketMultiplayerPeer.new()
	var err := _ws_mp.create_server(relay_port)
	if err != OK:
		push_error("Failed to start dedicated relay server on port %d" % relay_port)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = _ws_mp
	_my_id = 1
	print("Dedicated relay server running on port %d" % relay_port)
	set_process(true)


func host_game() -> void:
	if is_peer_connected():
		disconnect_game()

	_is_host = true
	_connection_succeeded_emitted = false
	_ws_mp = WebSocketMultiplayerPeer.new()
	var err := _ws_mp.create_server(relay_port)
	if err != OK:
		push_error("Failed to start relay server on port %d: %s" % [relay_port, error_string(err)])
		_ws_mp = null
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = _ws_mp
	_my_id = _ws_mp.get_unique_id()
	print("[MP:%d] host: relay server started on port %d" % [_my_id, relay_port])
	set_process(true)


func join_game() -> void:
	if is_peer_connected():
		disconnect_game()

	_is_host = false
	_connection_succeeded_emitted = false
	_ws_mp = WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [relay_address, relay_port]
	var err := _ws_mp.create_client(url)
	if err != OK:
		push_error("Failed to connect to relay server: %s" % error_string(err))
		_ws_mp = null
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = _ws_mp
	_my_id = _ws_mp.get_unique_id()
	print("[MP:%d] join: connecting to %s" % [_my_id, url])
	set_process(true)


func disconnect_game() -> void:
	set_process(false)
	_teardown()


func _teardown() -> void:
	if _ws_mp:
		_ws_mp.close()
		_ws_mp = null
	multiplayer.multiplayer_peer = null
	_my_id = 0
	_is_host = false
	_connected_peers.clear()
	_connection_succeeded_emitted = false


func _process(_delta: float) -> void:
	if not _ws_mp:
		return

	_ws_mp.poll()

	var status := _ws_mp.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if not _connection_succeeded_emitted:
			print("[MP:%d] connection failed or lost" % _my_id)
			connection_failed.emit()
			_teardown()
		else:
			print("[MP:%d] disconnected from relay" % _my_id)
			_teardown()
			peer_disconnected.emit(0)
		return

	if status == MultiplayerPeer.CONNECTION_CONNECTED and not _connection_succeeded_emitted:
		_my_id = _ws_mp.get_unique_id()
		print("[MP:%d] connected to relay, emitting connection_succeeded" % _my_id)
		_connection_succeeded_emitted = true
		connection_succeeded.emit()


func is_relay_ready() -> bool:
	if _my_id == 0:
		return false
	if _ws_mp == null:
		return false
	if _ws_mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	if _is_host:
		return true
	return not _connected_peers.is_empty()


func is_webrtc_ready() -> bool:
	return is_relay_ready()


func is_peer_connected() -> bool:
	if _ws_mp == null:
		return false
	var status := _ws_mp.get_connection_status()
	return status == MultiplayerPeer.CONNECTION_CONNECTED


func get_my_id() -> int:
	return _my_id


func is_host() -> bool:
	return _is_host


func get_peer_count() -> int:
	if not is_peer_connected():
		return 0
	return _connected_peers.size() + 1


func is_peer_webrtc_connected(peer_id: int) -> bool:
	return _connected_peers.has(peer_id)
