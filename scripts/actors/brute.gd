class_name Brute
extends Enemy
## The buff frog brawler. Super armour: light hits don't stagger it (use the smash,
## the launcher's follow-up, a parry, or just get out of the way). Three attacks:
##   PUNCH   one or two heavy punches (the second comes fast)
##   CHARGE  from mid-range it lowers its head and rushes across the arena
##   SLAM    leaps at you and lands with a shockwave that hits both sides

@export var slam_interval: float = 5.5
@export var charge_interval: float = 6.0
@export var charge_speed: float = 9.0
@export var punch_windup: float = 0.5
@export var slam_chain: int = 1                ## slams in a row (the enraged boss does 2)
@export var reach: float = 1.0                 ## scales attack ranges (the boss is bigger)

var _slam_cd := 2.5
var _charge_cd := 3.0
var _swung := false
var _airborne := false
var _slammed := false
var _slams_left := 0
var _combo_left := 0
var _charge_t := 0.0


func think(delta: float) -> void:
	_slam_cd -= delta
	_charge_cd -= delta
	match state:
		"idle", "walk":
			if not can_see():
				velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
				sprite.play("idle")
				return
			face_player()
			var d := dist()
			if can_attack():
				if d < 2.3 * reach:
					velocity.x = 0.0
					go("punch")
					_combo_left = randi_range(1, 2)
					_swung = false
					windup("punch", punch_windup)
					return
				if _slam_cd <= 0.0 and d > 3.5 * reach and d < 8.0 * reach and is_on_floor() and randf() < 0.6:
					_start_slam(slam_chain)
					return
				if _charge_cd <= 0.0 and d > 4.0 * reach and d < 12.0 * reach and absf(dy()) < 1.5:
					go("charge")
					_charge_t = 0.0
					_charge_cd = charge_interval * randf_range(0.8, 1.2)
					windup("walk", 0.55)
					Audio.sfx("croak", 0.0, 0.1)
					return
			velocity.x = move_toward(velocity.x, facing * move_speed, 12.0 * delta)
			sprite.play("walk")
			state = "walk"
		"punch":
			velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
			if not in_windup() and sprite.frame == 1:
				if not _swung:
					_swung = true
					velocity.x = facing * 3.0
					Audio.sfx("heavy_swing", -3.0)
				strike(2.7 * reach, 2.2 * reach)
		"charge":
			if in_windup():
				return
			_charge_t += delta
			sprite.play("walk", 2.4)
			velocity.x = facing * charge_speed
			strike(1.6 * reach, 2.0 * reach)
			if _charge_t > 1.3 or is_on_wall() or (_struck and _charge_t > 0.25):
				if is_on_wall():
					get_tree().call_group("camera", "add_trauma", 0.3)
					HitFx.dust(get_parent(), global_position + Vector3(facing, 0.5, 0), 10)
				velocity.x = 0.0
				go("idle", "idle")
		"slam":
			if not in_windup() and not _airborne:
				_airborne = true
				face_player()
				velocity = Vector3(facing * clampf(dist() * 1.3, 3.0, 9.0), 11.0, 0.0)
				sprite.pause()
				sprite.frame = 1
			elif _airborne and not _slammed and is_on_floor() and state_t > 0.2:
				_slammed = true
				state_t = 0.0
				velocity.x = 0.0
				sprite.frame = 2
				strike(3.6 * reach, 2.0 * reach, true)
				Audio.sfx("slam")
				HitFx.dust(get_parent(), global_position, 22)
				HitFx.ring(get_parent(), global_position + Vector3(0, 0.1, 0), 3.6 * reach, Color(1.3, 1.1, 0.9))
				get_tree().call_group("camera", "add_trauma", 0.55)
			elif _slammed and state_t > 0.6:
				_slams_left -= 1
				if _slams_left > 0 and can_see():
					_start_slam(_slams_left, 0.25)
				else:
					go("idle", "idle")


func _start_slam(count: int, tell: float = 0.45) -> void:
	go("slam")
	_airborne = false
	_slammed = false
	_slams_left = count
	_slam_cd = slam_interval
	windup("slam", tell, false)


func on_animation_done() -> void:
	if state == "punch":
		_combo_left -= 1
		if _combo_left > 0 and dist() < 3.0 * reach:
			face_player()
			go("punch")
			_swung = false
			windup("punch", punch_windup * 0.35, false)
		else:
			go("idle", "idle")
