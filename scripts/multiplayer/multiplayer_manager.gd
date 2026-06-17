extends Node

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()

@export var signaling_port: int = 9080
@export var signaling_address: String = "127.0.0.1"

var _signaling: Node = null
var _rtc_mp: WebRTCMultiplayerPeer = null
var _ws: WebSocketPeer = null
var _my_id: int = 0
var _mesh: bool = true
var _pending_candidates: Dictionary = {}  # peer_id -> Array[String]
var _remote_desc_set: Dictionary = {}  # peer_id -> bool


func _on_mp_peer_connected(peer_id: int) -> void:
	print("Multiplayer: Peer %d connected (WebRTC data channel)" % peer_id)
	peer_connected.emit(peer_id)


func _on_mp_peer_disconnected(peer_id: int) -> void:
	print("Multiplayer: Peer %d disconnected" % peer_id)
	peer_disconnected.emit(peer_id)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	if "--server" in OS.get_cmdline_user_args():
		_start_dedicated_server()


func _start_dedicated_server() -> void:
	print("Starting dedicated signaling server on port %d..." % signaling_port)
	_signaling = SignalingServer.new()
	_signaling.name = "SignalingServer"
	add_child(_signaling)
	if _signaling.start(signaling_port) != OK:
		push_error("Failed to start dedicated signaling server")
		get_tree().quit(1)
	else:
		print("Dedicated signaling server running.")


func host_game() -> void:
	if is_peer_connected():
		disconnect_game()

	_signaling = SignalingServer.new()
	_signaling.name = "SignalingServer"
	add_child(_signaling)
	if _signaling.start(signaling_port) != OK:
		push_error("Failed to start signaling server on port %d" % signaling_port)
		_signaling.queue_free()
		_signaling = null
		connection_failed.emit()
		return
	print("Signaling server started on port %d" % signaling_port)

	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url("ws://127.0.0.1:%d" % signaling_port)
	if err != OK:
		push_error("Failed to connect to signaling server")
		_teardown()
		connection_failed.emit()
		return

	set_process(true)
	print("Host: Connected to signaling server, waiting for ID...")


func join_game() -> void:
	if is_peer_connected():
		disconnect_game()

	_mesh = true

	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url("ws://%s:%d" % [signaling_address, signaling_port])
	if err != OK:
		push_error("Failed to connect to signaling server: %s" % error_string(err))
		_teardown()
		connection_failed.emit()
		return

	set_process(true)
	print("Client: Connecting to signaling server...")


func disconnect_game() -> void:
	set_process(false)
	_teardown()


func _teardown() -> void:
	if _rtc_mp:
		_rtc_mp.close()
		_rtc_mp = null
	if _ws:
		_ws.close()
		_ws = null
	if _signaling:
		_signaling.stop()
		_signaling.queue_free()
		_signaling = null
	multiplayer.multiplayer_peer = null
	_my_id = 0
	_pending_candidates.clear()
	_remote_desc_set.clear()


func is_peer_connected() -> bool:
	return _my_id != 0 and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func get_my_id() -> int:
	return _my_id


func is_host() -> bool:
	return _signaling != null


func get_peer_count() -> int:
	if not is_peer_connected():
		return 0
	return multiplayer.get_peers().size() + 1


func _process(_delta: float) -> void:
	if not _ws:
		return

	_ws.poll()

	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return

	while _ws.get_available_packet_count():
		var packet: PackedByteArray = _ws.get_packet()
		if _ws.was_string_packet():
			_handle_signaling_message(packet.get_string_from_utf8())


func _handle_signaling_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var msg: Dictionary = json.get_data()
	var msg_type_raw: String = msg.get("type", "")
	var msg_type: String = msg_type_raw.to_upper()
	var from_id: int = msg.get("id", 0)
	var data: String = msg.get("data", "")

	print("Signaling: received type=%s from=%d" % [msg_type, from_id])

	match msg_type:
		"ID":
			if _my_id == 0:
				_my_id = data.to_int()
				print("Signaling: Assigned ID %d" % _my_id)
				_rtc_mp = WebRTCMultiplayerPeer.new()
				if _mesh:
					_rtc_mp.create_mesh(_my_id)
				elif _my_id == 1:
					_rtc_mp.create_server()
				else:
					_rtc_mp.create_client(_my_id)
				multiplayer.multiplayer_peer = _rtc_mp
				_send("JOIN", 0, "")
				connection_succeeded.emit()
		"JOIN":
			if from_id != _my_id and from_id > 0:
				print("Signaling: Peer %d joined" % from_id)
				_create_webrtc_peer(from_id)
		"OFFER":
			_handle_offer(from_id, data)
		"ANSWER":
			_handle_answer(from_id, data)
		"CANDIDATE":
			_handle_candidate(from_id, data)


func _create_webrtc_peer(peer_id: int) -> void:
	if not _rtc_mp:
		return
	if _rtc_mp.has_peer(peer_id):
		return

	var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()
	peer.initialize({"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]})

	peer.session_description_created.connect(
		func(type: String, sdp: String):
			var msg_type_upper: String = type.to_upper()
			_send(msg_type_upper, peer_id, sdp)
			if type == "offer" or type == "answer":
				peer.set_local_description(type, sdp)
	)

	peer.ice_candidate_created.connect(
		func(mid: String, _index: int, sdp: String):
			_send("CANDIDATE", peer_id, "%s\n%s" % [mid, sdp])
	)

	var err := _rtc_mp.add_peer(peer, peer_id)
	if err != OK:
		push_error("WebRTC: Failed to add peer %d: %s" % [peer_id, error_string(err)])
		return
	print("WebRTC: Added peer %d to multiplayer peer" % peer_id)

	if _my_id < peer_id:
		# Only create an offer if the connection is still in the NEW state.
		if peer.get_connection_state() == WebRTCPeerConnection.STATE_NEW:
			peer.create_offer()
		else:
			push_warning("WebRTC: Skipping create_offer for peer %d – connection not in NEW state" % peer_id)


func _handle_offer(from_id: int, sdp: String) -> void:
	print("WebRTC: OFFER from %d" % from_id)
	if not _rtc_mp:
		return
	if not _rtc_mp.has_peer(from_id):
		_create_webrtc_peer(from_id)
	if _rtc_mp:
		var peer_dict: Dictionary = _rtc_mp.get_peer(from_id)
		if peer_dict.has("connection"):
			peer_dict.connection.set_remote_description("offer", sdp)
			_remote_desc_set[from_id] = true
			_flush_pending_candidates(from_id)


func _handle_answer(from_id: int, sdp: String) -> void:
	print("WebRTC: ANSWER from %d" % from_id)
	if _rtc_mp:
		var peer_dict: Dictionary = _rtc_mp.get_peer(from_id)
		if peer_dict.has("connection"):
			peer_dict.connection.set_remote_description("answer", sdp)
			_remote_desc_set[from_id] = true
			_flush_pending_candidates(from_id)


func _handle_candidate(from_id: int, data: String) -> void:
	if not _rtc_mp or not _rtc_mp.has_peer(from_id):
		_buffer_candidate(from_id, data)
		if _rtc_mp and not _rtc_mp.has_peer(from_id):
			_create_webrtc_peer(from_id)
		return

	if not _remote_desc_set.has(from_id):
		_buffer_candidate(from_id, data)
		return

	_apply_candidate(from_id, data)


func _buffer_candidate(peer_id: int, data: String) -> void:
	if not _pending_candidates.has(peer_id):
		_pending_candidates[peer_id] = []
	_pending_candidates[peer_id].append(data)
	print("WebRTC: Buffered candidate for peer %d (total: %d)" % [peer_id, _pending_candidates[peer_id].size()])


func _apply_candidate(peer_id: int, data: String) -> void:
	if not _rtc_mp:
		return
	var peer_dict: Dictionary = _rtc_mp.get_peer(peer_id)
	if peer_dict.has("connection"):
		var parts: PackedStringArray = data.split("\n", false, 1)
		if parts.size() >= 2:
			peer_dict.connection.add_ice_candidate(parts[0], 0, parts[1])
			print("WebRTC: Applied ICE candidate for peer %d" % peer_id)


func _flush_pending_candidates(peer_id: int) -> void:
	if not _pending_candidates.has(peer_id):
		return
	var candidates: Array = _pending_candidates[peer_id]
	print("WebRTC: Flushing %d buffered candidate(s) for peer %d" % [candidates.size(), peer_id])
	for candidate: String in candidates:
		_apply_candidate(peer_id, candidate)
	_pending_candidates.erase(peer_id)


func _send(msg_type: String, to_id: int, data: String) -> void:
	if not _ws or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg := {"type": msg_type, "to": to_id, "data": data}
	_ws.send_text(JSON.stringify(msg))
