@tool
class_name NavMeshGenerator
extends RefCounted

const AGENT_RADIUS: float = 0.25
const AGENT_HEIGHT: float = 1.5
const AGENT_MAX_CLIMB: float = 0.5
const AGENT_MAX_SLOPE: float = 50.0
const BORDER_SIZE_MULTIPLY: float = 1.0


static func get_nav_region_path(world_name: String, rrx: int, rrz: int) -> String:
	return "res://data/worlds/%s/nav_regions/nav_region_%02d_%02d.res" % [world_name, rrx, rrz]


static func load_nav_region(world_name: String, rrx: int, rrz: int) -> NavigationMesh:
	var path: String = get_nav_region_path(world_name, rrx, rrz)
	if not ResourceLoader.exists(path):
		return null
	var navmesh: NavigationMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if navmesh == null or navmesh.get_vertices().is_empty():
		return null
	return navmesh


static func has_nav_region(world_name: String, rrx: int, rrz: int) -> bool:
	return ResourceLoader.exists(get_nav_region_path(world_name, rrx, rrz))


static func create_region_navmesh_config(region_size: int, chunk_size: int) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_max_climb = AGENT_MAX_CLIMB
	navmesh.agent_max_slope = AGENT_MAX_SLOPE
	var region_world_size: float = float(region_size * chunk_size)
	var border: float = float(chunk_size) * BORDER_SIZE_MULTIPLY
	navmesh.border_size = border
	navmesh.filter_baking_aabb = AABB(
		Vector3(-border, -4.0, -border),
		Vector3(region_world_size + border * 2.0, 100.0, region_world_size + border * 2.0)
	)
	return navmesh


static func create_region_source_geometry(region: RegionData, region_size: int, chunk_size: int) -> NavigationMeshSourceGeometryData3D:
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	for local_rz: int in range(region_size):
		for local_rx: int in range(region_size):
			var chunk_data: ChunkData = ChunkData.from_region(region, local_rx, local_rz)
			if chunk_data == null or chunk_data.heightmap.is_empty():
				continue
			var faces: PackedVector3Array = CollisionGenerator.build_collision_faces(chunk_data)
			var offset_x: float = float(local_rx * chunk_size)
			var offset_z: float = float(local_rz * chunk_size)
			var offset := Transform3D(Basis(), Vector3(offset_x, 0.0, offset_z))
			if faces.size() > 0:
				source_geometry.add_faces(faces, offset)
	return source_geometry


static func save_nav_region(navmesh: NavigationMesh, world_name: String, rrx: int, rrz: int) -> void:
	if navmesh.get_vertices().is_empty():
		return
	var path: String = get_nav_region_path(world_name, rrx, rrz)
	ResourceSaver.save(navmesh, path, ResourceSaver.FLAG_COMPRESS)


static func bake_region_navmesh(region: RegionData, world_name: String, rrx: int, rrz: int, region_size: int, chunk_size: int) -> NavigationMesh:
	var navmesh := create_region_navmesh_config(region_size, chunk_size)
	var source_geometry := create_region_source_geometry(region, region_size, chunk_size)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source_geometry)
	if navmesh.get_vertices().is_empty():
		return null
	save_nav_region(navmesh, world_name, rrx, rrz)
	return navmesh


static func bake_region_navmesh_async(region: RegionData, _world_name: String, _rrx: int, _rrz: int, region_size: int, chunk_size: int, callback: Callable) -> void:
	var navmesh := create_region_navmesh_config(region_size, chunk_size)
	var source_geometry := create_region_source_geometry(region, region_size, chunk_size)
	NavigationServer3D.bake_from_source_geometry_data_async(navmesh, source_geometry, callback)


static func ensure_nav_region_dir(world_name: String) -> void:
	var dir_path: String = "res://data/worlds/%s/nav_regions" % world_name
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


static func delete_old_chunk_navmeshes(world_name: String) -> void:
	var old_dir: String = "res://data/worlds/%s/navmeshes" % world_name
	if not DirAccess.dir_exists_absolute(old_dir):
		return
	var dir := DirAccess.open(old_dir)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
	var base_dir := DirAccess.open("res://data/worlds/%s" % world_name)
	if base_dir:
		base_dir.remove("navmeshes")
