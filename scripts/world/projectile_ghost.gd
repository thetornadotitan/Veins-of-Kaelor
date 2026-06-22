class_name ProjectileGhost
extends Node3D

var source: Node3D
var velocity: Vector3 = Vector3.ZERO
var _area: Area3D
var _collision_shape: CollisionShape3D
var _lifetime: float = 5.0
var _age: float = 0.0


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func setup_collision(shape: ConcavePolygonShape3D) -> void:
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = shape
	_area.add_child(_collision_shape)


func setup_collision_capsule(radius: float, height: float) -> void:
	_collision_shape = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	_collision_shape.shape = shape
	_area.add_child(_collision_shape)


func _process(delta: float) -> void:
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	_age += delta
	if _age > _lifetime:
		queue_free()
		return
	position += velocity * delta


func sync_from_source(src: Node3D) -> void:
	source = src


func _on_body_entered(body: Node3D) -> void:
	if source and is_instance_valid(source) and source.has_method("on_ghost_hit"):
		source.call("on_ghost_hit", {"body": body, "position": global_position})
	queue_free()
