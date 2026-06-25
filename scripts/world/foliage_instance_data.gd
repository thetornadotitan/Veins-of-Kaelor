class_name FoliageInstanceData
extends RefCounted

var positions: PackedVector3Array = PackedVector3Array()
var rotations: PackedFloat32Array = PackedFloat32Array()
var scales: PackedFloat32Array = PackedFloat32Array()
var colors: PackedColorArray = PackedColorArray()
var custom_data: PackedColorArray = PackedColorArray()
var normals: PackedVector3Array = PackedVector3Array()


func instance_count() -> int:
	return positions.size()


func clear() -> void:
	positions = PackedVector3Array()
	rotations = PackedFloat32Array()
	scales = PackedFloat32Array()
	colors = PackedColorArray()
	custom_data = PackedColorArray()
	normals = PackedVector3Array()


func add_instance(pos: Vector3, rot: float, scale: float, color: Color, custom: Color, normal: Vector3 = Vector3.UP) -> void:
	positions.append(pos)
	rotations.append(rot)
	scales.append(scale)
	colors.append(color)
	custom_data.append(custom)
	normals.append(normal)
