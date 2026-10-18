class_name Enemy
extends CharacterBody3D
## Shared enemy behaviour. Subclasses only write think() — the decisions.
##
## What makes them dangerous and hard to predict:
##   * TELLS: before an attack the enemy freezes on its wind-up frame and flashes red —
##     but the wind-up length is randomised, so you can't just count a fixed rhythm.
##   * FEINTS: sometimes the wind-up is a bluff: it flashes, then hops back instead.
##   * EVASION: when you start a swing in front of them, agile enemies may dodge it.
##   * ATTACK SLOTS: at most two enemies commit to an attack at once, the rest circle,
##     so groups pressure you from both sides without becoming an unfair pile-on.
## What you can do to them:
##   * staggers (light hits on light enemies, heavy hits on anything)
##   * JUGGLES: launched enemies are helpless in the air until they land
##   * STUN: a parried enemy is dazed for a moment and takes extra damage

signal died(enemy: Enemy)

const PICKUP := preload("res://scenes/world/pickup.tscn")
const MAX_ATTACKERS := 2
const CALM_STATES := ["idle", "walk", "hop", "hurt", "dead", "air", "down", "stunned", "evade", "retreat"]

static var _attackers: Dictionary = {}       ## instance ids of enemies currently attacking

@export var max_hp: int = 3
@export var move_speed: float = 2.4
@export var aggro_range: float = 10.0
@export var damage: int = 1
@export var gravity: float = 30.0
@export var orb_drop: int = 2
@export_range(0.0, 1.0) var knock_resist: float = 0.0
@export_range(0.0, 1.0) var juggle_resist: float = 0.0   ## 1 = cannot be launched
@export_range(0.0, 1.0) var evade_chance: float = 0.0    ## chance to dodge a swing aimed at it
@export_range(0.0, 1.0) var feint_chance: float = 0.0    ## chance a wind-up is a bluff
@export var hurt_sound: String = "enemy_hurt"

var hp: int = 0
var facing: int = -1
var state: String = "idle"
var state_t: float = 0.0
var player: Player
var base_modulate := Color.WHITE

var _flash_t := 0.0
var _struck := false
var _windup_left := -1.0
var _windup_total := 0.0
var _feinting := false
var _stun_time := 0.0
var _evade_cd := 0.0

@onready var sprite: SheetSprite = $Sprite


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	sprite.modulate = base_modulate
	sprite.animation_finished.connect(on_animation_done)


func _exit_tree() -> void:
	_attackers.erase(get_instance_id())


func _physics_process(delta: float) -> void:
	state_t += delta
	_evade_cd -= delta
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
	velocity.y -= gravity * (0.55 if state == "air" and velocity.y < 0.0 else 1.0) * delta
	_update_windup(delta)
	match state:
		"dead":
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		"hurt":
			velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
			if state_t > 0.3:
				go("idle", "idle")
		"air":                                         # launched: helpless until landing
			velocity.x = move_toward(velocity.x, 0.0, 3.0 * delta)
			if is_on_floor() and state_t > 0.15:
				HitFx.dust(get_parent(), global_position, 8)
				go("down", "hurt")
		"down":
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			if state_t > 0.55:
				go("idle", "idle")
		"stunned":                                     # parried: dazed, flashing yellow
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			sprite.modulate = Color(1.8, 1.6, 0.6) if fmod(state_t, 0.2) > 0.1 else base_modulate
			if state_t > _stun_time:
				sprite.modulate = base_modulate
				go("idle", "idle")
		"evade":
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			if state_t > 0.4 and is_on_floor():
				go("idle", "idle")
		_:
			think(delta)
	move_and_slide()
	global_position.z = 0.0
	sprite.flip_h = facing < 0
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0 and _windup_left < 0.0 and state != "stunned":
			sprite.modulate = base_modulate


func _update_windup(delta: float) -> void:
	if _windup_left < 0.0:
		return
	_windup_left -= delta
	sprite.modulate = Color(1.9, 0.7, 0.65) if fmod(_windup_left, 0.12) > 0.06 else base_modulate
	if _feinting and _windup_left < _windup_total * 0.35:
		# it was a bluff: back off instead of attacking
		_windup_left = -1.0
		sprite.modulate = base_modulate
		go("evade", move_anim())
		velocity = Vector3(-facing * 5.5, 3.0, 0.0)
		return
	if _windup_left < 0.0:
		sprite.modulate = base_modulate
		sprite.play()                                  # release the attack


## Behaviour, implemented by each enemy type.
func think(_delta: float) -> void:
	pass


func on_animation_done() -> void:
	pass


func go(new_state: String, anim: String = "") -> void:
	state = new_state
	state_t = 0.0
	_struck = false
	if new_state in CALM_STATES:
		_attackers.erase(get_instance_id())
		_windup_left = -1.0
	if anim != "":
		sprite.play(anim)


## Is there a free attack slot (or do we already hold one)?
func can_attack() -> bool:
	for id: int in _attackers.keys():
		if not is_instance_id_valid(id):
			_attackers.erase(id)
	return _attackers.has(get_instance_id()) or _attackers.size() < MAX_ATTACKERS


## Freeze on the first frame of `anim`, flashing red — the tell. The length varies
## (±25%) and with `feint_chance` it is a bluff.
func windup(anim: String, seconds: float, can_feint: bool = true) -> void:
	_attackers[get_instance_id()] = true
	sprite.play(anim)
	sprite.pause()
	sprite.frame = 0
	_windup_total = seconds * randf_range(0.75, 1.25)
	_windup_left = _windup_total
	_feinting = can_feint and randf() < feint_chance


## The animation used for moving around ("walk", or "hop" for frogs that hop).
func move_anim() -> String:
	return "walk" if sprite.sprite_frames.has_animation(&"walk") else "hop"


func in_windup() -> bool:
	return _windup_left >= 0.0


func dx() -> float:
	return INF if player == null else player.global_position.x - global_position.x


func dist() -> float:
	return absf(dx())


func dy() -> float:
	return 0.0 if player == null else player.global_position.y - global_position.y


func can_see() -> bool:
	return player != null and player.state != Player.State.DEAD and dist() < aggro_range and absf(dy()) < 4.5


func face_player() -> void:
	if player != null:
		facing = 1 if dx() > 0.0 else -1


## Damage the player if they are within `reach` in front (or on both sides).
func strike(reach: float, height: float = 1.6, both_sides: bool = false) -> void:
	if _struck or player == null:
		return
	var d := dx()
	# a hunter rolling through the attack still counts as "dodged it" (perfect-dodge check)
	var dodging := player.state == Player.State.DODGE or player.state == Player.State.AIR_DASH
	if (both_sides or dodging or signf(d) == facing) and absf(d) <= reach * (1.4 if dodging else 1.0) \
			and absf(dy()) < height:
		_struck = true
		player.take_damage(damage, global_position.x, self)


## The player started a swing in front of us — maybe get out of the way.
func threatened(from_x: float) -> void:
	if not (state in ["idle", "walk"]) or _evade_cd > 0.0 or not is_on_floor() or randf() >= evade_chance:
		return
	_evade_cd = 1.4
	facing = 1 if from_x > global_position.x else -1
	go("evade", move_anim())
	velocity = Vector3(-facing * 7.5, 4.0, 0.0)
	HitFx.dust(get_parent(), global_position, 5)
	Audio.sfx("dodge", -6.0)


## Called by a parry: dazed and open to a counter-attack.
func stun(seconds: float) -> void:
	if state == "dead":
		return
	_stun_time = seconds
	go("stunned", "hurt")
	velocity = Vector3(-facing * 3.0, 0.0, 0.0)


## Returns true if the hit landed (false if the enemy dodged it).
func take_hit(dmg: int, from_x: float, heavy: bool, knock: float, lift: float = 0.0) -> bool:
	if state == "dead":
		return false
	if state == "evade" and state_t < 0.3:
		HitFx.popup(get_parent(), global_position + Vector3(0, 2.0, 0.4), "MISS", Color(0.9, 0.9, 1.0))
		return false
	var counter := state == "stunned"
	if counter:
		dmg += 1                                       # punishing a parried enemy hurts more
	hp -= dmg
	var away := 1.0 if global_position.x >= from_x else -1.0
	var k := 1.0 - knock_resist * (0.4 if heavy else 1.0)
	var airborne := state == "air" or not is_on_floor()
	velocity.x = away * knock * k
	if lift > 0.0 and juggle_resist < 1.0:
		velocity.y = lift * (1.0 - juggle_resist)
	elif airborne and juggle_resist < 1.0:
		velocity.y = maxf(velocity.y, 4.5)             # keep a juggled enemy in the air
	else:
		velocity.y = (6.5 if heavy else 2.5) * k
	sprite.modulate = Color(3.0, 3.0, 3.0)
	_flash_t = 0.09
	Audio.sfx(hurt_sound, -2.0)
	on_hit()
	if hp <= 0:
		die()
		return true
	if counter:
		return true
	var staggers := heavy or knock_resist < 0.5 or airborne or (lift > 0.0 and juggle_resist < 0.5)
	if staggers:
		face_player()
		if velocity.y > 3.5 and juggle_resist < 1.0:
			go("air", "hurt")
		else:
			go("hurt", "hurt")
	return true


func on_hit() -> void:
	pass


func die() -> void:
	if state == "dead":
		return
	go("dead", "death")
	sprite.modulate = base_modulate
	collision_layer = 0
	Audio.sfx("enemy_die", -2.0)
	if max_hp >= 5:                                    # big kills get the slow-motion kill cam
		GameState.hitstop(0.45, 0.25)
		get_tree().call_group("camera", "event", "kill")
	for i in orb_drop:
		var p := PICKUP.instantiate()
		p.set("kind", "orb")
		p.position = global_position + Vector3(randf_range(-0.8, 0.8), 0.5 + randf() * 0.5, 0.0)
		get_parent().add_child(p)
	died.emit(self)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(sprite, "scale", Vector3(1.0, 0.02, 1.0), 0.35)
	tw.tween_callback(queue_free)
