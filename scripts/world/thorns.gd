@tool
class_name Thorns
extends Area3D
## Bramble of thorns. Hurts on touch (the hunter is briefly invulnerable afterwards,
## so it does not drain every frame).


func _ready() -> void:
	for dx: float in [-0.5, 0.5]:
		add_child(Props.make("thorns", Vector3(dx, 0, 0.1 * dx)))


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for body in get_overlapping_bodies():
		if body is Player:
			(body as Player).take_damage(1, global_position.x)
