class_name DialogueBox
extends CanvasLayer
## Story conversations. Lines come from assets/dialogue/story.json as
## [speaker_id, text] pairs; the text types itself out letter by letter.
## E / Space / J advances (or finishes the current line instantly).
## Used through the "dialogue" group:  play(key, on_done)

const STORY_PATH := "res://assets/dialogue/story.json"
const CHARS_PER_SEC := 48.0

static var story: Dictionary = {}

var _lines: Array = []
var _index := 0
var _shown := 0.0
var _on_done: Callable
var _panel: PanelContainer
var _name: Label
var _body: Label
var _portrait: TextureRect
var _next: Label


static func load_story() -> Dictionary:
	if story.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH))
		if parsed is Dictionary:
			story = parsed
		else:
			push_error("DialogueBox: cannot parse " + STORY_PATH)
	return story


func _ready() -> void:
	add_to_group("dialogue")
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_story()
	_build()
	_panel.hide()


func is_open() -> bool:
	return _panel.visible


func play(key: String, on_done: Callable = Callable()) -> void:
	var lines: Variant = story.get(key, [])
	if not lines is Array or (lines as Array).is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_lines = lines
	_index = 0
	_on_done = on_done
	_panel.show()
	_show_line()


func _show_line() -> void:
	var line: Array = _lines[_index]
	var speaker := str(line[0])
	var speakers: Dictionary = story.get("speakers", {})
	_name.text = str(speakers.get(speaker, speaker))
	_body.text = str(line[1])
	_body.visible_characters = 0
	_shown = 0.0
	var portrait := "hermit" if speaker == "koax" else ""
	_portrait.texture = Props.texture(portrait) if portrait != "" else null
	_portrait.visible = portrait != ""
	Audio.sfx("menu_move", -10.0, 0.3)


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	var total := _body.get_total_character_count()
	_shown = minf(_shown + CHARS_PER_SEC * delta, float(total))
	_body.visible_characters = int(_shown)
	_next.visible = int(_shown) >= total and fmod(Time.get_ticks_msec() / 400.0, 2.0) > 0.6
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump") \
			or Input.is_action_just_pressed("attack"):
		if int(_shown) < total:
			_shown = float(total)
		else:
			_index += 1
			if _index >= _lines.size():
				_close()
			else:
				_show_line()


func _close() -> void:
	_panel.hide()
	Audio.sfx("menu_select", -8.0)
	if _on_done.is_valid():
		var cb := _on_done
		_on_done = Callable()
		# a short delay so the key press that closed the box does not also act in the game
		get_tree().create_timer(0.15, true).timeout.connect(cb)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -200
	_panel.offset_bottom = -26
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.09, 0.88)
	sb.border_color = Color(0.95, 0.78, 0.45, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(128, 140)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 26)
	_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	col.add_child(_name)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", 24)
	_body.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
	col.add_child(_body)
	_next = Label.new()
	_next.text = "E ▸"
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	col.add_child(_next)
