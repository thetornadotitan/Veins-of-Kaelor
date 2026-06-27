@tool
class_name WorldData
extends RefCounted

var world_name: String
var seed_value: int
var chunk_count_x: int = 128
var chunk_count_z: int = 128
var chunk_size: int = 40
var region_size: int = 8
var torus_radius: float = 1.0
var generation_params: NoiseParams

var _cached_regions: Dictionary = {}
var _threaded_loads: Dictionary = {}
var _threaded_load_start: Dictionary = {}


var world_size_x: float:
	get:
		return float(chunk_count_x * chunk_size)

var world_size_z: float:
	get:
		return float(chunk_count_z * chunk_size)

var region_count_x: int:
	get:
		return floori(chunk_count_x / float(region_size))

var region_count_z: int:
	get:
		return floori(chunk_count_z / float(region_size))


static func load_meta(p_world_name: String) -> WorldData:
	var path: String = "res://data/worlds/%s/world_meta.res" % p_world_name
	if not ResourceLoader.exists(path):
		push_error("WorldData: world_meta.res not found for '%s'" % p_world_name)
		return null
	var meta: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if meta == null:
		push_error("WorldData: failed to load world_meta.res for '%s'" % p_world_name)
		return null
	var wd := WorldData.new()
	wd.world_name = meta.world_name
	wd.seed_value = meta.seed_value
	wd.chunk_count_x = meta.chunk_count_x
	wd.chunk_count_z = meta.chunk_count_z
	wd.chunk_size = meta.chunk_size
	wd.region_size = meta.region_size
	wd.torus_radius = meta.torus_radius
	if meta.generation_params:
		wd.generation_params = meta.generation_params
	else:
		wd.generation_params = NoiseParams.new()
	print("[WorldData] Loaded world_meta.res: name=%s seed=%d chunks=%dx%d chunk_size=%d region_size=%d" % [
		wd.world_name, wd.seed_value, wd.chunk_count_x, wd.chunk_count_z,
		wd.chunk_size, wd.region_size
	])
	return wd


func get_chunk_data(rx: int, rz: int) -> ChunkData:
	var wrx: int = posmod(rx, chunk_count_x)
	var wrz: int = posmod(rz, chunk_count_z)
	var rrx: int = floori(wrx / float(region_size))
	var rrz: int = floori(wrz / float(region_size))
	var local_rx: int = wrx % region_size
	var local_rz: int = wrz % region_size
	var region: RegionData = _load_region(rrx, rrz)
	if region == null:
		return null
	return ChunkData.from_region(region, local_rx, local_rz)


func get_region_path(rrx: int, rrz: int) -> String:
	return "res://data/worlds/%s/regions/region_%02d_%02d.res" % [world_name, rrx, rrz]


func unload_distant_regions(keep_regions: Array[Vector2i]) -> void:
	for key: Vector2i in _cached_regions.keys():
		if key not in keep_regions:
			_cached_regions.erase(key)


func clear_cache() -> void:
	_cached_regions.clear()


func has_cached_region(key: Vector2i) -> bool:
	return _cached_regions.has(key)


func request_threaded_load(key: Vector2i) -> void:
	if _cached_regions.has(key) or _threaded_loads.has(key):
		return
	var path := get_region_path(key.x, key.y)
	if not ResourceLoader.exists(path):
		return
	ResourceLoader.load_threaded_request(path)
	_threaded_loads[key] = path
	_threaded_load_start[key] = Time.get_ticks_msec()


func is_region_ready_for(chunk_rx: int, chunk_rz: int) -> bool:
	var wrx: int = posmod(chunk_rx, chunk_count_x)
	var wrz: int = posmod(chunk_rz, chunk_count_z)
	var rrx: int = floori(wrx / float(region_size))
	var rrz: int = floori(wrz / float(region_size))
	var key := Vector2i(rrx, rrz)
	if _cached_regions.has(key):
		return true
	if not _threaded_loads.has(key):
		return false
	var path: String = _threaded_loads[key]
	var status: int = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var region: RegionData = ResourceLoader.load_threaded_get(path)
		if region != null:
			_cached_regions[key] = region
			_threaded_loads.erase(key)
			var start_msec: float = _threaded_load_start.get(key, 0.0)
			_threaded_load_start.erase(key)
			print("[WD-TIME] region(%d,%d) loaded in %.0f ms" % [key.x, key.y, Time.get_ticks_msec() - start_msec])
			return true
		_threaded_loads.erase(key)
		return false
	if status == ResourceLoader.THREAD_LOAD_FAILED:
		_threaded_loads.erase(key)
		return false
	return false


func _load_region(rrx: int, rrz: int) -> RegionData:
	var key := Vector2i(rrx, rrz)
	if _cached_regions.has(key):
		return _cached_regions[key]
	if _threaded_loads.has(key):
		var treaded_path: String = _threaded_loads[key]
		var status: int = ResourceLoader.load_threaded_get_status(treaded_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var treaded_region: RegionData = ResourceLoader.load_threaded_get(treaded_path)
			if treaded_region != null:
				_cached_regions[key] = treaded_region
				_threaded_loads.erase(key)
				var start_msec: float = _threaded_load_start.get(key, 0.0)
				_threaded_load_start.erase(key)
				print("[WD-TIME] region(%d,%d) loaded via _load_region in %.0f ms" % [key.x, key.y, Time.get_ticks_msec() - start_msec])
				return treaded_region
			_threaded_loads.erase(key)
			return null
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			_threaded_loads.erase(key)
			_threaded_load_start.erase(key)
			return null
		return null
	var path := get_region_path(rrx, rrz)
	if not ResourceLoader.exists(path):
		return null
	ResourceLoader.load_threaded_request(path)
	_threaded_loads[key] = path
	_threaded_load_start[key] = Time.get_ticks_msec()
	return null


func get_needed_regions_for_chunk(chunk_rx: int, chunk_rz: int, _radius: int) -> Array[Vector2i]:
	var regions: Array[Vector2i] = []
	var center_rrx: int = floori(posmod(chunk_rx, chunk_count_x) / float(region_size))
	var center_rrz: int = floori(posmod(chunk_rz, chunk_count_z) / float(region_size))
	var rcx: int = region_count_x
	var rcz: int = region_count_z
	for drx: int in range(-1, 2):
		for drz: int in range(-1, 2):
			var rrx: int = posmod(center_rrx + drx, rcx)
			var rrz: int = posmod(center_rrz + drz, rcz)
			var key := Vector2i(rrx, rrz)
			if key not in regions:
				regions.append(key)
	return regions
