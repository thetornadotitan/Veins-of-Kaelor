class_name TerrainChunk
extends Node3D

var _chunk_data: ChunkData
var _current_lod: int = -1
var _mesh_instance: MeshInstance3D
var _static_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _chunk_pos: Vector2i = Vector2i(-1, -1)
var _nav_ready: bool = false


func setup(chunk_data: ChunkData, lod: int, chunk_pos: Vector2i) -> void:
	_chunk_data = chunk_data
	_chunk_pos = chunk_pos
	_current_lod = lod

	var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(chunk_data, lod)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = TerrainMeshBuilder.get_terrain_material()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var chunk_aabb := AABB(Vector3.ZERO, Vector3(float(ChunkData.CHUNK_SIZE), float(ChunkData.GRID_RESOLUTION), float(ChunkData.CHUNK_SIZE)))
	_mesh_instance.custom_aabb = chunk_aabb
	add_child(_mesh_instance)

	var shape: ConcavePolygonShape3D = CollisionGenerator.build_collision_shape(chunk_data)
	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 1
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	_static_body.add_child(col_shape)
	add_child(_static_body)

	_nav_region = NavigationRegion3D.new()
	add_child(_nav_region)


func set_world_position(world_x: float, world_z: float) -> void:
	position = Vector3(world_x, 0.0, world_z)


func _ready() -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm:
		cm.queue_navmesh_bake(self)


func bake_navmesh_now() -> void:
	_bake_navmesh.call_deferred()


func _bake_navmesh() -> void:
	var gen := NavMeshGenerator.new()
	var navmesh: NavigationMesh = await gen.build_navmesh(self)
	if is_inside_tree() and _nav_region:
		_nav_region.navigation_mesh = navmesh
		_nav_ready = true


func update_lod(new_lod: int) -> void:
	if new_lod == _current_lod:
		return
	_current_lod = new_lod
	if _chunk_data == null:
		return
	var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(_chunk_data, new_lod)
	_mesh_instance.mesh = mesh


func get_chunk_pos() -> Vector2i:
	return _chunk_pos


func get_lod() -> int:
	return _current_lod
