@tool
class_name TerrainMeshBuilder
extends RefCounted

const LOD_DISTANCES: PackedFloat32Array = [80.0, 200.0, 400.0, 700.0, INF]

const SKIRT_DROP: float = 20.0

static var _terrain_material: StandardMaterial3D


static func get_terrain_material() -> StandardMaterial3D:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.vertex_color_use_as_albedo = true
		_terrain_material.roughness = 0.9
		_terrain_material.metallic = 0.0
	return _terrain_material


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _get_terrain_color(height: float, water_level: float, normal_y: float) -> Color:
	var h: float = height - water_level

	var ocean_floor := Color(0.14, 0.20, 0.16)
	var sand := Color(0.72, 0.64, 0.44)
	var grass := Color(0.29, 0.49, 0.25)
	var highland := Color(0.35, 0.42, 0.23)
	var rock := Color(0.42, 0.38, 0.34)
	var snow := Color(0.88, 0.88, 0.90)
	var cliff_rock := Color(0.40, 0.37, 0.33)

	var c: Color
	if h < -2.0:
		c = ocean_floor
	elif h < 0.0:
		c = ocean_floor.lerp(sand, _smoothstep(-2.0, 0.0, h))
	elif h < 3.0:
		c = sand
	elif h < 6.0:
		c = sand.lerp(grass, _smoothstep(3.0, 6.0, h))
	elif h < 20.0:
		c = grass
	elif h < 23.0:
		c = grass.lerp(highland, _smoothstep(20.0, 23.0, h))
	elif h < 45.0:
		c = highland
	elif h < 48.0:
		c = highland.lerp(rock, _smoothstep(45.0, 48.0, h))
	elif h < 65.0:
		c = rock
	elif h < 68.0:
		c = rock.lerp(snow, _smoothstep(65.0, 68.0, h))
	else:
		c = snow

	var slope_factor: float = 1.0 - _smoothstep(0.55, 0.85, normal_y)
	c = c.lerp(cliff_rock, slope_factor * 0.7)

	return c


static func _h(hm: PackedFloat32Array, lx: int, lz: int, res: int) -> float:
	var sr: int = res + 2
	return hm[clampi(lz + 1, 0, sr - 1) * sr + clampi(lx + 1, 0, sr - 1)]


static func _emit_quad_arrays(verts: PackedVector3Array, normals_arr: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, v00: Vector3, v10: Vector3, v01: Vector3, v11: Vector3, n00: Vector3, n10: Vector3, n01: Vector3, n11: Vector3, uv00: Vector2, uv10: Vector2, uv01: Vector2, uv11: Vector2, c00: Color, c10: Color, c01: Color, c11: Color) -> void:
	var base: int = verts.size()
	verts.append(v00)
	verts.append(v10)
	verts.append(v01)
	verts.append(v11)
	normals_arr.append(n00)
	normals_arr.append(n10)
	normals_arr.append(n01)
	normals_arr.append(n11)
	uvs.append(uv00)
	uvs.append(uv10)
	uvs.append(uv01)
	uvs.append(uv11)
	colors.append(c00)
	colors.append(c10)
	colors.append(c01)
	colors.append(c11)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base + 3)
	indices.append(base + 2)


static func _precompute_normals(chunk_data: ChunkData, res: int) -> Array:
	var normals = []
	normals.resize(res)
	for iz in range(res):
		var row = []
		row.resize(res)
		for ix in range(res):
			row[ix] = chunk_data.get_normal_at(float(ix), float(iz))
		normals[iz] = row
	return normals


static func _compute_border_width(res: int, spacing: int) -> int:
	var b: int = spacing
	var interior: int = (res - 1) - 2 * b
	while interior > 0 and interior % spacing != 0:
		b += 1
		interior = (res - 1) - 2 * b
	if interior < spacing:
		return 0
	return b


static func build_chunk_mesh_arrays(chunk_data: ChunkData, lod: int) -> Dictionary:
	var res: int = ChunkData.GRID_RESOLUTION
	var wl: float = chunk_data.water_level
	var hm: PackedFloat32Array = chunk_data.heightmap

	if hm.is_empty() or hm.size() < (res + 2) * (res + 2):
		push_error("[TerrainMeshBuilder] heightmap invalid for chunk (%d,%d)" % [chunk_data.chunk_rx, chunk_data.chunk_rz])
		return {}

	var pre_normals: Array = _precompute_normals(chunk_data, res)

	var spacing: int = 1 << lod
	var b: int = _compute_border_width(res, spacing)
	var rf: float = float(res)
	var _interior_start: int = b
	var _interior_end: int = (res - 1) - b

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var lz: int = 0
	while lz < res - 1:
		var step_z: int = _row_step(lz, spacing, b, res)
		var lx: int = 0
		while lx < res - 1:
			var step_x: int = _col_step(lx, lz, step_z, spacing, b, res)
			var nx: int = mini(lx + step_x, res - 1)
			var nz: int = mini(lz + step_z, res - 1)

			var n00: Vector3 = pre_normals[lz][lx]
			var n10: Vector3 = pre_normals[lz][nx]
			var n01: Vector3 = pre_normals[nz][lx]
			var n11: Vector3 = pre_normals[nz][nx]

			var h00: float = _h(hm, lx, lz, res)
			var h10: float = _h(hm, nx, lz, res)
			var h01: float = _h(hm, lx, nz, res)
			var h11: float = _h(hm, nx, nz, res)

			var base: int = verts.size()
			verts.append(Vector3(float(lx), h00, float(lz)))
			verts.append(Vector3(float(nx), h10, float(lz)))
			verts.append(Vector3(float(lx), h01, float(nz)))
			verts.append(Vector3(float(nx), h11, float(nz)))
			normals.append(n00)
			normals.append(n10)
			normals.append(n01)
			normals.append(n11)
			uvs.append(_uv(float(lx), float(lz), rf))
			uvs.append(_uv(float(nx), float(lz), rf))
			uvs.append(_uv(float(lx), float(nz), rf))
			uvs.append(_uv(float(nx), float(nz), rf))
			colors.append(_get_terrain_color(h00, wl, n00.y))
			colors.append(_get_terrain_color(h10, wl, n10.y))
			colors.append(_get_terrain_color(h01, wl, n01.y))
			colors.append(_get_terrain_color(h11, wl, n11.y))
			indices.append(base)
			indices.append(base + 1)
			indices.append(base + 2)
			indices.append(base + 1)
			indices.append(base + 3)
			indices.append(base + 2)

			lx += step_x
		lz += step_z

	_build_skirt_arrays(verts, normals, uvs, colors, indices, hm, res, wl, pre_normals)

	return {
		"verts": verts,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
	}


static func build_chunk_mesh(chunk_data: ChunkData, lod: int) -> ArrayMesh:
	var data: Dictionary = build_chunk_mesh_arrays(chunk_data, lod)
	if data.is_empty():
		var mesh := ArrayMesh.new()
		return mesh
	return _arrays_to_mesh(data)


static func _arrays_to_mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _in_border(v: int, res: int, b: int) -> bool:
	if b == 0:
		return v == 0 or v >= res - 1
	return v < b or v >= res - 1 - b


static func _row_step(lz: int, spacing: int, b: int, res: int) -> int:
	if _in_border(lz, res, b):
		return 1
	if lz + spacing > (res - 1) - b:
		return (res - 1) - b - lz
	return spacing


static func _col_step(lx: int, _lz: int, step_z: int, spacing: int, b: int, res: int) -> int:
	if _in_border(lx, res, b):
		return 1
	var natural_x: int = spacing
	if lx + spacing > (res - 1) - b:
		natural_x = (res - 1) - b - lx
		if natural_x <= 0:
			return 1
	if step_z < natural_x:
		return step_z
	return natural_x


static func _uv(x: float, z: float, res: float) -> Vector2:
	return Vector2(x / (res - 1.0), z / (res - 1.0))


static func _build_skirt_arrays(verts: PackedVector3Array, normals_arr: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, hm: PackedFloat32Array, res: int, wl: float, pre_normals: Array) -> void:
	var rf: float = float(res)
	for lx: int in range(res - 1):
		var h0: float = _h(hm, lx, 0, res)
		var h1: float = _h(hm, lx + 1, 0, res)
		var c0: Color = _get_terrain_color(h0, wl, pre_normals[0][lx].y)
		var c1: Color = _get_terrain_color(h1, wl, pre_normals[0][lx + 1].y)
		_emit_quad_arrays(verts, normals_arr, uvs, colors, indices,
			Vector3(float(lx), h0, 0.0), Vector3(float(lx + 1), h1, 0.0),
			Vector3(float(lx), h0 - SKIRT_DROP, 0.0), Vector3(float(lx + 1), h1 - SKIRT_DROP, 0.0),
			pre_normals[0][lx], pre_normals[0][lx + 1], pre_normals[0][lx], pre_normals[0][lx + 1],
			_uv(float(lx), 0.0, rf), _uv(float(lx + 1), 0.0, rf),
			_uv(float(lx), 0.0, rf), _uv(float(lx + 1), 0.0, rf),
			c0, c1, c0, c1)
	for lx: int in range(res - 1):
		var h0: float = _h(hm, lx, res - 1, res)
		var h1: float = _h(hm, lx + 1, res - 1, res)
		var c0: Color = _get_terrain_color(h0, wl, pre_normals[res - 1][lx].y)
		var c1: Color = _get_terrain_color(h1, wl, pre_normals[res - 1][lx + 1].y)
		_emit_quad_arrays(verts, normals_arr, uvs, colors, indices,
			Vector3(float(lx), h0, float(res - 1)), Vector3(float(lx + 1), h1, float(res - 1)),
			Vector3(float(lx), h0 - SKIRT_DROP, float(res - 1)), Vector3(float(lx + 1), h1 - SKIRT_DROP, float(res - 1)),
			pre_normals[res - 1][lx], pre_normals[res - 1][lx + 1], pre_normals[res - 1][lx], pre_normals[res - 1][lx + 1],
			_uv(float(lx), 1.0, rf), _uv(float(lx + 1), 1.0, rf),
			_uv(float(lx), 1.0, rf), _uv(float(lx + 1), 1.0, rf),
			c0, c1, c0, c1)
	for lz: int in range(res - 1):
		var h0: float = _h(hm, 0, lz, res)
		var h1: float = _h(hm, 0, lz + 1, res)
		var c0: Color = _get_terrain_color(h0, wl, pre_normals[lz][0].y)
		var c1: Color = _get_terrain_color(h1, wl, pre_normals[lz + 1][0].y)
		_emit_quad_arrays(verts, normals_arr, uvs, colors, indices,
			Vector3(0.0, h0, float(lz)), Vector3(0.0, h1, float(lz + 1)),
			Vector3(0.0, h0 - SKIRT_DROP, float(lz)), Vector3(0.0, h1 - SKIRT_DROP, float(lz + 1)),
			pre_normals[lz][0], pre_normals[lz + 1][0], pre_normals[lz][0], pre_normals[lz + 1][0],
			_uv(0.0, float(lz), rf), _uv(0.0, float(lz + 1), rf),
			_uv(0.0, float(lz), rf), _uv(0.0, float(lz + 1), rf),
			c0, c1, c0, c1)
	for lz: int in range(res - 1):
		var h0: float = _h(hm, res - 1, lz, res)
		var h1: float = _h(hm, res - 1, lz + 1, res)
		var c0: Color = _get_terrain_color(h0, wl, pre_normals[lz][res - 1].y)
		var c1: Color = _get_terrain_color(h1, wl, pre_normals[lz + 1][res - 1].y)
		_emit_quad_arrays(verts, normals_arr, uvs, colors, indices,
			Vector3(float(res - 1), h0, float(lz)), Vector3(float(res - 1), h1, float(lz + 1)),
			Vector3(float(res - 1), h0 - SKIRT_DROP, float(lz)), Vector3(float(res - 1), h1 - SKIRT_DROP, float(lz + 1)),
			pre_normals[lz][res - 1], pre_normals[lz + 1][res - 1], pre_normals[lz][res - 1], pre_normals[lz + 1][res - 1],
			_uv(1.0, float(lz), rf), _uv(1.0, float(lz + 1), rf),
			_uv(1.0, float(lz), rf), _uv(1.0, float(lz + 1), rf),
			c0, c1, c0, c1)


static func get_lod_for_distance(dist: float) -> int:
	for i: int in range(LOD_DISTANCES.size()):
		if dist < LOD_DISTANCES[i]:
			return i
	return LOD_DISTANCES.size() - 1
