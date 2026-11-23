class_name WorldConfig
extends RefCounted
## The one place that answers "what world are we building?"
## Every generator reads its seed (and, as chapters progress, world
## size, sea level, chunk size…) from here. No generator is allowed
## to invent private settings the others cannot see.
##
## The BOOK's master seed is 20261119 (the course used 20261116; the
## book is its own artefact and gets its own seed — PLAN.md §1).
## Stream names are unchanged from the course.

var master_seed: int = 20261119

## The demo stages are a 200 m × 200 m patch of world, centred on origin.
var world_size: float = 200.0

## Water sits at this height in every terrain stage that has water.
var sea_level: float = 0.0

# Terrain dials (added in Chapter 5, Listing 5.1). Every terrain consumer
# reads these from the config — no magic numbers buried inside generators.
# NOTE: Listing 5.1 also names sea_level (5.0), but that field already
# exists above (Part 0, default 0.0, the Part II stages' scale), so it is
# not redeclared here; the environments stage sets the Part I value 5.0
# on its own config instance instead.
var terrain_cells: int = 128            # cells across; points = cells + 1
var terrain_world_size: float = 400.0   # metres across the whole world
var terrain_height_scale: float = 30.0  # metres of relief, low to peak


## Helper: a fresh RNG for a named stream, derived from THIS config's
## master seed via SeedBank. This is the door generators should use —
## never SeedBank.stream_for(some_other_seed, …) and never global RNG.
func stream(stream_name: String) -> RandomNumberGenerator:
	return SeedBank.stream_for(master_seed, stream_name)


## Helper: a FastNoiseLite for a named stream, derived from THIS
## config's master seed via SeedBank, so noise fields stay isolated.
func noise(stream_name: String, frequency: float, octaves: int) -> FastNoiseLite:
	return SeedBank.noise_for(master_seed, stream_name, frequency, octaves)

# --- Chunking (added in Chapter 13, Listing 13.1) ---
var chunk_size_m: float = 64.0      # one chunk = 64 m x 64 m of world
var chunk_cells: int = 32           # 32 cells -> 33x33 vertices per chunk
var view_radius_chunks: int = 2     # fixed grid for now; streaming below

func cell_size_m() -> float:
	return chunk_size_m / float(chunk_cells)
