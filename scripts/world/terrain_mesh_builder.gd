@tool
class_name TerrainMeshBuilder
extends RefCounted

const BIOME_COLORS: Dictionary = {
	0: Color(0.290, 0.486, 0.247),
	1: Color(0.545, 0.451, 0.333),
	2: Color(0.180, 0.353, 0.549),
}

const LOD_DISTANCES: PackedFloat32Array = [80.0, 240.0, INF]

static var _terrain_material: StandardMaterial3D


static func get_terrain_material() -> StandardMaterial3D:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.vertex_color_use_as_albedo = true
		_terrain_material.roughness = 0.9
		_terrain_material.metallic = 0.0
	return _terrain_material


static func build_chunk_mesh(chunk_data: ChunkData, lod: int) -> ArrayMesh:
	var spacing: int = 1 << lod
	var resolution: int = ChunkData.GRID_RESOLUTION
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var color: Color = BIOME_COLORS.get(chunk_data.biome, BIOME_COLORS[0])

	if chunk_data.heightmap.is_empty():
		push_error("[TerrainMeshBuilder] build_chunk_mask: heightmap is empty for chunk (%d,%d)" % [chunk_data.chunk_rx, chunk_data.chunk_rz])
		return st.commit()
	if chunk_data.heightmap.size() < resolution * resolution:
		push_error("[TerrainMeshBuilder] build_chunk_mask: heightmap size %d < expected %d for chunk (%d,%d)" % [chunk_data.heightmap.size(), resolution * resolution, chunk_data.chunk_rx, chunk_data.chunk_rz])
		return st.commit()

	for lz: int in range(0, resolution - 1, spacing):
		for lx: int in range(0, resolution - 1, spacing):
			var h00: float = chunk_data.heightmap[lz * resolution + lx]
			var h10: float = chunk_data.heightmap[lz * resolution + lx + spacing]
			var h01: float = chunk_data.heightmap[(lz + spacing) * resolution + lx]
			var h11: float = chunk_data.heightmap[(lz + spacing) * resolution + lx + spacing]

			var lx1: float = float(lx + spacing)
			var lz1: float = float(lz + spacing)

			var uv00 := Vector2(float(lx) / float(resolution - 1), float(lz) / float(resolution - 1))
			var uv10 := Vector2(float(lx + spacing) / float(resolution - 1), float(lz) / float(resolution - 1))
			var uv01 := Vector2(float(lx) / float(resolution - 1), float(lz + spacing) / float(resolution - 1))
			var uv11 := Vector2(float(lx + spacing) / float(resolution - 1), float(lz + spacing) / float(resolution - 1))

			var v00 := Vector3(float(lx), h00, float(lz))
			var v10 := Vector3(lx1, h10, float(lz))
			var v01 := Vector3(float(lx), h01, lz1)
			var v11 := Vector3(lx1, h11, lz1)

			st.set_uv(uv00); st.set_color(color); st.add_vertex(v00)
			st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
			st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)
			st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
			st.set_uv(uv11); st.set_color(color); st.add_vertex(v11)
			st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)

	st.generate_normals()
	return st.commit()


static func get_lod_for_distance(dist: float) -> int:
	for i: int in range(LOD_DISTANCES.size()):
		if dist < LOD_DISTANCES[i]:
			return i
	return LOD_DISTANCES.size() - 1
