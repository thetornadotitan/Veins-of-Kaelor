class_name ChunkRecord
extends RefCounted

var chunk_pos: Vector2i = Vector2i(-1, -1)
var world_position: Transform3D = Transform3D()
var chunk_data: ChunkData = null
var current_lod: int = -1

var mesh: ArrayMesh = null
var shape: ConcavePolygonShape3D = null
var nav_mesh: NavigationMesh = null

var instance_rid: RID = RID()
var body_rid: RID = RID()
var shape_rid: RID = RID()
var nav_region_rid: RID = RID()
var nav_mesh_rid: RID = RID()

var has_collision: bool = false
var has_nav: bool = false
var is_visible: bool = true


func free_rids() -> void:
	if instance_rid != RID():
		RenderingServer.free_rid(instance_rid)
		instance_rid = RID()
	if body_rid != RID():
		PhysicsServer3D.free_rid(body_rid)
		body_rid = RID()
	shape_rid = RID()
	if nav_region_rid != RID():
		NavigationServer3D.free_rid(nav_region_rid)
		nav_region_rid = RID()
	nav_mesh_rid = RID()
	mesh = null
	shape = null
	nav_mesh = null
	has_collision = false
	has_nav = false


func remove_collision() -> void:
	if body_rid != RID():
		PhysicsServer3D.free_rid(body_rid)
		body_rid = RID()
	shape_rid = RID()
	shape = null
	has_collision = false


func remove_nav() -> void:
	if nav_region_rid != RID():
		NavigationServer3D.free_rid(nav_region_rid)
		nav_region_rid = RID()
	nav_mesh_rid = RID()
	nav_mesh = null
	has_nav = false
