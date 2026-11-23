class_name SeedBank
extends RefCounted
## THE spine of the book (mirrors the Procedural Generation Masterclass
## course SeedBank exactly — same API, same hash formula, same stream
## names — so book, course, and project always agree).
##
## Every generator gets its randomness from here, through a NAMED stream
## derived from the master seed.
##
## Why streams: a RandomNumberGenerator is a sequence. If two systems
## share one sequence, one extra draw in system A silently reshuffles
## system B's whole world. Streams isolate systems from each other:
## each stream is seeded by hashing "master_seed:stream_name", so the
## streams behave like strangers but are all children of one number.
##
## Book rule: NEVER use global randf()/randi() in generator code.
## Pick a stream name below, or add a new one HERE, in the open.

const STREAM_TERRAIN := "terrain"
const STREAM_TERRAIN_MOISTURE := "terrain_moisture"
const STREAM_PLANTS := "plants"
const STREAM_TREES := "trees"
const STREAM_DUNGEON := "dungeon"
const STREAM_HOUSES := "houses"
const STREAM_ROADS := "roads"
const STREAM_PARCELS := "parcels"
const STREAM_BUILDINGS := "buildings"
const STREAM_SCATTER := "scatter"
const STREAM_DRESSING := "dressing"
const STREAM_ZONING := "zoning"
const STREAM_WORLD := "world"  # added in Chapter 43 (Listing 43.1)


## A fresh RNG positioned at the start of the named stream's sequence.
## Calling this again with the same arguments restarts the sequence —
## that restartability is the whole determinism contract.
static func stream_for(master_seed: int, stream_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(master_seed) + ":" + stream_name)
	return rng


## A FastNoiseLite seeded from the same "master_seed:stream_name" hash,
## so noise fields are stream-isolated exactly like RNG streams.
static func noise_for(master_seed: int, stream_name: String, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.seed = hash(str(master_seed) + ":" + stream_name)
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


## A private RNG for ONE chunk and ONE purpose. The seed string contains
## the master seed, the stream name and the chunk coordinates — nothing
## else. No history, no load order, no shared state: any chunk's dice land
## the same way no matter what was generated before it.
static func stream_for_chunk(master_seed: int, stream_name: String, chunk_coord: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(master_seed) + ":" + stream_name + ":" + str(chunk_coord.x) + "," + str(chunk_coord.y))
	return rng


## The integer twin of stream_for_chunk(): the same contract with no
## strings at all. Each quantised chunk coordinate is multiplied by a
## distinct large prime, the master seed by another, the stream ID by a
## fourth, and the results are summed. Same position, same seed — on any
## machine, in any visit order — which is the version a C++ engine uses
## when string hashing is not available. Stream IDs are a registry, just
## like stream names: 0 = terrain, 1 = scatter. Write yours down.
static func chunk_position_seed(master_seed: int, stream_id: int, chunk_coord: Vector2i) -> int:
	var seed_value: int = master_seed * 83492791
	seed_value += chunk_coord.x * 73856093
	seed_value += chunk_coord.y * 19349663
	seed_value += stream_id * 2654435769
	return seed_value


static func stream_for_chunk_int(master_seed: int, stream_id: int, chunk_coord: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_position_seed(master_seed, stream_id, chunk_coord)
	return rng
