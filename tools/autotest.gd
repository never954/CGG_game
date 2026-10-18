extends Node
## Developer test harness (not part of the game). Loads a level, drives the hunter
## with simulated input, takes screenshots and logs FPS, then quits.
##   godot --path . res://tools/autotest.tscn -- --level=1 --out=/tmp/shots --at=10,40,98
## --at   x positions to teleport to (one screenshot each)
## --fight  also run a scripted fight next to the first enemy

var out_dir := "user://shots"
var level := 1
var spots: Array[float] = []
var fight := false
var walk := false
var climb_x := -1.0
var hop_x := -1.0
var push_x := -1.0


func _ready() -> void:
	if get_tree().current_scene == self:
		# the scene is about to be replaced: hand over to a copy living under the root
		var runner := Node.new()
		runner.name = "AutoTestRunner"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--at="):
			for s in a.substr(5).split(","):
				spots.append(float(s))
		elif a == "--fight":
			fight = true
		elif a.begins_with("--push="):
			push_x = float(a.substr(7))
		elif a.begins_with("--hop="):
			hop_x = float(a.substr(6))
		elif a.begins_with("--climb="):
			climb_x = float(a.substr(8))
		elif a == "--walk":
			walk = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	if "--title" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/ui/title.tscn")
		await _wait(4.0)
		await _shot("title")
		get_tree().quit()
		return
	GameState.new_game()
	GameState.level = level
	GameState.checkpoint = -1
	get_tree().change_scene_to_file.call_deferred("res://scenes/world/game.tscn")
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/L%d_%s.png" % [out_dir, level, tag])
	print("SHOT %s fps=%d" % [tag, Engine.get_frames_per_second()])


func _close_dialogue() -> void:
	for i in 200:
		var d := get_tree().get_first_node_in_group("dialogue") as DialogueBox
		if d == null or not d.is_open():
			return
		Input.action_press("interact")
		await _wait(0.06)
		Input.action_release("interact")
		await _wait(0.06)


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _run() -> void:
	await _wait(1.0)
	await _shot("start")
	await _wait(1.2)
	for i in 50:                                  # wait for the intro conversation to open
		var d := get_tree().get_first_node_in_group("dialogue") as DialogueBox
		if d and d.is_open():
			break
		await _wait(0.1)
	await _shot("intro_dialogue")
	await _close_dialogue()
	await _wait(0.5)
	for x in spots:
		var p := _player()
		p.respawn(Vector3(x, _ground_y(x), 0))
		await _wait(1.6)
		await _close_dialogue()
		await _shot("x%d" % int(x))
	if climb_x > 0.0:
		await _climb()
	if push_x > 0.0:
		var p := _player()
		p.respawn(Vector3(push_x, _ground_y(push_x), 0))
		await _wait(0.5)
		Input.action_press("move_right")
		await _wait(2.5)
		var crate := get_tree().get_first_node_in_group("crate") as Node3D
		print("PUSH crate x=%.2f player x=%.2f" % [crate.global_position.x, p.global_position.x])
		Input.action_press("jump")                 # onto the crate
		await _wait(0.4)
		Input.action_release("jump")
		for i in 60:
			if p.is_on_floor():
				break
			await get_tree().physics_frame
		print("PUSH on crate? y=%.2f x=%.2f" % [p.global_position.y, p.global_position.x])
		await _wait(0.1)
		Input.action_press("jump")                 # onto the ledge
		await _wait(0.45)
		Input.action_release("jump")
		await _wait(0.8)
		Input.action_release("move_right")
		print("PUSH player now x=%.2f y=%.2f" % [p.global_position.x, p.global_position.y])
		await _shot("push")
	if hop_x > 0.0:
		var p := _player()
		p.respawn(Vector3(hop_x, _ground_y(hop_x), 0))
		await _wait(0.6)
		var y0 := p.global_position.y
		Input.action_press("jump")
		await _wait(0.5)
		Input.action_release("jump")
		await _wait(1.0)
		print("HOP from y=%.2f landed y=%.2f on_floor=%s" % [y0, p.global_position.y, p.is_on_floor()])
		await _shot("hop")
		Input.action_press("move_down")
		Input.action_press("jump")
		await _wait(0.1)
		Input.action_release("jump")
		Input.action_release("move_down")
		await _wait(1.0)
		print("DROP now y=%.2f" % p.global_position.y)
	if walk:
		Input.action_press("move_right")
		for i in 8:
			Input.action_press("jump")
			await _wait(0.35)
			Input.action_release("jump")
			await _wait(0.6)
			await _close_dialogue()
		Input.action_release("move_right")
		await _shot("walk_end")
		print("walked to x=%.1f y=%.1f hp=%d" % [_player().global_position.x, _player().global_position.y, GameState.hp])
	if fight:
		var e := get_tree().get_first_node_in_group("enemy") as Node3D
		if e:
			var p := _player()
			p.respawn(e.global_position + Vector3(-3.0, 0.5, 0))
			await _wait(0.8)
			await _shot("fight_0")
			for i in 6:
				Input.action_press("attack")
				await get_tree().physics_frame
				Input.action_release("attack")
				await _wait(0.12)
				if i == 1:
					await _shot("fight_sweep")
			Input.action_press("heavy")
			await get_tree().physics_frame
			Input.action_release("heavy")
			await _wait(0.3)
			await _shot("fight_smash")
			await _wait(1.0)
			await _shot("fight_end")
	if "--duel" in OS.get_cmdline_user_args():
		await _duel()
	if "--combat" in OS.get_cmdline_user_args():
		await _combat()
	if "--killboss" in OS.get_cmdline_user_args():
		var p := _player()
		p.respawn(Vector3(80, _ground_y(80), 0))
		await _wait(1.5)
		await _close_dialogue()
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is ToadKing:
				e.take_hit(99, e.global_position.x - 1.0, true, 5.0)
		await _wait(4.0)
		await _close_dialogue()
		await _wait(6.0)
		await _shot("ending_a")
		await _wait(20.0)
		await _shot("ending_b")
	await _wait(0.3)
	print("DONE hp=%d orbs=%d" % [GameState.hp, GameState.orbs])
	get_tree().quit()


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.state != "dead" and (best == null or absf(e.global_position.x - _player().global_position.x) < absf(best.global_position.x - _player().global_position.x)):
			best = e
	return best


## Exercises the new moveset against real enemies and reports what happened.
func _combat() -> void:
	GameState.memories.assign([1, 2, 3])
	var p := _player()
	var e := _nearest_enemy()
	# 1. launcher -> chase -> air combo -> dive
	p.respawn(e.global_position + Vector3(-1.6, 0.3, 0))
	p.facing = 1
	await _wait(0.3)
	Input.action_press("move_up")
	await _tap("attack")
	Input.action_release("move_up")
	await _wait(0.16)
	print("COMBAT launch: enemy state=%s vy=%.1f" % [e.state, e.velocity.y])
	await _tap("jump", 12)
	await _wait(0.12)
	for i in 3:
		await _tap("attack")
		await _wait(0.17)
	print("COMBAT juggle: enemy state=%s y=%.1f player y=%.1f" % [e.state, e.global_position.y, p.global_position.y])
	await _shot("juggle")
	Input.action_press("move_down")
	await _tap("attack")
	Input.action_release("move_down")
	await _wait(0.12)
	await _shot("dive")
	await _wait(0.6)
	print("COMBAT after dive: enemy hp=%d state=%s" % [e.hp, e.state])
	# 2. parry: wait for a wind-up, block just before it releases
	var parried := false
	for attempt in 3:
		e = _nearest_enemy()
		if e == null:
			break
		p.respawn(e.global_position + Vector3(-1.8, 0.3, 0))
		p.facing = 1
		await _wait(0.2)
		var hp0 := GameState.hp
		var st0 := p.stamina
		for i in 400:
			await get_tree().physics_frame
			if not is_instance_valid(e):
				break
			if e.in_windup() and not e._feinting and e._windup_left < 0.08:
				await _tap("block", 1)
				Input.action_press("block")
				await _wait(0.3)
				Input.action_release("block")
				break
		if not is_instance_valid(e):
			continue
		print("COMBAT parry attempt %d: enemy state=%s hp %d->%d stamina %.0f->%.0f" % [attempt, e.state, hp0, GameState.hp, st0, p.stamina])
		if e.state == "stunned":
			parried = true
			await _shot("parry")
			break
	# 3. perfect dodge
	var perfect := false
	for attempt in 3:
		e = _nearest_enemy()
		if e == null:
			break
		p.respawn(e.global_position + Vector3(-1.8, 0.3, 0))
		p.facing = 1
		await _wait(0.4)
		GameState.spirit = 0.0
		var before := GameState.spirit
		var hp1 := GameState.hp
		for i in 400:
			await get_tree().physics_frame
			if not is_instance_valid(e):
				break
			if e.in_windup() and not e._feinting and e._windup_left < 0.06:
				await _tap("dodge")
				break
		var st := p.state
		await _wait(0.08)
		print("COMBAT dodge attempt %d: enemy=%s state_after_tap=%d perfect_used=%s time_scale=%.2f spirit %.0f -> %.0f hp %d->%d" % [attempt, e.name if is_instance_valid(e) else "?", st, p._perfect_used, Engine.time_scale, before, GameState.spirit, hp1, GameState.hp])
		if Engine.time_scale < 0.9:
			perfect = true
			await _shot("perfect")
			break
	# 4. Moon Breaker
	e = _nearest_enemy()
	if e:
		p.respawn(e.global_position + Vector3(-2.5, 0.3, 0))
	await _wait(0.4)
	GameState.spirit = GameState.MAX_SPIRIT
	await _tap("special")
	await _wait(0.35)
	await _shot("special_rise")
	await _wait(0.45)
	await _shot("special_impact")
	await _wait(1.0)
	print("COMBAT results: parried=%s perfect=%s enemies left=%d" % [parried, perfect, get_tree().get_nodes_in_group("enemy").filter(func(x): return x.state != "dead").size()])


## Deterministic checks against one cultist with no feints or dodges.
func _duel() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await get_tree().physics_frame
	var p := _player()
	p.respawn(Vector3(156.0, _ground_y(156.0), 0))
	p.facing = 1
	var results := {}
	for test in ["parry", "perfect", "launch"]:
		var c: Enemy = load("res://scenes/actors/cultist.tscn").instantiate()
		c.feint_chance = 0.0
		c.evade_chance = 0.0
		c.position = p.global_position + Vector3(2.0, 0.2, 0)
		p.get_parent().add_child(c)
		await _wait(0.3)
		p.respawn(Vector3(c.global_position.x - 1.9, c.global_position.y + 0.1, 0))
		p.facing = 1
		GameState.spirit = 0.0
		var hp0 := GameState.hp
		if test == "launch":
			await _wait(0.2)
			Input.action_press("move_up")
			await _tap("attack")
			Input.action_release("move_up")
			await _wait(0.15)
			results[test] = "enemy state=%s vy=%.1f" % [c.state, c.velocity.y]
			await _shot("duel_launch")
		else:
			for i in 600:
				await get_tree().physics_frame
				if c.in_windup() and c._windup_left < 0.07:
					if test == "parry":
						Input.action_press("block")
					else:
						await _tap("dodge")
					break
			await _wait(0.2 if test == "perfect" else 0.25)
			results[test] = "enemy state=%s time_scale=%.2f spirit=%.0f hp %d->%d" % [c.state, Engine.time_scale, GameState.spirit, hp0, GameState.hp]
			await _shot("duel_" + test)
			Input.action_release("block")
		await _wait(1.0)
		c.queue_free()
		await _wait(0.2)
	for k in results:
		print("DUEL %s: %s" % [k, results[k]])


## Wall-jump bot: hold towards a wall, jump off it, switch direction, repeat.
func _climb() -> void:
	var p := _player()
	p.respawn(Vector3(climb_x, _ground_y(climb_x), 0))
	await _wait(0.8)
	var dir := "move_right"
	var best := p.global_position.y
	Input.action_press(dir)
	Input.action_press("jump")
	for i in 260:
		await get_tree().physics_frame
		if i % 8 == 4:
			Input.action_release("jump")
		if p.is_on_floor() and i % 8 == 0:
			Input.action_press("jump")
		elif p.is_on_wall_only() and p.velocity.y < 1.0:
			Input.action_release(dir)
			dir = "move_left" if p.get_wall_normal().x < 0.0 else "move_right"
			Input.action_press("jump")
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_release("jump")
			await _wait(0.12)
			Input.action_press(dir)
		best = maxf(best, p.global_position.y)
		if i % 20 == 0:
			print("  t%d state=%d pos=(%.1f, %.1f) vel=(%.1f, %.1f) wall=%s floor=%s paused=%s" % [i, p.state, p.global_position.x, p.global_position.y, p.velocity.x, p.velocity.y, p.is_on_wall_only(), p.is_on_floor(), get_tree().paused])
		if i % 60 == 0:
			await _shot("climb_%d" % i)
	Input.action_release("move_left")
	Input.action_release("move_right")
	print("CLIMB best y=%.1f now x=%.1f y=%.1f" % [best, p.global_position.x, p.global_position.y])


func _ground_y(x: float) -> float:
	# top of the ground column standing on the bottom of the map (ignores roofs)
	var data := (get_tree().current_scene.get_node("Level") as LevelBuilder).data
	var c := int(x)
	var r := data.height - 1
	while r > 0 and data.is_solid(c, r - 1):
		r -= 1
	return data.row_bottom(r) + 1.05
