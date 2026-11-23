class_name Zoning
extends RefCounted

## What may stand where, as a queryable field. Three ingredients:
## distance-to-centre gradient, seeded noise (rings become
## districts), terrain vetoes (the contract outranks the plan).
## Answers one of: "office", "apartment", "house", "green".
## Data-first: use_at() returns a String and decides for no builder.
##
## Project integration note: Chapter 42's stage calls set_radii()
## (§42.2 names the seam), so the two radii are fields whose
## defaults are Listing 40.1's constants — step 8/9/10 behaviour is
## the listing's, unchanged.

const OFFICE_RADIUS: float = 120.0 # full office density inside this
const APARTMENT_RADIUS: float = 260.0 # apartments fade out by here
const SLOPE_BUILDABLE: float = 0.30 # slope_at() units (1 - cos)

var _terrain: TerrainHeight
var _centre: Vector2
var _noise: FastNoiseLite
var _office_radius: float = OFFICE_RADIUS
var _apartment_radius: float = APARTMENT_RADIUS


func _init(terrain: TerrainHeight, centre: Vector2,
		master_seed: int) -> void:
	_terrain = terrain
	_centre = centre
	_noise = SeedBank.noise_for(master_seed, SeedBank.STREAM_ZONING,
		0.004, 2)


## Chapter 42's seam: the same field at a real city's scale.
func set_radii(office_r: float, apartment_r: float) -> void:
	_office_radius = office_r
	_apartment_radius = apartment_r


## The density score at a point: 1.0 at the centre, 0.0 at the rim,
## pushed around by noise so equal-distance points differ — the
## difference between a gradient and a target diagram.
func density_at(x: float, z: float) -> float:
	var d: float = Vector2(x, z).distance_to(_centre)
	var base: float = clampf(1.0 - d / (_apartment_radius * 1.6), 0.0, 1.0)
	var wobble: float = _noise.get_noise_2d(x, z) * 0.22
	return clampf(base + wobble, 0.0, 1.0)


## The use a point proposes — BEFORE the parcel's size is consulted
## (that negotiation is the placer's, §40.2). Terrain vetoes first:
## no zoning outranks water or a cliff.
func use_at(x: float, z: float) -> String:
	if _terrain.biome_at_world(x, z) == 0:
		return "green" # water: park edge, never a building
	if _terrain.slope_at(x, z) > SLOPE_BUILDABLE:
		return "green" # too steep to build: the contract vetoes
	var density: float = density_at(x, z)
	var d: float = Vector2(x, z).distance_to(_centre)
	if d < _office_radius and density > 0.62:
		return "office"
	if d < _apartment_radius and density > 0.34:
		return "apartment"
	return "house"


## Height ceiling (metres) the use implies at this point — offices
## taper with the same field that placed them, so the skyline falls
## smoothly instead of stepping at a ring boundary.
func height_cap_at(x: float, z: float, use: String) -> float:
	var density: float = density_at(x, z)
	match use:
		"office":
			return lerpf(18.0, 68.0, density)
		"apartment":
			return lerpf(10.0, 26.0, density)
		"house":
			return 9.0
	return 0.0
