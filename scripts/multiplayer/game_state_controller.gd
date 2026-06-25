extends Node

enum State {
	MENU,
	CONNECTING,
	LOADING,
	WORLD_READY,
	PLAYING,
}

signal state_changed(new_state: State)

var _state: State = State.MENU
var _loading_overlay: Control


func _ready() -> void:
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	set_process(false)


func get_state() -> State:
	return _state


func begin_connecting() -> void:
	if _state != State.MENU and _state != State.CONNECTING:
		return
	_set_state(State.CONNECTING)
	if MultiplayerManager.is_webrtc_ready():
		_set_state(State.LOADING)
		_show_loading_overlay()
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	set_process(true)


func _on_connection_succeeded() -> void:
	if _state == State.CONNECTING:
		set_process(true)


func _process(_delta: float) -> void:
	match _state:
		State.CONNECTING:
			_process_connecting()
		State.LOADING:
			_process_loading()
		State.WORLD_READY:
			_process_world_ready()


func _process_connecting() -> void:
	if not MultiplayerManager.is_webrtc_ready():
		return
	print("[GSC:%d] connection ready, transitioning to LOADING" % MultiplayerManager.get_my_id())
	_set_state(State.LOADING)
	_show_loading_overlay()
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _process_loading() -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm == null:
		return
	if _loading_overlay:
		var progress_bar: ProgressBar = _loading_overlay.get_node_or_null("VBoxContainer/ProgressBar")
		if progress_bar:
			progress_bar.value = cm.get_spawn_area_progress() * 100.0
	if cm.is_spawn_area_ready():
		_set_state(State.WORLD_READY)


func _process_world_ready() -> void:
	var wm: WorldManager = _get_world_manager()
	if wm == null:
		return
	var my_id := MultiplayerManager.get_my_id()
	print("[GSC:%d] WORLD_READY: spawning initial players" % my_id)
	wm.spawn_initial_players()
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm:
		print("[GSC:%d] WORLD_READY: switching chunk manager to player tracking" % my_id)
		cm.switch_to_player_tracking()
	print("[GSC:%d] WORLD_READY: starting GhostManager" % my_id)
	GhostManager.start()
	print("[GSC:%d] WORLD_READY: enabling all sync" % my_id)
	_enable_all_sync()
	print("[GSC:%d] WORLD_READY: capturing mouse" % my_id)
	_capture_mouse()
	_set_state(State.PLAYING)
	set_process(false)
	_hide_loading_overlay()


func _set_state(new_state: State) -> void:
	var old := _state
	_state = new_state
	print("[GSC:%d] state %s → %s" % [MultiplayerManager.get_my_id(), State.find_key(old), State.find_key(new_state)])
	state_changed.emit(new_state)


func _show_loading_overlay() -> void:
	if _loading_overlay != null and is_instance_valid(_loading_overlay):
		return
	_loading_overlay = _create_loading_overlay()
	add_child(_loading_overlay)


func _hide_loading_overlay() -> void:
	if _loading_overlay != null and is_instance_valid(_loading_overlay):
		_loading_overlay.queue_free()
		_loading_overlay = null


func _create_loading_overlay() -> Control:
	var panel := ColorRect.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.color = Color(0.0, 0.0, 0.0, 0.85)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)

	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(300, 20)
	progress.min_value = 0.0
	progress.max_value = 100.0
	progress.value = 0.0
	progress.show_percentage = false

	vbox.add_child(label)
	vbox.add_child(progress)
	panel.add_child(vbox)
	return panel


func _get_world_manager() -> WorldManager:
	var root := get_tree().current_scene
	if root == null:
		return null
	for child: Node in root.get_children():
		if child is WorldManager:
			return child as WorldManager
	return null


func _enable_all_sync() -> void:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node == null:
		print("[GSC:%d] _enable_all_sync: no players node found" % MultiplayerManager.get_my_id())
		return
	for child: Node in players_node.get_children():
		var ns: NetworkSync = child.get_node_or_null("NetworkSync")
		if ns:
			print("[GSC:%d] _enable_all_sync: enabling sync on player %d" % [MultiplayerManager.get_my_id(), child.name.to_int()])
			ns.enable_sync()


func _capture_mouse() -> void:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node == null:
		return
	for child: Node in players_node.get_children():
		if child is CharacterBody3D and child.is_multiplayer_authority():
			var cam := child.get_node_or_null("CameraPivot/Camera3D")
			if cam and cam is Camera3D:
				(cam as Camera3D).make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			break
