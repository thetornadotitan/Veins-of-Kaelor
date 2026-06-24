class_name WaterPlane
extends MeshInstance3D

@export var water_level: float = 8.0
@export var plane_size: float = 600.0
@export var plane_subdivision: int = 64

var _shader_material: ShaderMaterial


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(plane_size, plane_size)
	plane.subdivide_width = plane_subdivision
	plane.subdivide_depth = plane_subdivision
	mesh = plane

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = preload("res://assets/shaders/water.gdshader")
	_shader_material.set_shader_parameter("water_level", water_level)
	material_override = _shader_material

	position.y = water_level
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_to_group("water_plane")


func _process(_delta: float) -> void:
	var player := _get_authority_player()
	if player:
		global_position.x = player.global_position.x
		global_position.z = player.global_position.z


func get_water_level() -> float:
	return water_level


func is_underwater(world_y: float) -> bool:
	return world_y < water_level


func _get_authority_player() -> Node3D:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child
	return null
