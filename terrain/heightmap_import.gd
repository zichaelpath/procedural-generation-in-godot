class_name HeightmapImport
extends RefCounted

## A heightmap SOURCE: image file in, height grid out. Sources never
## touch the scene tree — they produce data, exactly like the noise
## generator does. Downstream, nobody can tell the difference.

## Image row 0 is the TOP of the picture (the north edge, for a
## north-up QGIS export). Our grid row 0 sits at z = -size/2, which
## GeoReference (Listing 8.3) places at the NORTH edge too — so for
## this source the rows already agree and no flip is applied.
## FIX (captures): Listing 8.1 prints FLIP_Z = true on the claim that
## "grid row 0 is the SOUTH edge", but Listing 5.2's grid_to_world()
## and Listing 8.3's z = size/2 - north_m put row 0 at the north
## edge. With the flip on, the terrain lands mirrored north-south
## and Chapter 8's own landmark test convicts it: the Mount Royal
## lookout read 241.8 world units (~121 m, biome Grassland) instead
## of ~409 (Rock/Snow country), and only 1 of 11 St Lawrence
## centreline samples classified as Ocean. The flag stays per-source;
## a paint editor may still need it the other way.
const FLIP_Z: bool = false

# Returns {"heights": PackedFloat32Array, "points": int} with heights
# in METRES, or an empty Dictionary on failure.
static func import_grid(path: String, elev_range_m: float,
		exaggeration: float) -> Dictionary:
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("HeightmapImport: could not load " + path)
		return {}
	if img.is_compressed():
		img.decompress()
	var side: int = img.get_width()
	if img.get_height() != side:
		push_error("HeightmapImport: image must be square, got "
				+ str(side) + "x" + str(img.get_height()))
		return {}
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(side * side)
	var scale: float = elev_range_m * exaggeration
	for gz in range(side):
		var row: int = (side - 1 - gz) if FLIP_Z else gz
		for gx in range(side):
			# .r is brightness for greyscale sources — and for 16-bit
			# files it carries the fine steps through the SAME call.
			# The precision lives in the file, not in the code.
			var brightness: float = img.get_pixel(gx, row).r
			heights[gz * side + gx] = brightness * scale
	return {"heights": heights, "points": side}
