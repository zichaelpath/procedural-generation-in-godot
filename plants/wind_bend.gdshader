shader_type spatial;
render_mode cull_disabled;

// Blade gradient: root in shadowed green, tip in sunlit green.
// The instance colour (baked moisture tint) multiplies this.
uniform vec4 root_color : source_color = vec4(0.14, 0.26, 0.07, 1.0);
uniform vec4 tip_color : source_color = vec4(0.42, 0.60, 0.20, 1.0);
// Seasons multiply the whole field (Listing 19.4 drives this).
uniform vec4 season_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// The world's weather: project-wide, shared with the leaves.
global uniform float wind_strength;
global uniform vec2 wind_direction;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	// Bend mask: 0 at the planted root, 1 at the free tip,
	// squared so the blade curves instead of hinging.
	float mask = UV.y * UV.y;
	// Travelling gust: phase runs along the wind axis, so
	// wavefronts sweep across the field in the wind's direction.
	float phase = TIME * 1.6 - dot(world.xz, wind_direction) * 0.35;
	float gust = sin(phase) * 0.6 + sin(phase * 2.7) * 0.4;
	vec2 bend = wind_direction * (gust * wind_strength * mask);
	VERTEX.xz += bend;
	// A bent blade's tip drops along its arc; without this the
	// blade visibly stretches.
	VERTEX.y -= length(bend) * 0.35;
}

void fragment() {
	ALBEDO = mix(root_color.rgb, tip_color.rgb, UV.y) * COLOR.rgb * season_tint.rgb;
	ROUGHNESS = 0.9;
}
