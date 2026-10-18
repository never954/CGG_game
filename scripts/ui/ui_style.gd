class_name UiStyle
extends RefCounted
## Shared look for menus and buttons, so every screen matches.

const ACCENT := Color(1.0, 0.80, 0.46)
const TEXT := Color(0.95, 0.93, 0.90)
const SHADOW := Color(0.04, 0.03, 0.06, 0.9)


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 50)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.06, 0.1, 0.72)
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.16, 0.12, 0.12, 0.9)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.focus_entered.connect(func() -> void: Audio.sfx("menu_move", -8.0, 0.0))
	b.mouse_entered.connect(b.grab_focus)
	b.pressed.connect(func() -> void:
		Audio.sfx("menu_select", -4.0, 0.0)
		on_press.call())
	return b


## Pass `wrap_width` to wrap long text at that width (otherwise one line per line).
static func label(text: String, size: int, color: Color = TEXT, wrap_width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap_width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_width, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	return l


## A centred column filling the screen, optionally over a dark veil.
static func column(parent: Node, veil: float = 0.55) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, veil)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	return col
