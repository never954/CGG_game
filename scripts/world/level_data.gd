class_name LevelData
extends RefCounted
## One parsed level file (assets/levels/level_N.txt). Every character is a 1 x 1 metre
## tile; row 0 is the TOP of the level. See docs/LEVELS.md for the full legend.
##   ;  comment line          @key value   setting (name, theme, memory, ...)

var meta: Dictionary = {}
var rows: Array[String] = []
var width: int = 0
var height: int = 0


static func load_file(path: String) -> LevelData:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("LevelData: missing or empty level file " + path)
		return null
	var d := LevelData.new()
	for raw in text.split("\n"):
		var line := raw.rstrip("\r")
		if line.begins_with(";"):
			continue
		if line.begins_with("@"):
			var kv := line.substr(1).split(" ", false, 1)
			if kv.size() == 2:
				d.meta[kv[0]] = kv[1].strip_edges()
			continue
		if line.strip_edges() == "" and d.rows.is_empty():
			continue
		d.rows.append(line)
	while not d.rows.is_empty() and d.rows[d.rows.size() - 1].strip_edges() == "":
		d.rows.pop_back()
	d.height = d.rows.size()
	for r in d.rows:
		d.width = maxi(d.width, r.length())
	for i in d.height:
		d.rows[i] = d.rows[i].rpad(d.width, ".")
	return d


func cell(col: int, row: int) -> String:
	if col < 0 or row < 0 or col >= width or row >= height:
		return "."
	return rows[row][col]


## Solid ground. Outside the left/right/bottom edges counts as solid (no exposed faces there).
func is_solid(col: int, row: int) -> bool:
	if row >= height or col < 0 or col >= width:
		return row >= 0
	if row < 0:
		return false
	return rows[row][col] == "#"


## World-space y of the BOTTOM of a tile row (y points up, the map's bottom is y = 0).
func row_bottom(row: int) -> float:
	return float(height - 1 - row)


func setting(key: String, fallback: String = "") -> String:
	return str(meta.get(key, fallback))
