class_name CameraRig
extends Node3D
## The dynamic camera, the heart of the BREKEKEKEX feel. It does not glue itself to
## the hunter — it is a weighted dolly that is pulled towards where it wants to be:
##   * follow with delay   critically-damped spring, so it lags and settles
##   * look-ahead          frames more of the space you are running into
##   * jump / fall         tilts down to show the ground below you while airborne
##   * combat              when enemies are close it dollies in and swings round over
##                         your shoulder (±14 degrees) so the fight feels close-up
##   * impacts             heavy hits punch the field of view; screen shake from trauma
##   * depth of field      tilt-shift blur outside the play lane (the diorama look)
##   * arena framing       in a fight it frames BOTH the hunter and the nearest enemy
##                         (anime arena-fighter style) and pulls back when they separate
##   * event cameras       short scripted moves layered on top: a low angle that looks up
##                         at a launcher, a high angle for dives, a whip for air dashes,
##                         a slow push-in for parries / perfect dodges / kills, a sweeping
##                         crane shot for the Moon Breaker special and the boss's roar
## It also carries the floating fireflies/motes that drift around the hunter.

@export var distance: float = 13.0
@export var combat_distance: float = 9.0
@export var height: float = 2.0
@export var pitch_deg: float = -11.0
@export var air_pitch_deg: float = -22.0
@export var combat_yaw_deg: float = 22.0
@export var follow_speed: float = 4.5
@export var look_ahead: float = 2.4
@export var fov: float = 38.0

var target: Node3D
var level_bounds := AABB()
var motes_color := Color(1.5, 1.2, 0.7)

var camera: Camera3D
var _focus := Vector3.ZERO
var _vel := Vector3.ZERO
var _ahead := 0.0
var _combat := 0.0
var _combat_side := 1.0
var _pitch := 0.0
var _trauma := 0.0
var _fov_kick := 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _attrs: CameraAttributesPractical
var _motes: CPUParticles3D
var _foe: Node3D                 ## enemy currently framed with the hunter
var _last_us := 0
# event camera: offsets blended in over a short, real-time envelope
var _ev_t := 0.0
var _ev_dur := 0.0
var _ev := {"yaw": 0.0, "pitch": 0.0, "dist": 0.0, "fov": 0.0}


func _ready() -> void:
	add_to_group("camera")
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.2
	camera.far = 400.0
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_near_enabled = true
	_attrs.dof_blur_amount = 0.07
	camera.attributes = _attrs
	add_child(camera)
	camera.make_current()
	_noise.frequency = 0.9
	_pitch = deg_to_rad(pitch_deg)
	_make_motes()


func set_target(t: Node3D) -> void:
	target = t
	if target.has_signal("hit_landed"):
		target.connect("hit_landed", _on_hit_landed)
	snap()


## Jump straight to the target (level start, respawn).
func snap() -> void:
	if target == null:
		return
	_focus = _goal_focus()
	_vel = Vector3.ZERO
	_place(0.0)


## Named camera moves, triggered by gameplay through the "camera" group.
func event(kind: String) -> void:
	var side := -float(target.get("facing")) if target != null and target.get("facing") != null else 1.0
	match kind:                     # duration, yaw deg, pitch deg (+ = look up), distance, fov
		"launch":
			_set_event(0.75, 6.0 * side, 10.0, -2.5, 4.0)
		"dive":
			_set_event(0.6, 0.0, -16.0, -1.0, 4.0)
		"dash":
			_set_event(0.35, 0.0, 0.0, 0.5, 10.0)
		"perfect":
			_set_event(0.9, 16.0 * side, 4.0, -3.0, -6.0)
		"parry":
			_set_event(0.6, 10.0 * side, 3.0, -2.5, -8.0)
		"kill":
			_set_event(0.8, 12.0 * side, 5.0, -3.0, -5.0)
		"special":
			_set_event(1.3, 34.0 * side, 14.0, -1.0, 8.0)
		"slam":
			_set_event(0.8, 0.0, -8.0, 1.5, 12.0)
			add_trauma(0.9)
		"roar":
			_set_event(1.2, 0.0, 6.0, -2.0, 6.0)
			add_trauma(0.7)


func _set_event(dur: float, yaw: float, pitch: float, dist: float, fov_add: float) -> void:
	_ev_dur = dur
	_ev_t = dur
	_ev = {"yaw": yaw, "pitch": pitch, "dist": dist, "fov": fov_add}


## 0 → 1 → 0 envelope: snaps in quickly, holds, eases out.
func _event_weight() -> float:
	if _ev_t <= 0.0:
		return 0.0
	var t := 1.0 - _ev_t / _ev_dur
	return smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.55, 1.0, t))


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _on_hit_landed(heavy: bool, _at: Vector3) -> void:
	add_trauma(0.3 if heavy else 0.12)
	if heavy:
		_fov_kick = 5.0


func _goal_focus() -> Vector3:
	var p := target.global_position
	var f := p + Vector3(_ahead, height, 0.0)
	if _foe != null and is_instance_valid(_foe):     # arena framing: lean toward the opponent
		var mid := (p + _foe.global_position) * 0.5 + Vector3(0.0, height, 0.0)
		f = f.lerp(mid, 0.45 * _combat)
	if level_bounds.size.x > 0.0:
		var half_w := 7.0
		f.x = clampf(f.x, level_bounds.position.x + half_w, level_bounds.end.x - half_w)
		f.y = maxf(f.y, level_bounds.position.y + 4.0)
	return f


func _process(delta: float) -> void:
	# event cameras run in real time, so they still play during slow motion
	var now := Time.get_ticks_usec()
	var real_dt := 0.0 if _last_us == 0 else minf(0.1, (now - _last_us) / 1e6)
	_last_us = now
	_ev_t = maxf(0.0, _ev_t - real_dt)
	if target == null or not is_instance_valid(target):
		return
	# look-ahead in the direction the hunter faces / moves
	var facing := float(target.get("facing")) if target.get("facing") != null else 1.0
	var vel: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	_ahead = lerpf(_ahead, facing * look_ahead + clampf(vel.x * 0.15, -1.0, 1.0), 1.0 - exp(-2.0 * delta))

	# spring-damper follow (critically damped: no overshoot, but a visible lag)
	var goal := _goal_focus()
	var w := follow_speed
	if vel.y < -8.0:
		w *= 1.8                                          # catch up when falling fast
	var acc := (goal - _focus) * w * w - _vel * 2.0 * w
	_vel += acc * delta
	_focus += _vel * delta

	# combat: enemies near -> dolly in and swing round
	var near := 0
	var side := 0.0
	var best := INF
	_foe = null
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Node3D
		if en.get("state") == "dead":
			continue
		var d := en.global_position - target.global_position
		if absf(d.x) < 8.0 and absf(d.y) < 4.0:
			near += 1
			side += signf(d.x)
			if absf(d.x) < best:
				best = absf(d.x)
				_foe = en
	_combat = move_toward(_combat, 1.0 if near > 0 else 0.0, delta * (1.6 if near > 0 else 0.7))
	if near > 0 and side != 0.0:
		_combat_side = lerpf(_combat_side, signf(side), 1.0 - exp(-1.5 * delta))

	# tilt down while airborne so you see where you will land
	var airborne := target is CharacterBody3D and not (target as CharacterBody3D).is_on_floor()
	var want_pitch := deg_to_rad(air_pitch_deg if airborne and vel.y < 2.0 else pitch_deg)
	_pitch = lerp_angle(_pitch, want_pitch, 1.0 - exp(-2.2 * delta))

	_place(delta)


func _place(delta: float) -> void:
	var c := smoothstep(0.0, 1.0, _combat)
	var dist := lerpf(distance, combat_distance, c)
	if _foe != null and is_instance_valid(_foe):     # pull back to keep both fighters in frame
		dist += clampf(absf(_foe.global_position.x - target.global_position.x) - 3.5, 0.0, 4.0) * 0.6 * c
	var yaw := -_combat_side * deg_to_rad(combat_yaw_deg) * c
	var pitch := _pitch - deg_to_rad(4.0) * c
	var w := _event_weight()
	yaw += deg_to_rad(float(_ev["yaw"])) * w
	pitch += deg_to_rad(float(_ev["pitch"])) * w
	dist += float(_ev["dist"]) * w
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var cam_pos := _focus + basis * Vector3(0, 0, dist)
	camera.global_transform = Transform3D(basis, cam_pos)

	# impacts: FOV punch and trauma-based shake (offsets, so the transform stays clean)
	_fov_kick = move_toward(_fov_kick, 0.0, 30.0 * delta)
	camera.fov = fov - _fov_kick + 4.0 * c + float(_ev["fov"]) * w
	_trauma = maxf(0.0, _trauma - 1.4 * delta)
	_noise_t += delta * 60.0
	var shake := _trauma * _trauma
	camera.h_offset = shake * 0.55 * _noise.get_noise_2d(_noise_t, 0.0)
	camera.v_offset = shake * 0.55 * _noise.get_noise_2d(0.0, _noise_t)
	camera.rotation.z = shake * 0.04 * _noise.get_noise_2d(_noise_t, 50.0)

	# depth of field: keep the lane sharp, blur the far bank and the near reeds
	_attrs.dof_blur_far_distance = dist + 5.0
	_attrs.dof_blur_far_transition = 8.0
	_attrs.dof_blur_near_distance = maxf(1.0, dist - 5.0)
	_attrs.dof_blur_near_transition = 2.5

	if _motes:
		_motes.global_position = Vector3(_focus.x, _focus.y, -1.0)


func _make_motes() -> void:
	_motes = CPUParticles3D.new()
	_motes.amount = 70
	_motes.lifetime = 7.0
	_motes.preprocess = 7.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(18, 6, 6)
	_motes.direction = Vector3(0.3, 1, 0)
	_motes.spread = 60.0
	_motes.gravity = Vector3.ZERO
	_motes.initial_velocity_min = 0.1
	_motes.initial_velocity_max = 0.4
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = m
	_motes.mesh = mesh
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_motes.color_ramp = ramp
	_motes.color = motes_color
	add_child(_motes)


func set_motes_color(c: Color) -> void:
	motes_color = c
	if _motes:
		_motes.color = c
