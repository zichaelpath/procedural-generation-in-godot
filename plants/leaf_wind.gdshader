shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_texture;
uniform vec4 canopy_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

global uniform float wind_strength;
global uniform vec2 wind_direction;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	// Flutter: small, fast, per-card phase from world position,
	// masked to the card's free edge. Leaves jitter on a stem;
	// they do not sway like blades.
	float phase = TIME * 3.1 + dot(world.xz, vec2(2.3, 1.7));
	float flutter = sin(phase) * 0.5 + sin(phase * 3.7) * 0.5;
	float mask = UV.y;
	VERTEX.xz += wind_direction * (flutter * 0.05 * wind_strength * mask);
	VERTEX.y += flutter * 0.02 * wind_strength * mask;
}

void fragment() {
	vec4 tex = texture(leaf_texture, UV);
	if (tex.a < 0.5) {
		discard;  // alpha scissor, as Chapter 17 established
	}
	ALBEDO = tex.rgb * COLOR.rgb * canopy_tint.rgb;
	ROUGHNESS = 0.85;
}
