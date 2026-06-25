@tool
class_name NavMeshGenerator
extends RefCounted


func build_navmesh(chunk_node: Node3D) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.25
	navmesh.agent_height = 1.5
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 50.0

	var static_body: StaticBody3D = chunk_node.get_node_or_null("StaticBody3D")
	if static_body == null:
		return navmesh

	await chunk_node.get_tree().process_frame

	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationMeshGenerator.parse_source_geometry_data(navmesh, source_geometry, static_body)
	NavigationMeshGenerator.bake_from_source_geometry_data(navmesh, source_geometry)

	return navmesh


func build_navmesh_for_chunks(chunks: Array[ChunkData], parent_node: Node3D) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.25
	navmesh.agent_height = 1.5
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 50.0

	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	var temp_nodes: Array[StaticBody3D] = []

	for cd: ChunkData in chunks:
		var col_body := StaticBody3D.new()
		col_body.collision_layer = 1
		var col_shape := CollisionShape3D.new()
		col_shape.shape = CollisionGenerator.build_collision_shape(cd)
		col_body.add_child(col_shape)
		parent_node.add_child(col_body)
		temp_nodes.append(col_body)

	await parent_node.get_tree().process_frame

	for col_body: StaticBody3D in temp_nodes:
		NavigationMeshGenerator.parse_source_geometry_data(navmesh, source_geometry, col_body)
	NavigationMeshGenerator.bake_from_source_geometry_data(navmesh, source_geometry)

	for col_body: StaticBody3D in temp_nodes:
		col_body.queue_free()

	return navmesh
