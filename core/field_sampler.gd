class_name FieldSampler
extends RefCounted
## The book's sampling convention, in one place:
## ALWAYS sample noise at WORLD coordinates (metres, centred on the
## origin — see WorldConfig). Never sample by loop index or by pixel.
## Any two systems asking about the same world position then get the
## same answer automatically — that is what makes chunking possible.
##
## This tiny wrapper is the seed of Part II's TerrainHeight: when
## the sampling rule grows (height scale, falloff), it grows HERE and
## every caller is corrected at once.

static func sample_height(noise: FastNoiseLite, x: float, z: float) -> float:
	return noise.get_noise_2d(x, z)


## The shared demo field used by the sampling lab + probe.
static func demo_noise() -> FastNoiseLite:
	return SeedBank.noise_for(20261119, SeedBank.STREAM_TERRAIN, 0.02, 4)
