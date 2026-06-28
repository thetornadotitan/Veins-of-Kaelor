class_name WaterPlane
extends MeshInstance3D

@export var plane_size: float = 600.0
@export var plane_subdivision: int = 64

var water_level: float = 0.0
var _shader_material: ShaderMaterial


func _ready() -> void:
	var meta := _load_world_meta()
	if meta and meta.generation_params:
		water_level = meta.generation_params.water_level
	else:
		water_level = 15.0

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


func _load_world_meta() -> WorldMeta:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm and cm.get_world_data() and cm.get_world_data().generation_params:
		var params: NoiseParams = cm.get_world_data().generation_params
		var meta := WorldMeta.new()
		meta.generation_params = params
		return meta
	var world_name: String = "kaelor_alpha"
	if cm:
		world_name = cm.world_name
	var meta_path: String = "res://data/worlds/%s/world_meta.res" % world_name
	if ResourceLoader.exists(meta_path):
		return ResourceLoader.load(meta_path, "", ResourceLoader.CACHE_MODE_REUSE)
	return null


func _get_authority_player() -> Node3D:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child
	return null
