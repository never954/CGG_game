@tool
class_name LevelExit
extends Area3D
## The torii-like arch at the end of a level. It only lets you through once you hold
## this land's memory eye.

var _done := false
var _warned := 0.0


func _ready() -> void:
	add_child(Props.make("exit", Vector3(0, 0, -0.6)))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0, 3.0, 0.5)
	add_child(light)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _done or not body.is_in_group("player"):
		return
	if not GameState.memories.has(GameState.level):
		get_tree().call_group("hud", "show_hint", "Not yet. A memory of yours is still hidden in this land.", 3.0)
		return
	_done = true
	get_tree().call_group("game", "level_complete")
