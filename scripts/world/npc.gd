@tool
class_name Npc
extends Area3D
## Old Koax, the hermit of the marsh — the side character who knows the hunter's story.
## Stand next to him and press E (interact) to talk. What he says in each level comes
## from assets/dialogue/story.json under `dialogue_key`.

@export var dialogue_key: String = "level_1_hermit"
@export var prop: String = "hermit"

var _sprite: Sprite3D
var _prompt: Label3D
var _player: Player
var _talked := false


func _ready() -> void:
	_sprite = Props.make(prop, Vector3.ZERO)
	add_child(_sprite)
	_prompt = Label3D.new()
	_prompt.text = "E  Talk"
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.pixel_size = 0.006
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0, 2.9, 0.2)
	_prompt.modulate = Color(1.0, 0.92, 0.7)
	_prompt.visible = false
	add_child(_prompt)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _player == null:
		return
	_sprite.flip_h = _player.global_position.x < global_position.x
	_prompt.visible = _player.state == Player.State.NORMAL
	if not _talked:
		_prompt.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)


func _on_enter(body: Node3D) -> void:
	if body is Player:
		_player = body
		_player.interact_target = self


func _on_exit(body: Node3D) -> void:
	if body == _player:
		if _player.interact_target == self:
			_player.interact_target = null
		_player = null
		_prompt.visible = false


func interact(_by: Player) -> void:
	_talked = true
	_prompt.modulate.a = 1.0
	get_tree().call_group("game", "talk", dialogue_key)
