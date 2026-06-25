@tool
class_name FoliageGenerator
extends RefCounted

const GRASS_MAX_SLOPE: float = 0.95
const BUSH_MAX_SLOPE: float = 0.95
const TREE_MAX_SLOPE: float = 0.98
const MIN_HEIGHT_VARIANCE: float = 0.75

static func generate_foliage_for_chunk(
	chunk_rx: int,
	chunk_rz: int,
	heightmap: PackedFloat32Array,
	water_level: float,
	rng_seed: int
) -> Dictionary:
	var result: Dictionary = {}
	var grass_data := FoliageInstanceData.new()
	var bush_data := FoliageInstanceData.new()
	var tree_data := FoliageInstanceData.new()

	var rng := RandomNumberGenerator.new()
	var chunk_seed: int = (chunk_rx * 73856093) ^ (chunk_rz * 19349663) ^ rng_seed
	rng.seed = chunk_seed

	var res: int = ChunkData.GRID_RESOLUTION
	var cs: float = float(ChunkData.CHUNK_SIZE)

	var grass_count: int = rng.randi_range(800, 1500)
	var bush_count: int = rng.randi_range(15, 30)
	var tree_count: int = rng.randi_range(5, 10)

	for _i: int in range(grass_count):
		var lx: float = rng.randf() * cs
		var lz: float = rng.randf() * cs
		var gx: int = clampi(roundi(lx), 0, res - 1)
		var gz: int = clampi(roundi(lz), 0, res - 1)
		var h: float = _sample_heightmap(heightmap, res, lx, lz)
		if h < water_level + 0.5:
			continue
		var normal := _compute_normal(heightmap, res, lx, lz)
		if normal.dot(Vector3.UP) < GRASS_MAX_SLOPE:
			continue
		if _local_variance(heightmap, res, gx, gz) > MIN_HEIGHT_VARIANCE:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.6, 1.2)
		var c := Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 0.85 + rng.randf() * 0.15)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.5, 1.0), 0.0, 0.0)
		grass_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom, normal)

	for _i: int in range(bush_count):
		var lx: float = rng.randf_range(2.0, cs - 2.0)
		var lz: float = rng.randf_range(2.0, cs - 2.0)
		var gx: int = clampi(roundi(lx), 0, res - 1)
		var gz: int = clampi(roundi(lz), 0, res - 1)
		var h: float = _sample_heightmap(heightmap, res, lx, lz)
		if h < water_level + 1.0:
			continue
		var normal := _compute_normal(heightmap, res, lx, lz)
		if normal.dot(Vector3.UP) < BUSH_MAX_SLOPE:
			continue
		if _local_variance(heightmap, res, gx, gz) > MIN_HEIGHT_VARIANCE:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.7, 1.5)
		var c := Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 0.85 + rng.randf() * 0.15)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.3, 0.8), 0.0, 0.0)
		bush_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom, normal)

	for _i: int in range(tree_count):
		var lx: float = rng.randf_range(3.0, cs - 3.0)
		var lz: float = rng.randf_range(3.0, cs - 3.0)
		var gx: int = clampi(roundi(lx), 0, res - 1)
		var gz: int = clampi(roundi(lz), 0, res - 1)
		var h: float = _sample_heightmap(heightmap, res, lx, lz)
		if h < water_level + 2.0:
			continue
		var normal := _compute_normal(heightmap, res, lx, lz)
		if normal.dot(Vector3.UP) < TREE_MAX_SLOPE:
			continue
		if _local_variance(heightmap, res, gx, gz) > MIN_HEIGHT_VARIANCE:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.8, 1.5)
		var c := Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 0.85 + rng.randf() * 0.15)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.2, 0.7), 0.0, 0.0)
		tree_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom, normal)

	result["grass"] = grass_data
	result["bush"] = bush_data
	result["tree"] = tree_data
	return result


static func _local_variance(heightmap: PackedFloat32Array, res: int, cx: int, cz: int) -> float:
	var sr: int = res + 2
	var r: int = 2
	var sum: float = 0.0
	var sum_sq: float = 0.0
	var count: int = 0
	for dz: int in range(-r, r + 1):
		var nz: int = clampi(cz + dz + 1, 0, sr - 1)
		for dx: int in range(-r, r + 1):
			var nx: int = clampi(cx + dx + 1, 0, sr - 1)
			var hv: float = heightmap[nz * sr + nx]
			sum += hv
			sum_sq += hv * hv
			count += 1
	if count == 0:
		return 0.0
	var mean: float = sum / float(count)
	return (sum_sq / float(count)) - (mean * mean)


static func _compute_normal(heightmap: PackedFloat32Array, res: int, local_x: float, local_z: float) -> Vector3:
	var step: float = 1.0
	var h_m_x: float = _sample_heightmap(heightmap, res, local_x - step, local_z)
	var h_p_x: float = _sample_heightmap(heightmap, res, local_x + step, local_z)
	var h_m_z: float = _sample_heightmap(heightmap, res, local_x, local_z - step)
	var h_p_z: float = _sample_heightmap(heightmap, res, local_x, local_z + step)
	var n := Vector3(h_m_x - h_p_x, 2.0 * step, h_m_z - h_p_z)
	if n.length_squared() < 1e-8:
		return Vector3.UP
	return n.normalized()


static func _sample_heightmap(heightmap: PackedFloat32Array, res: int, local_x: float, local_z: float) -> float:
	var sr: int = res + 2
	var fx: float = clampf(local_x + 1.0, 0.0, float(sr - 1))
	var fz: float = clampf(local_z + 1.0, 0.0, float(sr - 1))
	var x0: int = int(fx)
	var z0: int = int(fz)
	var x1: int = mini(x0 + 1, sr - 1)
	var z1: int = mini(z0 + 1, sr - 1)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heightmap[z0 * sr + x0]
	var h10: float = heightmap[z0 * sr + x1]
	var h01: float = heightmap[z1 * sr + x0]
	var h11: float = heightmap[z1 * sr + x1]
	var h0: float = h00 * (1.0 - tx) + h10 * tx
	var h1: float = h01 * (1.0 - tx) + h11 * tx
	return h0 * (1.0 - tz) + h1 * tz
