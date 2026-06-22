@tool
class_name WorldGenerator
extends RefCounted

signal progress_changed(ratio: float)
signal generation_complete(world_name: String)
signal region_saved(rrx: int, rrz: int)


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
			progress_changed.emit(float(chunks_done) / float(total_chunks))
			await Engine.get_main_loop().process_frame

	_save_world_meta(config, actual_seed, backend_name, params)
	_export_meta_json(config, actual_seed, backend_name, params)

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
		},
	}
	var json_str: String = JSON.stringify(json_dict, "\t")
	var json_path: String = "res://data/worlds/%s/world_meta.json" % config.world_name
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
