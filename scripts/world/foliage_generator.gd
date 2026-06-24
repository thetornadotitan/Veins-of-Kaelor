@tool
class_name FoliageGenerator
extends RefCounted

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
	var chunk_seed: int = chunk_rx * 73856093 ^ chunk_rz * 19349663 ^ rng_seed
	rng.seed = absi(chunk_seed)

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
		var h: float = heightmap[gz * res + gx]
		if h < water_level + 0.5:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.6, 1.2)
		var c := Color(0.15 + rng.randf() * 0.15, 0.4 + rng.randf() * 0.2, 0.1 + rng.randf() * 0.1)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.5, 1.0), 0.0, 0.0)
		grass_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom)

	for _i: int in range(bush_count):
		var lx: float = rng.randf_range(2.0, cs - 2.0)
		var lz: float = rng.randf_range(2.0, cs - 2.0)
		var gx: int = clampi(roundi(lx), 0, res - 1)
		var gz: int = clampi(roundi(lz), 0, res - 1)
		var h: float = heightmap[gz * res + gx]
		if h < water_level + 1.0:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.7, 1.5)
		var c := Color(0.1 + rng.randf() * 0.1, 0.3 + rng.randf() * 0.2, 0.08)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.3, 0.8), 0.0, 0.0)
		bush_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom)

	for _i: int in range(tree_count):
		var lx: float = rng.randf_range(3.0, cs - 3.0)
		var lz: float = rng.randf_range(3.0, cs - 3.0)
		var gx: int = clampi(roundi(lx), 0, res - 1)
		var gz: int = clampi(roundi(lz), 0, res - 1)
		var h: float = heightmap[gz * res + gx]
		if h < water_level + 2.0:
			continue
		var rot: float = rng.randf() * TAU
		var s: float = rng.randf_range(0.8, 1.5)
		var c := Color(0.3 + rng.randf() * 0.15, 0.2 + rng.randf() * 0.1, 0.05 + rng.randf() * 0.05)
		var custom := Color(rng.randf() * TAU, rng.randf_range(0.2, 0.7), 0.0, 0.0)
		tree_data.add_instance(Vector3(lx, h, lz), rot, s, c, custom)

	result["grass"] = grass_data
	result["bush"] = bush_data
	result["tree"] = tree_data
	return result
