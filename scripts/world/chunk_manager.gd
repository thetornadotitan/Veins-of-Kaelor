class_name ChunkManager
extends Node3D

const LOAD_RADIUS: int = 5
const UNLOAD_DISTANCE: int = 7
const PROCESS_BUDGET_USEC: int = 4000
const COLLISION_BUDGET_USEC: int = 2000
const CHUNK_AABB_Y_MIN: float = -25.0
const CHUNK_AABB_HEIGHT: float = 110.0
const DEBUG_TIMING: bool = true

var _world_data: WorldData
var _nav_region_manager: NavRegionManager
var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(-9999, -9999)
var _initialized: bool = false
var _chunk_load_queue: Array[Vector2i] = []
var _spawn_chunk: Vector2i = Vector2i(0, 0)
var _using_spawn_point: bool = true
var _worker: ChunkWorker = null
var _use_threads: bool = true
var _scenario_rid: RID = RID()
var _space_rid: RID = RID()
var _nav_map_rid: RID = RID()
var _pending_results: Array[Dictionary] = []
var _pending_collision: Array[Vector2i] = []
var _frame_timing := {
	"apply": 0.0,
	"queue": 0.0,
	"nav": 0.0,
	"update": 0.0,
}
var _spawn_load_start_msec: float = 0.0
var _frame_count: int = 0
var _timing_log_interval: int = 60

@export var world_name: String = "kaelor_alpha"


func _ready() -> void:
	add_to_group("chunk_manager")
	_world_data = WorldData.load_meta(world_name)
	if _world_data == null:
		push_error("ChunkManager: failed to load world '%s'" % world_name)
		return
	_scenario_rid = get_world_3d().scenario
	_space_rid = get_world_3d().space
	_nav_map_rid = get_world_3d().navigation_map
	_use_threads = not OS.has_feature("web")
	if _use_threads:
		_worker = ChunkWorker.new()
		_worker.start()
	_nav_region_manager = NavRegionManager.new()
	add_child(_nav_region_manager)
	_nav_region_manager.initialize(_world_data, _nav_map_rid, world_name)
	_preload_spawn_regions()
	_spawn_load_start_msec = Time.get_ticks_msec()
	if DEBUG_TIMING:
		print("[CM-TIME] _ready done, spawn load starting at %.1f ms" % _spawn_load_start_msec)
	_initialized = true


func _preload_spawn_regions() -> void:
	var spawn_chunk: Vector2i = _world_to_chunk(_spawn_point_world_position())
	var needed: Dictionary = {}
	for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var crx: int = posmod(spawn_chunk.x + dx, _world_data.chunk_count_x)
			var crz: int = posmod(spawn_chunk.y + dz, _world_data.chunk_count_z)
			var rrx: int = floori(crx / float(_world_data.region_size))
			var rrz: int = floori(crz / float(_world_data.region_size))
			var key := Vector2i(rrx, rrz)
			needed[key] = true
	for key: Vector2i in needed:
		_world_data.request_threaded_load(key)


func _exit_tree() -> void:
	if _nav_region_manager:
		_nav_region_manager.shutdown()
		_nav_region_manager = null
	if _worker:
		_worker.stop()
		_worker = null
	_pending_collision.clear()
	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var rec: ChunkRecord = _loaded_chunks[chunk_pos]
		if rec:
			rec.free_rids()
	_loaded_chunks.clear()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_frame_count += 1
	var t0: int = Time.get_ticks_usec()
	if _use_threads:
		_apply_worker_results()
	var t1: int = Time.get_ticks_usec()
	_queue_load_tasks()
	var t2: int = Time.get_ticks_usec()
	_update_chunks()
	var t3: int = Time.get_ticks_usec()
	_process_pending_collision()
	var t4: int = Time.get_ticks_usec()
	_frame_timing["apply"] = float(t1 - t0) * 0.001
	_frame_timing["queue"] = float(t2 - t1) * 0.001
	_frame_timing["nav"] = float(t3 - t2) * 0.001
	_frame_timing["update"] = float(t4 - t3) * 0.001
	var total_ms: float = float(t4 - t0) * 0.001
	if DEBUG_TIMING and _frame_count % _timing_log_interval == 0:
		var qsize: int = _chunk_load_queue.size() if _use_threads else 0
		var pending: int = _pending_results.size() if _use_threads else 0
		var wqueue: int = _worker._queue.size() if _worker else 0
		var nav_regions: int = _nav_region_manager.get_loaded_region_count() if _nav_region_manager else 0
		print("[CM-TIME] frame=%d total=%.2fms apply=%.2f queue=%.2f nav=%.2f update=%.2f | loaded=%d q=%d pending=%d wq=%d coll=%d navreg=%d" % [
			_frame_count, total_ms,
			_frame_timing["apply"], _frame_timing["queue"],
			_frame_timing["nav"], _frame_timing["update"],
			_loaded_chunks.size(), qsize, pending, wqueue, _pending_collision.size(), nav_regions
		])


func set_spawn_chunk(chunk_x: int, chunk_z: int) -> void:
	_spawn_chunk = Vector2i(chunk_x, chunk_z)


func is_spawn_area_ready() -> bool:
	if not _initialized:
		return false
	if _using_spawn_point:
		var spawn_world: Vector3 = _spawn_point_world_position()
		var spawn_world_chunk: Vector2i = _world_to_chunk(spawn_world)
		for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			for dz: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
				var crx: int = posmod(spawn_world_chunk.x + dx, _world_data.chunk_count_x)
				var crz: int = posmod(spawn_world_chunk.y + dz, _world_data.chunk_count_z)
				var cp := Vector2i(crx, crz)
				if not _loaded_chunks.has(cp):
					return false
				var rec: ChunkRecord = _loaded_chunks[cp]
				if rec.instance_rid == RID():
					return false
		if DEBUG_TIMING:
			var elapsed: float = Time.get_ticks_msec() - _spawn_load_start_msec
			print("[CM-TIME] spawn area READY after %.0f ms (%.1f s), %d chunks" % [elapsed, elapsed * 0.001, _loaded_chunks.size()])
	return true


func get_spawn_area_progress() -> float:
	if not _initialized:
		return 0.0
	var spawn_world: Vector3 = _spawn_point_world_position()
	var spawn_world_chunk: Vector2i = _world_to_chunk(spawn_world)
	var total: int = 0
	var loaded: int = 0
	for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var crx: int = posmod(spawn_world_chunk.x + dx, _world_data.chunk_count_x)
			var crz: int = posmod(spawn_world_chunk.y + dz, _world_data.chunk_count_z)
			total += 1
			if _loaded_chunks.has(Vector2i(crx, crz)):
				loaded += 1
	if total == 0:
		return 0.0
	return float(loaded) / float(total)


func switch_to_player_tracking() -> void:
	_using_spawn_point = false
	_player_chunk = Vector2i(-9999, -9999)


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
		return 0.0
	var local_x: float = fposmod(world_x, float(ChunkData.CHUNK_SIZE))
	var local_z: float = fposmod(world_z, float(ChunkData.CHUNK_SIZE))
	return chunk_data.get_height_at(local_x, local_z)


func get_terrain_normal(world_x: float, world_z: float) -> Vector3:
	var chunk_x: int = posmod(floori(world_x / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_x)
	var chunk_z: int = posmod(floori(world_z / float(ChunkData.CHUNK_SIZE)), _world_data.chunk_count_z)
	var chunk_data: ChunkData = _world_data.get_chunk_data(chunk_x, chunk_z)
	if chunk_data == null or chunk_data.heightmap.is_empty():
		return Vector3.UP
	var local_x: float = fposmod(world_x, float(ChunkData.CHUNK_SIZE))
	var local_z: float = fposmod(world_z, float(ChunkData.CHUNK_SIZE))
	return chunk_data.get_normal_at(local_x, local_z)


func rewrap_remote_players() -> void:
	var players_node := get_tree().get_first_node_in_group("players")
	if players_node == null:
		return
	var ref_pos: Vector3 = _get_reference_position()
	for child: Node in players_node.get_children():
		if child is PlayerController and not child.is_multiplayer_authority():
			var remote_pos: Vector3 = child.global_position
			var new_pos := TorusUtils.wrap_vector3_near(remote_pos, ref_pos, _world_data)
			child.global_position = new_pos


func _apply_worker_results() -> void:
	if _worker == null:
		return
	_pending_results.append_array(_worker.pop_completed())
	var budget_usec: int = Time.get_ticks_usec() + PROCESS_BUDGET_USEC
	var remaining: Array[Dictionary] = []
	var applied: int = 0
	var total_build_usec: int = 0
	var ta0: int = Time.get_ticks_usec()
	for result: Dictionary in _pending_results:
		if Time.get_ticks_usec() > budget_usec:
			remaining.append(result)
			continue
		var chunk_pos: Vector2i = result["chunk_pos"]
		if not _loaded_chunks.has(chunk_pos):
			continue
		var rec: ChunkRecord = _loaded_chunks[chunk_pos]
		var task_type: int = result["type"]
		total_build_usec += int(result.get("build_usec", 0))
		if task_type == ChunkWorker.TaskType.LOAD:
			_apply_load_result(rec, result)
		elif task_type == ChunkWorker.TaskType.LOD_UPDATE:
			_apply_lod_result(rec, result)
		applied += 1
	_pending_results = remaining
	if DEBUG_TIMING and applied > 0:
		var apply_ms: float = float(Time.get_ticks_usec() - ta0) * 0.001
		var worker_build_ms: float = float(total_build_usec) * 0.001
		print("[CM-TIME] applied %d results in %.2fms (worker build=%.2fms) pending=%d" % [applied, apply_ms, worker_build_ms, remaining.size()])


func _apply_load_result(rec: ChunkRecord, result: Dictionary) -> void:
	var t0: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = result["mesh"]
	rec.mesh = mesh
	rec.current_lod = result["lod"]

	if rec.instance_rid != RID():
		RenderingServer.free_rid(rec.instance_rid)
		rec.instance_rid = RID()

	if mesh != null:
		var ti0: int = Time.get_ticks_usec()
		rec.instance_rid = RenderingServer.instance_create()
		RenderingServer.instance_set_base(rec.instance_rid, mesh.get_rid())
		RenderingServer.instance_set_scenario(rec.instance_rid, _scenario_rid)
		RenderingServer.instance_set_transform(rec.instance_rid, rec.world_position)
		var chunk_aabb := AABB(Vector3(0.0, CHUNK_AABB_Y_MIN, 0.0), Vector3(float(ChunkData.CHUNK_SIZE), CHUNK_AABB_HEIGHT, float(ChunkData.CHUNK_SIZE)))
		RenderingServer.instance_set_custom_aabb(rec.instance_rid, chunk_aabb)
		var mat_rid: RID = TerrainMeshBuilder.get_terrain_material().get_rid()
		RenderingServer.instance_set_surface_override_material(rec.instance_rid, 0, mat_rid)
		RenderingServer.instance_set_layer_mask(rec.instance_rid, 1)
		RenderingServer.instance_set_visible(rec.instance_rid, rec.is_visible)
		var render_ms: float = float(Time.get_ticks_usec() - ti0) * 0.001
		if DEBUG_TIMING:
			print("[CM-TIME]   chunk(%d,%d) LOD%d render_setup=%.2fms" % [rec.chunk_pos.x, rec.chunk_pos.y, rec.current_lod, render_ms])

	var shape: ConcavePolygonShape3D = result["shape"]
	rec.shape = shape
	if shape != null:
		var tp0: int = Time.get_ticks_usec()
		_pending_collision.append(rec.chunk_pos)
		var phys_ms: float = float(Time.get_ticks_usec() - tp0) * 0.001
		if DEBUG_TIMING:
			print("[CM-TIME]   chunk(%d,%d) LOD%d collision_deferred=%.2fms" % [rec.chunk_pos.x, rec.chunk_pos.y, rec.current_lod, phys_ms])

	_chunk_load_queue.erase(rec.chunk_pos)

	_populate_foliage(rec)

	var total_ms: float = float(Time.get_ticks_usec() - t0) * 0.001
	if DEBUG_TIMING and total_ms > 0.5:
		print("[CM-TIME]   chunk(%d,%d) LOD%d _apply_load total=%.2fms" % [rec.chunk_pos.x, rec.chunk_pos.y, rec.current_lod, total_ms])


func _apply_lod_result(rec: ChunkRecord, result: Dictionary) -> void:
	var mesh: ArrayMesh = result["mesh"]
	var old_mesh: ArrayMesh = rec.mesh
	rec.mesh = mesh
	rec.current_lod = result["lod"]

	if rec.instance_rid != RID():
		if mesh != null:
			RenderingServer.instance_set_base(rec.instance_rid, mesh.get_rid())
			var mat_rid: RID = TerrainMeshBuilder.get_terrain_material().get_rid()
			RenderingServer.instance_set_surface_override_material(rec.instance_rid, 0, mat_rid)
		else:
			RenderingServer.free_rid(rec.instance_rid)
			rec.instance_rid = RID()
	elif mesh != null:
		rec.instance_rid = RenderingServer.instance_create()
		RenderingServer.instance_set_base(rec.instance_rid, mesh.get_rid())
		RenderingServer.instance_set_scenario(rec.instance_rid, _scenario_rid)
		RenderingServer.instance_set_transform(rec.instance_rid, rec.world_position)
		var chunk_aabb := AABB(Vector3(0.0, CHUNK_AABB_Y_MIN, 0.0), Vector3(float(ChunkData.CHUNK_SIZE), CHUNK_AABB_HEIGHT, float(ChunkData.CHUNK_SIZE)))
		RenderingServer.instance_set_custom_aabb(rec.instance_rid, chunk_aabb)
		var mat_rid: RID = TerrainMeshBuilder.get_terrain_material().get_rid()
		RenderingServer.instance_set_surface_override_material(rec.instance_rid, 0, mat_rid)
		RenderingServer.instance_set_layer_mask(rec.instance_rid, 1)
		RenderingServer.instance_set_visible(rec.instance_rid, rec.is_visible)

	if old_mesh != null and old_mesh != mesh:
		old_mesh.unreference()

	var new_lod: int = result["lod"]
	var should_have_collision: bool = new_lod <= 1
	if should_have_collision and not rec.has_collision:
		var shape: ConcavePolygonShape3D = result.get("shape")
		if shape != null:
			rec.shape = shape
			_pending_collision.append(rec.chunk_pos)
	elif not should_have_collision and rec.has_collision:
		rec.remove_collision()


func _process_pending_collision() -> void:
	if _pending_collision.is_empty():
		return
	var budget_usec: int = Time.get_ticks_usec() + COLLISION_BUDGET_USEC
	var remaining: Array[Vector2i] = []
	var _created: int = 0
	for chunk_pos: Vector2i in _pending_collision:
		if Time.get_ticks_usec() > budget_usec:
			remaining.append(chunk_pos)
			continue
		if not _loaded_chunks.has(chunk_pos):
			continue
		var rec: ChunkRecord = _loaded_chunks[chunk_pos]
		if rec.has_collision or rec.shape == null:
			continue
		rec.body_rid = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rec.body_rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(rec.body_rid, _space_rid)
		PhysicsServer3D.body_set_collision_layer(rec.body_rid, 1)
		PhysicsServer3D.body_set_collision_mask(rec.body_rid, 1)
		PhysicsServer3D.body_set_state(rec.body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, rec.world_position)
		rec.shape_rid = rec.shape.get_rid()
		PhysicsServer3D.body_add_shape(rec.body_rid, rec.shape_rid)
		rec.has_collision = true
		_created += 1
		if DEBUG_TIMING:
			print("[CM-TIME]   chunk(%d,%d) LOD%d physics_setup=deferred" % [rec.chunk_pos.x, rec.chunk_pos.y, rec.current_lod])
	_pending_collision = remaining


func _queue_load_tasks() -> void:
	var budget_usec: int = Time.get_ticks_usec() + PROCESS_BUDGET_USEC
	var remaining: Array[Vector2i] = []
	var queued: int = 0
	var waiting_region: int = 0
	for chunk_pos: Vector2i in _chunk_load_queue:
		if Time.get_ticks_usec() > budget_usec:
			remaining.append(chunk_pos)
			continue
		if not _world_data.is_region_ready_for(chunk_pos.x, chunk_pos.y):
			remaining.append(chunk_pos)
			waiting_region += 1
			continue
		var chunk_data: ChunkData = _world_data.get_chunk_data(chunk_pos.x, chunk_pos.y)
		if chunk_data == null:
			remaining.append(chunk_pos)
			continue
		var lod: int = _determine_lod(chunk_pos)
		var needs_collision: bool = lod <= 1
		var rec := ChunkRecord.new()
		rec.chunk_pos = chunk_pos
		rec.chunk_data = chunk_data
		rec.current_lod = lod
		var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
		rec.world_position = Transform3D(Basis(), Vector3(world_pos.x, 0.0, world_pos.y))
		_loaded_chunks[chunk_pos] = rec
		if _use_threads:
			_worker.push_task(ChunkWorker.TaskType.LOAD, chunk_pos, chunk_data, lod, needs_collision)
		else:
			_process_load_sync(rec, chunk_data, lod, needs_collision)
		queued += 1
	_chunk_load_queue = remaining
	if DEBUG_TIMING and (queued > 0 or waiting_region > 0):
		print("[CM-TIME] queue_load: queued=%d waiting_region=%d remaining=%d" % [queued, waiting_region, remaining.size()])


func _process_load_sync(rec: ChunkRecord, chunk_data: ChunkData, lod: int, needs_collision: bool) -> void:
	var t0: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(chunk_data, lod)
	var mesh_ms: float = float(Time.get_ticks_usec() - t0) * 0.001
	var shape: ConcavePolygonShape3D = null
	var shape_ms: float = 0.0
	if needs_collision:
		var ts0: int = Time.get_ticks_usec()
		shape = CollisionGenerator.build_collision_shape(chunk_data)
		shape_ms = float(Time.get_ticks_usec() - ts0) * 0.001
	if DEBUG_TIMING:
		print("[CM-TIME]   sync chunk(%d,%d) LOD%d mesh=%.2fms collision=%.2fms" % [rec.chunk_pos.x, rec.chunk_pos.y, lod, mesh_ms, shape_ms])
	var result := {
		"type": ChunkWorker.TaskType.LOAD,
		"chunk_pos": rec.chunk_pos,
		"lod": lod,
		"mesh": mesh,
		"shape": shape,
		"needs_collision": needs_collision,
	}
	_apply_load_result(rec, result)


func _update_chunks() -> void:
	var ref_pos: Vector3 = _get_reference_position()
	var ref_chunk: Vector2i = _world_to_chunk(ref_pos)
	if ref_chunk == _player_chunk:
		return
	_player_chunk = ref_chunk
	_update_loaded_chunks()


func _update_loaded_chunks() -> void:
	var t0: int = Time.get_ticks_usec()
	var to_load: Array[Vector2i] = []
	for dx: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz: int in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var crx: int = posmod(_player_chunk.x + dx, _world_data.chunk_count_x)
			var crz: int = posmod(_player_chunk.y + dz, _world_data.chunk_count_z)
			var chunk_pos := Vector2i(crx, crz)
			if not _loaded_chunks.has(chunk_pos) and chunk_pos not in _chunk_load_queue:
				to_load.append(chunk_pos)

	var to_unload: Array[Vector2i] = []
	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var dist: int = _chunk_distance_wrapped(chunk_pos, _player_chunk)
		if dist > UNLOAD_DISTANCE:
			to_unload.append(chunk_pos)

	for chunk_pos: Vector2i in to_unload:
		_unload_chunk(chunk_pos)

	_preload_needed_regions(to_load)
	to_load.sort_custom(_sort_by_distance)
	_chunk_load_queue.append_array(to_load)

	var needed_regions: Array[Vector2i] = _world_data.get_needed_regions_for_chunk(
		_player_chunk.x, _player_chunk.y, LOAD_RADIUS
	)
	_world_data.unload_distant_regions(needed_regions)

	if _nav_region_manager:
		_nav_region_manager.update_for_player_chunk(_player_chunk)

	_refresh_chunk_positions()
	_update_lods()
	if DEBUG_TIMING:
		var ms: float = float(Time.get_ticks_usec() - t0) * 0.001
		print("[CM-TIME] update_loaded: load=%d unload=%d total=%.2fms" % [to_load.size(), to_unload.size(), ms])


func _preload_needed_regions(to_load: Array[Vector2i]) -> void:
	var needed: Dictionary = {}
	for chunk_pos: Vector2i in to_load:
		var wrx: int = posmod(chunk_pos.x, _world_data.chunk_count_x)
		var wrz: int = posmod(chunk_pos.y, _world_data.chunk_count_z)
		var rrx: int = floori(wrx / float(_world_data.region_size))
		var rrz: int = floori(wrz / float(_world_data.region_size))
		var key := Vector2i(rrx, rrz)
		needed[key] = true
	for key: Vector2i in needed:
		if not _world_data.has_cached_region(key):
			_world_data.request_threaded_load(key)


func _unload_chunk(chunk_pos: Vector2i) -> void:
	var rec: ChunkRecord = _loaded_chunks.get(chunk_pos)
	if rec:
		rec.free_rids()
		_loaded_chunks.erase(chunk_pos)
	_pending_collision.erase(chunk_pos)
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	if foliage_renderer:
		foliage_renderer.clear_chunk(chunk_pos)


func _populate_foliage(rec: ChunkRecord) -> void:
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	if foliage_renderer == null:
		return
	var world_pos: Vector3 = rec.world_position.origin
	var chunk_offset := Vector3(world_pos.x, 0.0, world_pos.z)
	var water_level: float = _world_data.generation_params.water_level
	var seed_value: int = _world_data.seed_value
	var heightmap: PackedFloat32Array = rec.chunk_data.heightmap
	foliage_renderer.queue_generation(rec.chunk_pos, heightmap, water_level, seed_value, chunk_offset)


func _chunk_to_nearest_world_position(chunk_pos: Vector2i) -> Vector2:
	var ref_pos: Vector3 = _get_reference_position()
	var base_x: float = float(chunk_pos.x * ChunkData.CHUNK_SIZE)
	var base_z: float = float(chunk_pos.y * ChunkData.CHUNK_SIZE)
	var x: float = TorusUtils.wrap_near(base_x, ref_pos.x, _world_data.world_size_x)
	var z: float = TorusUtils.wrap_near(base_z, ref_pos.z, _world_data.world_size_z)
	return Vector2(x, z)


func _refresh_chunk_positions() -> void:
	var foliage_renderer: FoliageRenderer = get_tree().get_first_node_in_group("foliage_renderer")
	for chunk_pos: Vector2i in _loaded_chunks.keys():
		var rec: ChunkRecord = _loaded_chunks[chunk_pos]
		var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
		var new_transform := Transform3D(Basis(), Vector3(world_pos.x, 0.0, world_pos.y))
		rec.world_position = new_transform
		if rec.instance_rid != RID():
			RenderingServer.instance_set_transform(rec.instance_rid, new_transform)
		if rec.body_rid != RID():
			PhysicsServer3D.body_set_state(rec.body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, new_transform)
		if foliage_renderer:
			foliage_renderer.set_chunk_world_pos(chunk_pos, world_pos.x, world_pos.y)
	if _nav_region_manager:
		_nav_region_manager.refresh_region_transforms()


func _update_lods() -> void:
	var ref_pos: Vector3 = _get_reference_position()
	var budget_usec: int = Time.get_ticks_usec() + PROCESS_BUDGET_USEC

	for chunk_pos: Vector2i in _loaded_chunks.keys():
		if Time.get_ticks_usec() > budget_usec:
			break
		var rec: ChunkRecord = _loaded_chunks[chunk_pos]
		var wp: Vector3 = rec.world_position.origin
		var chunk_center := Vector3(
			wp.x + float(ChunkData.CHUNK_SIZE) * 0.5,
			0.0,
			wp.z + float(ChunkData.CHUNK_SIZE) * 0.5
		)
		var diff := chunk_center - ref_pos
		var dist: float = diff.length()

		var new_lod: int = TerrainMeshBuilder.get_lod_for_distance(dist)
		if new_lod == rec.current_lod:
			continue
		if rec.chunk_data == null:
			continue

		var should_have_collision: bool = new_lod <= 1
		if _use_threads:
			_worker.push_task(
				ChunkWorker.TaskType.LOD_UPDATE,
				chunk_pos,
				rec.chunk_data,
				new_lod,
				should_have_collision
			)
		else:
			_process_lod_update_sync(rec, new_lod, should_have_collision)


func _process_lod_update_sync(rec: ChunkRecord, new_lod: int, needs_collision: bool) -> void:
	var t0: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(rec.chunk_data, new_lod)
	var mesh_ms: float = float(Time.get_ticks_usec() - t0) * 0.001
	var shape: ConcavePolygonShape3D = null
	if needs_collision:
		shape = CollisionGenerator.build_collision_shape(rec.chunk_data)
	if DEBUG_TIMING:
		print("[CM-TIME]   sync LOD chunk(%d,%d) LOD%d mesh=%.2fms" % [rec.chunk_pos.x, rec.chunk_pos.y, new_lod, mesh_ms])
	var result := {
		"type": ChunkWorker.TaskType.LOD_UPDATE,
		"chunk_pos": rec.chunk_pos,
		"lod": new_lod,
		"mesh": mesh,
		"shape": shape,
		"needs_collision": needs_collision,
	}
	_apply_lod_result(rec, result)


func _determine_lod(chunk_pos: Vector2i) -> int:
	var world_pos: Vector2 = _chunk_to_nearest_world_position(chunk_pos)
	var ref_pos: Vector3 = _get_reference_position()
	var chunk_center := Vector3(
		world_pos.x + float(ChunkData.CHUNK_SIZE) * 0.5,
		0.0,
		world_pos.y + float(ChunkData.CHUNK_SIZE) * 0.5
	)
	var diff := chunk_center - ref_pos
	var dist: float = diff.length()
	return TerrainMeshBuilder.get_lod_for_distance(dist)


func _get_reference_position() -> Vector3:
	if not _using_spawn_point:
		var players_node := get_tree().get_first_node_in_group("players")
		if players_node:
			for child: Node in players_node.get_children():
				if child is CharacterBody3D and child.is_multiplayer_authority():
					return child.global_position
	return _spawn_point_world_position()


func _spawn_point_world_position() -> Vector3:
	var x: float = float(_spawn_chunk.x * ChunkData.CHUNK_SIZE) + float(ChunkData.CHUNK_SIZE) * 0.5
	var z: float = float(_spawn_chunk.y * ChunkData.CHUNK_SIZE) + float(ChunkData.CHUNK_SIZE) * 0.5
	return Vector3(x, 0.0, z)


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


func _sort_by_distance(a: Vector2i, b: Vector2i) -> bool:
	return _chunk_distance_wrapped(a, _player_chunk) < _chunk_distance_wrapped(b, _player_chunk)
