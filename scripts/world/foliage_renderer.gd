class_name FoliageRenderer
extends Node3D

var FOLIAGE_TYPES: Dictionary = {
	"grass": {"max_per_chunk": 1500, "mesh_lo": null, "mesh_hi": null},
	"bush": {"max_per_chunk": 30, "mesh_lo": null, "mesh_hi": null},
	"tree": {"max_per_chunk": 10, "mesh_lo": null, "mesh_hi": null},
}

var _pool: Dictionary = {}
var _active: Dictionary = {}

var _foliage_queue: Array[Dictionary] = []
const FOLIAGE_PER_FRAME: int = 2

var _grass_mesh: ArrayMesh
var _bush_mesh: ArrayMesh
var _tree_mesh: ArrayMesh
var _foliage_material: ShaderMaterial


func _ready() -> void:
	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = preload("res://assets/shaders/foliage.gdshader")
	_grass_mesh = _create_grass_card()
	_bush_mesh = _create_bush_mesh()
	_tree_mesh = _create_tree_mesh()
	FOLIAGE_TYPES["grass"]["mesh_lo"] = _grass_mesh
	FOLIAGE_TYPES["bush"]["mesh_lo"] = _bush_mesh
	FOLIAGE_TYPES["tree"]["mesh_lo"] = _tree_mesh
	add_to_group("foliage_renderer")


func _process(_delta: float) -> void:
	for _i: int in range(mini(FOLIAGE_PER_FRAME, _foliage_queue.size())):
		var entry: Dictionary = _foliage_queue.pop_front()
		_process_foliage_chunk(entry)


func queue_generation(chunk_pos: Vector2i, heightmap: PackedFloat32Array, water_level: float, seed_value: int, chunk_offset: Vector3) -> void:
	_foliage_queue.append({
		"chunk_pos": chunk_pos,
		"heightmap": heightmap,
		"water_level": water_level,
		"seed_value": seed_value,
		"chunk_offset": chunk_offset,
	})


func populate(chunk_pos: Vector2i, foliage_data: Dictionary, chunk_offset: Vector3) -> void:
	_foliage_queue.append({
		"chunk_pos": chunk_pos,
		"foliage_data": foliage_data,
		"chunk_offset": chunk_offset,
	})


func _process_foliage_chunk(entry: Dictionary) -> void:
	var chunk_pos: Vector2i = entry["chunk_pos"]
	var chunk_offset: Vector3 = entry["chunk_offset"]

	var foliage_data: Dictionary
	if entry.has("foliage_data"):
		foliage_data = entry["foliage_data"]
	else:
		foliage_data = FoliageGenerator.generate_foliage_for_chunk(
			chunk_pos.x, chunk_pos.y,
			entry["heightmap"],
			entry["water_level"],
			entry["seed_value"]
		)

	clear_chunk(chunk_pos)

	for type_name: String in foliage_data:
		var instance_data: FoliageInstanceData = foliage_data[type_name]
		if instance_data == null or instance_data.instance_count() == 0:
			continue

		var mmi: MultiMeshInstance3D = _acquire_mmi(type_name, chunk_pos)
		mmi.position = chunk_offset
		var mm: MultiMesh = mmi.multimesh
		mm.instance_count = instance_data.instance_count()

		for i: int in range(instance_data.instance_count()):
			var pos: Vector3 = instance_data.positions[i]
			var rot: float = instance_data.rotations[i]
			var s: float = instance_data.scales[i]
			var i_basis := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(i_basis, pos))
			mm.set_instance_color(i, instance_data.colors[i])
			mm.set_instance_custom_data(i, instance_data.custom_data[i])

		mm.custom_aabb = AABB(Vector3.ZERO, Vector3(float(ChunkData.CHUNK_SIZE), 100.0, float(ChunkData.CHUNK_SIZE)))
		mmi.visible = true

	_active[chunk_pos] = true


func set_chunk_world_pos(chunk_pos: Vector2i, world_x: float, world_z: float) -> void:
	for type_name: String in FOLIAGE_TYPES:
		var key := _pool_key(type_name, chunk_pos)
		var mmi: MultiMeshInstance3D = _pool.get(key)
		if mmi:
			mmi.position = Vector3(world_x, 0.0, world_z)


func clear_chunk(chunk_pos: Vector2i) -> void:
	for type_name: String in FOLIAGE_TYPES:
		var key := _pool_key(type_name, chunk_pos)
		var mmi: MultiMeshInstance3D = _pool.get(key)
		if mmi:
			mmi.multimesh.instance_count = 0
			mmi.visible = false
	_active.erase(chunk_pos)


func _acquire_mmi(type_name: String, chunk_pos: Vector2i) -> MultiMeshInstance3D:
	var key: String = _pool_key(type_name, chunk_pos)
	if _pool.has(key):
		return _pool[key]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = FOLIAGE_TYPES[type_name]["mesh_lo"]

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _foliage_material
	mmi.visible = false
	add_child(mmi)
	_pool[key] = mmi
	return mmi


func _pool_key(type_name: String, chunk_pos: Vector2i) -> String:
	return "%s_%d_%d" % [type_name, chunk_pos.x, chunk_pos.y]


func _create_grass_card() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(-0.5, 0.0, 0.0))
	st.add_vertex(Vector3(0.5, 0.0, 0.0))
	st.add_vertex(Vector3(-0.25, 1.0, 0.0))
	st.add_vertex(Vector3(0.5, 0.0, 0.0))
	st.add_vertex(Vector3(0.25, 1.0, 0.0))
	st.add_vertex(Vector3(-0.25, 1.0, 0.0))
	return st.commit()


func _create_bush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(-0.5, 0.0, -0.5))
	st.add_vertex(Vector3(0.5, 0.0, -0.5))
	st.add_vertex(Vector3(0.0, 0.8, 0.0))
	st.add_vertex(Vector3(0.5, 0.0, 0.5))
	st.add_vertex(Vector3(-0.5, 0.0, 0.5))
	st.add_vertex(Vector3(0.0, 0.8, 0.0))
	st.add_vertex(Vector3(-0.5, 0.0, -0.5))
	st.add_vertex(Vector3(-0.5, 0.0, 0.5))
	st.add_vertex(Vector3(0.0, 0.8, 0.0))
	st.add_vertex(Vector3(0.5, 0.0, -0.5))
	st.add_vertex(Vector3(0.5, 0.0, 0.5))
	st.add_vertex(Vector3(0.0, 0.8, 0.0))
	return st.commit()


func _create_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h: float = 2.0
	var trunk_r: float = 0.15
	st.add_vertex(Vector3(-trunk_r, 0.0, -trunk_r))
	st.add_vertex(Vector3(trunk_r, 0.0, -trunk_r))
	st.add_vertex(Vector3(0.0, trunk_h, 0.0))
	st.add_vertex(Vector3(trunk_r, 0.0, -trunk_r))
	st.add_vertex(Vector3(trunk_r, 0.0, trunk_r))
	st.add_vertex(Vector3(0.0, trunk_h, 0.0))
	st.add_vertex(Vector3(trunk_r, 0.0, trunk_r))
	st.add_vertex(Vector3(-trunk_r, 0.0, trunk_r))
	st.add_vertex(Vector3(0.0, trunk_h, 0.0))
	st.add_vertex(Vector3(-trunk_r, 0.0, trunk_r))
	st.add_vertex(Vector3(-trunk_r, 0.0, -trunk_r))
	st.add_vertex(Vector3(0.0, trunk_h, 0.0))
	var canopy_y: float = trunk_h
	var canopy_r: float = 1.2
	var canopy_h: float = 1.5
	st.add_vertex(Vector3(-canopy_r, canopy_y, -canopy_r))
	st.add_vertex(Vector3(canopy_r, canopy_y, -canopy_r))
	st.add_vertex(Vector3(0.0, canopy_y + canopy_h, 0.0))
	st.add_vertex(Vector3(canopy_r, canopy_y, canopy_r))
	st.add_vertex(Vector3(-canopy_r, canopy_y, canopy_r))
	st.add_vertex(Vector3(0.0, canopy_y + canopy_h, 0.0))
	st.add_vertex(Vector3(-canopy_r, canopy_y, -canopy_r))
	st.add_vertex(Vector3(-canopy_r, canopy_y, canopy_r))
	st.add_vertex(Vector3(0.0, canopy_y + canopy_h, 0.0))
	st.add_vertex(Vector3(canopy_r, canopy_y, -canopy_r))
	st.add_vertex(Vector3(canopy_r, canopy_y, canopy_r))
	st.add_vertex(Vector3(0.0, canopy_y + canopy_h, 0.0))
	return st.commit()
