@tool
class_name HeightmapGenerator
extends RefCounted

static func create_noise(p_seed: int) -> RefCounted:
	if ClassDB.class_exists("SimplexNoise4DNative"):
		var noise = ClassDB.instantiate("SimplexNoise4DNative")
		noise.set_seed(p_seed)
		return noise
	return SimplexNoise4D.new(p_seed)


static func is_native_available() -> bool:
	return ClassDB.class_exists("SimplexNoise4DNative")


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _fbm(noise: RefCounted, use_native: bool, nx: float, ny: float, nz: float, nw: float, octaves: int, freq: float, persistence: float, lacunarity: float) -> float:
	if use_native:
		return noise.get_noise_4d_fbm(nx, ny, nz, nw, octaves, freq, persistence, lacunarity)
	return noise.noise_4d_fbm(nx, ny, nz, nw, octaves, freq, persistence, lacunarity)


static func _ridged_fbm(noise: RefCounted, use_native: bool, nx: float, ny: float, nz: float, nw: float, octaves: int, freq: float, persistence: float, lacunarity: float) -> float:
	if use_native and noise.has_method("get_noise_4d_ridged_fbm"):
		return noise.get_noise_4d_ridged_fbm(nx, ny, nz, nw, octaves, freq, persistence, lacunarity)
	return noise.noise_4d_ridged_fbm(nx, ny, nz, nw, octaves, freq, persistence, lacunarity)


static func generate_chunk_heightmap(
	chunk_rx: int,
	chunk_rz: int,
	noise: RefCounted,
	params: NoiseParams,
	world_size: float,
	torus_radius: float = 1.0
) -> PackedFloat32Array:
	var heightmap := PackedFloat32Array()
	var res: int = ChunkData.GRID_RESOLUTION
	heightmap.resize(res * res)

	var base_x: float = float(chunk_rx * ChunkData.CHUNK_SIZE)
	var base_z: float = float(chunk_rz * ChunkData.CHUNK_SIZE)
	var use_native: bool = noise.has_method("get_noise_4d_fbm")
	var two_pi_over_size: float = TAU / world_size

	var mo: float = params.mountain_mask_offset
	var d_off: float = params.detail_offset

	for lz: int in range(res):
		for lx: int in range(res):
			var wx: float = base_x + float(lx)
			var wz: float = base_z + float(lz)

			var nx: float = torus_radius * cos(two_pi_over_size * wx)
			var ny: float = torus_radius * sin(two_pi_over_size * wx)
			var nz: float = torus_radius * cos(two_pi_over_size * wz)
			var nw: float = torus_radius * sin(two_pi_over_size * wz)

			var continental: float = _fbm(noise, use_native,
				nx, ny, nz, nw,
				params.continental_octaves, params.continental_freq,
				0.5, 2.0)

			var mountain_mask: float = _fbm(noise, use_native,
				nx + mo, ny + mo, nz + mo, nw + mo,
				params.mountain_mask_octaves, params.mountain_mask_freq,
				0.5, 2.0)
			mountain_mask = _smoothstep(
				params.mountain_mask_edge0, params.mountain_mask_edge1,
				mountain_mask * 0.5 + 0.5)

			var mountains: float = _ridged_fbm(noise, use_native,
				nx, ny, nz, nw,
				params.mountain_octaves, params.mountain_freq,
				params.mountain_persistence, params.mountain_lacunarity)

			var plains: float = _fbm(noise, use_native,
				nx, ny, nz, nw,
				params.plains_octaves, params.plains_freq,
				params.plains_persistence, 2.0)

			var elevation: float = lerp(plains, mountains, mountain_mask) + params.continental_weight * continental

			var detail: float = _fbm(noise, use_native,
				nx + d_off, ny + d_off, nz + d_off, nw + d_off,
				params.detail_octaves, params.detail_freq,
				params.detail_persistence, params.detail_lacunarity)
			elevation += detail * params.detail_weight
			elevation = pow(maxf(0.0, elevation), params.power_exponent)

			heightmap[lz * res + lx] = (elevation * 0.5 + 0.5) * (params.height_range_max - params.height_range_min) + params.height_range_min

	return heightmap
