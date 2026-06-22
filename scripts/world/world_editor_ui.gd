@tool
extends Control

@onready var _seed_input: SpinBox = %SeedInput
@onready var _height_scale_slider: HSlider = %HeightScaleSlider
@onready var _height_scale_label: Label = %HeightScaleLabel
@onready var _octaves_input: SpinBox = %OctavesInput
@onready var _persistence_slider: HSlider = %PersistenceSlider
@onready var _persistence_label: Label = %PersistenceLabel
@onready var _lacunarity_slider: HSlider = %LacunaritySlider
@onready var _lacunarity_label: Label = %LacunarityLabel
@onready var _height_max_input: SpinBox = %HeightMaxInput
@onready var _water_level_input: SpinBox = %WaterLevelInput
@onready var _world_name_input: LineEdit = %WorldNameInput
@onready var _generate_btn: Button = %GenerateBtn
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _log_label: Label = %LogLabel
@onready var _backend_label: Label = %BackendLabel

var _generating: bool = false


func _ready() -> void:
	var has_native: bool = HeightmapGenerator.is_native_available()
	_backend_label.text = "GDExtension C++ (fast)" if has_native else "GDScript fallback (~10-20 min)"
	_update_slider_labels()


func _on_generate_btn_pressed() -> void:
	if _generating:
		return
	_generating = true
	_generate_btn.disabled = true
	_log_label.text = "Generating world..."

	var config := WorldGenConfig.new()
	config.seed_value = int(_seed_input.value)
	config.generate_new_seed = false
	config.height_scale = _height_scale_slider.value
	config.octaves = int(_octaves_input.value)
	config.persistence = _persistence_slider.value
	config.lacunarity = _lacunarity_slider.value
	config.height_range_max = _height_max_input.value
	config.water_level = _water_level_input.value
	config.world_name = _world_name_input.text
	config.chunk_count_x = 128
	config.chunk_count_z = 128
	config.chunk_size = 40
	config.region_size = 8

	var generator := WorldGenerator.new()
	generator.progress_changed.connect(_on_progress)
	generator.generation_complete.connect(_on_complete)
	await generator.generate_world(config)


func _on_progress(ratio: float) -> void:
	_progress_bar.value = ratio * 100.0
	_log_label.text = "Generating... %d%%" % int(ratio * 100.0)


func _on_complete(world_name: String) -> void:
	_generating = false
	_generate_btn.disabled = false
	_log_label.text = "Generation complete! World: %s" % world_name
	_progress_bar.value = 100.0


func _on_randomize_seed_btn_pressed() -> void:
	_seed_input.value = randi()


func _on_height_scale_changed(value: float) -> void:
	_update_slider_labels()


func _on_persistence_changed(value: float) -> void:
	_update_slider_labels()


func _on_lacunarity_changed(value: float) -> void:
	_update_slider_labels()


func _update_slider_labels() -> void:
	if _height_scale_label:
		_height_scale_label.text = "%.1f" % _height_scale_slider.value
	if _persistence_label:
		_persistence_label.text = "%.2f" % _persistence_slider.value
	if _lacunarity_label:
		_lacunarity_label.text = "%.1f" % _lacunarity_slider.value
