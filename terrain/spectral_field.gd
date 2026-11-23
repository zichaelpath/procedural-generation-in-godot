class_name SpectralField
extends RefCounted

## Sum-of-sines height source: the wave table IS the terrain.
## Each wave is a Dictionary with amp, fx, fz, phase.

static func build_table(rng: RandomNumberGenerator, wave_count: int) -> Array:
	var table: Array = []
	var freq: float = 0.01
	for i in range(wave_count):
		table.append({
			"amp": 1.0 / float(i + 1),
			"fx": freq * rng.randf_range(0.7, 1.3),
			"fz": freq * rng.randf_range(0.7, 1.3),
			"phase": rng.randf_range(0.0, TAU),
		})
		freq *= 1.9  # each wave finer than the last, like noise octaves
	return table

static func height_at(table: Array, x: float, z: float) -> float:
	var sum: float = 0.0
	var amp_total: float = 0.0
	for wave in table:
		var amp: float = wave["amp"]
		sum += amp * sin(x * wave["fx"] + z * wave["fz"] + wave["phase"])
		amp_total += amp
	return sum / amp_total  # -1..1, same range as a noise sample

# Bake a spectral surface into an existing TerrainHeight, then let the
# usual climate pipeline classify it. Provenance stays boring: the
# classifiers cannot tell where the heights came from.
static func bake_into(data: TerrainHeight, config: WorldConfig) -> void:
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, "terrain")
	var table: Array = build_table(rng, 24)
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			var wp: Vector2 = data.grid_to_world(ix, iz)
			var n: float = height_at(table, wp.x, wp.y)
			data.heights[data.index(ix, iz)] = (n * 0.5 + 0.5) * data.height_scale
	data.generate_moisture(config)
	data.generate_temperature()
	data.classify_all()
	data.build_rule_labels()
