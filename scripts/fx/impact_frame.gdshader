// Anime "impact frame": for a split second the whole screen becomes a stark two-tone
// image (black silhouettes on white, or the inverse) with a red accent on the midtones.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform bool inverted = false;
uniform vec3 accent : source_color = vec3(0.9, 0.12, 0.16);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float ink = step(0.52, lum);                      // two tones
	if (inverted) {
		ink = 1.0 - ink;
	}
	vec3 col = mix(vec3(0.02), vec3(1.0), ink);
	float mid = smoothstep(0.36, 0.5, lum) * (1.0 - smoothstep(0.52, 0.66, lum));
	col = mix(col, accent, mid * 0.85);
	COLOR = vec4(col, 1.0);
}
