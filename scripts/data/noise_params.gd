@tool
class_name NoiseParams
extends Resource

@export var height_scale: float = 4.0
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 2.0
@export var biome_temperature_scale: float = 0.005
@export var biome_moisture_scale: float = 0.008
@export var water_level: float = 15.0
@export var height_range_min: float = 0.0
@export var height_range_max: float = 80.0

@export_group("Continental", "continental_")
@export var continental_freq: float = 1.5
@export var continental_octaves: int = 2
@export var continental_weight: float = 0.35

@export_group("Mountain Mask", "mountain_mask_")
@export var mountain_mask_freq: float = 2.0
@export var mountain_mask_octaves: int = 2
@export var mountain_mask_edge0: float = 0.35
@export var mountain_mask_edge1: float = 0.65
@export var mountain_mask_offset: float = 100.0

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
@export var detail_offset: float = 200.0

@export_group("Power Curve", "power_")
@export var power_exponent: float = 1.5
