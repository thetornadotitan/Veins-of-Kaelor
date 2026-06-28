@tool
class_name WorldGenerator
extends RefCounted

signal progress_changed(ratio: float, stage: String)
signal generation_complete(world_name: String)
signal region_saved(rrx: int, rrz: int)
signal navmesh_progress(ratio: float)
signal step_progress(stage: String, done: int, total: int, chunk_x: int, chunk_z: int, elapsed_sec: float, remaining_sec: float)

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
	params.continental_edge0 = config.continental_edge0
	params.continental_edge1 = config.continental_edge1
	params.continental_warp_strength = config.continental_warp_strength
	params.continental_warp_freq = config.continental_warp_freq
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
	var t_start: float = Time.get_ticks_msec() / 1000.0

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
					var elapsed: float = Time.get_ticks_msec() / 1000.0 - t_start
					var rate: float = chunks_done / elapsed if elapsed > 0.01 else 0.0
					var remaining: float = (float(total_chunks - chunks_done) / rate) if rate > 0.01 else 0.0
					step_progress.emit("terrain", chunks_done, total_chunks, chunk_rx, chunk_rz, elapsed, remaining)

			var region_path: String = "res://data/worlds/%s/regions/region_%02d_%02d.res" % [config.world_name, rrx, rrz]
			var err: int = ResourceSaver.save(region, region_path)
			if err != OK:
				push_error("WorldGenerator: failed to save region %s: error %d" % [region_path, err])

			region_saved.emit(rrx, rrz)
			progress_changed.emit(float(chunks_done) / float(total_chunks) * 0.5, "terrain")
			await Engine.get_main_loop().process_frame

	_save_world_meta(config, actual_seed, backend_name, params)
	_export_meta_json(config, actual_seed, backend_name, params)

	await _bake_all_nav_regions(config)

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
			"continental_edge0": params.continental_edge0,
			"continental_edge1": params.continental_edge1,
			"continental_warp_strength": params.continental_warp_strength,
			"continental_warp_freq": params.continental_warp_freq,
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


func _bake_all_nav_regions(config: WorldGenConfig) -> void:
	var region_count_x: int = floori(config.chunk_count_x / float(config.region_size))
	var region_count_z: int = floori(config.chunk_count_z / float(config.region_size))
	var total_regions: int = region_count_x * region_count_z
	print("WorldGenerator: baking nav regions for %d regions..." % total_regions)
	NavMeshGenerator.ensure_nav_region_dir(config.world_name)
	NavMeshGenerator.delete_old_chunk_navmeshes(config.world_name)

	var counters := { "completed": 0, "in_flight": 0, "last_rrx": 0, "last_rrz": 0 }

	var regions: Array[RegionData] = []
	for rrx: int in range(region_count_x):
		for rrz: int in range(region_count_z):
			var region_path: String = "res://data/worlds/%s/regions/region_%02d_%02d.res" % [config.world_name, rrx, rrz]
			var region: RegionData = ResourceLoader.load(region_path, "", ResourceLoader.CACHE_MODE_REUSE)
			if region == null:
				push_error("WorldGenerator: failed to load region %s for nav baking" % region_path)
			regions.append(region)

	var nav_start_msec: float = Time.get_ticks_msec()

	for rrx: int in range(region_count_x):
		for rrz: int in range(region_count_z):
			var region: RegionData = regions[rrx * region_count_z + rrz]
			if region == null:
				counters["completed"] += 1
				continue

			var navmesh := NavMeshGenerator.create_region_navmesh_config(config.region_size, config.chunk_size)
			var source_geometry := NavMeshGenerator.create_region_source_geometry(region, config.region_size, config.chunk_size)
			var baked_callback := _make_region_bake_callback(navmesh, config.world_name, rrx, rrz, counters)
			NavigationServer3D.bake_from_source_geometry_data_async(navmesh, source_geometry, baked_callback)
			counters["in_flight"] += 1
			counters["last_rrx"] = rrx
			counters["last_rrz"] = rrz

			while counters["in_flight"] >= MAX_CONCURRENT_BAKES:
				var elapsed_sec: float = (Time.get_ticks_msec() - nav_start_msec) / 1000.0
				var done: int = counters["completed"]
				var rate: float = done / elapsed_sec if elapsed_sec > 0.01 else 0.0
				var remaining_sec: float = (float(total_regions - done) / rate) if rate > 0.01 else 0.0
				var total_chunks_done: int = done * config.region_size * config.region_size
				var last_cx: int = counters["last_rrx"] * config.region_size
				var last_cz: int = counters["last_rrz"] * config.region_size
				step_progress.emit("navmesh", total_chunks_done, config.chunk_count_x * config.chunk_count_z, last_cx, last_cz, elapsed_sec, remaining_sec)
				await Engine.get_main_loop().process_frame

	progress_changed.emit(0.5, "navmesh")

	var last_emit_msec: float = 0.0
	while counters["completed"] < total_regions:
		var now_msec: float = Time.get_ticks_msec()
		if now_msec - last_emit_msec >= 100.0:
			var elapsed_sec: float = (now_msec - nav_start_msec) / 1000.0
			var done: int = counters["completed"]
			var rate: float = done / elapsed_sec if elapsed_sec > 0.01 else 0.0
			var remaining_sec: float = (float(total_regions - done) / rate) if rate > 0.01 else 0.0
			var nav_ratio: float = float(done) / float(total_regions)
			progress_changed.emit(0.5 + nav_ratio * 0.5, "navmesh")
			navmesh_progress.emit(nav_ratio)
			var total_chunks_done: int = done * config.region_size * config.region_size
			var last_cx: int = counters["last_rrx"] * config.region_size
			var last_cz: int = counters["last_rrz"] * config.region_size
			step_progress.emit("navmesh", total_chunks_done, config.chunk_count_x * config.chunk_count_z, last_cx, last_cz, elapsed_sec, remaining_sec)
			last_emit_msec = now_msec
		await Engine.get_main_loop().process_frame

	progress_changed.emit(1.0, "navmesh")
	navmesh_progress.emit(1.0)
	print("WorldGenerator: nav region baking complete! %d/%d regions" % [counters["completed"], total_regions])


func _make_region_bake_callback(navmesh: NavigationMesh, world_name: String, rrx: int, rrz: int, counters: Dictionary) -> Callable:
	return func() -> void:
		NavMeshGenerator.save_nav_region(navmesh, world_name, rrx, rrz)
		counters["completed"] += 1
		counters["in_flight"] -= 1
		counters["last_rrx"] = rrx
		counters["last_rrz"] = rrz


func rebuild_navmeshes(world_name: String, chunk_count_x: int, chunk_count_z: int, region_size: int) -> void:
	NavMeshGenerator.delete_old_chunk_navmeshes(world_name)
	NavMeshGenerator.ensure_nav_region_dir(world_name)
	var config := WorldGenConfig.new()
	config.world_name = world_name
	config.chunk_count_x = chunk_count_x
	config.chunk_count_z = chunk_count_z
	config.region_size = region_size
	config.chunk_size = ChunkData.CHUNK_SIZE
	await _bake_all_nav_regions(config)
