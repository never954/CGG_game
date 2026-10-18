class_name ImpactFrame
extends CanvasLayer
## Anime impact frames (as in BREKEKEKEX and anime fighters): on a big hit the screen
## flashes for two or three frames as a stark black/white/red image, then snaps back.
## Triggered through the "impact" group:  play(strong)

var _rect: ColorRect
var _mat: ShaderMaterial
var _token := 0


func _ready() -> void:
	add_to_group("impact")
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/fx/impact_frame.gdshader")
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## strong = longer sequence (inverted, normal, inverted) for the special and parries.
func play(strong: bool = false) -> void:
	_token += 1
	var token := _token
	var steps := [true, false, true] if strong else [true, false]
	for inv: bool in steps:
		if token != _token:
			return
		_mat.set_shader_parameter("inverted", inv)
		_rect.visible = true
		await get_tree().create_timer(0.045, true, false, true).timeout
	if token == _token:
		_rect.visible = false
