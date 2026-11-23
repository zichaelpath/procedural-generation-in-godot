class_name Seasons
extends RefCounted

## A season is a palette row, not a regeneration. Tints multiply
## the world's baked colours; leaf_density says what fraction of
## the already-placed leaves are currently drawn. Summer is the
## identity row: the world's true colours, all leaves on.

const SEASONS: Dictionary = {
	"spring": {
		"canopy": Color(0.82, 1.00, 0.72), "grass": Color(0.88, 1.05, 0.78),
		"shrub": Color(0.85, 1.00, 0.75), "leaf_density": 0.85,
		"sun_color": Color(1.00, 0.98, 0.90), "sun_energy": 1.10,
	},
	"summer": {
		"canopy": Color(1.00, 1.00, 1.00), "grass": Color(1.00, 1.00, 1.00),
		"shrub": Color(1.00, 1.00, 1.00), "leaf_density": 1.00,
		"sun_color": Color(1.00, 0.97, 0.88), "sun_energy": 1.25,
	},
	"autumn": {
		"canopy": Color(1.00, 0.60, 0.28), "grass": Color(1.05, 0.80, 0.45),
		"shrub": Color(1.00, 0.52, 0.32), "leaf_density": 0.70,
		"sun_color": Color(1.00, 0.85, 0.64), "sun_energy": 1.00,
	},
	"winter": {
		"canopy": Color(0.90, 0.95, 1.05), "grass": Color(0.74, 0.80, 0.92),
		"shrub": Color(0.85, 0.90, 1.00), "leaf_density": 0.06,
		"sun_color": Color(0.86, 0.92, 1.05), "sun_energy": 0.80,
	},
}

const ORDER: Array[String] = ["spring", "summer", "autumn", "winter"]
