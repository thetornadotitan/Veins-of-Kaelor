class_name GhostPlayer
extends Node3D

var source: Node3D

var _sprite_nodes: Array[Sprite3D] = []


func _ready() -> void:
	_sync_visuals_from_source.call_deferred()


func _process(_delta: float) -> void:
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	_sync_visuals_from_source()


func sync_from_source(src: Node3D) -> void:
	source = src
	_sync_visuals_from_source()


func _sync_visuals_from_source() -> void:
	if source == null or not is_instance_valid(source):
		return
	var src_visuals: DirectionalSpriteStack = _get_visual_controller(source)
	if src_visuals == null:
		return
	_ensure_sprite_count(src_visuals)
	var src_sprites: Array[Node] = []
	for child in src_visuals.get_children():
		if child is Sprite3D:
			src_sprites.append(child)
	for i: int in range(mini(_sprite_nodes.size(), src_sprites.size())):
		var src_sprite: Sprite3D = src_sprites[i] as Sprite3D
		var ghost_sprite: Sprite3D = _sprite_nodes[i]
		ghost_sprite.texture = src_sprite.texture
		ghost_sprite.offset = src_sprite.offset
		ghost_sprite.pixel_size = src_sprite.pixel_size
		ghost_sprite.billboard = src_sprite.billboard
		ghost_sprite.texture_filter = src_sprite.texture_filter
		ghost_sprite.hframes = src_sprite.hframes
		ghost_sprite.frame = src_sprite.frame
		ghost_sprite.flip_h = src_sprite.flip_h
		ghost_sprite.position = src_sprite.position


func _ensure_sprite_count(src_visuals: DirectionalSpriteStack) -> void:
	var count: int = 0
	for child in src_visuals.get_children():
		if child is Sprite3D:
			count += 1
	while _sprite_nodes.size() < count:
		var sprite := Sprite3D.new()
		add_child(sprite)
		_sprite_nodes.append(sprite)
	while _sprite_nodes.size() > count:
		var sprite: Sprite3D = _sprite_nodes.pop_back()
		remove_child(sprite)
		sprite.queue_free()


func _get_visual_controller(node: Node) -> DirectionalSpriteStack:
	for child in node.get_children():
		if child is DirectionalSpriteStack:
			return child as DirectionalSpriteStack
	return null
