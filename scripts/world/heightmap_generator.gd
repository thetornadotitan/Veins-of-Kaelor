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

	for lz: int in range(res):
		for lx: int in range(res):
			var wx: float = base_x + float(lx)
			var wz: float = base_z + float(lz)

			var nx: float = torus_radius * cos(two_pi_over_size * wx)
			var ny: float = torus_radius * sin(two_pi_over_size * wx)
			var nz: float = torus_radius * cos(two_pi_over_size * wz)
			var nw: float = torus_radius * sin(two_pi_over_size * wz)

			var height: float
			if use_native:
				height = noise.get_noise_4d_fbm(
					nx, ny, nz, nw,
					params.octaves,
					params.height_scale,
					params.persistence,
					params.lacunarity
				)
			else:
				height = noise.noise_4d_fbm(
					nx, ny, nz, nw,
					params.octaves,
					params.height_scale,
					params.persistence,
					params.lacunarity
				)

			heightmap[lz * res + lx] = (height * 0.5 + 0.5) * (params.height_range_max - params.height_range_min) + params.height_range_min

	return heightmap
