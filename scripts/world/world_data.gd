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


func _load_region(rrx: int, rrz: int) -> RegionData:
	var key := Vector2i(rrx, rrz)
	if _cached_regions.has(key):
		return _cached_regions[key]
	var path := get_region_path(rrx, rrz)
	if not ResourceLoader.exists(path):
		push_error("WorldData: region file not found: %s" % path)
		return null
	var region: RegionData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if region == null:
		push_error("WorldData: failed to load region: %s" % path)
		return null
	_cached_regions[key] = region
	print("[WorldData] Loaded region (%d,%d): rx=%d rz=%d heightmaps=%d" % [
		rrx, rrz, region.region_rx, region.region_rz, region.chunk_heightmaps.size()
	])
	return region


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
