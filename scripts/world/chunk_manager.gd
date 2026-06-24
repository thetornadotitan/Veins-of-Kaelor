class_name ChunkManager
extends Node3D

const LOAD_RADIUS: int = 5
const UNLOAD_DISTANCE: int = 7

var _world_data: WorldData
var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(-9999, -9999)
var _initialized: bool = false

@export var world_name: String = "kaelor_alpha"

@onready var _terrain_root: Node3D = %TerrainRoot


func _ready() -> void:
	add_to_group("chunk_manager")
	_world_data = WorldData.load_meta(world_name)
	if _world_data == null:
		push_error("ChunkManager: failed to load world '%s'" % world_name)
		return
	print("[ChunkManager] Loaded world '%s': chunks=%dx%d size=%d region_size=%d world_size=%.0fx%.0f" % [
		world_name, _world_data.chunk_count_x, _world_data.chunk_count_z,
		_world_data.chunk_size, _world_data.region_size,
		_world_data.world_size_x, _world_data.world_size_z
	])
	_initialized = true


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_update_chunks()


func force_update() -> void:
	if not _initialized:
		return
	_update_chunks()


func get_world_data() -> WorldData:
	return _world_data


func get_terrain_height(world_x: float, world_z: float) -> float:
	var chunk_x: int = posmod(floori(world_x / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_x)
	var chunk_z: int = posmod(floori(world_z / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_z)
	var chunk_data: ChunkData = _world_data.get_chunk_data(chunk_x, chunk_z)
	if chunk_data == null or chunk_data.heightmap.is_empty():
		push_warning("[ChunkManager] Cannot get terrain height at (%.0f,%.0f): chunk data null/empty" % [world_x, world_z])
		return 0.0
	var local_x: float = fposmod(world_x, float(ChunkData.CHUNK_SIZE))
	var local_z: float = fposmod(world_z, float(ChunkData.CHUNK_SIZE))
	var h: float = chunk_data.get_height_at(local_x, local_z)
	print("[ChunkManager] Terrain height at (%.0f,%.0f) = %.2f" % [world_x, world_z, h])
	return h


func rewrap_remote_players() -> void:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node == null:
		return
	for child: Node in players_node.get_children():
		if child is PlayerController and not child.is_multiplayer_authority():
			var remote_pos: Vector3 = child.global_position
			var local_player_pos: Vector3 = _get_player_world_position()
			var new_pos := TorusUtils.wrap_vector3_near(remote_pos, local_player_pos, _world_data)
			child.global_position = new_pos


func _update_chunks() -> void:
	var player_pos: Vector3 = _get_player_world_position()
	var player_chunk: Vector2i = _world_to_chunk(player_pos)

	if player_chunk == _player_chunk:
		return
	print("[ChunkManager] Player at %s -> chunk %s (was %s), loaded=%d" % [
		player_pos, player_chunk, _player_chunk, _loaded_chunks.size()
	])
	_player_chunk = player_chunk
	_update_loaded_chunks()


func _update_loaded_chunks() -> void:
	var to_load: Array[Vector2i] = []
	var needed_regions: Array[Vector2i] = []

	for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var crx: int = posmod(_player_chunk.x + dx, _world_data.chunk_count_x)
			var crz: int = posmod(_player_chunk.y + dz, _world_data.chunk_count_z)
			var chunk_pos := Vector2i(crx, crz)
			if not _loaded_chunks.has(chunk_pos):
				to_load.append(chunk_pos)

	var to_unload: Array[Vector2i] = []
	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var dist: int = _chunk_distance_wrapped(chunk_pos, _player_chunk)
		if dist > UNLOAD_DISTANCE:
			to_unload.append(chunk_pos)

	for chunk_pos: Vector2i in to_load:
		_load_chunk(chunk_pos)

	for chunk_pos: Vector2i in to_unload:
		_unload_chunk(chunk_pos)

	needed_regions = _world_data.get_needed_regions_for_chunk(
		_player_chunk.x, _player_chunk.y, LOAD_RADIUS
	)
	_world_data.unload_distant_regions(needed_regions)

	_refresh_chunk_positions()

	_update_lods()


func _load_chunk(chunk_pos: Vector2i) -> void:
	var chunk_data: ChunkData = _world_data.get_chunk_data(chunk_pos.x, chunk_pos.y)
	if chunk_data == null:
		push_warning("[ChunkManager] get_chunk_data returned null for (%d, %d)" % [chunk_pos.x, chunk_pos.y])
		return

	var lod: int = _determine_lod(chunk_pos)
	var chunk_node := TerrainChunk.new()
	chunk_node.setup(chunk_data, lod, chunk_pos)
	_terrain_root.add_child(chunk_node)

	var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
	chunk_node.set_world_position(world_pos.x, world_pos.y)

	_populate_foliage(chunk_pos, chunk_data, world_pos)

	print("[ChunkManager] Loaded chunk (%d,%d) -> world(%.0f,%.0f) lod=%d heightmap_len=%d first_h=%.2f" % [
		chunk_pos.x, chunk_pos.y, world_pos.x, world_pos.y, lod,
		chunk_data.heightmap.size(), chunk_data.heightmap[0] if chunk_data.heightmap.size() > 0 else -1.0
	])
	_loaded_chunks[chunk_pos] = chunk_node


func _populate_foliage(chunk_pos: Vector2i, chunk_data: ChunkData, world_pos: Vector2) -> void:
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	if foliage_renderer == null:
		return
	var chunk_offset := Vector3(world_pos.x, 0.0, world_pos.y)
	var water_level: float = _world_data.generation_params.water_level
	var seed_value: int = _world_data.seed_value
	var heightmap: PackedFloat32Array = chunk_data.heightmap
	foliage_renderer.queue_generation(chunk_pos, heightmap, water_level, seed_value, chunk_offset)


func _chunk_to_nearest_world_position(chunk_pos: Vector2i) -> Vector2:
	var player_pos: Vector3 = _get_player_world_position()
	var base_x: float = float(chunk_pos.x * ChunkData.CHUNK_SIZE)
	var base_z: float = float(chunk_pos.y * ChunkData.CHUNK_SIZE)
	var x: float = TorusUtils.wrap_near(base_x, player_pos.x, _world_data.world_size_x)
	var z: float = TorusUtils.wrap_near(base_z, player_pos.z, _world_data.world_size_z)
	return Vector2(x, z)


func _refresh_chunk_positions() -> void:
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var chunk_node: TerrainChunk = _loaded_chunks[chunk_pos]
		var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
		chunk_node.set_world_position(world_pos.x, world_pos.y)
		if foliage_renderer:
			foliage_renderer.set_chunk_world_pos(chunk_pos, world_pos.x, world_pos.y)


func _unload_chunk(chunk_pos: Vector2i) -> void:
	var chunk_node: Node = _loaded_chunks.get(chunk_pos)
	if chunk_node:
		chunk_node.queue_free()
		_loaded_chunks.erase(chunk_pos)
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	if foliage_renderer:
		foliage_renderer.clear_chunk(chunk_pos)


func _update_lods() -> void:
	var player_pos: Vector3 = _get_player_world_position()

	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var chunk_node: TerrainChunk = _loaded_chunks[chunk_pos]
		var chunk_center_x: float = chunk_node.position.x + float(ChunkData.CHUNK_SIZE) * 0.5
		var chunk_center_z: float = chunk_node.position.z + float(ChunkData.CHUNK_SIZE) * 0.5
		var chunk_center := Vector3(chunk_center_x, 0.0, chunk_center_z)

		var diff := chunk_center - player_pos
		var dist: float = diff.length()

		var new_lod: int = TerrainMeshBuilder.get_lod_for_distance(dist)
		chunk_node.update_lod(new_lod)


func _determine_lod(chunk_pos: Vector2i) -> int:
	var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
	var player_pos: Vector3 = _get_player_world_position()
	var chunk_center := Vector3(
		world_pos.x + float(ChunkData.CHUNK_SIZE) * 0.5,
		0.0,
		world_pos.y + float(ChunkData.CHUNK_SIZE) * 0.5
	)
	var diff := chunk_center - player_pos
	var dist: float = diff.length()
	return TerrainMeshBuilder.get_lod_for_distance(dist)


func _get_player_world_position() -> Vector3:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child.global_position
	push_warning("[ChunkManager] No player with authority found, using Vector3.ZERO")
	return Vector3.ZERO


func _world_to_chunk(pos: Vector3) -> Vector2i:
	var cx: int = posmod(floori(pos.x / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_x)
	var cz: int = posmod(floori(pos.z / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_z)
	return Vector2i(cx, cz)


func _chunk_distance_wrapped(a: Vector2i, b: Vector2i) -> int:
	var dx: int = absi(a.x - b.x)
	var dz: int = absi(a.y - b.y)
	dx = mini(dx, _world_data.chunk_count_x - dx)
	dz = mini(dz, _world_data.chunk_count_z - dz)
	return maxi(dx, dz)
