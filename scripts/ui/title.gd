extends Node3D
## Start screen. The real level-1 marsh is built behind the menu and the camera drifts
## slowly along it. Continue loads the last save (level + shrine).

const GAME_SCENE := "res://scenes/world/game.tscn"

@onready var level: LevelBuilder = $Level
@onready var camera: Camera3D = $Camera

var _t := 0.0
var _menu: VBoxContainer
var _ui: CanvasLayer


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Audio.music("music_title")
	_ui = CanvasLayer.new()
	add_child(_ui)
	_build_menu()


func _process(delta: float) -> void:
	_t += delta
	var x := 20.0 + _t * 0.9
	camera.position = Vector3(x, 8.5 + sin(_t * 0.2) * 0.4, 11.0)
	camera.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(-8.0), 0.0)
	if x > 150.0:
		_t = 0.0


func _build_menu() -> void:
	for c in _ui.get_children():
		c.queue_free()
	var col := UiStyle.column(_ui, 0.18)
	var logo := UiStyle.label("BREKEKEKEX", 92, Color(0.72, 1.0, 0.55))
	col.add_child(logo)
	col.add_child(UiStyle.label("The Hunter Who Forgot", 32, UiStyle.ACCENT))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	col.add_child(spacer)
	if GameState.has_save():
		col.add_child(UiStyle.button("Continue", _continue))
	col.add_child(UiStyle.button("New Game", _new_game))
	col.add_child(UiStyle.button("Chapters", _show_chapters))
	col.add_child(UiStyle.button("Controls", _show_controls))
	col.add_child(UiStyle.button("Quit", get_tree().quit))
	_menu = col
	for c in col.get_children():
		if c is Button:
			(c as Button).grab_focus.call_deferred()
			break
	var tw := create_tween().set_loops()
	tw.tween_property(logo, "modulate", Color(1.15, 1.15, 1.0), 1.6)
	tw.tween_property(logo, "modulate", Color.WHITE, 1.6)


func _continue() -> void:
	GameState.load_game()
	get_tree().change_scene_to_file(GAME_SCENE)


func _new_game() -> void:
	GameState.new_game()
	get_tree().change_scene_to_file(GAME_SCENE)


## Chapter select: replay any land (all five are open, so every level can be shown).
## Starting land N grants the memories — and powers — of the lands before it.
func _show_chapters() -> void:
	for c in _ui.get_children():
		c.queue_free()
	var col := UiStyle.column(_ui, 0.7)
	col.add_child(UiStyle.label("CHAPTERS", 52, UiStyle.ACCENT))
	var levels: Array = DialogueBox.load_story().get("levels", [])
	var first: Button
	for i in levels.size():
		var n := i + 1
		var b := UiStyle.button("%d   %s" % [n, levels[i]["name"]], func() -> void:
			if not GameState.has_save():
				GameState.new_game()
			else:
				GameState.load_game()
			GameState.start_chapter(n)
			get_tree().change_scene_to_file(GAME_SCENE))
		col.add_child(b)
		if first == null:
			first = b
	col.add_child(UiStyle.button("Back", _build_menu))
	first.grab_focus.call_deferred()


func _show_controls() -> void:
	for c in _ui.get_children():
		c.queue_free()
	var col := UiStyle.column(_ui, 0.7)
	col.add_child(UiStyle.label("CONTROLS", 52, UiStyle.ACCENT))
	var rows := [
		["Move", "A / D   or   ← / →"],
		["Jump  (hold = higher)", "Space"],
		["Wall jump", "Space while sliding on a wall"],
		["Drop through wood", "S + Space"],
		["Staff sweep (combo)", "J"],
		["Launcher (uppercut)", "W + J, then Space to follow"],
		["Air combo  /  Dive", "J in the air  /  S + J or L in the air"],
		["Staff SMASH (stamina)", "L"],
		["Block  /  PARRY", "hold K  /  tap K just before a hit"],
		["Dodge  /  PERFECT dodge", "Shift  /  just as a hit lands"],
		["MOON BREAKER (full spirit)", "U"],
		["Staff Vault · Air Dash", "Space / Shift in mid-air (memory powers)"],
		["Talk / interact", "E"],
		["Pause", "Esc"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	for r: Array in rows:
		var a := UiStyle.label(r[0], 24)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(a)
		var b := UiStyle.label(r[1], 24, UiStyle.ACCENT)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(b)
	col.add_child(grid)
	col.add_child(UiStyle.label("Gamepad: A jump, X sweep, Y smash, B dodge, RB block, LB talk, R3 special", 20))
	var back := UiStyle.button("Back", _build_menu)
	col.add_child(back)
	back.grab_focus.call_deferred()
