class_name FoliageRenderer
extends Node3D

const PIXEL_SIZE: float = 0.05

var FOLIAGE_TYPES: Dictionary = {
	"grass": {
		"max_per_chunk": 1500,
		"sprite_size": Vector2i(16, 16),
		"texture_path": "res://assets/sprites/foliage/grass.png",
		"mesh_lo": null,
		"scale": 1.0,
		"has_collider": false,
		"collider_width_mod": 1.0,
		"collider_height_ratio": 0.7,
	},
	"bush": {
		"max_per_chunk": 30,
		"sprite_size": Vector2i(16, 16),
		"texture_path": "res://assets/sprites/foliage/bush.png",
		"mesh_lo": null,
		"scale": 1.0,
		"has_collider": true,
		"collider_width_mod": 0.6,
		"collider_height_ratio": 0.5,
	},
	"tree": {
		"max_per_chunk": 10,
		"sprite_size": Vector2i(16, 32),
		"texture_path": "res://assets/sprites/foliage/tree.png",
		"mesh_lo": null,
		"scale": 1.5,
		"has_collider": true,
		"collider_width_mod": 0.3,
		"collider_height_ratio": 0.6,
	},
}

var _pool: Dictionary = {}
var _active: Dictionary = {}
var _materials: Dictionary = {}
var _colliders: Dictionary = {}

var _foliage_queue: Array[Dictionary] = []
const FOLIAGE_PER_FRAME: int = 2


func _ready() -> void:
	var base_shader: Shader = preload("res://assets/shaders/foliage.gdshader")

	for type_name: String in FOLIAGE_TYPES:
		var cfg: Dictionary = FOLIAGE_TYPES[type_name]
		cfg.mesh_lo = _create_cross_plane(cfg.sprite_size)

		var mat := ShaderMaterial.new()
		mat.shader = base_shader
		var tex: Texture2D = load(cfg.texture_path)
		if tex:
			mat.set_shader_parameter("texture_albedo", tex)
		_materials[type_name] = mat

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

		var cfg: Dictionary = FOLIAGE_TYPES[type_name]
		var type_scale: float = cfg.get("scale", 1.0)
		var mmi: MultiMeshInstance3D = _acquire_mmi(type_name, chunk_pos)
		mmi.position = chunk_offset
		var mm: MultiMesh = mmi.multimesh
		mm.instance_count = instance_data.instance_count()

		for i: int in range(instance_data.instance_count()):
			var pos: Vector3 = instance_data.positions[i]
			var rot: float = instance_data.rotations[i]
			var inst_s: float = instance_data.scales[i] * type_scale
			var normal: Vector3 = instance_data.normals[i]
			var inst_basis := _align_to_ground(normal, rot, inst_s)
			mm.set_instance_transform(i, Transform3D(inst_basis, pos))
			mm.set_instance_color(i, instance_data.colors[i])
			mm.set_instance_custom_data(i, instance_data.custom_data[i])

		mm.custom_aabb = AABB(Vector3.ZERO, Vector3(float(ChunkData.CHUNK_SIZE), 100.0, float(ChunkData.CHUNK_SIZE)))
		mmi.visible = true

		if cfg.get("has_collider", false):
			_build_colliders(type_name, chunk_pos, chunk_offset, instance_data, cfg)

	_active[chunk_pos] = true


static func _align_to_ground(normal: Vector3, y_rot: float, inst_scale: float) -> Basis:
	var up := Vector3.UP
	var rot_basis := Basis(up, y_rot)
	var aligned_up := normal.normalized()
	var right := up.cross(aligned_up)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var forward := right.cross(aligned_up).normalized()
	var ground_basis := Basis(right, aligned_up, forward)
	return (ground_basis * rot_basis).scaled(Vector3(inst_scale, inst_scale, inst_scale))


func _build_colliders(type_name: String, chunk_pos: Vector2i, chunk_offset: Vector3, instance_data: FoliageInstanceData, cfg: Dictionary) -> void:
	_clear_colliders(type_name, chunk_pos)
	var width_mod: float = cfg.get("collider_width_mod", 1.0)
	var height_ratio: float = cfg.get("collider_height_ratio", 0.7)
	var sprite_h: float = float(FOLIAGE_TYPES[type_name]["sprite_size"].y) * PIXEL_SIZE * cfg.get("scale", 1.0)
	var sprite_w: float = float(FOLIAGE_TYPES[type_name]["sprite_size"].x) * PIXEL_SIZE * cfg.get("scale", 1.0)
	var capsule_radius: float = (sprite_w * 0.5) * width_mod
	var capsule_height: float = sprite_h * height_ratio

	var parent: Node3D = Node3D.new()
	parent.name = "%s_colliders_%d_%d" % [type_name, chunk_pos.x, chunk_pos.y]
	parent.position = chunk_offset
	add_child(parent)
	_colliders[_collider_key(type_name, chunk_pos)] = parent

	for i: int in range(instance_data.instance_count()):
		var pos: Vector3 = instance_data.positions[i]
		var rot: float = instance_data.rotations[i]
		var inst_s: float = instance_data.scales[i] * cfg.get("scale", 1.0)
		var normal: Vector3 = instance_data.normals[i]

		var shape := CapsuleShape3D.new()
		shape.radius = capsule_radius * inst_s
		shape.height = maxf(capsule_height * inst_s, shape.radius * 2.0 + 0.01)

		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(0.0, shape.height * 0.5, 0.0)
		body.add_child(collision)

		var col_basis := _align_to_ground(normal, rot, inst_s)
		body.transform = Transform3D(col_basis, pos)
		parent.add_child(body)


func set_chunk_world_pos(chunk_pos: Vector2i, world_x: float, world_z: float) -> void:
	for type_name: String in FOLIAGE_TYPES:
		var key := _pool_key(type_name, chunk_pos)
		var mmi: MultiMeshInstance3D = _pool.get(key)
		if mmi:
			mmi.position = Vector3(world_x, 0.0, world_z)
		var ck := _collider_key(type_name, chunk_pos)
		var col_parent: Node3D = _colliders.get(ck)
		if col_parent:
			col_parent.position = Vector3(world_x, 0.0, world_z)


func clear_chunk(chunk_pos: Vector2i) -> void:
	for type_name: String in FOLIAGE_TYPES:
		var key := _pool_key(type_name, chunk_pos)
		var mmi: MultiMeshInstance3D = _pool.get(key)
		if mmi:
			mmi.multimesh.instance_count = 0
			mmi.visible = false
		_clear_colliders(type_name, chunk_pos)
	_active.erase(chunk_pos)


func _clear_colliders(type_name: String, chunk_pos: Vector2i) -> void:
	var ck: String = _collider_key(type_name, chunk_pos)
	var parent: Node3D = _colliders.get(ck)
	if parent:
		parent.queue_free()
		_colliders.erase(ck)


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
	mmi.material_override = _materials[type_name]
	mmi.visible = false
	add_child(mmi)
	_pool[key] = mmi
	return mmi


func _pool_key(type_name: String, chunk_pos: Vector2i) -> String:
	return "%s_%d_%d" % [type_name, chunk_pos.x, chunk_pos.y]


func _collider_key(type_name: String, chunk_pos: Vector2i) -> String:
	return "col_%s_%d_%d" % [type_name, chunk_pos.x, chunk_pos.y]


func _create_cross_plane(sprite_size: Vector2i) -> ArrayMesh:
	var w: float = float(sprite_size.x) * PIXEL_SIZE * 0.5
	var h: float = float(sprite_size.y) * PIXEL_SIZE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(Vector3(-w, 0.0, 0.0))
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(Vector3(w, 0.0, 0.0))
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(Vector3(-w, h, 0.0))
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(Vector3(w, 0.0, 0.0))
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(Vector3(w, h, 0.0))
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(Vector3(-w, h, 0.0))

	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(Vector3(0.0, 0.0, -w))
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(Vector3(0.0, 0.0, w))
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(Vector3(0.0, h, -w))
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(Vector3(0.0, 0.0, w))
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(Vector3(0.0, h, w))
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(Vector3(0.0, h, -w))

	return st.commit()
