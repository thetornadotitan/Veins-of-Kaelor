class_name SignalingServer
extends Node

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

const DEFAULT_PORT: int = 9080

var _tcp_server: TCPServer = null
var _peers: Dictionary = {}
var _next_id: int = 1
var _running: bool = false

var port: int = DEFAULT_PORT


class PeerData:
	var id: int
	var ws: WebSocketPeer
	var ready: bool = false

	func _init(p_id: int, p_ws: WebSocketPeer) -> void:
		id = p_id
		ws = p_ws


func start(p_port: int = DEFAULT_PORT) -> Error:
	port = p_port
	stop()
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(port)
	if err != OK:
		push_error("Signaling: Failed to listen on port %d" % port)
		return err
	_running = true
	print("Signaling: Listening on port %d" % port)
	set_process(true)
	return OK


func stop() -> void:
	_running = false
	set_process(false)
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null
	for id: int in _peers:
		_peers[id].ws.close()
	_peers.clear()
	print("Signaling: Stopped")


func is_running() -> bool:
	return _running


func _process(_delta: float) -> void:
	if not _running:
		return

	# Accept new TCP connections.
	while _tcp_server.is_connection_available():
		var id := _next_id
		_next_id += 1
		var ws := WebSocketPeer.new()
		ws.accept_stream(_tcp_server.take_connection())
		_peers[id] = PeerData.new(id, ws)
		print("Signaling: Accepted TCP connection for peer %d" % id)

	# Poll all peers.
	var to_remove: Array[int] = []
	for id: int in _peers:
		var peer: PeerData = _peers[id]
		peer.ws.poll()

		if peer.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			print("Signaling: Peer %d disconnected" % id)
			to_remove.append(id)
			peer_disconnected.emit(id)
			continue

		# Wait for WebSocket handshake to complete before sending ID.
		if not peer.ready and peer.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.ready = true
			_send_to(id, "ID", id, str(id))
			print("Signaling: Peer %d ready, sent ID" % id)
			peer_connected.emit(id)

		# Relay messages from this peer.
		while peer.ws.get_available_packet_count():
			var packet: PackedByteArray = peer.ws.get_packet()
			if peer.ws.was_string_packet():
				_handle_message(id, packet.get_string_from_utf8())

	for id: int in to_remove:
		_peers.erase(id)


func _handle_message(from_id: int, text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var msg: Dictionary = json.get_data()
	var msg_type: String = msg.get("type", "")
	var to_id: int = msg.get("to", 0)
	var data: String = msg.get("data", "")

	match msg_type:
		"JOIN", "OFFER", "ANSWER", "CANDIDATE":
			_relay(from_id, to_id, msg_type, data)


func _relay(from_id: int, to_id: int, msg_type: String, data: String) -> void:
	if to_id == 0:
		# Broadcast to all peers except sender.
		for other_id: int in _peers:
			if other_id != from_id:
				_send_to(other_id, msg_type, from_id, data)
	elif _peers.has(to_id):
		_send_to(to_id, msg_type, from_id, data)


func _send_to(to_id: int, msg_type: String, from_id: int, data: String) -> void:
	if not _peers.has(to_id):
		return
	var peer: PeerData = _peers[to_id]
	if not peer.ready:
		return
	var msg := {"type": msg_type, "id": from_id, "data": data}
	peer.ws.send_text(JSON.stringify(msg))
