class_name Menus
extends CanvasLayer
## In-game screens: pause, game over, level complete, and the ending.
## Only one is visible at a time; each is rebuilt when shown.

signal retry
signal continue_next
signal quit_to_title

var can_pause: Callable = func() -> bool: return true

var _screen: Control
var _paused_screen := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _screen == null and can_pause.call():
		show_pause()
	elif _paused_screen:
		close()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _screen != null


func close() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	_paused_screen = false
	get_tree().paused = false


func _open(veil: float = 0.6) -> VBoxContainer:
	_paused_screen = false
	if _screen:
		_screen.queue_free()
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	return UiStyle.column(_screen, veil)


func _focus_first(col: Control) -> void:
	for c in col.get_children():
		if c is Button:
			(c as Button).grab_focus.call_deferred()
			return


func show_pause() -> void:
	get_tree().paused = true
	var col := _open()
	col.add_child(UiStyle.label("PAUSED", 56, UiStyle.ACCENT))
	col.add_child(UiStyle.label(_controls_text(), 20))
	col.add_child(UiStyle.button("Resume", close))
	col.add_child(UiStyle.button("Restart from shrine", func() -> void: close(); retry.emit()))
	col.add_child(UiStyle.button("Quit to title", func() -> void: close(); quit_to_title.emit()))
	_focus_first(col)
	_paused_screen = true


func show_game_over() -> void:
	get_tree().paused = true
	var col := _open(0.7)
	col.add_child(UiStyle.label("YOU FELL", 64, Color(0.95, 0.35, 0.3)))
	col.add_child(UiStyle.label("The marsh keeps what it takes... but not you. Not yet.", 22))
	col.add_child(UiStyle.button("Rise again (last shrine)", func() -> void: close(); retry.emit()))
	col.add_child(UiStyle.button("Quit to title", func() -> void: close(); quit_to_title.emit()))
	_focus_first(col)


func show_level_complete(level_name: String, memory_text: String) -> void:
	get_tree().paused = true
	var col := _open(0.65)
	col.add_child(UiStyle.label(level_name + " — cleared", 46, UiStyle.ACCENT))
	var mem := UiStyle.label("“" + memory_text + "”", 24, UiStyle.TEXT, 760.0)
	col.add_child(mem)
	col.add_child(UiStyle.label("Spirit orbs: %d      Falls: %d" % [GameState.orbs, GameState.deaths], 22))
	col.add_child(UiStyle.button("Continue", func() -> void: close(); continue_next.emit()))
	_focus_first(col)


## The ending: the hunter remembers — and then the sequel tease.
func show_ending(pages: Array) -> void:
	get_tree().paused = true
	var col := _open(0.0)
	var veil := _screen.get_child(0) as ColorRect
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 0.92, 2.0)
	var text := UiStyle.label("", 30, UiStyle.TEXT, 900.0)
	text.custom_minimum_size.y = 260
	col.add_child(text)
	for page: String in pages:
		tw.tween_callback(func() -> void: text.text = page; text.modulate.a = 0.0)
		tw.tween_property(text, "modulate:a", 1.0, 1.2)
		tw.tween_interval(clampf(page.length() * 0.055, 2.8, 7.0))
		tw.tween_property(text, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func() -> void:
		text.text = "BREKEKEKEX  KOAX  KOAX"
		text.add_theme_color_override("font_color", Color(0.6, 1.0, 0.55))
		get_tree().call_group("camera", "add_trauma", 0.8)
		Audio.sfx("croak", 6.0, 0.0))
	tw.tween_property(text, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void:
		text.text = "TO BE CONTINUED..."
		text.add_theme_color_override("font_color", UiStyle.ACCENT))
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void:
		col.add_child(UiStyle.button("Return to title", func() -> void: close(); quit_to_title.emit()))
		_focus_first(col))


static func _controls_text() -> String:
	return "Move  A/D      Jump  Space      Drop through  S + Space      Talk  E\n" \
		+ "Sweep  J      Launcher  W + J      Air combo  J in air      Dive  S + J in air\n" \
		+ "Smash  L      Block / Parry  K      Dodge / Perfect dodge  Shift      Moon Breaker  U"
