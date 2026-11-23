class_name WorldQuality
extends RefCounted

## Named quality tiers for the assembled world. THE RULE (§44.4):
## the skeleton never negotiates — terrain, edits, roads, parcels,
## uses, buildings, entrances are identical on every tier, because
## they are the seed's promise. Only garnish negotiates: ring size,
## scatter density, grass, dressing. Every knob below passes the
## test "no manifest address changes its content".

const TIERS: Dictionary = {
	"low": {
		"view_radius_chunks": 4,
		"scatter_density_scale": 0.35,
		"grass": false,
		"dressing": false,
		"lod_bias": 1, # start LOD one stride coarser (Ch 14 rings)
	},
	"medium": {
		"view_radius_chunks": 5,
		"scatter_density_scale": 0.65,
		"grass": true,
		"dressing": false,
		"lod_bias": 0,
	},
	"high": {
		"view_radius_chunks": 7,
		"scatter_density_scale": 1.0,
		"grass": true,
		"dressing": true,
		"lod_bias": 0,
	},
}


static func apply(tier_name: String, config: WorldConfig) -> Dictionary:
	var tier: Dictionary = TIERS.get(tier_name, TIERS["high"])
	config.view_radius_chunks = int(tier["view_radius_chunks"])
	return tier


static func tier_names() -> Array:
	return TIERS.keys()
