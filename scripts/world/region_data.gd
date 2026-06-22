@tool
class_name RegionData
extends Resource

const REGION_SIZE: int = 8

@export var region_rx: int
@export var region_rz: int
@export var chunk_heightmaps: Array[PackedFloat32Array]
@export var chunk_biomes: PackedInt32Array
@export var chunk_count_x: int = 128
@export var chunk_count_z: int = 128


func get_chunk_heightmap(local_rx: int, local_rz: int) -> PackedFloat32Array:
	var index: int = local_rz * REGION_SIZE + local_rx
	return chunk_heightmaps[index]


func set_chunk_heightmap(local_rx: int, local_rz: int, data: PackedFloat32Array) -> void:
	chunk_heightmaps[local_rz * REGION_SIZE + local_rx] = data


func get_chunk_biome(local_rx: int, local_rz: int) -> int:
	return chunk_biomes[local_rz * REGION_SIZE + local_rx]


func set_chunk_biome(local_rx: int, local_rz: int, biome_id: int) -> void:
	chunk_biomes[local_rz * REGION_SIZE + local_rx] = biome_id


static func create_empty(rx: int, rz: int, c_count_x: int = 128, c_count_z: int = 128) -> RegionData:
	var rd := RegionData.new()
	rd.region_rx = rx
	rd.region_rz = rz
	rd.chunk_count_x = c_count_x
	rd.chunk_count_z = c_count_z
	rd.chunk_heightmaps = []
	rd.chunk_heightmaps.resize(REGION_SIZE * REGION_SIZE)
	for i: int in range(REGION_SIZE * REGION_SIZE):
		rd.chunk_heightmaps[i] = PackedFloat32Array()
	rd.chunk_biomes = PackedInt32Array()
	rd.chunk_biomes.resize(REGION_SIZE * REGION_SIZE)
	return rd
