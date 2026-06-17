extends Node

@onready var _fps_label: Label = %FpsLabel
@onready var _peer_count_label: Label = %PeerCountLabel
@onready var _my_id_label: Label = %MyIdLabel


func _process(_delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if MultiplayerManager.is_peer_connected():
		_peer_count_label.text = "Peers: %d" % MultiplayerManager.get_peer_count()
		_my_id_label.text = "My ID: %d" % MultiplayerManager.get_my_id()
	else:
		_peer_count_label.text = "Peers: -"
		_my_id_label.text = "My ID: -"
