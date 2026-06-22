extends Node

@onready var _fps_label: Label = %FpsLabel
@onready var _peer_count_label: Label = %PeerCountLabel
@onready var _my_id_label: Label = %MyIdLabel
@onready var _pos_label: Label = %PosLabel
@onready var _chunk_label: Label = %ChunkLabel
@onready var _region_label: Label = %RegionLabel


func _process(_delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if MultiplayerManager.is_peer_connected():
		_peer_count_label.text = "Peers: %d" % MultiplayerManager.get_peer_count()
		_my_id_label.text = "My ID: %d" % MultiplayerManager.get_my_id()
	else:
		_peer_count_label.text = "Peers: -"
		_my_id_label.text = "My ID: -"

	var player: CharacterBody3D = _get_local_player()
	if player:
		var pos := player.global_position
		_pos_label.text = "Pos: %.0f, %.0f" % [pos.x, pos.z]
		var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
		if cm and cm.get_world_data():
			var wd: WorldData = cm.get_world_data()
			var cx: int = posmod(floori(pos.x / float(ChunkData.CHUNK_SIZE)), wd.chunk_count_x)
			var cz: int = posmod(floori(pos.z / float(ChunkData.CHUNK_SIZE)), wd.chunk_count_z)
			_chunk_label.text = "Chunk: %d, %d" % [cx, cz]
			var rx: int = floori(cx / float(wd.region_size))
			var rz: int = floori(cz / float(wd.region_size))
			_region_label.text = "Region: %d, %d" % [rx, rz]
	else:
		_pos_label.text = "Pos: -"
		_chunk_label.text = "Chunk: -"
		_region_label.text = "Region: -"


func _get_local_player() -> CharacterBody3D:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child as CharacterBody3D
	return null
