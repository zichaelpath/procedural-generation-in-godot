class_name TerrainGrader
extends RefCounted

## Terrain grading for the Part VIII borough cities (steps 10-11).
## The defect this fixes: road ribbons are built from a handful of
## height samples per segment, so on any slope the RAW terrain —
## which answers height_at() everywhere between those samples —
## pokes through the asphalt, and blocks stand on unlevelled
## relief. Grading rewrites the TerrainHeight grid itself (the
## same heights-array surgery city_stage._shape_highway_terrain()
## performs for steps 4-5), in two passes, so that mesh, ribbons,
## parcels and placement all read one graded surface:
##
##   1. TERRITORY grading — every borough gets ONE reference
##      height: the mean of the base heights over the land cells
##      of its shrunk-territory core (nearest-centre partition,
##      BoroughCity's BOUNDARY_GAP shrink, eroded a further
##      CORE_ERODE metres so the average is taken from the
##      borough's heartland, not its contested edge). Cells blend
##      toward their nearest borough's reference with weight 1
##      inside the shrunk territory, smoothstepping to 0 across
##      the boundary gap plus FALLOFF metres beyond it, so
##      neighbouring blends overlap smoothly IN the gap. A cell
##      farther than (borough half-diagonal + gap/2 + FALLOFF)
##      from the centre is open countryside/shore and is never
##      touched — the island is NOT flattened, only the city land.
##      TERRITORY DELTA CAP: the territory pass may move any
##      one cell by at most TERRITORY_MAX_DELTA metres. Grading
##      civilizes a borough’s building land; it does not move
##      mountains — relief beyond the cap is terrain the city
##      negotiates with, and the corridor pass still benches
##      roads through it. The corridor pass is NOT capped: a
##      road’s bench must reach its surveyed profile exactly.
##      (Uncapped, step 11’s territory pass pulled the Mount
##      Royal summit-area vertex 328.9 m toward the plateau
##      reference — the mountain is a landmark, not a grading
##      error.)
##      If a borough has too few land core cells (an offshore
##      centre), its reference falls back to the height AT the
##      centre. Land-only averaging is deliberate: a city's grade
##      is its land's average, not the river's — counting water
##      cells would drag a riverside borough's reference below
##      its own streets.
##
##   2. CORRIDOR grading — for every logic road (the FINAL set:
##      after connectors and highway routing), a longitudinal
##      profile is surveyed from the post-territory surface at
##      the polyline points and smoothed with a 5-point moving
##      average (2 neighbours each side; polyline points sit one
##      street pitch apart, so the window spans ~2 blocks).
##      Every grid cell within the ribbon half width + SHOULDER
##      of a polyline segment is pulled toward the profile height
##      at its closest point: weight 1 at or inside the half
##      width — extended one grid cell (capped at FLAT_EXTRA_CAP)
##      past the edge, because bilinear interpolation saddles any
##      cell whose corners straddle the flat's boundary — then
##      smoothstep to 0 across SHOULDER. The whole corridor pass
##      runs TWICE: the second, settle pass re-surveys profiles
##      from the graded surface so crossing streets agree at
##      junctions (see grade_city()). Where
##      corridors overlap, the STRONGEST claim wins (max weight;
##      ties keep the earlier road in logic_roads order) — one
##      deterministic winner per cell, never an average of two
##      streets' grades. (An equal-weight HIGHER-target rule was
##      tried and measured WORSE — 2.70% vs 2.28% poking samples
##      on step 10: the raised junction patch bulges across the
##      higher street's own ribbon. First-wins is the shipped
##      rule.)
##
## Deterministic and seed-stable: no RNG anywhere; every loop is
## over grid indices or logic_roads order. Call AFTER
## reserve_roads() (the final road set exists) and BEFORE
## rebuild_segments()/subdivide/placement/draws; grade_city()
## ends with terrain.refresh_climate() so biome-derived answers
## (shore tests, zoning, slope vetoes) read the graded heights.

const FALLOFF: float = 24.0 # m past the boundary where weight reaches 0
const CORE_ERODE: float = 12.0 # extra erosion for the reference core
const MIN_CORE_CELLS: int = 8 # below this, fall back to centre height
const SHOULDER: float = 8.0 # m of graded shoulder past the ribbon edge
const FLAT_EXTRA_CAP: float = 8.0 # cap on the one-cell flat extension
const HIGHWAY_HALF_WIDTH: float = 4.5 # RoadBuilder builds spans 9.0 m wide
const TERRITORY_MAX_DELTA: float = 25.0 # per-cell |delta h| cap, territory pass only


static func ribbon_half_width(kind: String) -> float:
	match kind:
		"avenue":
			return RoadBuilder.AVENUE_WIDTH * 0.5
		"highway":
			return HIGHWAY_HALF_WIDTH
		_:
			return RoadBuilder.STREET_WIDTH * 0.5


## Grade `terrain` for the city on `network` with the given
## borough table (entries carry centre / extent, as
## BoroughCity.borough_table() publishes). Returns the cert stats:
## cells touched by either pass and the largest |height change|.
static func grade_city(terrain: TerrainHeight, network: RoadNetwork,
		boroughs: Array) -> Dictionary:
	var stats: Dictionary = {
		"territory_cells": 0, "territory_max_delta": 0.0,
		"corridor_cells": 0,
		"cells_touched": 0, "max_delta": 0.0,
		"references": {}}
	if terrain.noise_backed or terrain.heights.is_empty():
		# Grid surgery needs a grid; the noise-backed capstone
		# grades through TerrainHeight's city edits instead.
		return stats
	var before: PackedFloat32Array = terrain.heights.duplicate()
	_grade_territories(terrain, boroughs, stats)
	_grade_corridors(terrain, network, stats)
	# Settle pass: a second corridor survey over the graded
	# surface. At a junction the two crossing streets' smoothed
	# profiles generally disagree about the junction's height;
	# the first pass surfaces the winner's target there, so the
	# re-surveyed profiles bend toward the surface that actually
	# exists and the second application pulls the losing street's
	# band into agreement instead of leaving a step at the kerb.
	_grade_corridors(terrain, network, stats)
	var touched: int = 0
	var max_delta: float = 0.0
	for i in range(terrain.heights.size()):
		var d: float = absf(terrain.heights[i] - before[i])
		if d > 0.0001:
			touched += 1
			max_delta = maxf(max_delta, d)
	stats["cells_touched"] = touched
	stats["max_delta"] = snappedf(max_delta, 0.001)
	terrain.refresh_climate()
	print("terrain grading: references=", stats["references"],
		" territory_cells=", stats["territory_cells"],
		" territory_max_delta=", stats["territory_max_delta"],
		" corridor_cells=", stats["corridor_cells"],
		" cells_touched=", touched,
		" max_delta=", stats["max_delta"])
	return stats


# --- Pass 1: territories -------------------------------------------------------

# Signed clearance of point p from borough i's shrunk territory:
# the minimum, over all other boroughs j, of the point's distance
# inside the bisector plane with j, minus the gap shrink. >= 0
# means inside the shrunk territory; larger = deeper inside.
static func _territory_clearance(p: Vector2, i: int,
		centres: Array) -> float:
	var ci: Vector2 = centres[i]
	var best: float = INF
	for j in range(centres.size()):
		if j == i:
			continue
		var cj: Vector2 = centres[j]
		var dir: Vector2 = cj - ci
		var dist: float = dir.length()
		if dist < 0.01:
			continue
		dir /= dist
		var mid: Vector2 = (ci + cj) * 0.5
		var inside: float = (mid - p).dot(dir) - BoroughCity.BOUNDARY_GAP * 0.5
		best = minf(best, inside)
	return best


static func _grade_territories(terrain: TerrainHeight,
		boroughs: Array, stats: Dictionary) -> void:
	var centres: Array = []
	var reach: Array = [] # max influence distance per borough
	for b in boroughs:
		centres.append(b["centre"])
		var ext: Vector2 = b.get("extent", Vector2(300, 300))
		reach.append(ext.length() * 0.5 + BoroughCity.BOUNDARY_GAP * 0.5
			+ FALLOFF)
	var w: int = terrain.row_width()
	# Reference heights: mean of the LAND cells of each borough's
	# eroded core (nearest centre + clearance >= gap/2 already in
	# _territory_clearance's terms: core = clearance >= CORE_ERODE).
	var sums: Array = []
	var counts: Array = []
	for i in range(centres.size()):
		sums.append(0.0)
		counts.append(0)
	for iz in range(w):
		for ix in range(w):
			var wp: Vector2 = terrain.grid_to_world(ix, iz)
			var bi: int = _nearest_centre(centres, wp)
			if wp.distance_to(centres[bi]) > reach[bi]:
				continue
			if _territory_clearance(wp, bi, centres) < CORE_ERODE:
				continue
			var h: float = terrain.heights[terrain.index(ix, iz)]
			if h < terrain.sea_level:
				continue # land cells only (see header)
			sums[bi] += h
			counts[bi] += 1
	var refs: Array = []
	for i in range(centres.size()):
		var ref: float
		if int(counts[i]) >= MIN_CORE_CELLS:
			ref = float(sums[i]) / float(counts[i])
		else:
			var c: Vector2 = centres[i]
			ref = terrain.height_at(c.x, c.y) # offshore fallback
		refs.append(ref)
		stats["references"][String(boroughs[i].get("name", i))] = \
			snappedf(ref, 0.01)
	# Blend: weight 1 inside the shrunk territory (clearance >= 0),
	# smoothstep to 0 at clearance = -(gap/2 + FALLOFF) — the falloff
	# band spans the whole boundary gap and FALLOFF metres beyond
	# the bisector, so the two sides' blends overlap in the gap.
	var band: float = BoroughCity.BOUNDARY_GAP * 0.5 + FALLOFF
	var touched: int = 0
	var territory_max: float = 0.0
	for iz in range(w):
		for ix in range(w):
			var wp: Vector2 = terrain.grid_to_world(ix, iz)
			var bi: int = _nearest_centre(centres, wp)
			if wp.distance_to(centres[bi]) > reach[bi]:
				continue
			var cl: float = _territory_clearance(wp, bi, centres)
			var weight: float = 1.0 - smoothstep(0.0, band, -cl) \
				if cl < 0.0 else 1.0
			if weight <= 0.0:
				continue
			var idx: int = terrain.index(ix, iz)
			var target: float = lerpf(terrain.heights[idx],
				refs[bi], weight)
			# Territory delta cap: never move one cell more
			# than TERRITORY_MAX_DELTA toward its borough
			# reference — relief beyond the cap stays put
			# (see header: grading does not move mountains).
			var delta: float = clampf(target - terrain.heights[idx],
				-TERRITORY_MAX_DELTA, TERRITORY_MAX_DELTA)
			terrain.heights[idx] += delta
			territory_max = maxf(territory_max, absf(delta))
			touched += 1
	stats["territory_cells"] = touched
	stats["territory_max_delta"] = snappedf(territory_max, 0.001)


static func _nearest_centre(centres: Array, p: Vector2) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(centres.size()):
		var d: float = p.distance_squared_to(centres[i])
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Pass 2: corridors ---------------------------------------------------------

static func _grade_corridors(terrain: TerrainHeight,
		network: RoadNetwork, stats: Dictionary) -> void:
	var n: int = terrain.heights.size()
	var best_w := PackedFloat32Array()
	best_w.resize(n)
	var best_t := PackedFloat32Array()
	best_t.resize(n)
	var cell: float = terrain.cell_size()
	var w: int = terrain.row_width()
	for road in network.logic_roads:
		var pts: PackedVector3Array = road["points"]
		if pts.size() < 2:
			continue
		var half: float = ribbon_half_width(String(road["kind"]))
		# The weight-1 flat extends one grid cell past the ribbon
		# edge (capped): height_at() is bilinear, so a cell whose
		# far corners sit OUTSIDE the flat interpolates a saddle
		# that bulges over the ribbon edge. Grading every cell the
		# ribbon touches at full weight keeps the surface the
		# ribbon actually crosses planar with the profile.
		var flat: float = half + minf(terrain.cell_size(),
			FLAT_EXTRA_CAP)
		var reach_r: float = flat + SHOULDER
		# Longitudinal profile: surveyed heights at the polyline
		# points, smoothed with a 5-point moving average.
		var prof := PackedFloat32Array()
		prof.resize(pts.size())
		for i in range(pts.size()):
			prof[i] = terrain.height_at(pts[i].x, pts[i].z)
		var smooth := PackedFloat32Array()
		smooth.resize(pts.size())
		for i in range(pts.size()):
			var sum: float = 0.0
			var cnt: int = 0
			for k in range(maxi(0, i - 2), mini(pts.size(), i + 3)):
				sum += prof[k]
				cnt += 1
			smooth[i] = sum / float(cnt)
		# Cumulative along-lengths for profile interpolation.
		var cum := PackedFloat32Array()
		cum.resize(pts.size())
		for i in range(1, pts.size()):
			cum[i] = cum[i - 1] + Vector2(pts[i].x - pts[i - 1].x,
				pts[i].z - pts[i - 1].z).length()
		for s in range(pts.size() - 1):
			var a := Vector2(pts[s].x, pts[s].z)
			var b := Vector2(pts[s + 1].x, pts[s + 1].z)
			var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) \
				- Vector2(reach_r, reach_r)
			var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) \
				+ Vector2(reach_r, reach_r)
			var ix0: int = clampi(int(floor(
				(lo.x + terrain.world_size * 0.5) / cell)), 0, terrain.cells)
			var ix1: int = clampi(int(floor(
				(hi.x + terrain.world_size * 0.5) / cell)), 0, terrain.cells)
			var iz0: int = clampi(int(floor(
				(lo.y + terrain.world_size * 0.5) / cell)), 0, terrain.cells)
			var iz1: int = clampi(int(floor(
				(hi.y + terrain.world_size * 0.5) / cell)), 0, terrain.cells)
			var ab: Vector2 = b - a
			var len_sq: float = ab.length_squared()
			for iz in range(iz0, iz1 + 1):
				for ix in range(ix0, ix1 + 1):
					var wp: Vector2 = terrain.grid_to_world(ix, iz)
					var t: float = 0.0
					if len_sq > 0.0001:
						t = clampf((wp - a).dot(ab) / len_sq, 0.0, 1.0)
					var closest: Vector2 = a + ab * t
					var dist: float = wp.distance_to(closest)
					if dist > reach_r:
						continue
					var weight: float = 1.0 if dist <= flat else \
						1.0 - smoothstep(flat, reach_r, dist)
					var along: float = lerpf(cum[s], cum[s + 1], t)
					var target: float = _profile_at(smooth, cum, along)
					var idx: int = terrain.index(ix, iz)
					if weight > best_w[idx] + 0.000001:
						best_w[idx] = weight
						best_t[idx] = target
	var touched: int = 0
	for i in range(n):
		if best_w[i] > 0.0:
			terrain.heights[i] = lerpf(terrain.heights[i],
				best_t[i], best_w[i])
			touched += 1
	stats["corridor_cells"] = touched


static func _profile_at(smooth: PackedFloat32Array,
		cum: PackedFloat32Array, along: float) -> float:
	if smooth.size() == 1 or along <= 0.0:
		return smooth[0]
	if along >= cum[cum.size() - 1]:
		return smooth[smooth.size() - 1]
	for i in range(1, cum.size()):
		if along <= cum[i]:
			var span: float = cum[i] - cum[i - 1]
			var t: float = 0.0 if span < 0.0001 else \
				(along - cum[i - 1]) / span
			return lerpf(smooth[i - 1], smooth[i], t)
	return smooth[smooth.size() - 1]
