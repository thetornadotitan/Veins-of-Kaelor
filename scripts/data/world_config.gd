@tool
class_name WorldGenConfig
extends Resource

@export var seed_value: int = 0
@export var generate_new_seed: bool = true
@export var height_scale: float = 4.0
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 2.0
@export var water_level: float = 8.0
@export var height_range_min: float = 0.0
@export var height_range_max: float = 40.0
@export var torus_radius: float = 1.0
@export var region_size: int = 8
@export var chunk_size: int = 40
@export var chunk_count_x: int = 128
@export var chunk_count_z: int = 128
@export var biome_enabled: bool = false
@export var world_name: String = "kaelor_alpha"

var world_size_x: float:
	get:
		return float(chunk_count_x * chunk_size)

var world_size_z: float:
	get:
		return float(chunk_count_z * chunk_size)
