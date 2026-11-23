class_name BoroughCity
extends RefCounted

## The V3 recipe (§41.1): five boroughs, each its own rotated grid
## with its own sampled pitch band, merged into ONE network; seams
## and landmarks divide them (§41.2); the pipeline of Chapters
## 39-40 then runs per borough, unchanged. Data-first throughout.
##
## Project integration notes:
## - The borough table, the shoreline test and the landmark
##   exclusion are injectable (set_borough_table / set_shore_test /
##   set_landmark_exclusion) — Chapter 42 §42.2 names exactly these
##   seams. Chapter 41's constants remain the defaults, so step 10
##   is untouched by step 11's needs.
## - road_ranges / block_ranges record which slice of the shared
##   network / block list each borough produced, so the stage can
##   draw per-borough builders and apply per-borough character caps
##   without re-deriving ownership.

# The borough table IS the recipe. Rotations differ by 15-32
# degrees between neighbours; pitch bands are sampling ranges,
# never fixed pitches (the "too textbook" lesson, Ch 37).
const BOROUGHS: Array[Dictionary] = [
	{"name": "downtown", "centre": Vector2(0, 40),
		"angle_deg": -8.0, "pitch": Vector2(55, 75),
		"extent": Vector2(330, 250), "character": "office"},
	{"name": "old_town", "centre": Vector2(-40, 265),
		"angle_deg": 24.0, "pitch": Vector2(40, 60),
		"extent": Vector2(300, 170), "character": "apartment"},
	{"name": "north_residential", "centre": Vector2(-30, -265),
		"angle_deg": -17.0, "pitch": Vector2(82, 112),
		"extent": Vector2(360, 190), "character": "house"},
	{"name": "south_residential", "centre": Vector2(150, 240),
		"angle_deg": 7.0, "pitch": Vector2(85, 120),
		"extent": Vector2(340, 200), "character": "house"},
	{"name": "industrial", "centre": Vector2(330, -190),
		"angle_deg": -32.0, "pitch": Vector2(70, 95),
		"extent": Vector2(190, 170), "character": "apartment"},
]

## Seams (§41.2): bands between boroughs where blocks are refused
## and crossings are chosen. Applied AFTER generate(): they edit
## the block list and ADD crossing logic roads to the network.
const SEAMS: Array[Dictionary] = [
	{"kind": "boulevard", "rect": Rect2(-380, -118, 760, 26),
		"crossings": [-140.0, 130.0]},
	{"kind": "park", "rect": Rect2(-330, 148, 660, 30),
		"crossings": [-60.0, 180.0]},
	{"kind": "river", "rect": Rect2(-430, 196, 860, 26),
		"crossings": [-180.0, 10.0, 210.0]},
]
const HILL_PARK_CENTRE: Vector2 = Vector2(-30, -390)
const HILL_PARK_RADIUS: float = 95.0

## Territorial arbitration (the overlap fix): neighbouring boroughs
## never generate through each other. Each borough's territory is
## the nearest-centre (Voronoi) cell of its centre, shrunk so that
## neighbours leave a green gap of BOUNDARY_GAP metres between
## them in total — each side yields half. Blocks AND street
## polylines are clipped to the shrunk territory at generation
## time; add_connectors() then joins the territories with avenues,
## and reserve_roads() carves every road's reserve band out of the
## land, so no block can stand on any road.
const BOUNDARY_GAP: float = 16.0

var _network: RoadNetwork
var _terrain: TerrainHeight
var _master_seed: int

# Per-borough products, kept for Chapters 39-40's pipeline + census.
var borough_blocks: Array[Dictionary] = [] # block + "borough" key

# Injectable recipe pieces (Chapter 42's seams; defaults = Ch 41).
var _table: Array = BOROUGHS.duplicate()
var _shore_test: Callable = Callable() # centre -> bool (is land)
var _landmark_centre: Vector2 = HILL_PARK_CENTRE
var _landmark_radius: float = HILL_PARK_RADIUS

# Ownership records: {name, first, last} index ranges.
var road_ranges: Array[Dictionary] = []
var block_ranges: Array[Dictionary] = []

# Connector avenues added by add_connectors(): {from, to, points,
# total} per pair, in (i, j) table order.
var connector_routes: Array[Dictionary] = []

# Per-borough clipping planes for the shrunk territory, parallel to
# _table: each entry is an Array of {point, dir} planes, inside <=>
# (p - point).dot(dir) <= 0. Built by generate().
var _territory_planes: Array = []


func _init(network: RoadNetwork, terrain: TerrainHeight,
		master_seed: int) -> void:
	_network = network
	_terrain = terrain
	_master_seed = master_seed


func set_borough_table(table: Array) -> void:
	_table = table.duplicate()


func set_shore_test(test: Callable) -> void:
	_shore_test = test


func set_landmark_exclusion(exclusion: Dictionary) -> void:
	_landmark_centre = exclusion["centre"]
	_landmark_radius = float(exclusion["radius"])


func borough_table() -> Array:
	return _table


func to_world(borough: Dictionary, local: Vector2) -> Vector2:
	var a: float = deg_to_rad(float(borough["angle_deg"]))
	var c: float = cos(a)
	var s: float = sin(a)
	var rotated := Vector2(local.x * c - local.y * s,
		local.x * s + local.y * c)
	return rotated + borough["centre"]


func generate() -> void:
	_territory_planes = _build_territory_planes()
	for i in range(_table.size()):
		_generate_borough(_table[i], _territory_planes[i])


# The shrunk nearest-centre partition: for borough i, one plane per
# other borough j — the perpendicular bisector of the two centres,
# pushed BOUNDARY_GAP * 0.5 toward i, so the two shrunk cells leave
# the full gap green between them.
func _build_territory_planes() -> Array:
	var all: Array = []
	for i in range(_table.size()):
		var ci: Vector2 = _table[i]["centre"]
		var planes: Array = []
		for j in range(_table.size()):
			if i == j:
				continue
			var cj: Vector2 = _table[j]["centre"]
			var dir: Vector2 = (cj - ci).normalized()
			var point: Vector2 = (ci + cj) * 0.5 \
				- dir * (BOUNDARY_GAP * 0.5)
			planes.append({"point": point, "dir": dir})
		all.append(planes)
	return all


# --- Hand-rolled clipping (Sutherland-Hodgman against planes) -----
# Geometry2D.clip_polygons / exclude_polygons are NOT used anywhere
# in this file: in Godot 4.7.2 they return their input polygons as
# separate pieces (verified empirically during the overlap fix).
# intersect_polygons / merge_polygons behave as documented and are
# used for measurement only.

# Clip one polygon against one plane (inside: (p-point).dot(dir)<=0).
func _clip_polygon_plane(poly: PackedVector2Array, point: Vector2,
		dir: Vector2) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % poly.size()]
		var d_cur: float = (cur - point).dot(dir)
		var d_nxt: float = (nxt - point).dot(dir)
		if d_cur <= 0.0:
			out.append(cur)
		if (d_cur < 0.0 and d_nxt > 0.0) \
				or (d_cur > 0.0 and d_nxt < 0.0):
			var t: float = d_cur / (d_cur - d_nxt)
			out.append(cur + (nxt - cur) * t)
	return out


func _clip_polygon_planes(poly: PackedVector2Array,
		planes: Array) -> PackedVector2Array:
	var out: PackedVector2Array = poly
	for plane in planes:
		out = _clip_polygon_plane(out, plane["point"], plane["dir"])
		if out.is_empty():
			break
	return out


# Clip one segment against the plane list, parametrically. Returns
# [] when nothing survives, else [a, b] (the surviving endpoints).
func _clip_segment_planes(a: Vector2, b: Vector2,
		planes: Array) -> Array:
	var t0: float = 0.0
	var t1: float = 1.0
	for plane in planes:
		var point: Vector2 = plane["point"]
		var dir: Vector2 = plane["dir"]
		var da: float = (a - point).dot(dir)
		var db: float = (b - point).dot(dir)
		if da <= 0.0 and db <= 0.0:
			continue
		if da > 0.0 and db > 0.0:
			return []
		var t: float = da / (da - db)
		if da > 0.0:
			t0 = maxf(t0, t) # entering the kept side
		else:
			t1 = minf(t1, t) # leaving it
		if t0 > t1:
			return []
	return [a + (b - a) * t0, a + (b - a) * t1]


# Clip a polyline against the plane list. Returns an Array of runs
# (PackedVector2Array, >= 2 points each): a street that leaves the
# territory and re-enters survives as two runs, never as a chord
# drawn across the gap.
func _clip_polyline_planes(points: Array,
		planes: Array) -> Array:
	var runs: Array = []
	var current := PackedVector2Array()
	for i in range(points.size() - 1):
		var seg: Array = _clip_segment_planes(points[i],
			points[i + 1], planes)
		if seg.is_empty():
			if current.size() >= 2:
				runs.append(current)
			current = PackedVector2Array()
			continue
		if current.size() > 0 and current[current.size() - 1] \
				.distance_squared_to(seg[0]) > 0.0001:
			if current.size() >= 2:
				runs.append(current)
			current = PackedVector2Array()
		if current.is_empty():
			current.append(seg[0])
		current.append(seg[1])
	if current.size() >= 2:
		runs.append(current)
	return runs


func _generate_borough(borough: Dictionary, planes: Array) -> void:
	var road_first: int = _network.logic_roads.size()
	var block_first: int = borough_blocks.size()
	# 1. Generate in the borough's LOCAL frame, on a scratch network:
	#    Chapter 37's generator, unmodified, in local coordinates.
	var scratch := RoadNetwork.new(_terrain)
	var ext: Vector2 = borough["extent"]
	scratch.generate_grid(
		Rect2(-ext * 0.5, ext), borough["pitch"].x, borough["pitch"].y,
		_master_seed + String(borough["name"]).hash())
	# 2. Extract this borough's blocks LOCALLY (Ch 39, unmodified),
	#    then transform their polygons into the world frame.
	var bp := BlockParcels.new(scratch, _terrain)
	for block in bp.extract_grid_blocks():
		if block["kind"] != "land":
			continue
		var world_poly := PackedVector2Array()
		for p in block["polygon"]:
			world_poly.append(to_world(borough, p))
		# Territorial arbitration: the block is clipped to this
		# borough's shrunk territory BEFORE any other test, so no
		# part of it can lie in a neighbour's land or in the gap.
		var clipped: PackedVector2Array = _clip_polygon_planes(
			world_poly, planes)
		if clipped.size() < 3:
			continue
		var area: float = BlockParcels._polygon_area(clipped)
		if area < BlockParcels.MIN_BLOCK_AREA:
			continue
		var centre: Vector2 = BlockParcels._polygon_centre(clipped)
		if _shore_test.is_valid():
			if not bool(_shore_test.call(centre)):
				continue # the real shoreline clips boroughs
		elif not _inside_island(clipped):
			continue # the shoreline clips boroughs, not vice versa
		block["polygon"] = clipped
		block["centre"] = centre
		block["area"] = area
		block["borough"] = borough["name"]
		borough_blocks.append(block)
	# 3. Merge the scratch network's logic roads into the shared
	#    network, transformed. Segments are NOT merged — they are
	#    re-derived once, globally, by the caller (Ch 37's rule:
	#    derived data has exactly one producer).
	for road in scratch.logic_roads:
		var wpts: Array = []
		for p in road["points"]:
			wpts.append(to_world(borough, Vector2(p.x, p.z)))
		# Streets are clipped to the same shrunk territory: a grid
		# line that would cross into the neighbour (or the gap)
		# ends at the boundary instead.
		for run in _clip_polyline_planes(wpts, planes):
			var run_len: float = 0.0
			for i in range(run.size() - 1):
				run_len += run[i].distance_to(run[i + 1])
			if run.size() < 2 or run_len < 2.0:
				continue
			var pts := PackedVector3Array()
			for w in run:
				pts.append(Vector3(w.x,
					_terrain.height_at(w.x, w.y), w.y))
			_network.add_logic_road(pts, road["kind"])
	road_ranges.append({"name": borough["name"], "first": road_first,
		"last": _network.logic_roads.size() - 1})
	block_ranges.append({"name": borough["name"], "first": block_first,
		"last": borough_blocks.size() - 1})


# The organic island: an elongated ellipse whose radius is bent by
# three low-frequency sine terms (V3's shoreline). A block belongs
# to the city only if its centre is inside; shoreline blocks are
# clipped by omission at this scale, and §41.2's seams do the rest.
func _inside_island(poly: PackedVector2Array) -> bool:
	var centre: Vector2 = BlockParcels._polygon_centre(poly)
	var angle: float = atan2(centre.y / 290.0, centre.x / 430.0)
	var wobble: float = 1.0 + 0.10 * sin(angle * 3.0 + 1.7) \
		+ 0.06 * sin(angle * 5.0 + 0.4) + 0.04 * sin(angle * 8.0 + 2.9)
	var q: Vector2 = centre / Vector2(430.0, 290.0) / wobble
	return q.length() <= 1.0


func apply_seams() -> Array[Dictionary]:
	var bridges: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for block in borough_blocks:
		if _in_any_seam(block["centre"]) \
				or block["centre"].distance_to(_landmark_centre) \
					< _landmark_radius:
			continue # the band keeps the land; no block survives it
		kept.append(block)
	borough_blocks = kept
	# Block ranges were recorded against the pre-seam list; seams
	# only REMOVE blocks, so ranges are rebuilt by borough key.
	_rebuild_block_ranges()
	for seam in SEAMS:
		var rect: Rect2 = seam["rect"]
		for cx in seam["crossings"]:
			var a := Vector3(cx, 0.0, rect.position.y - 14.0)
			var b := Vector3(cx, 0.0, rect.end.y + 14.0)
			a.y = _terrain.height_at(a.x, a.z)
			b.y = _terrain.height_at(b.x, b.z)
			_network.add_logic_road(PackedVector3Array([a, b]),
				"avenue" if seam["kind"] != "river" else "street")
			if seam["kind"] == "river":
				# A bridge record for the builder: the span over the
				# band, deck at the higher bank (Ch 38's rule).
				bridges.append({"from": Vector2(cx, rect.position.y),
					"to": Vector2(cx, rect.end.y),
					"deck_y": maxf(a.y, b.y) + 1.2})
	return bridges


func _rebuild_block_ranges() -> void:
	block_ranges.clear()
	var current: String = ""
	for i in range(borough_blocks.size()):
		var name: String = borough_blocks[i]["borough"]
		if name != current:
			block_ranges.append({"name": name, "first": i, "last": i})
			current = name
		else:
			block_ranges[block_ranges.size() - 1]["last"] = i


func _in_any_seam(point: Vector2) -> bool:
	for seam in SEAMS:
		if seam["rect"].has_point(point):
			return true
	return false


## The diagonal avenue: one logic road across downtown at 24
## degrees off its grid, drawn AFTER the grid — Chapter 37's
## rebuild_segments() will clip every street it crosses, and the
## blocks it slices are re-cut in §41.3's placement pass.
func add_diagonal_avenue() -> void:
	var borough: Dictionary = _table[0] # downtown
	var dir := Vector2(1.0, 0.0).rotated(
		deg_to_rad(float(borough["angle_deg"]) + 24.0))
	var centre: Vector2 = borough["centre"]
	var a2: Vector2 = centre - dir * 260.0
	var b2: Vector2 = centre + dir * 260.0
	var a := Vector3(a2.x, 0.0, a2.y)
	var b := Vector3(b2.x, 0.0, b2.y)
	a.y = _terrain.height_at(a.x, a.z)
	b.y = _terrain.height_at(b.x, b.z)
	_network.add_logic_road(PackedVector3Array([a, b]), "avenue")


## Connectors: avenues joining TRUE neighbours — pairs whose
## centre-midpoint is still nearest to one of the two centres (the
## midpoint test is exactly "these two territories touch"). If the
## candidate graph alone leaves the city in pieces, the shortest
## bridging pairs are added until it is one graph. Each pair is
## routed centre-to-centre over the terrain's own cost field (a
## fresh HighwayRouter, no blockers); a pair the router refuses
## falls back to the straight line, loudly.
func add_connectors() -> void:
	connector_routes.clear()
	var n: int = _table.size()
	var centres: Array = []
	for borough in _table:
		centres.append(borough["centre"])
	var pairs: Array = [] # Array of Vector2i(i, j), i < j
	var in_pairs: Dictionary = {}
	for i in range(n):
		for j in range(i + 1, n):
			var mid: Vector2 = (centres[i] + centres[j]) * 0.5
			var nearest: int = 0
			var best_d: float = INF
			for k in range(n):
				var d: float = mid.distance_squared_to(centres[k])
				if d < best_d:
					best_d = d
					nearest = k
			if nearest == i or nearest == j:
				pairs.append(Vector2i(i, j))
				in_pairs["%d:%d" % [i, j]] = true
	# Connectivity completion: while the pair graph is in pieces,
	# add the shortest pair that bridges two pieces.
	while true:
		var comp: Dictionary = _pair_components(pairs, n)
		var ncomp: Dictionary = {}
		for v in comp.values():
			ncomp[v] = true
		if ncomp.size() <= 1:
			break
		var best_pair := Vector2i(-1, -1)
		var best_len: float = INF
		for i in range(n):
			for j in range(i + 1, n):
				if in_pairs.has("%d:%d" % [i, j]):
					continue
				if comp[i] == comp[j]:
					continue
				var len: float = centres[i].distance_to(centres[j])
				if len < best_len:
					best_len = len
					best_pair = Vector2i(i, j)
		if best_pair.x < 0:
			break # no bridging pair exists (cannot happen for n >= 2)
		pairs.append(best_pair)
		in_pairs["%d:%d" % [best_pair.x, best_pair.y]] = true
	pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	for pair in pairs:
		var i: int = pair.x
		var j: int = pair.y
		var router := HighwayRouter.new(_terrain)
		var route: Dictionary = router.find_route(centres[i], centres[j])
		var points := PackedVector3Array()
		var total: float = 0.0
		if route.is_empty() or (route["points"] as PackedVector3Array).is_empty():
			print("add_connectors: WARNING no route ",
				_table[i]["name"], " -> ", _table[j]["name"],
				"; straight-line fallback")
			var a2: Vector2 = centres[i]
			var b2: Vector2 = centres[j]
			points.append(Vector3(a2.x,
				_terrain.height_at(a2.x, a2.y), a2.y))
			points.append(Vector3(b2.x,
				_terrain.height_at(b2.x, b2.y), b2.y))
			total = a2.distance_to(b2)
		else:
			points = route["points"]
			total = float(route["total"])
		_network.add_logic_road(points, "avenue")
		connector_routes.append({"from": _table[i]["name"],
			"to": _table[j]["name"], "points": points,
			"total": total})
		print("add_connectors: ", _table[i]["name"], " -> ",
			_table[j]["name"], " total=", snappedf(total, 0.1),
			" points=", points.size())


func _pair_components(pairs: Array, n: int) -> Dictionary:
	var parent: Array = []
	for i in range(n):
		parent.append(i)
	for pair in pairs:
		var ra: int = pair.x
		while parent[ra] != ra:
			ra = parent[ra]
		var rb: int = pair.y
		while parent[rb] != rb:
			rb = parent[rb]
		if ra != rb:
			parent[ra] = rb
	var comp: Dictionary = {}
	for i in range(n):
		var r: int = i
		while parent[r] != r:
			r = parent[r]
		comp[i] = r
	return comp


static func _intersect_area(a: PackedVector2Array,
		b: PackedVector2Array) -> float:
	var total: float = 0.0
	for piece in Geometry2D.intersect_polygons(a, b):
		total += BlockParcels._polygon_area(piece)
	return total


static func _polygon_aabb(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for pt in poly:
		r = r.expand(pt)
	return r


## The public overlap census (the stage cert lines quote it):
## pairwise block <-> block overlap over borough_blocks, broadphase
## + intersect_polygons, counting only overlaps above 0.05 m^2.
func count_block_overlaps() -> int:
	var count: int = 0
	var aabbs: Array = []
	for block in borough_blocks:
		aabbs.append(_polygon_aabb(block["polygon"]))
	for i in range(borough_blocks.size()):
		for j in range(i + 1, borough_blocks.size()):
			if not (aabbs[i] as Rect2).intersects(aabbs[j]):
				continue
			if _intersect_area(borough_blocks[i]["polygon"],
					borough_blocks[j]["polygon"]) > 0.05:
				count += 1
	return count


# One convex difference: subject \ band, where band is a CONVEX
# quad. Successive half-plane decomposition: for each edge plane of
# the band, the part of the remainder OUTSIDE that plane is a final
# piece, and the part INSIDE continues to the next plane; whatever
# is still inside after every plane is the band's own share and is
# discarded. Hand-rolled on _clip_polygon_plane — no
# exclude_polygons / clip_polygons (see the clipping note above).
func _convex_difference(subject: PackedVector2Array,
		band: PackedVector2Array) -> Array:
	var pieces: Array = []
	var band_centre: Vector2 = BlockParcels._polygon_centre(band)
	var current: PackedVector2Array = subject
	for e in range(band.size()):
		if current.is_empty():
			break
		var p0: Vector2 = band[e]
		var p1: Vector2 = band[(e + 1) % band.size()]
		var edge: Vector2 = p1 - p0
		if edge.length() < 0.0001:
			continue
		var dir_e: Vector2 = edge.normalized()
		var normal := Vector2(-dir_e.y, dir_e.x)
		if (band_centre - p0).dot(normal) > 0.0:
			normal = -normal # now inside <=> (p - p0).dot(normal) <= 0
		var outside: PackedVector2Array = _clip_polygon_plane(
			current, p0, -normal)
		if outside.size() >= 3:
			pieces.append(outside)
		current = _clip_polygon_plane(current, p0, normal)
	return pieces


## The road reserve pass: EVERY logic road's reserve band is carved
## out of the land, in one unified pass — borough streets, seam
## crossings, the diagonal avenue, connectors, and (step 11) the
## south-shore highway alike. Bands: street -> BlockParcels.
## ROAD_RESERVE (5.5 m half width), avenue / highway -> 7.5 m.
## Returns {dropped, clipped}: blocks removed outright, and blocks
## whose land changed (area lost or split into pieces).
func reserve_roads() -> Dictionary:
	# 0. Stub pruning (the overlap fix, forced by the reachability
	#    gate): territorial clipping and the seam design leave a few
	#    logic roads that touch NOTHING — a grid fragment that only
	#    grazes a territory corner, a seam crossing whose streets
	#    were clipped away. rebuild_segments() would render each as
	#    its own 2-node component, forever "unconnected". Roads are
	#    nodes of a crossing graph (edge = a shared polyline point
	#    at RoadNetwork's 1 cm key, or a proper segment crossing);
	#    only the largest component is a road system, so the rest
	#    are removed here — loudly, one print per road — before any
	#    band is carved. road_ranges are repaired for removed
	#    borough roads.
	var stubs: int = _prune_stub_roads()
	if stubs > 0:
		print("reserve_roads: pruned ", stubs, " stub logic roads")
	# 1. The reserve bands: one convex quad per polyline segment.
	var bands: Array = []
	var band_aabbs: Array = []
	for road in _network.logic_roads:
		var half: float = BlockParcels.ROAD_RESERVE \
			if String(road["kind"]) == "street" else 7.5
		var pts: PackedVector3Array = road["points"]
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var d: Vector2 = b - a
			if d.length() < 0.01:
				continue
			var perp: Vector2 = Vector2(-d.y, d.x).normalized() * half
			var quad := PackedVector2Array(
				[a + perp, b + perp, b - perp, a - perp])
			bands.append(quad)
			band_aabbs.append(_polygon_aabb(quad))
	# 2. Subtract the bands from every block.
	var out: Array[Dictionary] = []
	var dropped: int = 0
	var clipped_count: int = 0
	for block in borough_blocks:
		var block_aabb: Rect2 = _polygon_aabb(block["polygon"])
		var pieces: Array = [block["polygon"]]
		for bi in range(bands.size()):
			if pieces.is_empty():
				break
			if not block_aabb.intersects(band_aabbs[bi]):
				continue
			var next: Array = []
			for piece in pieces:
				if _intersect_area(piece, bands[bi]) <= 0.05:
					next.append(piece)
					continue
				for sub in _convex_difference(piece, bands[bi]):
					if (sub as PackedVector2Array).size() >= 3:
						next.append(sub)
			pieces = next
		var kept_area: float = 0.0
		var kept: Array = []
		for piece in pieces:
			var area: float = BlockParcels._polygon_area(piece)
			if area >= BlockParcels.MIN_BLOCK_AREA:
				kept.append(piece)
				kept_area += area
		if kept.is_empty():
			dropped += 1
			continue
		if kept.size() != 1 or kept_area < float(block["area"]) - 0.05:
			clipped_count += 1
		for piece in kept:
			var nb: Dictionary = block.duplicate()
			nb["polygon"] = piece
			nb["area"] = BlockParcels._polygon_area(piece)
			nb["centre"] = BlockParcels._polygon_centre(piece)
			out.append(nb)
	borough_blocks = out
	_rebuild_block_ranges()
	var overlaps: int = count_block_overlaps()
	print("reserve_roads: block overlaps after pass = ", overlaps)
	print("reserve_roads: dropped=", dropped, " clipped=", clipped_count,
		" blocks=", borough_blocks.size())
	return {"dropped": dropped, "clipped": clipped_count}


# Road-crossing graph components over _network.logic_roads, and
# removal of every road outside the largest component. Returns the
# number of roads removed.
func _prune_stub_roads() -> int:
	var roads: Array = _network.logic_roads
	if roads.size() <= 1:
		return 0
	# Shared-point edges (RoadNetwork._key: a 1 cm grid).
	var key_roads: Dictionary = {} # Vector2i -> Array of road idx
	for r in range(roads.size()):
		var seen: Dictionary = {}
		for p in roads[r]["points"]:
			var k := Vector2i(roundi(p.x * 100.0),
				roundi(p.z * 100.0))
			if seen.has(k):
				continue
			seen[k] = true
			if not key_roads.has(k):
				key_roads[k] = []
			key_roads[k].append(r)
	var parent: Array = []
	for r in range(roads.size()):
		parent.append(r)
	var find_root := func(x: int) -> int:
		var root: int = x
		while parent[root] != root:
			root = parent[root]
		return root
	for k in key_roads.keys():
		var list: Array = key_roads[k]
		for i in range(1, list.size()):
			var ra: int = find_root.call(list[0])
			var rb: int = find_root.call(list[i])
			if ra != rb:
				parent[ra] = rb
	# Crossing edges, with the same AABB broadphase rebuild_
	# segments() uses: only road pairs whose boxes meet can cross.
	var boxes: Array = []
	for r in range(roads.size()):
		boxes.append(_road_aabb(roads[r]["points"]))
	for a in range(roads.size()):
		for b in range(a + 1, roads.size()):
			if find_root.call(a) == find_root.call(b):
				continue
			if not (boxes[a] as Rect2).intersects(boxes[b]):
				continue
			if _roads_cross(roads[a]["points"], roads[b]["points"]):
				parent[find_root.call(a)] = find_root.call(b)
	# The largest component (most roads; ties -> lowest root) wins.
	var sizes: Dictionary = {}
	for r in range(roads.size()):
		var root: int = find_root.call(r)
		sizes[root] = int(sizes.get(root, 0)) + 1
	var main_root: int = -1
	var main_size: int = -1
	for root in sizes.keys():
		if int(sizes[root]) > main_size:
			main_size = int(sizes[root])
			main_root = root
	if main_size == roads.size():
		return 0
	var removed: Array = []
	for r in range(roads.size()):
		if find_root.call(r) != main_root:
			removed.append(r)
	for r in removed:
		var pts: PackedVector3Array = roads[r]["points"]
		print("reserve_roads: stub road #", r, " kind=",
			roads[r]["kind"], " from=", Vector2(pts[0].x, pts[0].z),
			" points=", pts.size(), " — touches nothing, removed")
	removed.sort()
	removed.reverse()
	for r in removed:
		_network.logic_roads.remove_at(r)
	# Repair road_ranges for the removed indices (original order).
	removed.sort()
	for rec in road_ranges:
		var first: int = int(rec["first"])
		var last: int = int(rec["last"])
		var shift_first: int = 0
		var shift_last: int = 0
		for r in removed:
			if r < first:
				shift_first += 1
			if r <= last:
				shift_last += 1
		rec["first"] = first - shift_first
		rec["last"] = last - shift_last
	return removed.size()


static func _road_aabb(pts: PackedVector3Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var min_x: float = pts[0].x
	var max_x: float = pts[0].x
	var min_z: float = pts[0].z
	var max_z: float = pts[0].z
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	return Rect2(min_x - 0.01, min_z - 0.01,
		(max_x - min_x) + 0.02, (max_z - min_z) + 0.02)


# Proper segment crossing in the XZ plane, mirroring
# RoadNetwork._segment_hit's strict-interior rule.
static func _roads_cross(pa: PackedVector3Array,
		pb: PackedVector3Array) -> bool:
	for i in range(pa.size() - 1):
		for j in range(pb.size() - 1):
			var r := Vector2(pa[i + 1].x - pa[i].x,
				pa[i + 1].z - pa[i].z)
			var sv := Vector2(pb[j + 1].x - pb[j].x,
				pb[j + 1].z - pb[j].z)
			var denom: float = r.x * sv.y - r.y * sv.x
			if absf(denom) < 0.000001:
				continue
			var qp := Vector2(pb[j].x - pa[i].x, pb[j].z - pa[i].z)
			var t: float = (qp.x * sv.y - qp.y * sv.x) / denom
			var u: float = (qp.x * r.y - qp.y * r.x) / denom
			if t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999:
				return true
	return false
