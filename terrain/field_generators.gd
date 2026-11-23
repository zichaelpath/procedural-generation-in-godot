class_name FieldGenerators
extends RefCounted
## Pure generator functions: numbers in, data out, NO scene tree.
## Static, so any code anywhere — demos, the seed browser, the
## determinism test, a headless server — can call them.
## (Chapter 4, Listing 4.3.)

## Fills a HeightField with FBM noise, sampled at WORLD coordinates
## (centred on origin, per the Chapter 3 convention) via the
## "terrain" stream's noise configuration.
static func fractal_height_field(master_seed: int, size: int = 65, cell_size: float = 2.0, height_scale: float = 18.0) -> HeightField:
	var field := HeightField.new(size, cell_size)
	var noise := SeedBank.noise_for(master_seed, SeedBank.STREAM_TERRAIN, 0.012, 5)
	var half: float = field.world_extent() * 0.5
	for z in size:
		for x in size:
			var wx: float = float(x) * cell_size - half
			var wz: float = float(z) * cell_size - half
			var n: float = noise.get_noise_2d(wx, wz)
			field.set_point(x, z, n * height_scale)
	return field
