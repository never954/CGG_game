extends Area3D
## Deep water (created by the LevelBuilder under every water surface). The hunter
## cannot swim: falling in costs a heart and puts him back on the last safe ground.
## Enemies drown, crates float back to where they started.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	HitFx.splash(get_parent(), Vector3(body.global_position.x, global_position.y + (get_child(0).shape as BoxShape3D).size.y * 0.5, 0.3))
	Audio.sfx("land", -2.0)
	if body is Player:
		(body as Player).drown.call_deferred()
	elif body is Enemy:
		(body as Enemy).die()
	elif body is Crate:
		(body as Crate).respawn()
