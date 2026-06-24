@tool
class_name TerrainMeshBuilder
extends RefCounted

const BIOME_COLORS: Dictionary = {
	0: Color(0.290, 0.486, 0.247),
	1: Color(0.545, 0.451, 0.333),
	2: Color(0.180, 0.353, 0.549),
}

const LOD_DISTANCES: PackedFloat32Array = [80.0, 200.0, 400.0, 700.0, INF]

const SKIRT_DROP: float = 10.0
const BORDER_WIDTH: int = 2

static var _terrain_material: StandardMaterial3D


static func get_terrain_material() -> StandardMaterial3D:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.vertex_color_use_as_albedo = true
		_terrain_material.roughness = 0.9
		_terrain_material.metallic = 0.0
	return _terrain_material


static func _h(hm: PackedFloat32Array, lx: int, lz: int, res: int) -> float:
	return hm[clampi(lz, 0, res - 1) * res + clampi(lx, 0, res - 1)]


static func _in_border(v: int, res: int, b: int) -> bool:
	return v < b or v >= res - 1 - b


static func _emit_quad(st: SurfaceTool, v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3, uv00: Vector2, uv10: Vector2, uv01: Vector2, uv11: Vector2, color: Color) -> void:
	st.set_uv(uv00); st.set_color(color); st.add_vertex(v00)
	st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
	st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)
	st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
	st.set_uv(uv11); st.set_color(color); st.add_vertex(v11)
	st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)


static func build_chunk_mesh(chunk_data: ChunkData, lod: int) -> ArrayMesh:
	var res: int = ChunkData.GRID_RESOLUTION
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var color: Color = BIOME_COLORS.get(chunk_data.biome, BIOME_COLORS[0])
	var hm: PackedFloat32Array = chunk_data.heightmap

	if hm.is_empty() or hm.size() < res * res:
		push_error("[TerrainMeshBuilder] heightmap invalid for chunk (%d,%d)" % [chunk_data.chunk_rx, chunk_data.chunk_rz])
		return st.commit()

	var spacing: int = 1 << lod
	var b: int = BORDER_WIDTH
	var rf: float = float(res)

	var lz: int = 0
	while lz < res - 1:
		var step_z: int = _row_step(lz, spacing, b, res)
		var lx: int = 0
		while lx < res - 1:
			var step: int = _col_step(lx, lz, step_z, spacing, b, res)
			var nx: int = mini(lx + step, res - 1)
			var nz: int = mini(lz + step_z, res - 1)

			_emit_quad(st,
				Vector3(float(lx), _h(hm, lx, lz, res), float(lz)),
				Vector3(float(nx), _h(hm, nx, lz, res), float(lz)),
				Vector3(float(lx), _h(hm, lx, nz, res), float(nz)),
				Vector3(float(nx), _h(hm, nx, nz, res), float(nz)),
				_uv(float(lx), float(lz), rf),
				_uv(float(nx), float(lz), rf),
				_uv(float(lx), float(nz), rf),
				_uv(float(nx), float(nz), rf),
				color)
			lx += step
		lz += step_z

	_build_skirt(st, hm, res, color)

	st.generate_normals()
	return st.commit()


static func _row_step(lz: int, spacing: int, b: int, res: int) -> int:
	if _in_border(lz, res, b):
		return 1
	if lz + spacing > res - 1 - b:
		return (res - 1 - b) - lz
	return spacing


static func _col_step(lx: int, _lz: int, step_z: int, spacing: int, b: int, res: int) -> int:
	if _in_border(lx, res, b):
		return 1
	var natural_x: int = spacing
	if lx + spacing > res - 1 - b:
		natural_x = (res - 1 - b) - lx
		if natural_x <= 0:
			return 1
	if step_z < natural_x:
		return step_z
	return natural_x


static func _uv(x: float, z: float, res: float) -> Vector2:
	return Vector2(x / (res - 1.0), z / (res - 1.0))


static func _build_skirt(st: SurfaceTool, hm: PackedFloat32Array, res: int, color: Color) -> void:
	var rf: float = float(res)
	for lx: int in range(res - 1):
		var h0: float = _h(hm, lx, 0, res)
		var h1: float = _h(hm, lx + 1, 0, res)
		_emit_quad(st,
			Vector3(float(lx), h0, 0.0),
			Vector3(float(lx + 1), h1, 0.0),
			Vector3(float(lx), h0 - SKIRT_DROP, 0.0),
			Vector3(float(lx + 1), h1 - SKIRT_DROP, 0.0),
			_uv(float(lx), 0.0, rf), _uv(float(lx + 1), 0.0, rf),
			_uv(float(lx), 0.0, rf), _uv(float(lx + 1), 0.0, rf),
			color)

	for lx: int in range(res - 1):
		var h0: float = _h(hm, lx, res - 1, res)
		var h1: float = _h(hm, lx + 1, res - 1, res)
		_emit_quad(st,
			Vector3(float(lx), h0, float(res - 1)),
			Vector3(float(lx + 1), h1, float(res - 1)),
			Vector3(float(lx), h0 - SKIRT_DROP, float(res - 1)),
			Vector3(float(lx + 1), h1 - SKIRT_DROP, float(res - 1)),
			_uv(float(lx), 1.0, rf), _uv(float(lx + 1), 1.0, rf),
			_uv(float(lx), 1.0, rf), _uv(float(lx + 1), 1.0, rf),
			color)

	for lz: int in range(res - 1):
		var h0: float = _h(hm, 0, lz, res)
		var h1: float = _h(hm, 0, lz + 1, res)
		_emit_quad(st,
			Vector3(0.0, h0, float(lz)),
			Vector3(0.0, h1, float(lz + 1)),
			Vector3(0.0, h0 - SKIRT_DROP, float(lz)),
			Vector3(0.0, h1 - SKIRT_DROP, float(lz + 1)),
			_uv(0.0, float(lz), rf), _uv(0.0, float(lz + 1), rf),
			_uv(0.0, float(lz), rf), _uv(0.0, float(lz + 1), rf),
			color)

	for lz: int in range(res - 1):
		var h0: float = _h(hm, res - 1, lz, res)
		var h1: float = _h(hm, res - 1, lz + 1, res)
		_emit_quad(st,
			Vector3(float(res - 1), h0, float(lz)),
			Vector3(float(res - 1), h1, float(lz + 1)),
			Vector3(float(res - 1), h0 - SKIRT_DROP, float(lz)),
			Vector3(float(res - 1), h1 - SKIRT_DROP, float(lz + 1)),
			_uv(1.0, float(lz), rf), _uv(1.0, float(lz + 1), rf),
			_uv(1.0, float(lz), rf), _uv(1.0, float(lz + 1), rf),
			color)


static func get_lod_for_distance(dist: float) -> int:
	for i: int in range(LOD_DISTANCES.size()):
		if dist < LOD_DISTANCES[i]:
			return i
	return LOD_DISTANCES.size() - 1
