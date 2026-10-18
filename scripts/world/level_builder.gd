@tool
class_name LevelBuilder
extends Node3D
## Builds a whole level from its text map (assets/levels/level_N.txt):
##   - the play lane: merged terrain meshes (grassy tops, rocky faces) with depth
##     shading baked into vertex colours, plus merged box collision
##   - wooden one-way platforms and reflective swamp water
##   - every letter in the map becomes a game object (enemies, keys, shrines, ...)
##   - the diorama around the lane: a river bank with trees and reeds, lanterns with
##     real lights, a mirror-like lake in front and behind, hills and mountains in fog
##   - the sky, sun, fog, bloom and colour grade for the level's theme
## It is a @tool script, so the level is also built inside the editor viewport.

const LANE_BACK := 2.4        ## ground reaches this far behind the play lane (-z)
const LANE_FRONT := 1.4       ## ... and this far in front of it (+z)
const TEX_M := 1.92           ## metres per 64 px texture tile = same pixel density as the sprites
const BANK_DEPTH := 9.0       ## depth of the river bank behind the lane
const WATER_DROP := 1.15      ## lake surface sits this far below the base ground
const EDGE_PAD := 24          ## terrain drawn this many tiles beyond each end of the map

const SCENES := {
	"h": preload("res://scenes/actors/hopper.tscn"),
	"B": preload("res://scenes/actors/brute.tscn"),
	"c": preload("res://scenes/actors/cultist.tscn"),
	"b": preload("res://scenes/actors/boss.tscn"),
	"N": preload("res://scenes/world/npc.tscn"),
	"D": preload("res://scenes/world/gate.tscn"),
	"S": preload("res://scenes/world/shrine.tscn"),
	"X": preload("res://scenes/world/exit.tscn"),
	"C": preload("res://scenes/world/crate.tscn"),
	"^": preload("res://scenes/world/thorns.tscn"),
}
const PICKUP := preload("res://scenes/world/pickup.tscn")
const PICKUP_KINDS := { "o": "orb", "p": "peach", "k": "key", "e": "eye" }
const WATER_SHADER := preload("res://scripts/world/water.gdshader")

@export_range(1, 5) var level_index: int = 1:
	set(value):
		level_index = value
		if is_node_ready() and auto_build:
			build()
@export var auto_build: bool = true          ## build on ready (the game scene builds manually)
@export var with_atmosphere: bool = true     ## also create sky, sun, fog and post effects
@export var spawn_entities: bool = true

var data: LevelData
var theme: Dictionary = {}
var spawn_point := Vector3.ZERO
var shrines: Array[Node3D] = []              ## in left-to-right order (checkpoint index)
var bounds := AABB()
var base_y := 0.0
var environment: Environment

var _root: Node3D
var _mats: Dictionary = {}


func _ready() -> void:
	if auto_build:
		build()


func build() -> void:
	if _root and is_instance_valid(_root):
		remove_child(_root)
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	shrines.clear()
	_mats.clear()

	data = LevelData.load_file("res://assets/levels/level_%d.txt" % level_index)
	if data == null:
		return
	theme = Themes.get_theme(data.setting("theme", "reeds"))
	bounds = AABB(Vector3(0, 0, -LANE_BACK), Vector3(data.width, data.height, LANE_BACK + LANE_FRONT))
	base_y = _base_ground_y()

	if with_atmosphere:
		_build_atmosphere()
	_build_terrain()
	_build_platforms()
	_build_water()
	_build_backdrop()
	if spawn_entities:
		_spawn_entities()
	_scatter_decor()


# ================================================================== helpers
func _group(group_name: String) -> Node3D:
	var n := _root.get_node_or_null(group_name) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = group_name
		_root.add_child(n)
	return n


func _h(i: int, k: int) -> float:
	var n := (i * 73856093) ^ (k * 19349663) ^ (level_index * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0


func _material(tex_name: String) -> StandardMaterial3D:
	if _mats.has(tex_name):
		return _mats[tex_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s.png" % tex_name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[tex_name] = m
	return m


func _quad(st: SurfaceTool, v: Array, n: Vector3, uv: Array, col: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(col[i])
		st.set_uv(uv[i])
		st.add_vertex(v[i])


func _mesh_node(st: SurfaceTool, mat: Material, node_name: String, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Lowest exposed ground running along the bottom of the map (the "water line" level).
func _base_ground_y() -> float:
	var tops: Array[float] = []
	for c in data.width:
		var r := data.height - 1
		if not data.is_solid(c, r):
			continue
		while r > 0 and data.is_solid(c, r - 1):
			r -= 1
		tops.append(data.row_bottom(r) + 1.0)
	if tops.is_empty():
		return 2.0
	tops.sort()
	return tops[int(tops.size() * 0.3)]


## y of the top of the solid run that contains (col,row).
func _column_top(col: int, row: int) -> float:
	var r := row
	while r > 0 and data.is_solid(col, r - 1):
		r -= 1
	return data.row_bottom(r) + 1.0


# ================================================================== atmosphere
func _build_atmosphere() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme["sky_top"]
	sky_mat.sky_horizon_color = theme["sky_horizon"]
	sky_mat.ground_horizon_color = theme["sky_horizon"]
	sky_mat.ground_bottom_color = theme["ground"]
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 24.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme["ambient"]
	env.ambient_light_energy = theme["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = theme["fog"]
	env.fog_density = theme["fog_density"]
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = theme["vfog_density"]
	env.volumetric_fog_albedo = theme["vfog_albedo"]
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 48.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	environment = env
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = theme["sun"]
	sun.light_energy = theme["sun_energy"]
	sun.rotation_degrees = theme["sun_rot"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 45.0
	_root.add_child(sun)


# ================================================================== terrain
## Solid test that repeats the first/last column outwards, so the ground does not
## stop dead at the edge of the map when the camera looks past it.
func _solid_ext(c: int, r: int) -> bool:
	if c < -EDGE_PAD or c >= data.width + EDGE_PAD:
		return true
	return data.is_solid(clampi(c, 0, data.width - 1), r)


func _build_terrain() -> void:
	var g := _group("Terrain")
	var tops := SurfaceTool.new()
	var sides := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zb := -LANE_BACK
	var zf := LANE_FRONT
	var t := TEX_M
	for r in data.height:
		for c in range(-EDGE_PAD, data.width + EDGE_PAD):
			if not _solid_ext(c, r):
				continue
			var x0 := float(c)
			var x1 := x0 + 1.0
			var y0 := data.row_bottom(r)
			var y1 := y0 + 1.0
			var top := _column_top(clampi(c, 0, data.width - 1), r)
			var shade_hi := 1.0 - clampf((top - y1) / 7.0, 0.0, 0.62)       # darker deeper below the surface
			var shade_lo := 1.0 - clampf((top - y0) / 7.0, 0.0, 0.62)
			var chi := Color(shade_hi, shade_hi, shade_hi)
			var clo := Color(shade_lo, shade_lo, shade_lo)
			if not _solid_ext(c, r - 1):
				var w := Color.WHITE
				_quad(tops, [Vector3(x0, y1, zb), Vector3(x1, y1, zb), Vector3(x1, y1, zf), Vector3(x0, y1, zf)], Vector3.UP,
					[Vector2(x0 / t, zb / t), Vector2(x1 / t, zb / t), Vector2(x1 / t, zf / t), Vector2(x0 / t, zf / t)], [w, w, w, w])
				# mossy lip hanging over the front edge
				var lip := Color(0.82, 0.82, 0.82)
				var lz := zf + 0.01
				_quad(tops, [Vector3(x0, y1, lz), Vector3(x1, y1, lz), Vector3(x1, y1 - 0.22 - 0.1 * _h(c, r), lz), Vector3(x0, y1 - 0.22 - 0.1 * _h(c + 1, r), lz)],
					Vector3.BACK, [Vector2(x0 / t, 0), Vector2(x1 / t, 0), Vector2(x1 / t, 0.12), Vector2(x0 / t, 0.12)], [lip, lip, lip, lip])
			# front face (the cliff you look at)
			_quad(sides, [Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y1, zf), Vector3(x0, y1, zf)], Vector3.BACK,
				[Vector2(x0 / t, -y0 / t), Vector2(x1 / t, -y0 / t), Vector2(x1 / t, -y1 / t), Vector2(x0 / t, -y1 / t)], [clo, clo, chi, chi])
			var sc := 0.8
			if not _solid_ext(c - 1, r):
				_quad(sides, [Vector3(x0, y0, zb), Vector3(x0, y0, zf), Vector3(x0, y1, zf), Vector3(x0, y1, zb)], Vector3.LEFT,
					[Vector2(zb / t, -y0 / t), Vector2(zf / t, -y0 / t), Vector2(zf / t, -y1 / t), Vector2(zb / t, -y1 / t)],
					[clo * sc, clo * sc, chi * sc, chi * sc])
			if not _solid_ext(c + 1, r):
				_quad(sides, [Vector3(x1, y0, zf), Vector3(x1, y0, zb), Vector3(x1, y1, zb), Vector3(x1, y1, zf)], Vector3.RIGHT,
					[Vector2(zf / t, -y0 / t), Vector2(zb / t, -y0 / t), Vector2(zb / t, -y1 / t), Vector2(zf / t, -y1 / t)],
					[clo * sc, clo * sc, chi * sc, chi * sc])
			if r + 1 < data.height and not _solid_ext(c, r + 1):
				var d := Color(0.4, 0.4, 0.42)
				_quad(sides, [Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y0, zb), Vector3(x0, y0, zb)], Vector3.DOWN,
					[Vector2(x0 / t, zf / t), Vector2(x1 / t, zf / t), Vector2(x1 / t, zb / t), Vector2(x0 / t, zb / t)], [d, d, d, d])
	_mesh_node(tops, _material(theme["top"]), "Tops", g)
	_mesh_node(sides, _material(theme["side"]), "Faces", g)
	_build_solid_collision(g)


## Greedy-merge solid tiles into as few boxes as possible.
func _build_solid_collision(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var used := {}
	for r in data.height:
		for c in data.width:
			if not data.is_solid(c, r) or used.has(Vector2i(c, r)):
				continue
			var c2 := c
			while c2 + 1 < data.width and data.is_solid(c2 + 1, r) and not used.has(Vector2i(c2 + 1, r)):
				c2 += 1
			var r2 := r
			var grow := true
			while grow and r2 + 1 < data.height:
				for cc in range(c, c2 + 1):
					if not data.is_solid(cc, r2 + 1) or used.has(Vector2i(cc, r2 + 1)):
						grow = false
						break
				if grow:
					r2 += 1
			for rr in range(r, r2 + 1):
				for cc in range(c, c2 + 1):
					used[Vector2i(cc, rr)] = true
			var shape := BoxShape3D.new()
			shape.size = Vector3(c2 - c + 1, r2 - r + 1, LANE_BACK + LANE_FRONT)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = Vector3((c + c2 + 1) * 0.5, data.row_bottom(r2) + (r2 - r + 1) * 0.5, (LANE_FRONT - LANE_BACK) * 0.5)
			body.add_child(col)
	# invisible walls at both ends and a lid over the top, so nothing leaves the map
	var h := float(data.height)
	var w := float(data.width)
	for box: AABB in [AABB(Vector3(-1, -4, 0), Vector3(1, h + 14, 0)), AABB(Vector3(w, -4, 0), Vector3(1, h + 14, 0)),
			AABB(Vector3(-1, h + 1.5, 0), Vector3(w + 2, 1, 0))]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(box.size.x, box.size.y, LANE_BACK + LANE_FRONT)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5, (LANE_FRONT - LANE_BACK) * 0.5)
		body.add_child(col)


# ================================================================== platforms (one-way, drop through with Down + Jump)
func _build_platforms() -> void:
	var g := _group("Platforms")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := TEX_M
	for r in data.height:
		var c := 0
		while c < data.width:
			if data.cell(c, r) != "=":
				c += 1
				continue
			var c2 := c
			while c2 + 1 < data.width and data.cell(c2 + 1, r) == "=":
				c2 += 1
			var x0 := float(c) - 0.05
			var x1 := float(c2 + 1) + 0.05
			var y1 := data.row_bottom(r) + 1.0
			var y0 := y1 - 0.28
			var z0 := -0.9
			var z1 := 0.9
			var w := Color.WHITE
			var dk := Color(0.55, 0.55, 0.55)
			_quad(st, [Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.UP,
				[Vector2(x0 / t, z0 / t), Vector2(x1 / t, z0 / t), Vector2(x1 / t, z1 / t), Vector2(x0 / t, z1 / t)], [w, w, w, w])
			_quad(st, [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.BACK,
				[Vector2(x0 / t, 0.3), Vector2(x1 / t, 0.3), Vector2(x1 / t, 0.15), Vector2(x0 / t, 0.15)], [dk, dk, w, w])
			_quad(st, [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)], Vector3.DOWN,
				[Vector2(x0 / t, 0), Vector2(x1 / t, 0), Vector2(x1 / t, 0.4), Vector2(x0 / t, 0.4)], [dk, dk, dk, dk])
			for ex: float in [x0, x1]:
				_quad(st, [Vector3(ex, y0, z0), Vector3(ex, y0, z1), Vector3(ex, y1, z1), Vector3(ex, y1, z0)], Vector3.RIGHT,
					[Vector2(0, 0.3), Vector2(0.4, 0.3), Vector2(0.4, 0.15), Vector2(0, 0.15)], [dk, dk, w, w])
			var body := StaticBody3D.new()
			body.name = "Platform"
			body.collision_layer = 0
			body.set_collision_layer_value(3, true)
			body.collision_mask = 0
			var shape := BoxShape3D.new()
			shape.size = Vector3(x1 - x0, 0.28, LANE_BACK + LANE_FRONT)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = Vector3((x0 + x1) * 0.5, y1 - 0.14, (LANE_FRONT - LANE_BACK) * 0.5)
			body.add_child(col)
			g.add_child(body)
			c = c2 + 1
	_mesh_node(st, _material(theme["platform"]), "PlatformMesh", g)


# ================================================================== water
func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("shallow", theme["water"])
	m.set_shader_parameter("deep", theme["water_deep"])
	return m


func _water_plane(parent: Node3D, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	pm.subdivide_width = int((x1 - x0) / 4.0)
	mi.mesh = pm
	mi.material_override = _water_material()
	mi.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_water() -> void:
	var g := _group("Water")
	for r in data.height:
		var c := 0
		while c < data.width:
			if data.cell(c, r) != "~" or data.cell(c, r - 1) == "~":
				c += 1
				continue
			var c2 := c
			while c2 + 1 < data.width and data.cell(c2 + 1, r) == "~" and data.cell(c2 + 1, r - 1) != "~":
				c2 += 1
			var surface := data.row_bottom(r) + 1.0 - 0.15
			_water_plane(g, c - 0.02, c2 + 1.02, -LANE_BACK, LANE_FRONT + 0.4, surface)
			# drowning zone: falling in costs health and returns you to safe ground
			var depth := 0
			while data.cell(c, r + depth) == "~":
				depth += 1
			var zone := Area3D.new()
			zone.name = "Drown"
			zone.add_to_group("water")
			zone.collision_layer = 0
			zone.set_collision_layer_value(7, true)
			zone.collision_mask = 2 | 8 | 32         # player, enemies, crates
			var shape := BoxShape3D.new()
			shape.size = Vector3(c2 - c + 1, maxf(1.0, float(depth)) - 0.35, LANE_BACK + LANE_FRONT)
			var col := CollisionShape3D.new()
			col.shape = shape
			zone.add_child(col)
			zone.position = Vector3((c + c2 + 1) * 0.5, surface - shape.size.y * 0.5 - 0.15, (LANE_FRONT - LANE_BACK) * 0.5)
			zone.set_script(load("res://scripts/world/water_zone.gd"))
			g.add_child(zone)
			c = c2 + 1


# ================================================================== the diorama around the lane
func _build_backdrop() -> void:
	var g := _group("Backdrop")
	var w := float(data.width)
	var lake_y := base_y - WATER_DROP
	# the river bank behind the lane, and its front face down into the water
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := TEX_M
	var x0 := -40.0
	var x1 := w + 40.0
	var zb0 := -LANE_BACK
	var zb1 := -BANK_DEPTH
	var white := Color.WHITE
	_quad(st, [Vector3(x0, base_y, zb1), Vector3(x1, base_y, zb1), Vector3(x1, base_y, zb0), Vector3(x0, base_y, zb0)], Vector3.UP,
		[Vector2(x0 / t, zb1 / t), Vector2(x1 / t, zb1 / t), Vector2(x1 / t, zb0 / t), Vector2(x0 / t, zb0 / t)], [white, white, white, white])
	_mesh_node(st, _material(theme["top"]), "Bank", g)
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dk := Color(0.55, 0.55, 0.58)
	for z in [zb1, zb0]:
		_quad(faces, [Vector3(x0, lake_y - 3, z), Vector3(x1, lake_y - 3, z), Vector3(x1, base_y, z), Vector3(x0, base_y, z)], Vector3.BACK,
			[Vector2(x0 / t, 2), Vector2(x1 / t, 2), Vector2(x1 / t, 0), Vector2(x0 / t, 0)], [dk * 0.6, dk * 0.6, dk, dk])
	_mesh_node(faces, _material(theme["side"]), "BankFaces", g)
	# mirror-like lake behind the bank and in front of the lane
	_water_plane(g, x0, x1, -95.0, zb1, lake_y)
	_water_plane(g, x0, x1, LANE_FRONT, 24.0, lake_y)
	# distant hills and mountains (vertex-coloured strips, softened by fog)
	_ridge(g, "Hills", -46.0, -58.0, lake_y + 0.2, 5.0, 9.0, theme["hills"], 3.0, 11)
	_ridge(g, "Mountains", -120.0, -150.0, lake_y + 0.5, 18.0, 34.0, theme["mountains"], 9.0, 23)


func _ridge(parent: Node3D, node_name: String, z_front: float, z_back: float, y0: float, hmin: float, hmax: float,
		col: Color, step: float, seed_k: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := -160.0
	var xe := float(data.width) + 160.0
	var i := 0
	while x < xe:
		var hA := hmin + (hmax - hmin) * (0.5 + 0.5 * sin(x * 0.05 + seed_k) * cos(x * 0.021)) * (0.7 + 0.3 * _h(i, seed_k))
		var hB := hmin + (hmax - hmin) * (0.5 + 0.5 * sin((x + step) * 0.05 + seed_k) * cos((x + step) * 0.021)) * (0.7 + 0.3 * _h(i + 1, seed_k))
		var lo := col.darkened(0.25)
		_quad(st, [Vector3(x, y0, z_front), Vector3(x + step, y0, z_front), Vector3(x + step, y0 + hB, z_back), Vector3(x, y0 + hA, z_back)],
			Vector3(0, 0.6, 0.8).normalized(), [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [lo, lo, col, col])
		x += step
		i += 1
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_node(st, m, node_name, parent)


# ================================================================== entities from the map
func _spawn_entities() -> void:
	var g := _group("Entities")
	var shrine_list: Array[Node3D] = []
	for r in data.height:
		for c in data.width:
			var ch := data.cell(c, r)
			var foot := Vector3(c + 0.5, data.row_bottom(r), 0.0)
			if ch == "P":
				spawn_point = foot
			elif PICKUP_KINDS.has(ch):
				var p := PICKUP.instantiate()
				p.set("kind", PICKUP_KINDS[ch])
				p.position = foot + Vector3(0, 0.45, 0)
				g.add_child(p)
			elif SCENES.has(ch):
				var n: Node3D = SCENES[ch].instantiate()
				n.position = foot
				if ch == "N":
					n.set("dialogue_key", "level_%d_hermit" % level_index)
				g.add_child(n)
				if ch == "S":
					shrine_list.append(n)
			elif ch == "L":
				_lantern(g, foot + Vector3(0, 0, -1.5))
			elif ch == "T":
				g.add_child(Props.make(_pick(theme["bank"], c, r, ["tree", "willow", "pine"]), foot + Vector3(0, 0, -1.9)))
			elif ch == "r":
				g.add_child(Props.make("reeds", foot + Vector3(0, 0, -1.2)))
	shrine_list.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.x < b.position.x)
	for i in shrine_list.size():
		shrine_list[i].set("index", i)
	shrines = shrine_list


func _lantern(parent: Node3D, foot: Vector3) -> void:
	parent.add_child(Props.make("lantern", foot))
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = theme["lantern_color"]
	light.light_energy = 2.2
	light.omni_range = 7.5
	light.omni_attenuation = 1.6
	light.light_volumetric_fog_energy = 2.5
	light.position = foot + Vector3(0, 2.0, 0.35)
	parent.add_child(light)


# ================================================================== decoration (deterministic, so it never changes)
func _pick(table: Array, i: int, k: int, only: Array = []) -> String:
	var total := 0.0
	for e: Array in table:
		if only.is_empty() or only.has(e[0]):
			total += float(e[1])
	var x := _h(i, k) * total
	for e: Array in table:
		if only.is_empty() or only.has(e[0]):
			x -= float(e[1])
			if x <= 0.0:
				return e[0]
	return "reeds" if only.is_empty() else only[0]


func _scatter_decor() -> void:
	var g := _group("Decor")
	var w := data.width
	# river bank: trees, willows, ruins further back; reeds along the water's edge
	var x := -36.0
	var i := 0
	while x < w + 36:
		if _h(i, 1) < 0.72:
			var z := -3.4 - _h(i, 2) * 4.6
			g.add_child(Props.make(_pick(theme["bank"], i, 3), Vector3(x + _h(i, 4), base_y, z), 0.9 + _h(i, 5) * 0.35))
		if _h(i, 6) < 0.5:
			g.add_child(Props.make("reeds", Vector3(x + 1.2, base_y - 0.05, -BANK_DEPTH + 0.3 + _h(i, 7) * 0.6)))
		x += 2.6 + _h(i, 8) * 1.8
		i += 1
	# reeds standing in the front lake (they blur in the depth of field)
	x = -20.0
	i = 0
	while x < w + 20:
		if _h(i, 11) < 0.45:
			g.add_child(Props.make("reeds", Vector3(x, base_y - WATER_DROP - 0.1, 2.3 + _h(i, 12) * 3.5), 1.1, false))
		x += 4.0 + _h(i, 13) * 5.0
		i += 1
	# grass and flowers on walkable tops, mostly behind the lane
	for r in data.height:
		for c in w:
			if not data.is_solid(c, r) or data.is_solid(c, r - 1) or data.cell(c, r - 1) != ".":
				continue
			if _h(c * 31 + r, 21) < 0.38:
				var z := -1.9 + _h(c, r + 7) * 1.1
				g.add_child(Props.make(_pick(theme["lane"], c, r), Vector3(c + _h(c, r), data.row_bottom(r) + 1.0, z), 1.0, false))
	# lanterns with real lights at intervals along the lane
	var spacing := 16
	for c in range(8, w - 4, spacing):
		for r in data.height:
			if data.is_solid(c, r) and not data.is_solid(c, r - 1):
				_lantern(g, Vector3(c + 0.5, data.row_bottom(r) + 1.0, -1.7))
				break
