@tool
class_name ChunkData
extends RefCounted

const CHUNK_SIZE: int = 40
const GRID_RESOLUTION: int = 41
const SAMPLE_RESOLUTION: int = GRID_RESOLUTION + 2

var chunk_rx: int
var chunk_rz: int
var heightmap: PackedFloat32Array
var biome: int = 0


static func from_region(region: RegionData, local_rx: int, local_rz: int) -> ChunkData:
	var cd := ChunkData.new()
	var hm: PackedFloat32Array = region.get_chunk_heightmap(local_rx, local_rz)
	if not hm.is_empty() and hm.size() == GRID_RESOLUTION * GRID_RESOLUTION:
		hm = _expand_heightmap_border(hm)
	cd.heightmap = hm
	var biome_index: int = local_rz * RegionData.REGION_SIZE + local_rx
	cd.biome = region.chunk_biomes[biome_index]
	cd.chunk_rx = region.region_rx * RegionData.REGION_SIZE + local_rx
	cd.chunk_rz = region.region_rz * RegionData.REGION_SIZE + local_rz
	return cd


static func _expand_heightmap_border(hm: PackedFloat32Array) -> PackedFloat32Array:
	var gr: int = GRID_RESOLUTION
	var sr: int = SAMPLE_RESOLUTION
	var out := PackedFloat32Array()
	out.resize(sr * sr)
	for lz: int in range(sr):
		for lx: int in range(sr):
			var sx: int = clampi(lx - 1, 0, gr - 1)
			var sz: int = clampi(lz - 1, 0, gr - 1)
			out[lz * sr + lx] = hm[sz * gr + sx]
	return out


func get_height_at(local_x: float, local_z: float) -> float:
	var fx: float = clampf(local_x + 1.0, 0.0, float(SAMPLE_RESOLUTION - 1))
	var fz: float = clampf(local_z + 1.0, 0.0, float(SAMPLE_RESOLUTION - 1))
	var x0: int = int(fx)
	var z0: int = int(fz)
	var x1: int = mini(x0 + 1, SAMPLE_RESOLUTION - 1)
	var z1: int = mini(z0 + 1, SAMPLE_RESOLUTION - 1)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heightmap[z0 * SAMPLE_RESOLUTION + x0]
	var h10: float = heightmap[z0 * SAMPLE_RESOLUTION + x1]
	var h01: float = heightmap[z1 * SAMPLE_RESOLUTION + x0]
	var h11: float = heightmap[z1 * SAMPLE_RESOLUTION + x1]
	var h0: float = h00 * (1.0 - tx) + h10 * tx
	var h1: float = h01 * (1.0 - tx) + h11 * tx
	return h0 * (1.0 - tz) + h1 * tz


func get_normal_at(local_x: float, local_z: float) -> Vector3:
	var step: float = 1.0
	var h_m_x: float = get_height_at(local_x - step, local_z)
	var h_p_x: float = get_height_at(local_x + step, local_z)
	var h_m_z: float = get_height_at(local_x, local_z - step)
	var h_p_z: float = get_height_at(local_x, local_z + step)
	var n := Vector3(h_m_x - h_p_x, 2.0 * step, h_m_z - h_p_z)
	if n.length_squared() < 1e-8:
		return Vector3.UP
	return n.normalized()


func get_vertex(lx: int, lz: int) -> Vector3:
	var h: float = heightmap[(lz + 1) * SAMPLE_RESOLUTION + (lx + 1)]
	return Vector3(float(lx), h, float(lz))
