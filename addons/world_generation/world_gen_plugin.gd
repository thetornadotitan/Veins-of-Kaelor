@tool
extends EditorPlugin

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://scenes/world/world_editor.tscn").instantiate()
	_panel.name = "WorldGenEditor"
	add_control_to_bottom_panel(_panel, "World Gen")


func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
