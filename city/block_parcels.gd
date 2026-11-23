class_name BlockParcels
extends RefCounted

## Blocks and parcels: the land the roads enclose, as data.
## A BLOCK is a polygon of buildable land, inset from the road
## centrelines by the road reserve. A PARCEL is a slice of a block
## with a measured frontage on a real street (§39.2). Data-first:
## this class returns Dictionaries and builds nothing.
##
## Project integration note: _polygon_area(), _polygon_centre() and
## _to_world() are static here. Chapter 40 calls BlockParcels.
## _to_world() and Chapter 41 calls BlockParcels._polygon_centre()
## through the CLASS, which Godot only allows for static functions;
## the listings print them as instance methods while their own
## later chapters call them statically. Static is the reading that
## makes all three chapters true at once (and instance calls to a
## static function still work, so Listing 39.2's own uses are
## unaffected).

const ROAD_RESERVE: float = 5.5 # half street + pavement, metres
const MIN_BLOCK_AREA: float = 220.0 # below this, land is verge

## Subdivision targets: Parts V–VII's real footprints (§39.2).
const TARGETS: Dictionary = {
	"house": {"w": Vector2(10.0, 16.0), "d": Vector2(18.0, 30.0)},
	"apartment": {"w": Vector2(24.0, 40.0), "d": Vector2(20.0, 30.0)},
	"office": {"w": Vector2(30.0, 45.0), "d": Vector2(28.0, 45.0)},
}

var _network: RoadNetwork
var _terrain: TerrainHeight


func _init(network: RoadNetwork, terrain: TerrainHeight) -> void:
	_network = network
	_terrain = terrain


## Grid-family extraction: the block at cell (ix, iz) is the quad of
## nodes (ix,iz)-(ix+1,iz)-(ix+1,iz+1)-(ix,iz+1), inset. Cells whose
## inset area collapses (slivers at the map rim) are skipped, and
## cells mostly over water are returned as shore, not blocks.
func extract_grid_blocks() -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var cells: Dictionary = _network.grid_index
	# Find the index range from the keys themselves.
	var max_ix: int = 0
	var max_iz: int = 0
	for key in cells.keys():
		var cell: Vector2i = key
		max_ix = maxi(max_ix, cell.x)
		max_iz = maxi(max_iz, cell.y)
	for iz in range(max_iz):
		for ix in range(max_ix):
			var corners: Array[Vector2] = []
			var complete: bool = true
			for off in [Vector2i(0, 0), Vector2i(1, 0),
					Vector2i(1, 1), Vector2i(0, 1)]:
				var cell: Vector2i = Vector2i(ix, iz) + off
				if not cells.has(cell):
					complete = false
					break
				var n: Vector3 = _network.nodes[int(cells[cell])]
				corners.append(Vector2(n.x, n.z))
			if not complete:
				continue
			var poly: PackedVector2Array = _inset_quad(corners)
			if poly.size() != 4:
				continue
			var area: float = _polygon_area(poly)
			if area < MIN_BLOCK_AREA:
				continue
			var centre: Vector2 = _polygon_centre(poly)
			var kind: String = "land"
			if _terrain.biome_at_world(centre.x, centre.y) == 0:
				kind = "shore" # mostly water: not a building block
			blocks.append({"polygon": poly, "area": area,
				"centre": centre, "kind": kind,
				"cell": Vector2i(ix, iz)})
	return blocks


# Pull each edge of a (convex, ordered) quad inward by ROAD_RESERVE
# and re-intersect consecutive edges. Non-convex quads — warped
# grids can make them — fall back to a centre-shrink, which is
# conservative: it can only lose land, never gain road.
func _inset_quad(corners: Array[Vector2]) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for c in corners:
		centre += c
	centre /= 4.0
	var out := PackedVector2Array()
	for i in range(4):
		var prev: Vector2 = corners[(i + 3) % 4]
		var here: Vector2 = corners[i]
		var next: Vector2 = corners[(i + 1) % 4]
		var e1: Vector2 = (here - prev).normalized()
		var e2: Vector2 = (next - here).normalized()
		var n1 := Vector2(-e1.y, e1.x) # left normal of incoming edge
		var n2 := Vector2(-e2.y, e2.x)
		if n1.dot(here - centre) < 0.0:
			n1 = -n1
		if n2.dot(here - centre) < 0.0:
			n2 = -n2
		# n1/n2 point OUTWARD (away from centre) after the flips
		# above, so the edge lines move INWARD by the reserve —
		# with a plus sign here the "inset" EXPANDS every block by
		# 5.5 m a side and the census areas rat it out (a 52 m cell
		# "insets" to 3,969 m² instead of 1,681 m²).
		var l1_from: Vector2 = prev - n1 * ROAD_RESERVE
		var l1_dir: Vector2 = e1
		var l2_from: Vector2 = here - n2 * ROAD_RESERVE
		var l2_dir: Vector2 = e2
		var hit: Variant = Geometry2D.line_intersects_line(
			l1_from, l1_dir, l2_from, l2_dir)
		if hit == null:
			return PackedVector2Array() # degenerate: caller skips
		out.append(hit)
	return out


static func _polygon_area(poly: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


static func _polygon_centre(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(poly.size())


## The census every later chapter quotes: count, area spread, and
## how many blocks are NOT rectangles (warped/diagonal grids) —
## Chapter 41 compares its boroughs against this baseline.
func census(blocks: Array[Dictionary]) -> Dictionary:
	if blocks.is_empty():
		return {"count": 0, "min": 0.0, "median": 0.0, "max": 0.0,
			"non_rectangular": 0}
	var areas: Array[float] = []
	var non_rect: int = 0
	for b in blocks:
		areas.append(float(b["area"]))
		var poly: PackedVector2Array = b["polygon"]
		for i in range(poly.size()):
			var e1: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
			var e2: Vector2 = poly[(i + 2) % poly.size()] \
				- poly[(i + 1) % poly.size()]
			if absf(e1.normalized().dot(e2.normalized())) > 0.02:
				non_rect += 1
				break
	areas.sort()
	return {"count": blocks.size(), "min": areas[0],
		"median": areas[areas.size() / 2], "max": areas[-1],
		"non_rectangular": non_rect}


## Subdivide one block into parcels. Works in the block's local
## frame: origin at the frontage edge's start, +x along the street,
## +z into the block. Returns parcels in WORLD XZ polygons plus
## their local rects — Chapter 40 places buildings from the rects.
## Split targets are Parts V-VII's real footprints (§39.2).
func subdivide_block(block: Dictionary, master_seed: int,
		block_index: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		master_seed, SeedBank.STREAM_PARCELS)
	# Deterministic per block: skip ahead in the one parcels stream
	# by a block-derived count, so editing block 3 never re-rolls
	# block 4's lots. (The seed tree of Chapter 44 does this properly;
	# the skip is this part's honest placeholder, named as such.)
	for i in range(block_index * 7):
		rng.randf()
	var frame: Dictionary = _block_frame(block)
	var width: float = frame["width"]
	var depth: float = frame["depth"]
	var out: Array[Dictionary] = []
	_split(Rect2(0.0, 0.0, width, depth), true, rng, frame, out,
		block_index)
	# Parcel-containment guard (the overlap fix): _split cuts from
	# the block's frame RECTANGLE, so on a non-rectangular block a
	# parcel can escape the true polygon onto a road or a neighbour.
	# Each parcel must fit inside the block's polygon; one that
	# escapes is shrunk about its position corner (x0.9 per try, no
	# RNG draws — determinism preserved) and retested, up to 24
	# times, and dropped if it still escapes or either dimension
	# falls below 6 m. On a rectangular block every parcel corner
	# lies on or inside the edges, so the first test passes at full
	# size and rectangular blocks are provably unaffected.
	var block_poly: PackedVector2Array = block["polygon"]
	var kept: Array[Dictionary] = []
	for parcel in out:
		var fitted: Dictionary = _fit_parcel(parcel, block_poly,
			frame, block_index)
		if not fitted.is_empty():
			kept.append(fitted)
	return kept


# The fit test behind the guard: intersection area of the parcel's
# world polygon with the block's polygon must cover the parcel
# (0.5 m^2 of survey slack allowed). Returns the (possibly shrunk)
# parcel, or {} when it cannot be made to fit.
func _fit_parcel(parcel: Dictionary, block_poly: PackedVector2Array,
		frame: Dictionary, block_index: int) -> Dictionary:
	var current: Dictionary = parcel
	for attempt in range(25):
		var poly: PackedVector2Array = current["polygon"]
		var inter: float = 0.0
		for piece in Geometry2D.intersect_polygons(poly, block_poly):
			inter += _polygon_area(piece)
		if inter >= float(current["area"]) - 0.5:
			return current
		if attempt == 24:
			return {}
		var rect: Rect2 = current["local_rect"]
		var new_size: Vector2 = rect.size * 0.9
		if new_size.x < 6.0 or new_size.y < 6.0:
			return {}
		current = _make_parcel(Rect2(rect.position, new_size),
			bool(current["fronting"]), frame, block_index)
	return {}


# Recursive split. `fronting` is true when the rect's z=0 edge lies
# on the street. A fronting rect splits ALONG the street (vertical
# cuts) until its width fits a target band, then its depth is
# checked: excess depth becomes an interior parcel, labelled, never
# silently buildable.
func _split(rect: Rect2, fronting: bool, rng: RandomNumberGenerator,
		frame: Dictionary, out: Array[Dictionary],
		block_index: int) -> void:
	if rect.size.x > 46.0 and fronting:
		# Too wide for any single building: cut along the street.
		var cut: float = rng.randf_range(14.0, rect.size.x - 14.0)
		_split(Rect2(rect.position, Vector2(cut, rect.size.y)),
			fronting, rng, frame, out, block_index)
		_split(Rect2(rect.position + Vector2(cut, 0.0),
			Vector2(rect.size.x - cut, rect.size.y)),
			fronting, rng, frame, out, block_index)
		return
	if rect.size.y > 34.0 and fronting:
		# Too deep: the front band is the lot; the rear is interior.
		var lot_depth: float = rng.randf_range(20.0, 30.0)
		_split(Rect2(rect.position, Vector2(rect.size.x, lot_depth)),
			true, rng, frame, out, block_index)
		out.append(_make_parcel(
			Rect2(rect.position + Vector2(0.0, lot_depth),
				Vector2(rect.size.x, rect.size.y - lot_depth)),
			false, frame, block_index))
		return
	out.append(_make_parcel(rect, fronting, frame, block_index))


func _make_parcel(local: Rect2, fronting: bool, frame: Dictionary,
		block_index: int) -> Dictionary:
	var world: PackedVector2Array = PackedVector2Array()
	for corner in [local.position,
			local.position + Vector2(local.size.x, 0.0),
			local.position + local.size,
			local.position + Vector2(0.0, local.size.y)]:
		world.append(_to_world(frame, corner))
	return {"local_rect": local, "polygon": world,
		"frontage": local.size.x if fronting else 0.0,
		"depth": local.size.y, "area": local.get_area(),
		"fronting": fronting, "block": block_index,
		"frame": frame, "use": ""} # "use" is Chapter 40's to assign


# The block's local frame from its polygon: the longest edge is the
# frontage (it fronts the longest street — the usual case, and the
# exercises test where it isn't), origin at its start, depth = the
# farthest perpendicular distance of the remaining corners.
func _block_frame(block: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = block["polygon"]
	var best_i: int = 0
	var best_len: float = -1.0
	for i in range(poly.size()):
		var len: float = poly[i].distance_to(
			poly[(i + 1) % poly.size()])
		if len > best_len:
			best_len = len
			best_i = i
	var origin: Vector2 = poly[best_i]
	var axis: Vector2 = (poly[(best_i + 1) % poly.size()] - origin) \
		.normalized()
	var perp := Vector2(-axis.y, axis.x)
	var depth: float = 0.0
	for p in poly:
		depth = maxf(depth, absf((p - origin).dot(perp)))
	if perp.dot(_polygon_centre(poly) - origin) < 0.0:
		perp = -perp
	return {"origin": origin, "axis": axis, "perp": perp,
		"width": best_len, "depth": depth}


static func _to_world(frame: Dictionary, local: Vector2) -> Vector2:
	return frame["origin"] + frame["axis"] * local.x \
		+ frame["perp"] * local.y
