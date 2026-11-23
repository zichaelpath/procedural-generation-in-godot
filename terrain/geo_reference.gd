class_name GeoReference
extends RefCounted

## Converts real latitude/longitude into world XZ metres for a square
## heightmap whose SOUTH-WEST corner sits at (sw_lat, sw_lon) and whose
## world is centred on the origin. Equirectangular approximation:
## fine at city scale, wrong at continent scale — know which game
## you are making.

const METRES_PER_DEGREE_LAT: float = 111320.0

static func latlon_to_world(lat: float, lon: float,
		sw_lat: float, sw_lon: float, world_size_m: float) -> Vector2:
	var metres_per_degree_lon: float = METRES_PER_DEGREE_LAT * cos(deg_to_rad(sw_lat))
	var east_m: float = (lon - sw_lon) * metres_per_degree_lon
	var north_m: float = (lat - sw_lat) * METRES_PER_DEGREE_LAT
	# World x runs east from -size/2; world z runs SOUTH, so going
	# north from the south edge SUBTRACTS z from +size/2.
	var x: float = -world_size_m * 0.5 + east_m
	var z: float = world_size_m * 0.5 - north_m
	return Vector2(x, z)
