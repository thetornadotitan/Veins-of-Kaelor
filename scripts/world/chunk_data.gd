@tool
class_name ChunkData
extends RefCounted

const CHUNK_SIZE: int = 40
const GRID_RESOLUTION: int = 41

var chunk_rx: int
var chunk_rz: int
var heightmap: PackedFloat32Array
var biome: int = 0


static func from_region(region: RegionData, local_rx: int, local_rz: int) -> ChunkData:
	var cd := ChunkData.new()
	cd.heightmap = region.get_chunk_heightmap(local_rx, local_rz)
	var biome_index: int = local_rz * RegionData.REGION_SIZE + local_rx
	cd.biome = region.chunk_biomes[biome_index]
	cd.chunk_rx = region.region_rx * RegionData.REGION_SIZE + local_rx
	cd.chunk_rz = region.region_rz * RegionData.REGION_SIZE + local_rz
	return cd


func get_height_at(local_x: float, local_z: float) -> float:
	var fx: float = clampf(local_x, 0.0, float(GRID_RESOLUTION - 1))
	var fz: float = clampf(local_z, 0.0, float(GRID_RESOLUTION - 1))
	var x0: int = int(fx)
	var z0: int = int(fz)
	var x1: int = mini(x0 + 1, GRID_RESOLUTION - 1)
	var z1: int = mini(z0 + 1, GRID_RESOLUTION - 1)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heightmap[z0 * GRID_RESOLUTION + x0]
	var h10: float = heightmap[z0 * GRID_RESOLUTION + x1]
	var h01: float = heightmap[z1 * GRID_RESOLUTION + x0]
	var h11: float = heightmap[z1 * GRID_RESOLUTION + x1]
	var h0: float = h00 * (1.0 - tx) + h10 * tx
	var h1: float = h01 * (1.0 - tx) + h11 * tx
	return h0 * (1.0 - tz) + h1 * tz


func get_vertex(lx: int, lz: int) -> Vector3:
	var h: float = heightmap[lz * GRID_RESOLUTION + lx]
	return Vector3(float(lx), h, float(lz))
