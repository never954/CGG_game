@tool
class_name SheetSprite
extends AnimatedSprite3D
## Turns a generated sprite sheet (PNG + JSON written by tools/assetgen) into a set of
## animations: one row per animation, one cell per frame, frame rate and looping from
## the JSON. The sprite is offset so the character's FEET sit at the parent's origin.
## It is a @tool script, so characters are visible inside the editor too.

@export var sheet: String = "res://assets/sprites/hunter":
	set(value):
		sheet = value
		if is_node_ready():
			build()
@export var start_animation: String = "idle"
@export var size_scale: float = 1.0                ## bosses are the same art drawn bigger

var cell := Vector2i(64, 64)
var foot := Vector2i(32, 60)


func _ready() -> void:
	build()


func build() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sheet + ".json"))
	if not parsed is Dictionary:
		push_error("SheetSprite: cannot read " + sheet + ".json")
		return
	var meta: Dictionary = parsed
	cell = Vector2i(int(meta["cell"][0]), int(meta["cell"][1]))
	foot = Vector2i(int(meta["foot"][0]), int(meta["foot"][1]))
	var tex: Texture2D = load(sheet + ".png")
	var frames := SpriteFrames.new()
	for a: Dictionary in meta["animations"]:
		var anim := StringName(str(a["name"]))
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(a["fps"]))
		frames.set_animation_loop(anim, bool(a["loop"]))
		for i in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * cell.x, int(a["row"]) * cell.y, cell.x, cell.y)
			frames.add_frame(anim, at)
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	sprite_frames = frames
	Props.style(self, size_scale)
	position = Vector3(0.0, (foot.y - cell.y * 0.5) * pixel_size, 0.0)
	if frames.has_animation(start_animation):
		play(start_animation)
