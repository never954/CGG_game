class_name Player
extends CharacterBody3D
## The hunter. A state machine (see State) driven by _physics_process at 60 Hz.
##
## Platforming: acceleration curves, coyote time, jump buffering, variable jump height,
## heavier falls, wall-slide/wall-jump, drop-through platforms (Down + Jump), crate pushing.
##
## Combat in the spirit of BREKEKEKEX — direction matters, defence is movement, hits hurt:
##   J            horizontal SWEEP (wide, hits crowds, chains into a second sweep)
##   W + J        LAUNCHER uppercut: throws the enemy into the air — jump after it
##   J in the air air combo (you float while swinging, juggled enemies stay up)
##   S + J / L in the air   DIVE: plunge down, bounce the enemy off the ground
##   L            vertical SMASH (slow, heavy, staggers anything; costs stamina)
##   K            block — tap it just before a hit to PARRY (enemy stunned)
##   Shift        dodge roll — dodge just as a hit lands for a PERFECT DODGE (slow motion)
##   U            MOON BREAKER, the special (needs a full spirit meter)
## Powers come back with memories: Staff Vault (double jump), Air Dash, Spirit Wave.

signal died
signal hit_landed(heavy: bool, at: Vector3)
signal damaged(amount: int)
signal landed(impact: float)

enum State { NORMAL, ATTACK, HEAVY, LAUNCH, AIR_ATTACK, DIVE, AIR_DASH, DODGE, BLOCK, HURT, DEAD, TALK, SPECIAL }

@export_group("Run & jump")
@export var run_speed: float = 6.6
@export var ground_accel: float = 60.0
@export var ground_decel: float = 70.0
@export var air_accel: float = 38.0
@export var jump_velocity: float = 14.5
@export var gravity: float = 30.0
@export var fall_multiplier: float = 1.5
@export var max_fall_speed: float = 24.0
@export var jump_cut: float = 0.45
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.13
@export var vault_velocity: float = 12.5
@export_group("Wall")
@export var wall_slide_speed: float = 3.2
@export var wall_jump_push: float = 7.6
@export var wall_jump_lock: float = 0.17
@export_group("Combat")
@export var dodge_speed: float = 11.5
@export var dodge_time: float = 0.34
@export var dodge_cost: float = 22.0
@export var heavy_cost: float = 28.0
@export var block_cost: float = 18.0
@export var stamina_regen: float = 34.0
@export var parry_window: float = 0.26         ## seconds after pressing block in which a hit is parried
@export var perfect_window: float = 0.22       ## a hit this early in a dodge is a perfect dodge
@export var air_dash_speed: float = 15.0
@export var air_dash_time: float = 0.2
@export var dive_speed: float = 26.0
@export var special_radius: float = 7.5

var state: State = State.NORMAL
var facing: int = 1
var stamina: float = GameState.MAX_STAMINA
var interact_target: Node = null

var _state_t := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _wall_lock := 0.0
var _drop_timer := 0.0
var _invuln := 0.0
var _regen_delay := 0.0
var _combo := 0
var _queued := ""                 ## next ground attack chained during the current one
var _heavy_swung := false
var _heavy_slammed := false
var _hit_ids: Array[int] = []
var _was_on_floor := true
var _step_t := 0.0
var _safe_pos := Vector3.ZERO
var _safe_t := 0.0
var _parry_t := 0.0
var _perfect_used := false
var _air_dashes := 1
var _vaults := 1
var _air_combo := 0
var _anim_lock := 0.0             ## keeps a one-shot animation (vault) from being replaced
var _special_falling := false

@onready var sprite: SheetSprite = $Sprite
@onready var hitbox: Area3D = $Hitbox
@onready var hitbox_shape: CollisionShape3D = $Hitbox/Shape


func _ready() -> void:
	add_to_group("player")
	sprite.animation_finished.connect(_on_animation_finished)
	_safe_pos = global_position


func _physics_process(delta: float) -> void:
	_state_t += delta
	_invuln = maxf(0.0, _invuln - delta)
	_regen_delay = maxf(0.0, _regen_delay - delta)
	_parry_t = parry_window if Input.is_action_just_pressed("block") else maxf(0.0, _parry_t - delta)
	_anim_lock = maxf(0.0, _anim_lock - delta)
	if _regen_delay <= 0.0 and state != State.BLOCK:
		stamina = minf(GameState.MAX_STAMINA, stamina + stamina_regen * delta)
	var input_x := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()
	if on_floor:
		_air_dashes = 1
		_vaults = 1
		_air_combo = 0
	_coyote = coyote_time if on_floor else maxf(0.0, _coyote - delta)
	_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else maxf(0.0, _buffer - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)

	match state:
		State.NORMAL:
			_normal(delta, input_x, on_floor)
		State.ATTACK, State.HEAVY, State.LAUNCH:
			_attacking(delta, on_floor)
		State.AIR_ATTACK:
			_air_attacking(delta, input_x, on_floor)
		State.DIVE:
			_diving(delta, on_floor)
		State.AIR_DASH:
			_air_dashing()
		State.SPECIAL:
			_special(delta, on_floor)
		State.DODGE:
			velocity.y -= gravity * delta
			if _state_t > dodge_time:
				_set_state(State.NORMAL)
		State.BLOCK:
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			velocity.y -= gravity * delta
			if not Input.is_action_pressed("block") or not on_floor:
				_set_state(State.NORMAL)
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.y -= gravity * delta
			if _state_t > 0.32:
				_set_state(State.NORMAL)
		State.DEAD, State.TALK:
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			velocity.y -= gravity * delta

	velocity.y = maxf(velocity.y, -(dive_speed + 10.0 if state in [State.DIVE, State.SPECIAL] else max_fall_speed))
	# one-way platforms: solid only while falling onto them (and not dropping through)
	set_collision_mask_value(3, velocity.y <= 0.5 and _drop_timer <= 0.0)
	_drop_timer = maxf(0.0, _drop_timer - delta)

	var fall_speed := velocity.y
	move_and_slide()
	global_position.z = 0.0
	_push_crates(input_x)

	if is_on_floor() and not _was_on_floor:
		_on_land(-fall_speed)
	_was_on_floor = is_on_floor()
	_track_safe_ground(delta)
	sprite.flip_h = facing < 0
	sprite.visible = _invuln <= 0.0 or state in [State.DEAD, State.DODGE, State.AIR_DASH, State.SPECIAL] \
			or fmod(_invuln, 0.14) > 0.07


# ------------------------------------------------------------------ movement
func _normal(delta: float, input_x: float, on_floor: bool) -> void:
	if _wall_lock <= 0.0:
		var target := input_x * run_speed
		var rate := (ground_accel if absf(target) > 0.1 else ground_decel) if on_floor else air_accel
		velocity.x = move_toward(velocity.x, target, rate * delta)
	velocity.y -= gravity * (fall_multiplier if velocity.y < 0.0 else 1.0) * delta

	var wall_normal := get_wall_normal() if is_on_wall_only() else Vector3.ZERO
	var sliding := wall_normal != Vector3.ZERO and velocity.y < 0.0 and absf(input_x) > 0.1 \
			and signf(input_x) == -signf(wall_normal.x)
	if sliding:
		velocity.y = maxf(velocity.y, -wall_slide_speed)

	if on_floor and Input.is_action_pressed("move_down") and Input.is_action_just_pressed("jump") and _on_platform():
		_drop_timer = 0.3
		_buffer = 0.0
		position.y -= 0.06
	elif _buffer > 0.0:
		if _coyote > 0.0:
			_jump(jump_velocity)
		elif wall_normal != Vector3.ZERO:
			_jump(jump_velocity * 0.92)
			velocity.x = wall_normal.x * wall_jump_push
			_wall_lock = wall_jump_lock
			facing = 1 if wall_normal.x > 0.0 else -1
		elif _vaults > 0 and GameState.has_power("vault"):
			_vault()
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	if absf(input_x) > 0.1 and _wall_lock <= 0.0:
		facing = 1 if input_x > 0.0 else -1

	# actions
	if Input.is_action_just_pressed("interact") and interact_target != null:
		interact_target.call("interact", self)
	elif Input.is_action_just_pressed("special") and GameState.spirit >= GameState.MAX_SPIRIT:
		_start_special()
	elif Input.is_action_just_pressed("dodge"):
		if on_floor and stamina >= dodge_cost:
			_dodge(input_x)
		elif not on_floor and _air_dashes > 0 and GameState.has_power("air_dash"):
			_air_dash(input_x)
	elif Input.is_action_just_pressed("heavy"):
		if on_floor and stamina >= heavy_cost:
			_start_heavy()
		elif not on_floor:
			_start_dive()
	elif Input.is_action_just_pressed("attack"):
		if on_floor:
			if Input.is_action_pressed("move_up"):
				_start_launch()
			else:
				_start_attack()
		elif Input.is_action_pressed("move_down"):
			_start_dive()
		else:
			_start_air_attack()
	elif Input.is_action_pressed("block") and on_floor:
		_set_state(State.BLOCK)
		sprite.play("block")

	# animation
	if state == State.NORMAL and _anim_lock <= 0.0:
		if on_floor:
			var speed_ratio := absf(velocity.x) / run_speed
			if speed_ratio > 0.08:
				sprite.play("run", clampf(speed_ratio, 0.6, 1.2))
				_step_t -= delta
				if _step_t <= 0.0:
					_step_t = 0.27
					Audio.sfx("step", -14.0, 0.15)
			else:
				sprite.play("idle")
		else:
			sprite.play("jump" if velocity.y > 0.0 else "fall")


func _jump(v: float) -> void:
	velocity.y = v
	_buffer = 0.0
	_coyote = 0.0
	Audio.sfx("jump", -6.0)
	HitFx.dust(get_parent(), global_position, 6)


## Staff Vault (memory 1): plant the staff in thin air and spring off it.
func _vault() -> void:
	_vaults -= 1
	velocity.y = vault_velocity
	_buffer = 0.0
	sprite.play("vault")
	_anim_lock = 0.22
	Audio.sfx("jump", -2.0, 0.0)
	HitFx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), 1.2, Color(1.4, 1.2, 0.7))


func _dodge(input_x: float) -> void:
	stamina -= dodge_cost
	_regen_delay = 0.5
	if absf(input_x) > 0.1:
		facing = 1 if input_x > 0.0 else -1
	velocity.x = facing * dodge_speed
	_invuln = maxf(_invuln, dodge_time)
	_perfect_used = false
	_set_state(State.DODGE)
	sprite.play("dodge")
	Audio.sfx("dodge", -3.0)
	HitFx.dust(get_parent(), global_position, 4)


## Air Dash (memory 2): a burst through the air that also cuts what it passes.
func _air_dash(input_x: float) -> void:
	_air_dashes -= 1
	if absf(input_x) > 0.1:
		facing = 1 if input_x > 0.0 else -1
	velocity = Vector3(facing * air_dash_speed, 0.0, 0.0)
	_invuln = maxf(_invuln, air_dash_time + 0.05)
	_perfect_used = false
	_hit_ids.clear()
	_set_state(State.AIR_DASH)
	sprite.play("airdash")
	Audio.sfx("dodge", 0.0)
	get_tree().call_group("camera", "event", "dash")
	HitFx.dust(get_parent(), global_position + Vector3(0, 0.9, 0), 6)


func _air_dashing() -> void:
	velocity.y = 0.0
	_set_hitbox(Vector3(1.8, 1.8, 2.0), Vector3(0.0, 0.9, 0.0))
	_apply_hits(1, 4.0, false, 3.0)
	if _state_t > air_dash_time:
		velocity.x *= 0.45
		_set_state(State.NORMAL)


func _on_land(impact: float) -> void:
	var k := clampf(impact / max_fall_speed, 0.0, 1.0)
	if k > 0.25:
		Audio.sfx("land", -8.0 + 6.0 * k)
		HitFx.dust(get_parent(), global_position, int(4 + 10 * k))
	landed.emit(k)


func _on_platform() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as CollisionObject3D
		if c.get_normal().y > 0.7 and body != null and body.get_collision_layer_value(3):
			return true
	return false


func _push_crates(input_x: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb != null and absf(c.get_normal().x) > 0.6 and signf(input_x) == -signf(c.get_normal().x):
			rb.apply_central_impulse(Vector3(-c.get_normal().x * 0.55, 0.0, 0.0))


func _track_safe_ground(delta: float) -> void:
	if is_on_floor() and state != State.HURT:
		_safe_t += delta
		if _safe_t > 0.35:
			_safe_pos = global_position
	else:
		_safe_t = 0.0


# ------------------------------------------------------------------ attacks
## Tell enemies in front that a swing is coming — some of them will try to dodge it.
func _threaten() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: float = e.global_position.x - global_position.x
		if signf(d) == facing and absf(d) < 3.4 and absf(e.global_position.y - global_position.y) < 2.0:
			e.call("threatened", global_position.x)


func _start_attack() -> void:
	_combo = (_combo + 1) % 2
	_set_state(State.ATTACK)
	_hit_ids.clear()
	_queued = ""
	sprite.play("attack1" if _combo == 1 else "attack2")
	velocity.x = facing * 2.6
	_set_hitbox(Vector3(2.4, 1.9, 2.0), Vector3(facing * 1.2, 0.95, 0.0))
	Audio.sfx("swing", -2.0)
	_threaten()


## Launcher: vertical uppercut that throws the target into the air for a juggle.
func _start_launch() -> void:
	_set_state(State.LAUNCH)
	_hit_ids.clear()
	_queued = ""
	sprite.play("launch")
	velocity.x = facing * 1.5
	_set_hitbox(Vector3(2.0, 2.8, 2.0), Vector3(facing * 1.1, 1.4, 0.0))
	Audio.sfx("swing", 0.0, 0.0)
	_threaten()


func _start_heavy() -> void:
	stamina -= heavy_cost
	_regen_delay = 0.7
	_set_state(State.HEAVY)
	_hit_ids.clear()
	_heavy_swung = false
	_heavy_slammed = false
	sprite.play("heavy")
	velocity.x = 0.0
	_set_hitbox(Vector3(2.8, 2.6, 2.0), Vector3(facing * 1.35, 1.1, 0.0))
	_threaten()


func _attacking(delta: float, on_floor: bool) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
	velocity.y -= gravity * delta
	var f := sprite.frame
	match state:
		State.ATTACK:
			if f >= 1 and f <= 2:
				_apply_hits(1, 5.5, false)
			if f >= 2 and Input.is_action_just_pressed("attack"):
				_queued = "launch" if Input.is_action_pressed("move_up") else "attack"
			if f >= 2 and Input.is_action_just_pressed("dodge") and stamina >= dodge_cost:
				_dodge(Input.get_axis("move_left", "move_right"))
		State.LAUNCH:
			if f >= 1 and f <= 2:
				_apply_hits(1, 1.5, false, 13.0)
			if f >= 2 and Input.is_action_just_pressed("jump"):
				_set_state(State.NORMAL)           # chase the enemy into the air
				_jump(jump_velocity)
			elif f >= 2 and Input.is_action_just_pressed("dodge") and stamina >= dodge_cost:
				_dodge(Input.get_axis("move_left", "move_right"))
		State.HEAVY:
			if f == 2 and not _heavy_swung:
				_heavy_swung = true
				Audio.sfx("heavy_swing", 0.0)
			if f >= 2 and f <= 3:
				_apply_hits(3, 10.0, true)
			if f == 3 and on_floor and not _heavy_slammed:
				_heavy_slammed = true                 # the staff hits the ground
				HitFx.dust(get_parent(), global_position + Vector3(facing * 1.6, 0, 0), 14)
				get_tree().call_group("camera", "add_trauma", 0.25)
				if GameState.has_power("spirit_wave"):
					Projectile.spawn(get_parent(), global_position + Vector3(facing * 1.6, 0.5, 0),
							Vector3(facing * 14.0, 0, 0), 2, self, false)


func _start_air_attack() -> void:
	_air_combo += 1
	_set_state(State.AIR_ATTACK)
	sprite.play("air")
	sprite.frame = 0
	_hit_ids.clear()
	velocity.y = maxf(velocity.y, 1.5)                # a little hang at the start of each swing
	Audio.sfx("swing", -2.0, 0.15)


func _air_attacking(delta: float, input_x: float, on_floor: bool) -> void:
	velocity.x = move_toward(velocity.x, input_x * run_speed * 0.8, air_accel * delta)
	velocity.y -= gravity * 0.55 * delta              # floaty while swinging: anime air combos
	_set_hitbox(Vector3(2.6, 2.6, 2.0), Vector3(facing * 0.4, 0.9, 0.0))
	_apply_hits(1, 3.0, false, 6.5)                   # the lift keeps a juggled enemy up
	if Input.is_action_just_pressed("attack") and _state_t > 0.14:
		if Input.is_action_pressed("move_down"):
			_start_dive()
		elif _air_combo < 4:
			_start_air_attack()
	elif Input.is_action_just_pressed("heavy"):
		_start_dive()
	elif Input.is_action_just_pressed("dodge") and _air_dashes > 0 and GameState.has_power("air_dash"):
		_air_dash(input_x)
	elif on_floor or _state_t > 0.38:
		_set_state(State.NORMAL)


## Dive: a short pop, then a plunge. Hit enemies bounce off the ground (back into a juggle).
func _start_dive() -> void:
	_set_state(State.DIVE)
	sprite.play("dive")
	_hit_ids.clear()
	velocity = Vector3(facing * 3.5, 4.0, 0.0)
	Audio.sfx("heavy_swing", -2.0)
	get_tree().call_group("camera", "event", "dive")


func _diving(delta: float, on_floor: bool) -> void:
	if _state_t < 0.12:
		velocity.y -= gravity * delta
	else:
		velocity.y = -dive_speed
	_set_hitbox(Vector3(1.8, 2.2, 2.0), Vector3(facing * 0.4, 0.3, 0.0))
	_apply_hits(2, 3.0, true, 7.0)
	if on_floor and _state_t > 0.1:
		_ground_shock(2.4, 1, 5.0)
		HitFx.dust(get_parent(), global_position, 16)
		HitFx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), 2.4, Color(1.2, 1.1, 0.9))
		Audio.sfx("slam", -4.0)
		get_tree().call_group("camera", "add_trauma", 0.35)
		_set_state(State.NORMAL)


## Damage every enemy standing within `radius` of the hunter (dive and special landings).
func _ground_shock(radius: float, dmg: int, lift: float) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: Vector3 = e.global_position - global_position
		if absf(d.x) < radius and absf(d.y) < 2.0 and not _hit_ids.has(e.get_instance_id()):
			_hit_ids.append(e.get_instance_id())
			e.call("take_hit", dmg, global_position.x, true, 6.0, lift)
			_on_hit(dmg >= 3, e.global_position)
	for c in get_tree().get_nodes_in_group("crate"):
		if (c.global_position - global_position).length() < radius:
			c.call("smash")


## MOON BREAKER: leap into the air spinning the staff, then crash down. Everything nearby
## is launched; costs the whole spirit meter.
func _start_special() -> void:
	GameState.spirit = 0.0
	_set_state(State.SPECIAL)
	_special_falling = false
	_hit_ids.clear()
	sprite.play("special")
	velocity = Vector3(0.0, 13.0, 0.0)
	_invuln = 2.5
	Audio.sfx("memory", 2.0, 0.0)
	Audio.sfx("heavy_swing", 0.0, 0.0)
	get_tree().call_group("camera", "event", "special")
	GameState.hitstop(0.4, 0.35)
	HitFx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), 3.0, Color(1.8, 1.5, 0.6))


func _special(delta: float, on_floor: bool) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	if not _special_falling:
		velocity.y -= gravity * 0.6 * delta
		if _state_t > 0.6:
			_special_falling = true
			sprite.play("dive")
			velocity = Vector3(facing * 2.0, -34.0, 0.0)
	elif on_floor:
		_ground_shock(special_radius, 5, 11.0)
		HitFx.dust(get_parent(), global_position, 40)
		HitFx.ring(get_parent(), global_position + Vector3(0, 0.15, 0), special_radius, Color(2.0, 1.6, 0.6))
		HitFx.sparks(get_parent(), global_position + Vector3(0, 0.6, 0.4), true)
		Audio.sfx("slam", 4.0, 0.0)
		Audio.sfx("heavy_hit", 2.0, 0.0)
		get_tree().call_group("impact", "play", true)
		get_tree().call_group("camera", "event", "slam")
		GameState.hitstop(0.25, 0.05)
		_invuln = 0.4
		_set_state(State.NORMAL)


func _apply_hits(dmg: int, knock: float, heavy: bool, lift: float = 0.0) -> void:
	for body in hitbox.get_overlapping_bodies():
		var id := body.get_instance_id()
		if _hit_ids.has(id):
			continue
		if body.is_in_group("enemy") and body.has_method("take_hit"):
			_hit_ids.append(id)
			var landed_hit: bool = body.call("take_hit", dmg, global_position.x, heavy, knock, lift)
			if landed_hit:
				_on_hit(heavy, body.global_position)
				if lift > 8.0:
					get_tree().call_group("camera", "event", "launch")
		elif body is RigidBody3D:
			_hit_ids.append(id)
			(body as RigidBody3D).apply_central_impulse(Vector3(facing * knock * 0.9, knock * 0.4, 0.0))
			if heavy and body.has_method("smash"):
				body.call("smash")
			_on_hit(heavy, body.global_position)


func _on_hit(heavy: bool, at: Vector3) -> void:
	GameState.hitstop(0.12 if heavy else 0.055)
	GameState.add_spirit(10.0 if heavy else 6.0)
	Audio.sfx("heavy_hit" if heavy else "hit", 0.0 if heavy else -3.0)
	HitFx.sparks(get_parent(), at + Vector3(0, 0.9, 0.3), heavy)
	get_tree().call_group("hud", "add_hit")
	if heavy:
		get_tree().call_group("impact", "play", false)
	hit_landed.emit(heavy, at)
	if state == State.AIR_ATTACK:
		velocity.y = maxf(velocity.y, 4.0)            # stay up with the juggled enemy


## True while the staff is swinging (used to knock thrown daggers back).
func is_striking() -> bool:
	return state in [State.ATTACK, State.HEAVY, State.LAUNCH, State.AIR_ATTACK, State.AIR_DASH, State.DIVE]


func _set_hitbox(size: Vector3, offset: Vector3) -> void:
	(hitbox_shape.shape as BoxShape3D).size = size
	hitbox.position = offset


# ------------------------------------------------------------------ taking hits
## Returns what happened: "hit", "blocked", "parried", "dodged" or "immune".
func take_damage(amount: int, from_x: float, source: Node = null) -> String:
	if state == State.DEAD or state == State.SPECIAL:
		return "immune"
	if state == State.DODGE or state == State.AIR_DASH:
		if _state_t < perfect_window and not _perfect_used:
			_perfect_dodge()
		return "dodged"
	if _invuln > 0.0:
		return "immune"
	var away := 1.0 if global_position.x >= from_x else -1.0
	var frontal := signf(from_x - global_position.x) == facing
	if state == State.BLOCK and frontal:
		if _parry_t > 0.0:
			_parry(source)
			return "parried"
		stamina -= block_cost
		_regen_delay = 0.6
		velocity.x = away * 3.5
		Audio.sfx("block")
		HitFx.sparks(get_parent(), global_position + Vector3(facing * 0.6, 1.1, 0.3), false)
		get_tree().call_group("camera", "add_trauma", 0.15)
		if stamina > 0.0:
			return "blocked"
		stamina = 0.0                                   # guard broken: the hit goes through
	GameState.damage(amount)
	damaged.emit(amount)
	Audio.sfx("hurt")
	_invuln = 1.1
	velocity = Vector3(away * 7.0, 6.0, 0.0)
	get_tree().call_group("hud", "break_combo")
	if GameState.hp <= 0:
		_die()
	else:
		_set_state(State.HURT)
		sprite.play("hurt")
	return "hit"


## Dodged at the last instant: time slows ("frog time"), stamina refunded, spirit gained.
func _perfect_dodge() -> void:
	_perfect_used = true
	_invuln = maxf(_invuln, 0.5)
	stamina = minf(GameState.MAX_STAMINA, stamina + dodge_cost)
	GameState.add_spirit(20.0)
	GameState.hitstop(0.7, 0.3)
	Audio.sfx("dodge", 2.0, 0.0)
	Audio.sfx("orb", 0.0, 0.0)
	HitFx.popup(get_parent(), global_position + Vector3(0, 2.4, 0.4), "PERFECT", Color(0.5, 1.6, 2.0))
	get_tree().call_group("camera", "event", "perfect")
	var tw := create_tween()
	sprite.modulate = Color(0.6, 1.8, 2.2)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.6)


## Blocked at the last instant: the attacker is stunned and open for a counter.
func _parry(source: Node) -> void:
	_parry_t = 0.0
	sprite.play("parry")
	if source != null and is_instance_valid(source) and source.has_method("stun"):
		source.call("stun", 1.6)
	GameState.add_spirit(25.0)
	GameState.hitstop(0.2, 0.05)
	Audio.sfx("block", 4.0, 0.0)
	Audio.sfx("heavy_hit", -2.0, 0.0)
	HitFx.sparks(get_parent(), global_position + Vector3(facing * 0.7, 1.2, 0.4), true)
	HitFx.popup(get_parent(), global_position + Vector3(0, 2.4, 0.4), "PARRY", Color(2.0, 1.6, 0.6))
	get_tree().call_group("impact", "play", false)
	get_tree().call_group("camera", "event", "parry")


func drown() -> void:
	if state == State.DEAD:
		return
	Audio.sfx("land")
	GameState.damage(1)
	damaged.emit(1)
	if GameState.hp <= 0:
		_die()
		return
	respawn(_safe_pos)
	_invuln = 1.2


func _die() -> void:
	_set_state(State.DEAD)
	sprite.play("death")
	Audio.sfx("death")
	await get_tree().create_timer(1.3).timeout
	died.emit()


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_set_state(State.NORMAL)
	get_tree().call_group("camera", "snap")


func set_talking(on: bool) -> void:
	if state == State.DEAD:
		return
	_set_state(State.TALK if on else State.NORMAL)
	if on:
		sprite.play("idle")


func _set_state(s: State) -> void:
	state = s
	_state_t = 0.0


func _on_animation_finished() -> void:
	match state:
		State.ATTACK, State.LAUNCH:
			match _queued:
				"attack":
					_start_attack()
				"launch":
					_start_launch()
				_:
					_set_state(State.NORMAL)
		State.HEAVY, State.DODGE:
			_set_state(State.NORMAL)
		State.BLOCK:
			sprite.play("block")                       # back to guarding after a parry
