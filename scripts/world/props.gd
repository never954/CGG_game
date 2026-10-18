class_name Props
extends RefCounted
## Flat pixel-art "cut-outs" standing in the 3D world — the HD-2D look.
## Every sprite uses the same pixel size so characters, trees and items share one
## pixel grid. Sizes and foot points come from assets/sprites/props/props.json.

const PIXEL := 0.03           ## metres per sprite pixel (used by every sprite in the game)
const DIR := "res://assets/sprites/props/"

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}


static func info(prop_name: String) -> Array:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "props.json"))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest.get(prop_name, [32, 32, 16, 31])


static func texture(prop_name: String) -> Texture2D:
	if not _textures.has(prop_name):
		_textures[prop_name] = load(DIR + prop_name + ".png")
	return _textures[prop_name]


## A sprite whose FOOT (bottom-centre point) stands exactly at `at`.
static func make(prop_name: String, at: Vector3, scale: float = 1.0, shadows: bool = true) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = prop_name.capitalize()
	s.texture = texture(prop_name)
	style(s, scale, shadows)
	var inf := info(prop_name)
	var w := float(inf[0])
	var h := float(inf[1])
	var fx := float(inf[2])
	var fy := float(inf[3])
	s.position = at + Vector3(-(fx - w * 0.5) * s.pixel_size, (fy - h * 0.5) * s.pixel_size, 0.0)
	return s


## Shared settings for every sprite: crisp pixels, lit by the scene, casting shadows.
static func style(s: SpriteBase3D, scale: float = 1.0, shadows: bool = true) -> void:
	s.pixel_size = PIXEL * scale
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.double_sided = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
