class_name Crate
extends RigidBody3D
## A wooden crate run by the physics engine: push it by walking into it, knock it with
## the staff, stand on it to reach high ledges. A heavy smash breaks it (dropping an
## orb the first time) and a fresh crate drops back in at its starting spot, so a
## crate puzzle can never become impossible.

const PICKUP := preload("res://scenes/world/pickup.tscn")

var _home := Vector3.ZERO
var _rewarded := false
var _respawning := false


func _ready() -> void:
	_home = global_position
	add_to_group("crate")


func _physics_process(_delta: float) -> void:
	if global_position.y < -20.0:
		respawn()


func smash() -> void:
	if _respawning:
		return
	Audio.sfx("crate")
	HitFx.dust(get_parent(), global_position + Vector3(0, 0.5, 0), 14)
	if not _rewarded:
		_rewarded = true
		var p := PICKUP.instantiate()
		p.set("kind", "orb")
		p.position = global_position + Vector3(0, 0.8, 0)
		get_parent().add_child(p)
	respawn()


func respawn() -> void:
	if _respawning:
		return
	_respawning = true
	visible = false
	collision_layer = 0
	await get_tree().create_timer(1.2, false).timeout
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), _home + Vector3(0, 1.5, 0)))
	linear_velocity = Vector3.ZERO
	collision_layer = 32
	visible = true
	_respawning = false
	HitFx.dust(get_parent(), _home, 8)
