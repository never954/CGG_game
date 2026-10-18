class_name HitFx
extends RefCounted
## One-shot particle bursts: dust puffs (jumps, landings, slams) and glowing sparks
## (staff hits). Each burst is a CPUParticles3D that frees itself when it is done.
## Spark colours go above 1.0, so the bloom in the environment makes them glow.

static var _quad: QuadMesh
static var _dust_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D


static func _setup() -> void:
	if _quad != null:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.22, 0.22)
	_dust_mat = _material(false)
	_spark_mat = _material(true)


static func _material(glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var soft := GradientTexture2D.new()                  # round, soft-edged particle
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	soft.width = 32
	soft.height = 32
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	m.albedo_texture = soft
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _burst(parent: Node, at: Vector3, amount: int, lifetime: float, mat: Material) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	var mesh := _quad.duplicate() as QuadMesh
	mesh.material = mat
	p.mesh = mesh
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.position = at
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(lifetime + 0.3, false).timeout.connect(p.queue_free)
	return p


## Puff of dust at someone's feet.
static func dust(parent: Node, at: Vector3, amount: int = 6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := _burst(parent, at + Vector3(0, 0.1, 0.2), amount, 0.55, _dust_mat)
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6 + amount * 0.08
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.80, 0.74, 0.60, 0.55))
	ramp.set_color(1, Color(0.80, 0.74, 0.60, 0.0))
	p.color_ramp = ramp


## Burst of glowing sparks where the staff connects.
static func sparks(parent: Node, at: Vector3, heavy: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := _burst(parent, at, 18 if heavy else 9, 0.35 if heavy else 0.25, _spark_mat)
	p.direction = Vector3(0, 0.4, 1)
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0 if heavy else 6.5
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4 if heavy else 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(3.0, 2.6, 1.6, 1.0))
	ramp.set_color(1, Color(2.0, 0.8, 0.3, 0.0))
	p.color_ramp = ramp


## Splash when something falls into water.
static func splash(parent: Node, at: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := _burst(parent, at, 16, 0.7, _dust_mat)
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -18.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.9, 1.0, 0.85))
	ramp.set_color(1, Color(0.75, 0.9, 1.0, 0.0))
	p.color_ramp = ramp


## Floating word that rises and fades ("PERFECT", "PARRY", "MISS"...).
static func popup(parent: Node, at: Vector3, text: String, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.02, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	parent.add_child(l)
	var tw := l.create_tween().set_ignore_time_scale(true)
	l.scale = Vector3.ONE * 0.4
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", at.y + 0.8, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.25)
	tw.tween_callback(l.queue_free)


## Expanding shockwave ring on the ground (slams, dives, the special).
static func ring(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 48
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3(0.2, 0.15, 0.2)
	parent.add_child(mi)
	var tw := mi.create_tween().set_ignore_time_scale(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.15, radius * 0.6), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(mi.queue_free)
