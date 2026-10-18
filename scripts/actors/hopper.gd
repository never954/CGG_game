class_name Hopper
extends Enemy
## Small swamp frog. Erratic: hops toward you — or suddenly away. Up close it lashes
## its tongue; from a few metres away it can POUNCE, flying at you body-first.

var _cooldown := 0.4
var _lashed := false
var _leapt := false
var _leap_t := 0.0


func think(delta: float) -> void:
	match state:
		"idle":
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			if sprite.animation != &"idle":
				sprite.play("idle")
			if not can_see() or state_t < _cooldown:
				return
			face_player()
			var d := dist()
			if d < 2.8 and absf(dy()) < 1.0 and can_attack():
				go("tongue")
				_lashed = false
				windup("tongue", 0.38)
				Audio.sfx("croak", -5.0)
			elif d > 3.2 and d < 6.5 and absf(dy()) < 2.0 and randf() < 0.45 and can_attack():
				go("pounce")
				_leapt = false
				windup("hop", 0.34)
				Audio.sfx("croak", -3.0, 0.2)
			else:
				go("hop", "hop")
				var dir := facing if randf() > 0.25 else -facing   # sometimes it hops away
				velocity = Vector3(dir * randf_range(3.0, 5.2), randf_range(6.5, 10.0), 0.0)
				Audio.sfx("croak", -12.0, 0.25)
		"hop":
			if is_on_floor() and state_t > 0.12:
				go("idle", "idle")
				_cooldown = randf_range(0.15, 0.7)
				HitFx.dust(get_parent(), global_position, 3)
		"pounce":
			if not in_windup() and not _leapt:
				_leapt = true
				_leap_t = 0.0
				face_player()
				velocity = Vector3(facing * clampf(dist() * 1.9, 5.0, 11.0), 8.5, 0.0)
				sprite.play("hop")
			if _leapt:
				_leap_t += delta
				strike(1.1, 1.3)
				if is_on_floor() and _leap_t > 0.2:
					HitFx.dust(get_parent(), global_position, 5)
					go("idle", "idle")
					_cooldown = 0.9
		"tongue":
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			if not in_windup() and sprite.frame >= 1 and sprite.frame <= 2:
				if not _lashed:
					_lashed = true
					Audio.sfx("tongue", -2.0)
				strike(3.0, 1.2)


func on_animation_done() -> void:
	if state == "tongue":
		go("idle", "idle")
		_cooldown = randf_range(0.5, 1.0)
