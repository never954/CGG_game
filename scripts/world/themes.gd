class_name Themes
extends RefCounted
## The look of each of the five lands: sky, sun, fog, textures, water, decoration and
## music. Colours with channels above 1.0 are HDR and bloom.

const DATA := {
	# Level 1 — golden dusk over the reed marsh
	"reeds": {
		"sky_top": Color(0.20, 0.25, 0.50), "sky_horizon": Color(1.0, 0.66, 0.44), "ground": Color(0.10, 0.09, 0.13),
		"sun": Color(1.0, 0.80, 0.58), "sun_energy": 1.3, "sun_rot": Vector3(-24, -40, 0),
		"ambient": Color(0.58, 0.52, 0.66), "ambient_energy": 0.6,
		"fog": Color(0.88, 0.62, 0.52), "fog_density": 0.010, "vfog_density": 0.014, "vfog_albedo": Color(0.98, 0.78, 0.62),
		"top": "grass", "side": "cliff", "platform": "planks",
		"water": Color(0.22, 0.34, 0.38), "water_deep": Color(0.05, 0.10, 0.13),
		"hills": Color(0.28, 0.30, 0.38), "mountains": Color(0.48, 0.38, 0.52),
		"bank": [["willow", 3.0], ["tree", 2.0], ["reeds", 2.5], ["pine", 1.0], ["ruin", 0.4]],
		"lane": [["grass", 4.0], ["flowers", 2.0]],
		"lantern_color": Color(1.0, 0.68, 0.36), "motes": Color(1.5, 1.2, 0.7),
		"music": "music_marsh",
	},
	# Level 2 — misty teal morning in the flooded willow grove
	"grove": {
		"sky_top": Color(0.32, 0.45, 0.56), "sky_horizon": Color(0.80, 0.86, 0.80), "ground": Color(0.10, 0.12, 0.13),
		"sun": Color(0.96, 0.94, 0.84), "sun_energy": 1.05, "sun_rot": Vector3(-34, -32, 0),
		"ambient": Color(0.55, 0.64, 0.66), "ambient_energy": 0.65,
		"fog": Color(0.62, 0.74, 0.72), "fog_density": 0.022, "vfog_density": 0.03, "vfog_albedo": Color(0.82, 0.92, 0.9),
		"top": "marsh", "side": "cliff", "platform": "planks",
		"water": Color(0.20, 0.36, 0.36), "water_deep": Color(0.04, 0.10, 0.11),
		"hills": Color(0.30, 0.38, 0.40), "mountains": Color(0.50, 0.58, 0.60),
		"bank": [["willow", 4.0], ["pine", 2.0], ["reeds", 3.5], ["mushroom", 0.6]],
		"lane": [["grass", 4.0], ["flowers", 1.0]],
		"lantern_color": Color(1.0, 0.76, 0.46), "motes": Color(0.9, 1.4, 0.9),
		"music": "music_marsh",
	},
	# Level 3 — night in the glowing hollows (bioluminescent fungus)
	"hollow": {
		"sky_top": Color(0.03, 0.04, 0.10), "sky_horizon": Color(0.12, 0.20, 0.32), "ground": Color(0.02, 0.02, 0.04),
		"sun": Color(0.62, 0.74, 1.0), "sun_energy": 0.8, "sun_rot": Vector3(-42, -26, 0),
		"ambient": Color(0.40, 0.48, 0.70), "ambient_energy": 0.85,
		"fog": Color(0.14, 0.26, 0.36), "fog_density": 0.022, "vfog_density": 0.03, "vfog_albedo": Color(0.45, 0.75, 0.85),
		"top": "marsh", "side": "cave", "platform": "planks",
		"water": Color(0.10, 0.22, 0.30), "water_deep": Color(0.02, 0.05, 0.08),
		"hills": Color(0.08, 0.10, 0.16), "mountains": Color(0.12, 0.14, 0.24),
		"bank": [["mushroom", 3.0], ["pine", 2.0], ["ruin", 1.0], ["reeds", 1.5]],
		"lane": [["grass", 2.0], ["mushroom", 1.5]],
		"lantern_color": Color(0.45, 0.85, 1.0), "motes": Color(0.6, 1.4, 1.6),
		"music": "music_hollow",
	},
	# Level 4 — twilight over the sunken temple
	"temple": {
		"sky_top": Color(0.18, 0.24, 0.38), "sky_horizon": Color(0.66, 0.60, 0.64), "ground": Color(0.08, 0.08, 0.10),
		"sun": Color(0.92, 0.84, 0.76), "sun_energy": 0.95, "sun_rot": Vector3(-30, -42, 0),
		"ambient": Color(0.50, 0.52, 0.62), "ambient_energy": 0.6,
		"fog": Color(0.46, 0.50, 0.56), "fog_density": 0.02, "vfog_density": 0.022, "vfog_albedo": Color(0.8, 0.82, 0.88),
		"top": "stone", "side": "stone", "platform": "planks",
		"water": Color(0.18, 0.32, 0.36), "water_deep": Color(0.04, 0.09, 0.12),
		"hills": Color(0.26, 0.28, 0.36), "mountains": Color(0.40, 0.40, 0.50),
		"bank": [["ruin", 4.0], ["willow", 1.0], ["reeds", 2.0], ["pine", 1.0]],
		"lane": [["grass", 2.0], ["flowers", 0.6]],
		"lantern_color": Color(1.0, 0.70, 0.40), "motes": Color(1.3, 1.2, 0.9),
		"music": "music_hollow",
	},
	# Level 5 — the frog cult's throne under a blood moon
	"throne": {
		"sky_top": Color(0.10, 0.05, 0.10), "sky_horizon": Color(0.62, 0.26, 0.24), "ground": Color(0.05, 0.03, 0.04),
		"sun": Color(1.0, 0.66, 0.56), "sun_energy": 1.0, "sun_rot": Vector3(-24, -36, 0),
		"ambient": Color(0.50, 0.40, 0.50), "ambient_energy": 0.6,
		"fog": Color(0.34, 0.16, 0.18), "fog_density": 0.012, "vfog_density": 0.012, "vfog_albedo": Color(0.9, 0.6, 0.6),
		"top": "stone", "side": "cliff", "platform": "planks",
		"water": Color(0.24, 0.10, 0.12), "water_deep": Color(0.07, 0.02, 0.03),
		"hills": Color(0.16, 0.08, 0.10), "mountains": Color(0.30, 0.12, 0.14),
		"bank": [["ruin", 3.0], ["pine", 1.0], ["reeds", 1.0]],
		"lane": [["grass", 1.0]],
		"lantern_color": Color(1.0, 0.42, 0.28), "motes": Color(1.6, 0.6, 0.4),
		"music": "music_boss",
	},
}


static func get_theme(theme_name: String) -> Dictionary:
	return DATA.get(theme_name, DATA["reeds"])
