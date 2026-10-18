// Swamp water: dark, glossy and gently rippling. It is opaque and almost mirror-smooth,
// so the engine's screen-space reflections (SSR) show the hunter, the frogs, the trees
// and the lantern glow in it. A fresnel term brightens it at grazing angles.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow : source_color = vec4(0.22, 0.34, 0.38, 1.0);
uniform vec4 deep : source_color = vec4(0.05, 0.10, 0.13, 1.0);
uniform float ripple_speed = 0.55;
uniform float ripple_strength = 0.12;

varying vec3 world_pos;

float height(vec2 p) {
	return sin(p.x * 1.7 + TIME * ripple_speed) * 0.5
		+ sin(p.y * 2.3 - TIME * ripple_speed * 1.3) * 0.5
		+ sin((p.x + p.y) * 3.7 + TIME * ripple_speed * 0.8) * 0.25;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float e = 0.06;
	float dx = height(p + vec2(e, 0.0)) - height(p - vec2(e, 0.0));
	float dz = height(p + vec2(0.0, e)) - height(p - vec2(0.0, e));
	vec3 n = normalize(vec3(-dx * ripple_strength, 1.0, -dz * ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.25 + 0.35 * fresnel);
	ROUGHNESS = 0.04;
	METALLIC = 0.25;
	SPECULAR = 0.7;
}
