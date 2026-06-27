@tool
class_name WorldGenerator
extends RefCounted

signal progress_changed(ratio: float, stage: String)
signal generation_complete(world_name: String)
signal region_saved(rrx: int, rrz: int)
signal navmesh_progress(ratio: float)

const MAX_CONCURRENT_BAKES: int = 16


func generate_world(config: WorldGenConfig) -> void:
	var actual_seed: int = config.seed_value
	if config.generate_new_seed:
		actual_seed = randi()

	var noise: RefCounted = HeightmapGenerator.create_noise(actual_seed)
	var backend_name: String = "GDExtension" if noise.has_method("get_noise_4d_fbm") else "GDScript"
	print("WorldGenerator: generating world '%s' (seed=%d, backend=%s)" % [config.world_name, actual_seed, backend_name])

	var params := NoiseParams.new()
	params.height_scale = config.height_scale
	params.octaves = config.octaves
	params.persistence = config.persistence
	params.lacunarity = config.lacunarity
	params.water_level = config.water_level
	params.height_range_min = config.height_range_min
	params.height_range_max = config.height_range_max
	params.biome_temperature_scale = 0.005
	params.biome_moisture_scale = 0.008
	params.continental_freq = config.continental_freq
	params.continental_octaves = config.continental_octaves
	params.continental_weight = config.continental_weight
	params.mountain_mask_freq = config.mountain_mask_freq
	params.mountain_mask_octaves = config.mountain_mask_octaves
	params.mountain_mask_edge0 = config.mountain_mask_edge0
	params.mountain_mask_edge1 = config.mountain_mask_edge1
	params.mountain_freq = config.mountain_freq
	params.mountain_octaves = config.mountain_octaves
	params.mountain_persistence = config.mountain_persistence
	params.mountain_lacunarity = config.mountain_lacunarity
	params.plains_freq = config.plains_freq
	params.plains_octaves = config.plains_octaves
	params.plains_persistence = config.plains_persistence
	params.detail_freq = config.detail_freq
	params.detail_octaves = config.detail_octaves
	params.detail_persistence = config.detail_persistence
	params.detail_lacunarity = config.detail_lacunarity
	params.detail_weight = config.detail_weight
	params.power_exponent = config.power_exponent

	var total_chunks: int = config.chunk_count_x * config.chunk_count_z
	var chunks_done: int = 0

	var region_count_x: int = floori(config.chunk_count_x / float(config.region_size))
	var region_count_z: int = floori(config.chunk_count_z / float(config.region_size))
	var world_size: float = config.world_size_x

	var regions_dir: String = "res://data/worlds/%s/regions" % config.world_name
	if not DirAccess.dir_exists_absolute(regions_dir):
		DirAccess.make_dir_recursive_absolute(regions_dir)

	for rrx: int in range(region_count_x):
		for rrz: int in range(region_count_z):
			var region := RegionData.create_empty(rrx, rrz, config.chunk_count_x, config.chunk_count_z)

			for local_rx: int in range(RegionData.REGION_SIZE):
				for local_rz: int in range(RegionData.REGION_SIZE):
					var chunk_rx: int = rrx * RegionData.REGION_SIZE + local_rx
					var chunk_rz: int = rrz * RegionData.REGION_SIZE + local_rz

					var heightmap := HeightmapGenerator.generate_chunk_heightmap(
						chunk_rx, chunk_rz, noise, params, world_size, config.torus_radius
					)

					region.set_chunk_heightmap(local_rx, local_rz, heightmap)
					region.set_chunk_biome(local_rx, local_rz, 0)

					chunks_done += 1

			var region_path: String = "res://data/worlds/%s/regions/region_%02d_%02d.res" % [config.world_name, rrx, rrz]
			var err: int = ResourceSaver.save(region, region_path)
			if err != OK:
				push_error("WorldGenerator: failed to save region %s: error %d" % [region_path, err])

			region_saved.emit(rrx, rrz)
			progress_changed.emit(float(chunks_done) / float(total_chunks) * 0.5, "terrain")
			await Engine.get_main_loop().process_frame

	_save_world_meta(config, actual_seed, backend_name, params)
	_export_meta_json(config, actual_seed, backend_name, params)

	await _bake_all_navmeshes(config)

	generation_complete.emit(config.world_name)
	print("WorldGenerator: complete! Generated %d chunks in %d regions" % [total_chunks, region_count_x * region_count_z])


func _save_world_meta(config: WorldGenConfig, actual_seed: int, backend_name: String, params: NoiseParams) -> void:
	var meta := WorldMeta.new()
	meta.world_name = config.world_name
	meta.seed_value = actual_seed
	meta.created = Time.get_datetime_string_from_system()
	meta.version = "3.0"
	meta.chunk_size = config.chunk_size
	meta.chunk_count_x = config.chunk_count_x
	meta.chunk_count_z = config.chunk_count_z
	meta.region_size = config.region_size
	meta.height_range_min = config.height_range_min
	meta.height_range_max = config.height_range_max
	meta.torus_radius = config.torus_radius
	meta.generation_backend = backend_name
	meta.generation_params = params

	var meta_path: String = "res://data/worlds/%s/world_meta.res" % config.world_name
	var err: int = ResourceSaver.save(meta, meta_path)
	if err != OK:
		push_error("WorldGenerator: failed to save world_meta.res: error %d" % err)


func _export_meta_json(config: WorldGenConfig, actual_seed: int, backend_name: String, params: NoiseParams) -> void:
	var json_dict: Dictionary = {
		"name": config.world_name,
		"seed": actual_seed,
		"created": Time.get_datetime_string_from_system(),
		"version": "3.0",
		"chunk_size": config.chunk_size,
		"chunk_count_x": config.chunk_count_x,
		"chunk_count_z": config.chunk_count_z,
		"region_size": config.region_size,
		"height_range": {"min": config.height_range_min, "max": config.height_range_max},
		"torus_radius": config.torus_radius,
		"generation_backend": backend_name,
		"generation_params": {
			"height_scale": params.height_scale,
			"octaves": params.octaves,
			"persistence": params.persistence,
			"lacunarity": params.lacunarity,
			"biome_temperature_scale": params.biome_temperature_scale,
			"biome_moisture_scale": params.biome_moisture_scale,
			"water_level": params.water_level,
			"continental_freq": params.continental_freq,
			"continental_octaves": params.continental_octaves,
			"continental_weight": params.continental_weight,
			"mountain_mask_freq": params.mountain_mask_freq,
			"mountain_mask_octaves": params.mountain_mask_octaves,
			"mountain_mask_edge0": params.mountain_mask_edge0,
			"mountain_mask_edge1": params.mountain_mask_edge1,
			"mountain_freq": params.mountain_freq,
			"mountain_octaves": params.mountain_octaves,
			"mountain_persistence": params.mountain_persistence,
			"mountain_lacunarity": params.mountain_lacunarity,
			"plains_freq": params.plains_freq,
			"plains_octaves": params.plains_octaves,
			"plains_persistence": params.plains_persistence,
			"detail_freq": params.detail_freq,
			"detail_octaves": params.detail_octaves,
			"detail_persistence": params.detail_persistence,
			"detail_lacunarity": params.detail_lacunarity,
			"detail_weight": params.detail_weight,
			"power_exponent": params.power_exponent,
		},
	}
	var json_str: String = JSON.stringify(json_dict, "\t")
	var json_path: String = "res://data/worlds/%s/world_meta.json" % config.world_name
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()


func _bake_all_navmeshes(config: WorldGenConfig) -> void:
	var total_chunks: int = config.chunk_count_x * config.chunk_count_z
	print("WorldGenerator: baking navmeshes for %d chunks (async)..." % total_chunks)
	NavMeshGenerator.ensure_navmesh_dir(config.world_name)

	var region_count_x: int = floori(config.chunk_count_x / float(config.region_size))
	var region_count_z: int = floori(config.chunk_count_z / float(config.region_size))

	var counters := { "completed": 0, "in_flight": 0 }

	var regions: Array[RegionData] = []
	for rrx: int in range(region_count_x):
		for rrz: int in range(region_count_z):
			var region_path: String = "res://data/worlds/%s/regions/region_%02d_%02d.res" % [config.world_name, rrx, rrz]
			var region: RegionData = ResourceLoader.load(region_path, "", ResourceLoader.CACHE_MODE_REUSE)
			if region == null:
				push_error("WorldGenerator: failed to load region %s for navmesh baking" % region_path)
			regions.append(region)

	for rrx: int in range(region_count_x):
		for rrz: int in range(region_count_z):
			var region: RegionData = regions[rrx * region_count_z + rrz]
			if region == null:
				counters["completed"] += RegionData.REGION_SIZE * RegionData.REGION_SIZE
				continue
			for local_rx: int in range(RegionData.REGION_SIZE):
				for local_rz: int in range(RegionData.REGION_SIZE):
					var chunk_rx: int = region.region_rx * RegionData.REGION_SIZE + local_rx
					var chunk_rz: int = region.region_rz * RegionData.REGION_SIZE + local_rz
					var chunk_data: ChunkData = ChunkData.from_region(region, local_rx, local_rz)
					if chunk_data == null or chunk_data.heightmap.is_empty():
						counters["completed"] += 1
						continue
					var navmesh := NavMeshGenerator.create_navmesh_config()
					var source_geometry := NavMeshGenerator.create_source_geometry(chunk_data)
					var baked_callback := _make_bake_callback(navmesh, config.world_name, chunk_rx, chunk_rz, counters)
					NavMeshGenerator.bake_prepared_navmesh_async(navmesh, source_geometry, baked_callback)
					counters["in_flight"] += 1

					while counters["in_flight"] >= MAX_CONCURRENT_BAKES:
						await Engine.get_main_loop().process_frame

	progress_changed.emit(0.5, "navmesh")

	while counters["completed"] < total_chunks:
		await Engine.get_main_loop().process_frame
		progress_changed.emit(0.5 + float(counters["completed"]) / float(total_chunks) * 0.5, "navmesh")
		navmesh_progress.emit(float(counters["completed"]) / float(total_chunks))

	progress_changed.emit(1.0, "navmesh")
	navmesh_progress.emit(1.0)
	print("WorldGenerator: navmesh baking complete! %d/%d chunks" % [counters["completed"], total_chunks])


func _make_bake_callback(navmesh: NavigationMesh, world_name: String, chunk_rx: int, chunk_rz: int, counters: Dictionary) -> Callable:
	return func() -> void:
		NavMeshGenerator.save_navmesh(navmesh, world_name, chunk_rx, chunk_rz)
		counters["completed"] += 1
		counters["in_flight"] -= 1


func rebuild_navmeshes(world_name: String, chunk_count_x: int, chunk_count_z: int, region_size: int) -> void:
	var nav_dir: String = "res://data/worlds/%s/navmeshes" % world_name
	if DirAccess.dir_exists_absolute(nav_dir):
		var dir := DirAccess.open(nav_dir)
		if dir:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".res"):
					dir.remove(file_name)
				file_name = dir.get_next()
	var config := WorldGenConfig.new()
	config.world_name = world_name
	config.chunk_count_x = chunk_count_x
	config.chunk_count_z = chunk_count_z
	config.region_size = region_size
	await _bake_all_navmeshes(config)
