class_name OsmImport
extends RefCounted

## Reads an Overpass JSON export and converts its ways into world-space
## polylines through GeoReference, using the SAME origin as the DEM
## import. One origin for every layer is the whole trick.

# Returns an Array of Dictionaries: {"highway": String, "points":
# PackedVector2Array}. Ways missing geometry are skipped, never guessed.
static func load_roads(json_path: String, sw_lat: float, sw_lon: float,
		world_size_m: float) -> Array:
	var text: String = FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		push_error("OsmImport: could not read " + json_path)
		return []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("OsmImport: JSON did not parse as an object")
		return []
	var roads: Array = []
	var elements: Array = parsed.get("elements", [])
	for element in elements:
		if typeof(element) != TYPE_DICTIONARY:
			continue
		if element.get("type", "") != "way":
			continue
		var geometry: Array = element.get("geometry", [])
		if geometry.size() < 2:
			continue
		var points: PackedVector2Array = PackedVector2Array()
		for node in geometry:
			var p: Vector2 = GeoReference.latlon_to_world(
					float(node.get("lat", 0.0)), float(node.get("lon", 0.0)),
					sw_lat, sw_lon, world_size_m)
			points.append(p)
		var tags: Dictionary = element.get("tags", {})
		roads.append({
			"highway": String(tags.get("highway", "unclassified")),
			"points": points,
		})
	return roads
