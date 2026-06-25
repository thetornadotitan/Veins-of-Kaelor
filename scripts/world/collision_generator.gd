@tool
class_name CollisionGenerator
extends RefCounted


static func build_collision_shape(chunk_data: ChunkData) -> ConcavePolygonShape3D:
	var resolution: int = ChunkData.GRID_RESOLUTION
	var sr: int = ChunkData.SAMPLE_RESOLUTION
	var faces := PackedVector3Array()

	for lz: int in range(resolution - 1):
		for lx: int in range(resolution - 1):
			var h00: float = chunk_data.heightmap[(lz + 1) * sr + (lx + 1)]
			var h10: float = chunk_data.heightmap[(lz + 1) * sr + (lx + 2)]
			var h01: float = chunk_data.heightmap[(lz + 2) * sr + (lx + 1)]
			var h11: float = chunk_data.heightmap[(lz + 2) * sr + (lx + 2)]
			var v00 := Vector3(float(lx), h00, float(lz))
			var v10 := Vector3(float(lx + 1), h10, float(lz))
			var v01 := Vector3(float(lx), h01, float(lz + 1))
			var v11 := Vector3(float(lx + 1), h11, float(lz + 1))
			faces.append(v00)
			faces.append(v10)
			faces.append(v01)
			faces.append(v10)
			faces.append(v11)
			faces.append(v01)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape
