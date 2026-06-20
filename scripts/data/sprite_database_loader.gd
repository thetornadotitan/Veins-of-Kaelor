extends Node

var _sheets: Dictionary[String, SheetData] = {}

const DATABASE_PATH: String = "res://data/sprite_database.json"

func _ready() -> void:
	_load_database()

func get_sheet(sheet_id: String) -> SheetData:
	if not _sheets.has(sheet_id):
		push_error("SpriteDatabaseLoader: sheet '%s' not found" % sheet_id)
		return null
	return _sheets[sheet_id]

func _load_database() -> void:
	if not FileAccess.file_exists(DATABASE_PATH):
		push_error("SpriteDatabaseLoader: %s not found" % DATABASE_PATH)
		return

	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if not file:
		push_error("SpriteDatabaseLoader: failed to open %s" % DATABASE_PATH)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("SpriteDatabaseLoader: JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data: Dictionary = json.get_data()
	if not data is Dictionary:
		push_error("SpriteDatabaseLoader: root is not a dictionary")
		return

	for sheet_id in data:
		var entry: Dictionary = data[sheet_id]
		var sheet := SheetData.new()
		sheet.texture = load(entry.get("texture_path", ""))
		sheet.parts = _parse_parts(entry.get("parts", {}))
		sheet.world = _parse_world(entry.get("world", {}))
		sheet.styles = _parse_styles(entry.get("styles", {}))
		_sheets[sheet_id] = sheet

	print("SpriteDatabaseLoader: loaded %d sheets" % _sheets.size())

func _parse_parts(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# raw is expected to be a dict of direction -> {part_name: {px_offset, px_width, px_height}}
	for dir_name in raw:
		var dir_raw: Dictionary = raw[dir_name]
		var dir_dict: Dictionary = {}
		for part_name in dir_raw:
			var d: Dictionary = dir_raw[part_name]
			var def := PartDef.new()
			var offset_arr: Array = d.get("px_offset", [0, 0])
			def.px_offset = Vector2i(int(offset_arr[0]), int(offset_arr[1]))
			def.px_width = int(d.get("px_width", 0))
			def.px_height = int(d.get("px_height", 0))
			dir_dict[part_name] = def
		result[dir_name] = dir_dict
	return result

func _parse_world(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for dir_name in raw:
		var dir_raw: Dictionary = raw[dir_name]
		var dir_dict: Dictionary = {}
		for part_name in dir_raw:
			var d: Dictionary = dir_raw[part_name]
			var def := WorldDef.new()
			var offset_arr: Array = d.get("sprite_offset", [0.0, 0.0])
			def.sprite_offset = Vector2(float(offset_arr[0]), float(offset_arr[1]))
			def.y = float(d.get("y", 0.0))
			dir_dict[part_name] = def
		result[dir_name] = dir_dict
	return result

func _parse_styles(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# raw is a dict of style_name -> [x, y]
	for style_name in raw:
		var arr: Array = raw[style_name]
		if arr.size() >= 2:
			var origin := Vector2i(int(arr[0]), int(arr[1]))
			result[style_name] = origin
		else:
			push_error("Style entry for %s does not contain a valid [x, y] array" % style_name)
	return result
