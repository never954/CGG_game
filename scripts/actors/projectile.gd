class_name Projectile
extends Node3D
## A flying hit: the cultist's thrown dagger (hostile) or the hunter's Spirit Wave
## (friendly). A hostile one can be knocked back with a swing of the staff or parried —
## then it flies back and hurts enemies instead.

var velocity := Vector3.ZERO
var damage := 1
var hostile := true
var source: Node = null
var _life := 3.0
var _mesh: MeshInstance3D
var _light: OmniLight3D


static func spawn(parent: Node, at: Vector3, vel: Vector3, dmg: int, from: Node, is_hostile: bool) -> Projectile:
	var p := Projectile.new()
	p.velocity = vel
	p.damage = dmg
	p.source = from
	p.hostile = is_hostile
	p.position = at
	parent.add_child(p)
	return p


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = Vector3(0.22, 0.6, 0.06) if hostile else Vector3(0.5, 1.1, 0.3)
	_mesh.mesh = m
	_mesh.rotation.z = -PI / 2 if velocity.x > 0.0 else PI / 2          # point along the flight
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.omni_range = 2.5
	_light.light_energy = 1.5
	add_child(_light)
	_paint()


func _paint() -> void:
	var col := Color(1.6, 0.5, 1.8) if hostile else Color(2.0, 1.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	_light.light_color = Color(col.r / 2.0, col.g / 2.0, col.b / 2.0)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var from := global_position
	global_position += velocity * delta
	# hit a wall or the ground
	var q := PhysicsRayQueryParameters3D.create(from, global_position, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		HitFx.dust(get_parent(), global_position, 4)
		queue_free()
		return
	if hostile:
		_hostile_step()
	else:
		_friendly_step()


func _hostile_step() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if player.is_striking() and player.hitbox.global_position.distance_to(global_position) < 1.6:
		_reflect(player)
		return
	if (player.global_position + Vector3(0, 0.9, 0)).distance_to(global_position) < 0.75:
		match player.take_damage(damage, global_position.x - signf(velocity.x), self):
			"parried":
				_reflect(player)
			"dodged", "immune":
				pass                                     # it flies straight past
			_:
				queue_free()


func _friendly_step() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.state != "dead" and (e.global_position + Vector3(0, 0.8, 0)).distance_to(global_position) < 1.1:
			e.call("take_hit", damage + 1, global_position.x - signf(velocity.x), false, 6.0)
			HitFx.sparks(get_parent(), global_position, false)
			Audio.sfx("hit", -3.0)
			queue_free()
			return


## Knocked back by the hunter: now it hunts its thrower.
func _reflect(player: Player) -> void:
	hostile = false
	_life = 2.0
	var target := source as Node3D
	if target != null and is_instance_valid(target):
		velocity = (target.global_position + Vector3(0, 0.9, 0) - global_position).normalized() * 16.0
	else:
		velocity = Vector3(player.facing * 16.0, 0.0, 0.0)
	_mesh.rotation.z = -PI / 2 if velocity.x > 0.0 else PI / 2
	_paint()
	Audio.sfx("block", 2.0, 0.0)
	GameState.hitstop(0.08)
	GameState.add_spirit(10.0)
	HitFx.sparks(get_parent(), global_position, true)
	HitFx.popup(get_parent(), global_position + Vector3(0, 0.8, 0.3), "REFLECT", Color(2.0, 1.6, 0.6))
