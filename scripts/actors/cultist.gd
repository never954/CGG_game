class_name Cultist
extends Enemy
## Frog-masked cultist with a curved blade — the most cunning enemy.
##   * keeps its distance and sways in and out of your reach instead of walking straight in
##   * slashes in combos of 1–3, each hit telegraphed (the follow-ups very briefly)
##   * throws daggers from range (knock them back with a swing, or parry them)
##   * often dodges your swings and bluffs its wind-ups

var _cooldown := 0.5
var _swung := false
var _thrown := false
var _combo_left := 0
var _sway := 1
var _sway_t := 0.0
var _throw_cd := 1.5


func think(delta: float) -> void:
	_throw_cd -= delta
	match state:
		"idle", "walk":
			if not can_see():
				velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
				sprite.play("idle")
				return
			face_player()
			var d := dist()
			_sway_t -= delta
			if _sway_t <= 0.0:
				_sway = 1 if randf() < 0.5 else -1
				_sway_t = randf_range(0.35, 1.0)
			if state_t > _cooldown and can_attack():
				if d < 2.2 and absf(dy()) < 1.5:
					go("attack")
					_combo_left = randi_range(1, 3)
					_swung = false
					windup("attack", 0.42)
					return
				if d > 4.5 and d < 9.5 and absf(dy()) < 2.5 and _throw_cd <= 0.0:
					go("throw")
					_thrown = false
					_throw_cd = randf_range(2.0, 3.5)
					windup("attack", 0.45, false)
					return
			# spacing: close in to about 3 m, then dance in and out of reach
			var want := 0.0
			if d > 3.6:
				want = facing * move_speed
			elif d < 1.6:
				want = -facing * move_speed * 0.8
			else:
				want = _sway * move_speed * 0.7
			velocity.x = move_toward(velocity.x, want, 12.0 * delta)
			sprite.play("walk" if absf(velocity.x) > 0.3 else "idle")
			state = "walk"
		"attack":
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			if not in_windup() and sprite.frame >= 1:
				if not _swung:
					_swung = true
					velocity.x = facing * 4.5
					Audio.sfx("swing", -2.0)
				strike(2.3, 1.7)
		"throw":
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			if not in_windup() and sprite.frame >= 1 and not _thrown:
				_thrown = true
				Audio.sfx("swing", -4.0, 0.2)
				var from := global_position + Vector3(facing * 0.6, 1.1, 0.0)
				var to := player.global_position + Vector3(0, 0.9, 0)
				Projectile.spawn(get_parent(), from, (to - from).normalized() * 11.0, damage, self, true)
		"retreat":
			velocity.x = -facing * 4.5
			if state_t > 0.3:
				go("idle", "idle")
				_cooldown = randf_range(0.4, 0.9)


func on_animation_done() -> void:
	match state:
		"attack":
			_combo_left -= 1
			if _combo_left > 0 and dist() < 3.2:
				face_player()
				go("attack")
				_swung = false
				windup("attack", 0.14, false)       # quick follow-up slash
			elif randf() < 0.5:
				go("retreat", "walk")
			else:
				go("idle", "idle")
				_cooldown = randf_range(0.4, 0.9)
		"throw":
			go("idle", "idle")
			_cooldown = 0.6
