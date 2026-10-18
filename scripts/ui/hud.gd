class_name Hud
extends CanvasLayer
## Heads-up display, drawn with Control._draw (hearts, stamina, orbs, keys, memory
## eyes, boss health) plus fading text for level titles and hints.
## Other nodes talk to it through the "hud" group:
##   show_hint(text, seconds)   show_title(title, subtitle)   show_boss(name, fraction)
##   add_hit()   break_combo()   (the combo counter)
## Also shows the spirit meter, which unlocks the Moon Breaker special (U) when full.

const HEART_RED := Color(0.92, 0.22, 0.26)
const GOLD := Color(1.0, 0.86, 0.5)

var _canvas: Control
var _font: Font
var _hint := ""
var _hint_t := 0.0
var _title := ""
var _subtitle := ""
var _title_t := 0.0
var _boss_name := ""
var _boss_frac := -1.0
var _boss_shown := 0.0
var _hp_shown := float(GameState.MAX_HP)
var _player: Node
var _combo := 0
var _combo_t := 0.0
var _combo_pop := 0.0


func _ready() -> void:
	add_to_group("hud")
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS          # titles keep fading while a dialogue pauses the game
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func show_hint(text: String, seconds: float = 3.0) -> void:
	_hint = text
	_hint_t = seconds


func show_title(title: String, subtitle: String = "") -> void:
	_title = title
	_subtitle = subtitle
	_title_t = 4.0


func show_boss(boss_name: String, fraction: float) -> void:
	_boss_name = boss_name
	_boss_frac = fraction


func add_hit() -> void:
	_combo = _combo + 1 if _combo_t > 0.0 else 1
	_combo_t = 1.8
	_combo_pop = 1.0


func break_combo() -> void:
	_combo_t = 0.0


func _process(delta: float) -> void:
	_combo_t = maxf(0.0, _combo_t - delta)
	_combo_pop = move_toward(_combo_pop, 0.0, delta * 5.0)
	_hint_t = maxf(0.0, _hint_t - delta)
	_title_t = maxf(0.0, _title_t - delta)
	_hp_shown = move_toward(_hp_shown, GameState.hp, delta * 4.0)
	if _boss_frac >= 0.0:
		_boss_shown = move_toward(_boss_shown, _boss_frac, delta * 0.8)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	_canvas.queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string_outline(_font, pos, s, align, width, size, 6, Color(0.05, 0.03, 0.06, col.a * 0.9))
	_canvas.draw_string(_font, pos, s, align, width, size, col)


func _heart(c: Vector2, r: float, fill: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0 * TAU
		# classic heart curve, scaled to radius r
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * r / 16.0)
	_canvas.draw_colored_polygon(pts, Color(0.12, 0.06, 0.08, 0.85))
	if fill > 0.0:
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(c + (p - c) * 0.78)
		var col := HEART_RED if fill >= 1.0 else HEART_RED.darkened(0.45)
		_canvas.draw_colored_polygon(inner, col)
		_canvas.draw_circle(c + Vector2(-r * 0.38, -r * 0.35), r * 0.16, Color(1, 0.75, 0.75, 0.8))
	_canvas.draw_polyline(pts, Color(0.05, 0.02, 0.04), 2.0, true)


func _draw_hud() -> void:
	var size := _canvas.size
	# hearts
	for i in GameState.MAX_HP:
		var fill := clampf(_hp_shown - i, 0.0, 1.0)
		_heart(Vector2(40 + i * 46, 42), 19.0, fill)
	# stamina
	var stamina := 100.0
	if _player != null and is_instance_valid(_player):
		stamina = float(_player.get("stamina"))
	var bar := Rect2(22, 72, 220, 12)
	_canvas.draw_rect(bar.grow(3), Color(0.05, 0.03, 0.06, 0.8))
	var sc := Color(0.55, 0.9, 0.45) if stamina >= 22.0 else Color(0.95, 0.45, 0.3)
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * stamina / GameState.MAX_STAMINA, bar.size.y)), sc)
	# spirit meter (gold) — full means the Moon Breaker is ready
	var sp := GameState.spirit / GameState.MAX_SPIRIT
	var sbar := Rect2(22, 92, 220, 8)
	_canvas.draw_rect(sbar.grow(3), Color(0.05, 0.03, 0.06, 0.8))
	var full := sp >= 1.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	var gold := Color(1.0, 0.78, 0.3).lerp(Color(1.6, 1.4, 0.8), pulse if full else 0.0)
	_canvas.draw_rect(Rect2(sbar.position, Vector2(sbar.size.x * sp, sbar.size.y)), gold)
	if full:
		_text(Vector2(252, 102), "U  MOON BREAKER", 20, Color(1.0, 0.9, 0.5, 0.6 + 0.4 * pulse))
	# combo counter
	if _combo >= 2 and _combo_t > 0.0:
		var a := clampf(_combo_t * 2.0, 0.0, 1.0)
		var sz := int(44 + 18 * _combo_pop)
		_text(Vector2(size.x - 260, size.y * 0.42), "%d" % _combo, sz, Color(1.0, 0.85, 0.4, a), HORIZONTAL_ALIGNMENT_RIGHT, 150)
		_text(Vector2(size.x - 104, size.y * 0.42), "HITS", 22, Color(1, 0.95, 0.85, a))
	# orbs and keys
	var x := size.x - 40.0
	_canvas.draw_texture_rect(Props.texture("orb"), Rect2(x - 150, 22, 32, 32), false)
	_text(Vector2(x - 110, 48), "%d" % GameState.orbs, 26, GOLD)
	if GameState.keys > 0:
		_canvas.draw_texture_rect(Props.texture("key"), Rect2(x - 150, 60, 36, 36), false)
		_text(Vector2(x - 110, 88), "x%d" % GameState.keys, 24, GOLD)
	# memory eyes recovered
	for i in GameState.LEVEL_COUNT:
		var got := GameState.memories.has(i + 1)
		var col := Color.WHITE if got else Color(0.25, 0.25, 0.3, 0.7)
		_canvas.draw_texture_rect(Props.texture("eye"), Rect2(size.x * 0.5 - 95 + i * 38, 18, 34, 34), false, col)
	# level title card
	if _title_t > 0.0:
		var a := clampf(minf(_title_t, 4.0 - _title_t) * 1.5, 0.0, 1.0)
		_canvas.draw_rect(Rect2(0, size.y * 0.30, size.x, 120), Color(0, 0, 0, 0.35 * a))
		_text(Vector2(0, size.y * 0.30 + 64), _title, 52, Color(1, 0.93, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(Vector2(0, size.y * 0.30 + 102), _subtitle, 24, Color(0.85, 0.85, 0.9, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# hint
	var talking := get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if _hint_t > 0.0 and not (talking and talking.is_open()):
		var a2 := clampf(_hint_t * 2.0, 0.0, 1.0)
		_text(Vector2(0, size.y - 70), _hint, 26, Color(1, 0.95, 0.85, a2), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# boss bar
	if _boss_frac >= 0.0 and _boss_shown > 0.001:
		var w := size.x * 0.5
		var r := Rect2((size.x - w) * 0.5, size.y - 40, w, 14)
		_canvas.draw_rect(r.grow(4), Color(0.05, 0.02, 0.03, 0.85))
		_canvas.draw_rect(Rect2(r.position, Vector2(w * _boss_shown, r.size.y)), Color(0.85, 0.2, 0.2))
		_canvas.draw_rect(Rect2(r.position, Vector2(w * _boss_frac, r.size.y)), Color(0.95, 0.35, 0.3))
		_text(Vector2(0, size.y - 52), _boss_name, 24, Color(1, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
