class_name NavRegionManager
extends Node

const NAV_UNLOAD_BUFFER: int = 2

var _world_data: WorldData
var _nav_map_rid: RID = RID()
var _loaded_regions: Dictionary = {}
var _pending_loads: Dictionary = {}
var _world_name: String = ""
var DEBUG_TIMING: bool = true


func initialize(world_data: WorldData, nav_map_rid: RID, world_name: String) -> void:
	_world_data = world_data
	_nav_map_rid = nav_map_rid
	_world_name = world_name


func update_for_player_chunk(player_chunk: Vector2i) -> void:
	if _world_data == null:
		return
	var needed := _get_needed_nav_regions(player_chunk)
	_load_needed_regions(needed)
	_unload_distant_regions(needed)


func get_loaded_region_count() -> int:
	return _loaded_regions.size()


func is_region_loaded(rrx: int, rrz: int) -> bool:
	return _loaded_regions.has(Vector2i(rrx, rrz))


func get_region_world_position(rrx: int, rrz: int) -> Vector2:
	var ref_pos: Vector3 = _get_reference_position()
	var base_x: float = float(rrx * _world_data.region_size * ChunkData.CHUNK_SIZE)
	var base_z: float = float(rrz * _world_data.region_size * ChunkData.CHUNK_SIZE)
	var x: float = TorusUtils.wrap_near(base_x, ref_pos.x, _world_data.world_size_x)
	var z: float = TorusUtils.wrap_near(base_z, ref_pos.z, _world_data.world_size_z)
	return Vector2(x, z)


func refresh_region_transforms() -> void:
	for key: Vector2i in _loaded_regions.keys():
		var rec: Dictionary = _loaded_regions[key]
		var world_pos: Vector2 = get_region_world_position(key.x, key.y)
		var new_transform := Transform3D(Basis(), Vector3(world_pos.x, 0.0, world_pos.y))
		if rec.region_rid != RID():
			NavigationServer3D.region_set_transform(rec.region_rid, new_transform)


func shutdown() -> void:
	for key: Vector2i in _loaded_regions.keys():
		var rec: Dictionary = _loaded_regions[key]
		if rec.region_rid != RID():
			NavigationServer3D.free_rid(rec.region_rid)
	_loaded_regions.clear()
	_pending_loads.clear()


func _get_needed_nav_regions(player_chunk: Vector2i) -> Dictionary:
	var needed: Dictionary = {}
	var load_radius_chunks: int = ChunkManager.LOAD_RADIUS
	var rcx: int = _world_data.region_count_x
	var rcz: int = _world_data.region_count_z
	var center_rrx: int = floori(posmod(player_chunk.x, _world_data.chunk_count_x) / float(_world_data.region_size))
	var center_rrz: int = floori(posmod(player_chunk.y, _world_data.chunk_count_z) / float(_world_data.region_size))
	var region_radius: int = ceili(float(load_radius_chunks) / float(_world_data.region_size)) + 1
	for drx: int in range(-region_radius, region_radius + 1):
		for drz: int in range(-region_radius, region_radius + 1):
			var rrx: int = posmod(center_rrx + drx, rcx)
			var rrz: int = posmod(center_rrz + drz, rcz)
			var key := Vector2i(rrx, rrz)
			needed[key] = true
	return needed


func _load_needed_regions(needed: Dictionary) -> void:
	for key: Vector2i in needed.keys():
		if _loaded_regions.has(key):
			continue
		if _pending_loads.has(key):
			var status: int = ResourceLoader.load_threaded_get_status(_pending_loads[key])
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var _path: String = _pending_loads[key]
				var navmesh: NavigationMesh = ResourceLoader.load_threaded_get(_path)
				_pending_loads.erase(key)
				if navmesh != null and not navmesh.get_vertices().is_empty():
					_apply_nav_region(key, navmesh)
				elif DEBUG_TIMING:
					print("[NAV-REGION] region(%d,%d) loaded but empty, skipping" % [key.x, key.y])
			elif status == ResourceLoader.THREAD_LOAD_FAILED:
				_pending_loads.erase(key)
				if DEBUG_TIMING:
					print("[NAV-REGION] region(%d,%d) load FAILED" % [key.x, key.y])
			continue
		var path: String = NavMeshGenerator.get_nav_region_path(_world_name, key.x, key.y)
		if not ResourceLoader.exists(path):
			continue
		ResourceLoader.load_threaded_request(path)
		_pending_loads[key] = path
		if DEBUG_TIMING:
			print("[NAV-REGION] requesting region(%d,%d)" % [key.x, key.y])


func _apply_nav_region(key: Vector2i, navmesh: NavigationMesh) -> void:
	var world_pos: Vector2 = get_region_world_position(key.x, key.y)
	var transform := Transform3D(Basis(), Vector3(world_pos.x, 0.0, world_pos.y))
	var region_rid: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region_rid, _nav_map_rid)
	NavigationServer3D.region_set_transform(region_rid, transform)
	NavigationServer3D.region_set_navigation_mesh(region_rid, navmesh)
	_loaded_regions[key] = {
		"region_rid": region_rid,
		"navmesh": navmesh,
	}
	if DEBUG_TIMING:
		print("[NAV-REGION] region(%d,%d) LOADED verts=%d pos=(%.0f,%.0f)" % [key.x, key.y, navmesh.get_vertices().size(), world_pos.x, world_pos.y])


func _unload_distant_regions(needed: Dictionary) -> void:
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _loaded_regions.keys():
		if not needed.has(key):
			var dist: int = _region_distance_wrapped(key, needed)
			if dist > NAV_UNLOAD_BUFFER:
				to_remove.append(key)
	for key: Vector2i in to_remove:
		var rec: Dictionary = _loaded_regions[key]
		if rec.region_rid != RID():
			NavigationServer3D.free_rid(rec.region_rid)
		_loaded_regions.erase(key)
		if DEBUG_TIMING:
			print("[NAV-REGION] region(%d,%d) UNLOADED" % [key.x, key.y])


func _region_distance_wrapped(region_key: Vector2i, needed: Dictionary) -> int:
	var min_dist: int = 999
	for needed_key: Vector2i in needed.keys():
		var dx: int = absi(region_key.x - needed_key.x)
		var dz: int = absi(region_key.y - needed_key.y)
		dx = mini(dx, _world_data.region_count_x - dx)
		dz = mini(dz, _world_data.region_count_z - dz)
		var dist: int = maxi(dx, dz)
		if dist < min_dist:
			min_dist = dist
	return min_dist


func _get_reference_position() -> Vector3:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node:
		for child: Node in players_node.get_children():
			if child is CharacterBody3D and child.is_multiplayer_authority():
				return child.global_position
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager")
	if cm:
		return cm._spawn_point_world_position()
	return Vector3.ZERO
