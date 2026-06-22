extends Node

const SEAM_MARGIN: float = 160.0

var _ghosts: Dictionary = {}
var _world_data: WorldData


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED


func start() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _world_data == null:
		_try_get_world_data()
		return
	var ghostables: Array[Node] = get_tree().get_nodes_in_group("ghostable")
	var active_ids: Dictionary = {}
	for entity in ghostables:
		if not entity is Node3D:
			continue
		var entity_3d: Node3D = entity as Node3D
		if not entity_3d.is_inside_tree():
			continue
		var iid: int = entity_3d.get_instance_id()
		active_ids[iid] = true
		var canonical: Vector3 = _get_canonical(entity_3d)
		var near_seam: bool = TorusUtils.is_near_boundary(canonical, _world_data, SEAM_MARGIN)
		var has_ghosts_flag: bool = _ghosts.has(iid)
		if near_seam and not has_ghosts_flag:
			_spawn_ghosts(entity_3d, canonical)
		elif not near_seam and has_ghosts_flag:
			_despawn_ghosts(iid)
		elif has_ghosts_flag:
			_update_ghosts(iid, entity_3d)
	for iid_variant: Variant in _ghosts.keys():
		var iid: int = iid_variant as int
		if not active_ids.has(iid):
			_despawn_ghosts(iid)


func _try_get_world_data() -> void:
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	if cm and cm.get_world_data():
		_world_data = cm.get_world_data()
		start()


func _get_canonical(entity: Node3D) -> Vector3:
	if entity.has_method("get_canonical_position"):
		return entity.call("get_canonical_position") as Vector3
	return TorusUtils.canonical_position(entity.global_position, _world_data)


func _spawn_ghosts(entity: Node3D, canonical: Vector3) -> void:
	if not entity.has_method("create_ghost"):
		return
	var ghost_positions: Array[Vector3] = _get_ghost_positions(entity, canonical)
	if ghost_positions.is_empty():
		return
	var ghosts: Array[Node3D] = []
	for gpos: Vector3 in ghost_positions:
		var ghost: Node3D = entity.call("create_ghost") as Node3D
		if ghost == null:
			continue
		ghost.name = "Ghost_%d_%d" % [entity.get_instance_id(), ghosts.size()]
		ghost.position = gpos
		add_child(ghost)
		ghosts.append(ghost)
	_ghosts[entity.get_instance_id()] = ghosts


func _get_ghost_positions(entity: Node3D, canonical: Vector3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var scene_pos: Vector3 = entity.global_position
	var wsx: float = _world_data.world_size_x
	var wsz: float = _world_data.world_size_z
	var near_x_neg: bool = canonical.x < SEAM_MARGIN
	var near_x_pos: bool = canonical.x > wsx - SEAM_MARGIN
	var near_z_neg: bool = canonical.z < SEAM_MARGIN
	var near_z_pos: bool = canonical.z > wsz - SEAM_MARGIN
	if near_x_neg:
		positions.append(Vector3(canonical.x + wsx, canonical.y, canonical.z))
	if near_x_pos:
		positions.append(Vector3(canonical.x - wsx, canonical.y, canonical.z))
	if near_z_neg:
		positions.append(Vector3(canonical.x, canonical.y, canonical.z + wsz))
	if near_z_pos:
		positions.append(Vector3(canonical.x, canonical.y, canonical.z - wsz))
	if near_x_neg and near_z_neg:
		positions.append(Vector3(canonical.x + wsx, canonical.y, canonical.z + wsz))
	if near_x_neg and near_z_pos:
		positions.append(Vector3(canonical.x + wsx, canonical.y, canonical.z - wsz))
	if near_x_pos and near_z_neg:
		positions.append(Vector3(canonical.x - wsx, canonical.y, canonical.z + wsz))
	if near_x_pos and near_z_pos:
		positions.append(Vector3(canonical.x - wsx, canonical.y, canonical.z - wsz))
	var filtered: Array[Vector3] = []
	for pos: Vector3 in positions:
		var dx: float = absf(pos.x - scene_pos.x)
		var dz: float = absf(pos.z - scene_pos.z)
		if dx > 1.0 or dz > 1.0:
			filtered.append(pos)
	return filtered


func _update_ghosts(iid: int, entity: Node3D) -> void:
	var ghosts: Array = _ghosts.get(iid, [])
	if ghosts.is_empty():
		return
	var canonical: Vector3 = _get_canonical(entity)
	var ghost_positions: Array[Vector3] = _get_ghost_positions(entity, canonical)
	var valid_ghosts: Array[Node3D] = []
	for i: int in range(ghosts.size()):
		var ghost: Node3D = ghosts[i] as Node3D
		if ghost and is_instance_valid(ghost) and ghost.is_inside_tree():
			if i < ghost_positions.size():
				ghost.position = ghost_positions[i]
				if ghost.has_method("sync_from_source"):
					ghost.call("sync_from_source", entity)
				valid_ghosts.append(ghost)
			else:
				ghost.queue_free()
	while ghost_positions.size() > valid_ghosts.size():
		var idx: int = valid_ghosts.size()
		var gpos: Vector3 = ghost_positions[idx]
		if entity.has_method("create_ghost"):
			var ghost: Node3D = entity.call("create_ghost") as Node3D
			if ghost:
				ghost.name = "Ghost_%d_%d" % [entity.get_instance_id(), idx]
				ghost.position = gpos
				add_child(ghost)
				if ghost.has_method("sync_from_source"):
					ghost.call("sync_from_source", entity)
				valid_ghosts.append(ghost)
	if not valid_ghosts.is_empty():
		_ghosts[iid] = valid_ghosts
	else:
		_ghosts.erase(iid)


func _despawn_ghosts(iid: int) -> void:
	var ghosts: Array = _ghosts.get(iid, [])
	for ghost_variant: Variant in ghosts:
		var ghost: Node3D = ghost_variant as Node3D
		if ghost and is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.erase(iid)


func get_all_ghosts_for(entity: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var ghosts: Array = _ghosts.get(entity.get_instance_id(), [])
	for ghost_variant: Variant in ghosts:
		var ghost: Node3D = ghost_variant as Node3D
		if ghost and is_instance_valid(ghost):
			result.append(ghost)
	return result


func has_ghosts(entity: Node3D) -> bool:
	return _ghosts.has(entity.get_instance_id())


func disable_authority_collision(entity: Node3D) -> void:
	var col: CollisionShape3D = _find_collision_shape(entity)
	if col:
		col.disabled = true


func enable_authority_collision(entity: Node3D) -> void:
	var col: CollisionShape3D = _find_collision_shape(entity)
	if col:
		col.disabled = false


func _find_collision_shape(entity: Node3D) -> CollisionShape3D:
	for child in entity.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		if child is StaticBody3D or child is CharacterBody3D or child is RigidBody3D:
			for subchild in child.get_children():
				if subchild is CollisionShape3D:
					return subchild as CollisionShape3D
	return null
