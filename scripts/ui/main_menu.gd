extends Control

@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _status_label: Label = %StatusLabel
@onready var _peer_count_label: Label = %PeerCountLabel
@onready var _my_id_label: Label = %MyIdLabel


func _ready() -> void:
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	MultiplayerManager.connection_failed.connect(_on_connection_failed)
	MultiplayerManager.peer_connected.connect(_on_peer_connected)
	MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)

	if OS.has_feature("web"):
		_host_button.disabled = true
		_host_button.tooltip_text = "Not available in browser"

	_update_ui("Disconnected")


func _on_host_pressed() -> void:
	if OS.has_feature("web"):
		return
	MultiplayerManager.host_game()


func _on_join_pressed() -> void:
	MultiplayerManager.join_game()


func _on_disconnect_pressed() -> void:
	MultiplayerManager.disconnect_game()
	_update_ui("Disconnected")


func _on_connection_succeeded() -> void:
	_update_ui("Connected")
	GameStateController.begin_connecting()


func _on_connection_failed() -> void:
	_update_ui("Connection Failed")


func _on_peer_connected(_peer_id: int) -> void:
	_update_peer_count()


func _on_peer_disconnected(_peer_id: int) -> void:
	_update_peer_count()


func _update_ui(status: String) -> void:
	_status_label.text = "Status: %s" % status
	_update_peer_count()

	var id: int = MultiplayerManager.get_my_id()
	_my_id_label.text = "My ID: %d" % id

	var connected := MultiplayerManager.is_peer_connected()
	_host_button.disabled = connected
	_join_button.disabled = connected
	_disconnect_button.disabled = not connected


func _update_peer_count() -> void:
	var count: int = MultiplayerManager.get_peer_count()
	if count > 0:
		_peer_count_label.text = "Peers: %d" % count
	else:
		_peer_count_label.text = "Peers: -"
