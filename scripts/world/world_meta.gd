@tool
class_name WorldMeta
extends Resource

@export var world_name: String = "kaelor_alpha"
@export var seed_value: int = 0
@export var created: String = ""
@export var version: String = "3.0"
@export var chunk_size: int = 40
@export var chunk_count_x: int = 128
@export var chunk_count_z: int = 128
@export var region_size: int = 8
@export var height_range_min: float = 0.0
@export var height_range_max: float = 40.0
@export var torus_radius: float = 1.0
@export var generation_backend: String = "gdscript"
@export var generation_params: NoiseParams
