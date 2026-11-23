shader_type spatial;

// Chapter 12, Listing 12.1 — splat texturing.
// Integration addition: a `tint` uniform (default white = no effect).
// Chapter 13's ChunkManager._material_for() sets a "tint" shader
// parameter for its per-chunk / per-LOD debug views; without a uniform
// of that name the debug tint silently does nothing.

uniform sampler2D grass_tex : filter_linear, repeat_enable;
uniform sampler2D rock_tex : filter_linear, repeat_enable;
uniform sampler2D sand_tex : filter_linear, repeat_enable;
uniform sampler2D snow_tex : filter_linear, repeat_enable;
uniform float tex_scale = 0.06;      // world metres per texture tile
uniform float snow_start = 20.0;
uniform float rock_slope = 0.55;     // slope (0..1) where rock takes over
uniform float tint_strength = 0.55;  // how much the vertex-colour tint matters
uniform vec3 tint = vec3(1.0);       // debug tint (Ch13 manager); white = off

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz * tex_scale;
	// Slope: 0 = flat, 1 = vertical, from how sideways the normal points.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	// Weights: grass is the default; rock wins on steep ground; snow
	// wins above the snowline (but not on cliffs); sand wins at the shore.
	float w_rock = clamp((slope - rock_slope * 0.5) * 2.5, 0.0, 1.0);
	float w_snow = smoothstep(snow_start, snow_start + 4.0, world_pos.y) * (1.0 - slope * 0.5);
	float w_sand = smoothstep(7.5, 6.0, world_pos.y) * (1.0 - slope);
	float w_grass = clamp(1.0 - w_rock - w_snow - w_sand, 0.0, 1.0);
	float total = w_grass + w_rock + w_snow + w_sand;
	vec3 albedo = texture(grass_tex, uv).rgb * (w_grass / total)
		+ texture(rock_tex, uv).rgb * (w_rock / total)
		+ texture(snow_tex, uv).rgb * (w_snow / total)
		+ texture(sand_tex, uv).rgb * (w_sand / total);
	// The biome vertex colour survives as a large-scale tint.
	ALBEDO = albedo * mix(vec3(1.0), COLOR.rgb, tint_strength) * tint;
	ROUGHNESS = 0.95;
}
