class_name TorusUtils
extends RefCounted


static func wrap_near(value: float, ref: float, size: float) -> float:
	var d: float = value - ref
	while d > size * 0.5:
		value -= size
		d = value - ref
	while d < -size * 0.5:
		value += size
		d = value - ref
	return value


static func wrap_vector3_near(pos: Vector3, ref: Vector3, wd: WorldData) -> Vector3:
	if wd == null:
		return pos
	pos.x = wrap_near(pos.x, ref.x, wd.world_size_x)
	pos.z = wrap_near(pos.z, ref.z, wd.world_size_z)
	return pos


static func toroidal_delta(a: float, b: float, size: float) -> float:
	var d: float = b - a
	while d > size * 0.5:
		d -= size
	while d < -size * 0.5:
		d += size
	return d


static func toroidal_distance_sq(a: Vector3, b: Vector3, wsx: float, wsz: float) -> float:
	var dx: float = toroidal_delta(a.x, b.x, wsx)
	var dz: float = toroidal_delta(a.z, b.z, wsz)
	var dy: float = a.y - b.y
	return dx * dx + dy * dy + dz * dz


static func toroidal_distance(a: Vector3, b: Vector3, wsx: float, wsz: float) -> float:
	return sqrt(toroidal_distance_sq(a, b, wsx, wsz))


static func is_near_boundary(pos: Vector3, wd: WorldData, margin: float) -> bool:
	if wd == null:
		return false
	return pos.x < margin or pos.x > wd.world_size_x - margin \
		or pos.z < margin or pos.z > wd.world_size_z - margin


static func canonical_position(pos: Vector3, wd: WorldData) -> Vector3:
	if wd == null:
		return pos
	pos.x = fposmod(pos.x, wd.world_size_x)
	pos.z = fposmod(pos.z, wd.world_size_z)
	return pos


static func get_wrapped_offsets(pos: Vector3, wd: WorldData, margin: float) -> Array[Vector3]:
	if wd == null or not is_near_boundary(pos, wd, margin):
		return []
	var offsets: Array[Vector3] = []
	var wsx: float = wd.world_size_x
	var wsz: float = wd.world_size_z
	var near_x_neg: bool = pos.x < margin
	var near_x_pos: bool = pos.x > wsx - margin
	var near_z_neg: bool = pos.z < margin
	var near_z_pos: bool = pos.z > wsz - margin
	if near_x_neg:
		offsets.append(Vector3(pos.x + wsx, pos.y, pos.z))
	if near_x_pos:
		offsets.append(Vector3(pos.x - wsx, pos.y, pos.z))
	if near_z_neg:
		offsets.append(Vector3(pos.x, pos.y, pos.z + wsz))
	if near_z_pos:
		offsets.append(Vector3(pos.x, pos.y, pos.z - wsz))
	if near_x_neg and near_z_neg:
		offsets.append(Vector3(pos.x + wsx, pos.y, pos.z + wsz))
	if near_x_neg and near_z_pos:
		offsets.append(Vector3(pos.x + wsx, pos.y, pos.z - wsz))
	if near_x_pos and near_z_neg:
		offsets.append(Vector3(pos.x - wsx, pos.y, pos.z + wsz))
	if near_x_pos and near_z_pos:
		offsets.append(Vector3(pos.x - wsx, pos.y, pos.z - wsz))
	return offsets
