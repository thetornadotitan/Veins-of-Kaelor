@tool
class_name NavMeshGenerator
extends RefCounted

const AGENT_RADIUS: float = 0.25
const AGENT_HEIGHT: float = 1.5
const AGENT_MAX_CLIMB: float = 0.25
const AGENT_MAX_SLOPE: float = 50.0
const BORDER_SIZE_MULTIPLY: float = 1.0


static func get_navmesh_path(world_name: String, chunk_rx: int, chunk_rz: int) -> String:
	return "res://data/worlds/%s/navmeshes/nav_%d_%d.res" % [world_name, chunk_rx, chunk_rz]


static func load_cached_navmesh(world_name: String, chunk_rx: int, chunk_rz: int) -> NavigationMesh:
	var path: String = get_navmesh_path(world_name, chunk_rx, chunk_rz)
	if not ResourceLoader.exists(path):
		return null
	var navmesh: NavigationMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if navmesh == null or navmesh.get_vertices().is_empty():
		return null
	return navmesh


static func create_navmesh_config() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_max_climb = AGENT_MAX_CLIMB
	navmesh.agent_max_slope = AGENT_MAX_SLOPE
	var border: float = float(ChunkData.CHUNK_SIZE) * BORDER_SIZE_MULTIPLY
	navmesh.border_size = border
	navmesh.filter_baking_aabb = AABB(
		Vector3(-border, -2.0, -border),
		Vector3(float(ChunkData.CHUNK_SIZE) + border * 2.0, float(ChunkData.GRID_RESOLUTION) + 4.0, float(ChunkData.CHUNK_SIZE) + border * 2.0)
	)
	return navmesh


static func create_source_geometry(chunk_data: ChunkData) -> NavigationMeshSourceGeometryData3D:
	var faces: PackedVector3Array = CollisionGenerator.build_collision_faces(chunk_data)
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	source_geometry.add_faces(faces, Transform3D.IDENTITY)
	return source_geometry


static func save_navmesh(navmesh: NavigationMesh, world_name: String, chunk_rx: int, chunk_rz: int) -> void:
	if navmesh.get_vertices().is_empty():
		return
	var path: String = get_navmesh_path(world_name, chunk_rx, chunk_rz)
	ResourceSaver.save(navmesh, path, ResourceSaver.FLAG_COMPRESS)


static func bake_prepared_navmesh(navmesh: NavigationMesh, source_geometry: NavigationMeshSourceGeometryData3D, world_name: String, chunk_rx: int, chunk_rz: int) -> NavigationMesh:
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source_geometry)
	if navmesh.get_vertices().is_empty():
		return null
	var path: String = get_navmesh_path(world_name, chunk_rx, chunk_rz)
	ResourceSaver.save(navmesh, path, ResourceSaver.FLAG_COMPRESS)
	return navmesh


static func bake_prepared_navmesh_async(navmesh: NavigationMesh, source_geometry: NavigationMeshSourceGeometryData3D, callback: Callable) -> void:
	NavigationServer3D.bake_from_source_geometry_data_async(navmesh, source_geometry, callback)


static func is_baking(navmesh: NavigationMesh) -> bool:
	return NavigationServer3D.is_baking_navigation_mesh(navmesh)


static func ensure_navmesh_dir(world_name: String) -> void:
	var dir_path: String = "res://data/worlds/%s/navmeshes" % world_name
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
