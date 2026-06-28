@tool
class_name WorldGenConfig
extends Resource

@export var seed_value: int = 0
@export var generate_new_seed: bool = true
@export var height_scale: float = 4.0
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 2.0
@export var water_level: float = 15.0
@export var height_range_min: float = 0.0
@export var height_range_max: float = 80.0
@export var torus_radius: float = 1.0
@export var region_size: int = 8
@export var chunk_size: int = 40
@export var chunk_count_x: int = 128
@export var chunk_count_z: int = 128
@export var biome_enabled: bool = false
@export var world_name: String = "kaelor_alpha"

@export_group("Continental", "continental_")
@export var continental_freq: float = 0.2
@export var continental_octaves: int = 2
@export var continental_edge0: float = 0.52
@export var continental_edge1: float = 0.68
@export var continental_warp_strength: float = 0.3
@export var continental_warp_freq: float = 0.6

@export_group("Mountain Mask", "mountain_mask_")
@export var mountain_mask_freq: float = 2.0
@export var mountain_mask_octaves: int = 2
@export var mountain_mask_edge0: float = 0.35
@export var mountain_mask_edge1: float = 0.65

@export_group("Mountain Ridges", "mountain_")
@export var mountain_freq: float = 4.0
@export var mountain_octaves: int = 5
@export var mountain_persistence: float = 0.50
@export var mountain_lacunarity: float = 2.0

@export_group("Plains", "plains_")
@export var plains_freq: float = 3.0
@export var plains_octaves: int = 3
@export var plains_persistence: float = 0.3

@export_group("Detail", "detail_")
@export var detail_freq: float = 30.0
@export var detail_octaves: int = 2
@export var detail_persistence: float = 0.25
@export var detail_lacunarity: float = 2.5
@export var detail_weight: float = 0.03

@export_group("Power Curve", "power_")
@export var power_exponent: float = 1.5

var world_size_x: float:
	get:
		return float(chunk_count_x * chunk_size)

var world_size_z: float:
	get:
		return float(chunk_count_z * chunk_size)
