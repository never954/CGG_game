@tool
class_name Gate
extends StaticBody3D
## A locked cult gate. Walk up to it carrying a key and it sinks into the ground.

var _sprite: Sprite3D
var _open := false


func _ready() -> void:
	_sprite = Props.make("gate", Vector3.ZERO)
	add_child(_sprite)
	if Engine.is_editor_hint():
		return
	($Sense as Area3D).body_entered.connect(_on_sense)


func _on_sense(body: Node3D) -> void:
	if _open or not body.is_in_group("player"):
		return
	if not GameState.use_key():
		get_tree().call_group("hud", "show_hint", "Locked. A key must be somewhere in this land.", 2.5)
		return
	_open = true
	Audio.sfx("gate")
	get_tree().call_group("camera", "add_trauma", 0.3)
	HitFx.dust(get_parent(), global_position, 16)
	$Shape.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_sprite, "position:y", _sprite.position.y - 3.2, 1.1).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_sprite.hide)
