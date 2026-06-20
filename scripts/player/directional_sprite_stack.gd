class_name DirectionalSpriteStack
extends Node3D

enum Direction { FORWARD, LEFT, RIGHT, AWAY }

@onready var _head: Sprite3D   = %Head
@onready var _chest: Sprite3D  = %Chest
@onready var _l_leg: Sprite3D  = %L_Leg
@onready var _r_leg: Sprite3D  = %R_Leg
@onready var _l_arm: Sprite3D  = %L_Arm
@onready var _r_arm: Sprite3D  = %R_Arm
@onready var _l_hand: Sprite3D = %L_Hand
@onready var _r_hand: Sprite3D = %R_Hand

var _base_y: Dictionary[String, float] = {}
var _part_nodes: Dictionary[String, Sprite3D] = {}

const SHEET_MAP: Dictionary[String, String] = {
	"chest": "human_chest",
	"legs": "human_legs",
	"hands": "human_hands",
	"head": "human_faces",
}

const DIR_NAMES: Dictionary[int, String] = {
	Direction.FORWARD: "forward",
	Direction.LEFT: "left",
	Direction.RIGHT: "right",
	Direction.AWAY: "away",
}

@export var equipped_styles: Dictionary[String, String] = {
	"chest": "style_01",
	"legs": "style_01",
	"hands": "style_01",
	"head": "style_01",
}

func _ready() -> void:
	_part_nodes = {
		"Head":   _head,
		"Chest":  _chest,
		"L_Leg":  _l_leg,
		"R_Leg":  _r_leg,
		"L_Arm":  _l_arm,
		"R_Arm":  _r_arm,
		"L_Hand": _l_hand,
		"R_Hand": _r_hand,
	}
	_cache_base_y()
	initialize_default_styles()

func initialize_default_styles() -> void:
	for slot in SHEET_MAP:
		var sheet_id: String = SHEET_MAP[slot]
		var sheet: SheetData = SpriteDatabaseLoader.get_sheet(sheet_id)
		if not sheet or sheet.styles.is_empty():
			continue
		var first_style: String = sheet.styles.keys()[0]
		equipped_styles[slot] = first_style

func _cache_base_y() -> void:
	for part_name in _part_nodes:
		var node: Sprite3D = _part_nodes[part_name]
		if node:
			_base_y[part_name] = node.position.y

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var dir := _calculate_direction(camera)
	_apply_visuals(dir)
	_update_render_order(dir)

func _calculate_direction(camera: Camera3D) -> Direction:
	var to_target: Vector3 = (global_position - camera.global_position).normalized()
	var angle: float = atan2(to_target.x, to_target.z)
	var yaw: float = wrapf(angle, 0, TAU)
	
	var owner_controller := owner as PlayerController
	var char_yaw: float = wrapf(owner_controller.camera_yaw, 0, TAU) if owner_controller else 0.0
	var rel_yaw: float = wrapf(yaw - char_yaw, 0, TAU)
	
	if rel_yaw < PI/4 or rel_yaw >= 7*PI/4:
		return Direction.FORWARD
	elif rel_yaw < 3*PI/4:
		return Direction.LEFT
	elif rel_yaw < 5*PI/4:
		return Direction.AWAY
	else:
		return Direction.RIGHT

func _apply_visuals(dir: Direction) -> void:
	var dir_name: String = DIR_NAMES[dir]
	
	for slot in SHEET_MAP:
		var sheet_id: String = SHEET_MAP[slot]
		var sheet: SheetData = SpriteDatabaseLoader.get_sheet(sheet_id)
		if not sheet:
			continue
		var style: String = equipped_styles.get(slot, "style_01")
		var origin_val: Variant = sheet.styles.get(style, null)
		if origin_val == null:
			continue
		var origin: Vector2i = origin_val
		# Retrieve per-direction parts dict
		var dir_parts_val: Variant = sheet.parts.get(dir_name, null)
		if dir_parts_val == null:
			continue
		var dir_parts: Dictionary = dir_parts_val
		# Retrieve per-direction world dict
		var dir_world_val: Variant = sheet.world.get(dir_name, null)
		if dir_world_val == null:
			continue
		var dir_world: Dictionary = dir_world_val
		for part_name in dir_parts:
			var part: PartDef = dir_parts[part_name]
			var sprite_node: Sprite3D = _part_nodes.get(part_name)
			if not sprite_node:
				continue
			# Per‑part world data
			var world: WorldDef = dir_world.get(part_name, WorldDef.new())
			var region_rect := Rect2(
				origin + part.px_offset,
				Vector2(part.px_width, part.px_height)
			)
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet.texture
			atlas.region = region_rect
			sprite_node.texture = atlas
				
			# Apply per‑part world offsets
			sprite_node.offset = world.sprite_offset
			sprite_node.position.y = _base_y.get(part_name, 0.0) + world.y * sprite_node.pixel_size

func _update_render_order(dir: Direction) -> void:
	match dir:
		Direction.LEFT:
			_l_arm.render_priority = -1
			_chest.render_priority = 0
			_r_arm.render_priority = 1
		Direction.RIGHT:
			_r_arm.render_priority = -1
			_chest.render_priority = 0
			_l_arm.render_priority = 1
		_:
			_head.render_priority   = 0
			_chest.render_priority  = 0
			_l_arm.render_priority  = 0
			_r_arm.render_priority  = 0
			_l_leg.render_priority  = 0
			_r_leg.render_priority  = 0
			_l_hand.render_priority = 0
			_r_hand.render_priority = 0

func equip_item(slot: String, style: String) -> void:
	if not SHEET_MAP.has(slot):
		push_error("Unknown equipment slot: %s" % slot)
		return
	if not SpriteDatabaseLoader.get_sheet(SHEET_MAP[slot]).styles.has(style):
		push_error("Style '%s' not found for slot '%s'" % [style, slot])
		return
	equipped_styles[slot] = style
