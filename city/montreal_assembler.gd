class_name MontrealAssembler
extends RefCounted

## Part I's real Montreal, under Part VIII's city stack. This file
## contains NO new generator: it builds the real terrain through
## Part I's importer, re-runs Ch 8's landmark test, and expresses
## Ch 41's borough recipe in real coordinates. If a function here
## starts generating, it has wandered into the wrong file.
##
## Project integration notes: Part I's importer class is
## HeightmapImport (import_grid(path, elev_range_m, exaggeration))
## and its converter is GeoReference.latlon_to_world() — the
## chapter's "TerrainImport.load_height_png / latlon_to_world" is
## the same surface under the guide's names. The heightmap on disk
## is res://terrain/data/montreal_heightmap.png (Listing 42.2's
## "montreal_height.png" is the same export, misnamed). Sea level
## 16.0 is Part I's own tuned value for this river (the Part I
## environments stage sets it before load_grid(), and so do we:
## load_grid() re-runs the climate classification that reads it).

# Part I's frozen contract numbers — copied, never re-derived.
const WORLD_SIZE: float = 24000.0
const HEIGHT_SCALE: float = 466.0 # 233 m range x 2.0 exaggeration
const SW_LAT: float = 45.4000
const SW_LON: float = -73.7500

var terrain: TerrainHeight
var lookout_height: float = 0.0
var lookout_biome: int = -1


## Build the real terrain via Chapter 8's importer and verify it
## with the landmark test BEFORE any city code runs. Returns false
## on a failed test: a city on a mis-imported place is worse than
## no city.
func setup(import_path: String) -> bool:
	terrain = TerrainHeight.new()
	terrain.sea_level = 16.0 # Part I's tuned river level (see header)
	var result: Dictionary = HeightmapImport.import_grid(
		import_path, 233.0, 2.0)
	if result.is_empty():
		push_error("Montreal import failed: no grid loaded")
		return false
	terrain.load_grid(result["heights"], int(result["points"]),
		WORLD_SIZE, HEIGHT_SCALE)
	return landmark_test()


## Chapter 8's test, verbatim in spirit: the lookout must read as
## high, rocky ground — the island's local maximum, river to its
## south-east. Known answers: height ~394.5, biome Rock.
func landmark_test() -> bool:
	var lookout: Vector2 = GeoReference.latlon_to_world(
		45.5048, -73.5878, SW_LAT, SW_LON, WORLD_SIZE)
	lookout_height = terrain.height_at(lookout.x, lookout.y)
	lookout_biome = terrain.biome_at_world(lookout.x, lookout.y)
	print("landmark: world=", lookout, " height=",
		snappedf(lookout_height, 0.1), " biome=", lookout_biome)
	return lookout_height > 350.0 and lookout_biome != 0


## The borough recipe in real coordinates: Ch 41's five characters,
## placed by lat/lon at the districts they echo, scaled to real
## block sizes. Angles are the real districts' approximate grid
## rotations — Montreal's grids genuinely turn like this, which is
## why Ch 41's recipe exists.
func borough_table() -> Array[Dictionary]:
	return [
		{"name": "downtown", "centre": _latlon(45.5017, -73.5673),
			"angle_deg": -32.0, "pitch": Vector2(70, 120),
			"extent": Vector2(2600, 1800), "character": "office"},
		{"name": "old_town", "centre": _latlon(45.5075, -73.5530),
			"angle_deg": -28.0, "pitch": Vector2(45, 70),
			"extent": Vector2(1400, 700), "character": "apartment"},
		{"name": "plateau", "centre": _latlon(45.5270, -73.5800),
			"angle_deg": -34.0, "pitch": Vector2(60, 100),
			"extent": Vector2(2400, 1600), "character": "house"},
		{"name": "north_shore", "centre": _latlon(45.5600, -73.6600),
			"angle_deg": -12.0, "pitch": Vector2(80, 130),
			"extent": Vector2(2600, 1500), "character": "house"},
		{"name": "port_industrial", "centre": _latlon(45.5450, -73.5200),
			"angle_deg": -20.0, "pitch": Vector2(90, 140),
			"extent": Vector2(1800, 1200), "character": "apartment"},
	]


func _latlon(lat: float, lon: float) -> Vector2:
	return GeoReference.latlon_to_world(lat, lon, SW_LAT, SW_LON,
		WORLD_SIZE)


## Mount Royal as the landmark exclusion: a disc around the
## lookout. The slope veto (Ch 40) would refuse most of it anyway;
## the disc exists because a park is a DECISION, not just a slope
## verdict — the flat summit meadow is buildable ground that the
## city chooses not to build on. Both layers ship.
func hill_park() -> Dictionary:
	var lookout: Vector2 = _latlon(45.5048, -73.5878)
	return {"centre": lookout, "radius": 620.0}
