@tool
class_name Pickup
extends Area3D
## Something to collect. The kind decides the sprite and the effect:
##   orb    spirit orb (the currency/score; drifts towards you when you are close)
##   peach  heals 2 hearts
##   key    opens one gate
##   eye    a frog eye holding one of the hunter's memories — the goal of each level

@export_enum("orb", "peach", "key", "eye") var kind: String = "orb"

var _sprite: Sprite3D
var _t := 0.0
var _taken := false
var _player: Node3D


func _ready() -> void:
	_t = randf() * TAU
	_sprite = Sprite3D.new()
	_sprite.texture = Props.texture(kind)
	Props.style(_sprite, 1.0, false)
	add_child(_sprite)
	if kind == "key" or kind == "eye":
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.4) if kind == "key" else Color(0.5, 1.0, 0.6)
		light.light_energy = 1.4
		light.omni_range = 3.5
		add_child(light)
	if Engine.is_editor_hint():
		return
	if kind == "eye" and GameState.memories.has(GameState.level):
		queue_free()                                         # already recovered (continuing a save)
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	_sprite.position.y = sin(_t * 2.6) * 0.12
	if kind == "eye" or kind == "key":
		_sprite.rotation.y = sin(_t * 1.4) * 0.6
	if Engine.is_editor_hint() or _taken or kind != "orb":
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var to := _player.global_position + Vector3(0, 0.9, 0) - global_position
	if to.length() < 3.2:                                    # orbs are drawn to the hunter
		global_position += to.normalized() * minf(to.length(), 9.0 * delta)


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	match kind:
		"orb":
			GameState.add_orbs(1)
			Audio.sfx("orb", -6.0, 0.15)
		"peach":
			GameState.heal(2)
			Audio.sfx("heal")
			get_tree().call_group("hud", "show_hint", "+2 health", 1.5)
		"key":
			GameState.add_key()
			Audio.sfx("key")
			get_tree().call_group("hud", "show_hint", "Found a key — it opens a gate", 2.5)
		"eye":
			Audio.sfx("memory")
			get_tree().call_group("game", "memory_found")
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector3(1.8, 1.8, 1.8), 0.12)
	tw.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)
