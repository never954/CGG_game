@tool
class_name Shrine
extends Area3D
## Checkpoint. Touch it and it lights up: your health is restored and the game is
## saved — if you die (or quit) you start again from the last shrine you lit.

var index: int = 0        ## set by the LevelBuilder, left to right
var lit := false

var _sprite: Sprite3D
var _light: OmniLight3D


func _ready() -> void:
	_sprite = Props.make("shrine", Vector3.ZERO)
	add_child(_sprite)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.95, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	_light.light_volumetric_fog_energy = 3.0
	_light.position = Vector3(0, 1.8, 0.4)
	add_child(_light)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


## Light without ceremony (used when a saved game is loaded).
func set_lit() -> void:
	lit = true
	_sprite.texture = Props.texture("shrine_lit")
	_light.light_energy = 2.2


func _on_body_entered(body: Node3D) -> void:
	if lit or not body.is_in_group("player"):
		return
	set_lit()
	GameState.reach_checkpoint(index)
	Audio.sfx("shrine")
	HitFx.sparks(get_parent(), global_position + Vector3(0, 1.6, 0.3), true)
	get_tree().call_group("hud", "show_hint", "Shrine lit — health restored, progress saved", 2.5)
	var tw := create_tween()
	_light.light_energy = 7.0
	tw.tween_property(_light, "light_energy", 2.2, 1.2)
