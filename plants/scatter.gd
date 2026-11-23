class_name Scatter
extends RefCounted

## Scatter utilities for the whole book (plants now, props and lamps
## later). All samplers work in 2D plan view (x, z carried in a Vector2)
## over a region and take the caller's RNG — a named stream — so a
## scatter is exactly replayable from the master seed.

## Plain uniform random: included mostly so you can SEE it clump.
static func random_points(region: Vector2, count: int, rng: RandomNumberGenerator) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for n in count:
		pts.append(Vector2(rng.randf_range(0.0, region.x), rng.randf_range(0.0, region.y)))
	return pts

## Jittered grid: one point per cell, offset randomly inside the cell.
## Soft minimum distance, very fast. The right tool for small,
## numerous things that read as texture rather than as individuals.
static func jittered_grid(region: Vector2, cell_size: float, rng: RandomNumberGenerator) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var cols: int = int(region.x / cell_size)
	var rows: int = int(region.y / cell_size)
	for cx in cols:
		for cz in rows:
			pts.append(Vector2(
				(float(cx) + rng.randf()) * cell_size,
				(float(cz) + rng.randf()) * cell_size))
	return pts

## Bridson Poisson-disc sampling (2007): guarantees min_dist between
## every pair of returned points. Candidates are born in the ANNULUS
## (the ring between min_dist and 2*min_dist) around an active point,
## so coverage grows outward like a crystal instead of peppering the
## region and leaving voids. Grid acceleration: cell = min_dist /
## sqrt(2) holds at most one point (see the walkthrough), so a
## candidate only ever checks the surrounding 5x5 cells.
static func poisson_disc(region: Vector2, min_dist: float, rng: RandomNumberGenerator, tries: int = 30) -> Array[Vector2]:
	var cell: float = min_dist / sqrt(2.0)
	var cols: int = int(ceil(region.x / cell))
	var rows: int = int(ceil(region.y / cell))
	var grid: Array[int] = []
	grid.resize(cols * rows)
	grid.fill(-1)
	var points: Array[Vector2] = []
	var active: Array[int] = []
	var first: Vector2 = Vector2(rng.randf_range(0.0, region.x), rng.randf_range(0.0, region.y))
	points.append(first)
	active.append(0)
	grid[_cell_index(first, cell, cols)] = 0
	while not active.is_empty():
		var pick: int = rng.randi_range(0, active.size() - 1)
		var centre_idx: int = active[pick]
		var centre: Vector2 = points[centre_idx]
		var placed: bool = false
		for t in tries:
			var ang: float = rng.randf_range(0.0, TAU)
			var rad: float = rng.randf_range(min_dist, 2.0 * min_dist)  # the annulus
			var cand: Vector2 = centre + Vector2(cos(ang), sin(ang)) * rad
			if cand.x < 0.0 or cand.y < 0.0 or cand.x >= region.x or cand.y >= region.y:
				continue
			if _is_free(cand, min_dist, cell, cols, rows, grid, points):
				points.append(cand)
				active.append(points.size() - 1)
				grid[_cell_index(cand, cell, cols)] = points.size() - 1
				placed = true
				break
		if not placed:
			active.remove_at(pick)  # exhausted: retire this point
	return points

static func _cell_index(p: Vector2, cell: float, cols: int) -> int:
	return int(p.y / cell) * cols + int(p.x / cell)

static func _is_free(cand: Vector2, min_dist: float, cell: float, cols: int, rows: int, grid: Array[int], points: Array[Vector2]) -> bool:
	var cx: int = int(cand.x / cell)
	var cz: int = int(cand.y / cell)
	for gz in range(maxi(cz - 2, 0), mini(cz + 3, rows)):
		for gx in range(maxi(cx - 2, 0), mini(cx + 3, cols)):
			var occupant: int = grid[gz * cols + gx]
			if occupant != -1 and points[occupant].distance_to(cand) < min_dist:
				return false
	return true

## Chunked Poisson-disc: the same Bridson sampler, but BEFORE placing
## any of its own points it pre-loads the points neighbouring chunks
## already placed (passed in THIS chunk's local coordinates — a west
## neighbour's points arrive with negative x). Neighbours block via
## the grid, are never active, and are never returned. Without this,
## two independently sampled chunks clump across their shared border:
## neither sampler ever saw the other chunk's points.
static func poisson_disc_chunked(region: Vector2, min_dist: float, rng: RandomNumberGenerator, neighbour_points: Array[Vector2], tries: int = 30) -> Array[Vector2]:
	var cell: float = min_dist / sqrt(2.0)
	# The grid covers the region PLUS one min_dist of margin on every
	# side: the only band a neighbour point can threaten a candidate from.
	var origin: Vector2 = Vector2(-min_dist, -min_dist)
	var span: Vector2 = region + Vector2(2.0 * min_dist, 2.0 * min_dist)
	var cols: int = int(ceil(span.x / cell))
	var rows: int = int(ceil(span.y / cell))
	var grid: Array[int] = []
	grid.resize(cols * rows)
	grid.fill(-1)
	var points: Array[Vector2] = []
	var active: Array[int] = []
	# Pre-load the neighbours: into the points list (so distance checks
	# can find them) and into the grid — but NOT into the active list.
	for np in neighbour_points:
		if np.x < origin.x or np.y < origin.y or np.x >= origin.x + span.x or np.y >= origin.y + span.y:
			continue  # beyond the margin: cannot threaten any candidate here
		points.append(np)
		grid[_cell_index_at(np, cell, cols, origin)] = points.size() - 1
	var neighbour_count: int = points.size()
	# The first own point is a candidate like any other now — it must
	# respect the neighbours, so it goes through the same free check.
	var first_placed: bool = false
	for attempt in tries:
		var cand: Vector2 = Vector2(rng.randf_range(0.0, region.x), rng.randf_range(0.0, region.y))
		if _is_free_at(cand, min_dist, cell, cols, rows, grid, points, origin):
			points.append(cand)
			active.append(points.size() - 1)
			grid[_cell_index_at(cand, cell, cols, origin)] = points.size() - 1
			first_placed = true
			break
	if not first_placed:
		return []  # the neighbours left no legal room even for one point
	while not active.is_empty():
		var pick: int = rng.randi_range(0, active.size() - 1)
		var centre_idx: int = active[pick]
		var centre: Vector2 = points[centre_idx]
		var placed: bool = false
		for t in tries:
			var ang: float = rng.randf_range(0.0, TAU)
			var rad: float = rng.randf_range(min_dist, 2.0 * min_dist)  # the annulus
			var cand: Vector2 = centre + Vector2(cos(ang), sin(ang)) * rad
			if cand.x < 0.0 or cand.y < 0.0 or cand.x >= region.x or cand.y >= region.y:
				continue
			if _is_free_at(cand, min_dist, cell, cols, rows, grid, points, origin):
				points.append(cand)
				active.append(points.size() - 1)
				grid[_cell_index_at(cand, cell, cols, origin)] = points.size() - 1
				placed = true
				break
		if not placed:
			active.remove_at(pick)  # exhausted: retire this point
	# Strip the neighbours back off: a chunk returns only its own points.
	var own: Array[Vector2] = []
	for i in range(neighbour_count, points.size()):
		own.append(points[i])
	return own

static func _cell_index_at(p: Vector2, cell: float, cols: int, origin: Vector2) -> int:
	return int((p.y - origin.y) / cell) * cols + int((p.x - origin.x) / cell)

static func _is_free_at(cand: Vector2, min_dist: float, cell: float, cols: int, rows: int, grid: Array[int], points: Array[Vector2], origin: Vector2) -> bool:
	var cx: int = int((cand.x - origin.x) / cell)
	var cz: int = int((cand.y - origin.y) / cell)
	for gz in range(maxi(cz - 2, 0), mini(cz + 3, rows)):
		for gx in range(maxi(cx - 2, 0), mini(cx + 3, cols)):
			var occupant: int = grid[gz * cols + gx]
			if occupant != -1 and points[occupant].distance_to(cand) < min_dist:
				return false
	return true

## World-space moisture: bilinear over the published moisture GRID
## (moisture_at(ix, iz) is the grid accessor; quantities interpolate,
## categories never do — biome IDs are still read via biome_at_world).
static func moisture_at_world(terrain: TerrainHeight, x: float, z: float) -> float:
	var g: Vector2 = terrain.world_to_grid_f(x, z)
	var ix: int = clampi(int(g.x), 0, terrain.cells - 1)
	var iz: int = clampi(int(g.y), 0, terrain.cells - 1)
	var fx: float = clampf(g.x - float(ix), 0.0, 1.0)
	var fz: float = clampf(g.y - float(iz), 0.0, 1.0)
	var m00: float = terrain.moisture_at(ix, iz)
	var m10: float = terrain.moisture_at(ix + 1, iz)
	var m01: float = terrain.moisture_at(ix, iz + 1)
	var m11: float = terrain.moisture_at(ix + 1, iz + 1)
	return lerpf(lerpf(m00, m10, fx), lerpf(m01, m11, fx), fz)

## World-space scatter density: bilinear over Chapter 12's published
## scatter_density grid. 0.0 = the biome wants nothing planted here.
static func density_at_world(terrain: TerrainHeight, x: float, z: float) -> float:
	if terrain.scatter_density.is_empty():
		return 0.0
	var g: Vector2 = terrain.world_to_grid_f(x, z)
	var ix: int = clampi(int(g.x), 0, terrain.cells - 1)
	var iz: int = clampi(int(g.y), 0, terrain.cells - 1)
	var fx: float = clampf(g.x - float(ix), 0.0, 1.0)
	var fz: float = clampf(g.y - float(iz), 0.0, 1.0)
	var w: int = terrain.row_width()
	var d00: float = terrain.scatter_density[iz * w + ix]
	var d10: float = terrain.scatter_density[iz * w + ix + 1]
	var d01: float = terrain.scatter_density[(iz + 1) * w + ix]
	var d11: float = terrain.scatter_density[(iz + 1) * w + ix + 1]
	return lerpf(lerpf(d00, d10, fx), lerpf(d01, d11, fx), fz)

## Thinning: keep each point with probability = the density map at
## that point. Removing points can never violate the minimum
## distance, so a thinned Poisson set keeps Bridson's guarantee
## while its KEPT density follows the terrain's wishes.
static func thin_by_density(points: Array[Vector2], terrain: TerrainHeight, origin: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	var kept: Array[Vector2] = []
	for p in points:
		var world: Vector2 = origin + p
		if rng.randf() < density_at_world(terrain, world.x, world.y):
			kept.append(p)
	return kept

## Ecology placement: rejection sampling against a density built from
## terrain DATA — height, slope, moisture, and the published density
## grid. One pass returns a manifest of {position, kind, scale, yaw}
## dictionaries. The builder that renders the manifest decides
## nothing; the manifest IS the decision.
##
## Slope reminder (Chapter 9): slope_at() returns 1 - cos(angle), so
## 0.03 ~ 14 degrees, 0.08 ~ 23 degrees, 0.20 ~ 37 degrees,
## 0.30 ~ 46 degrees. The thresholds below are in THOSE units.
static func ecology_scatter(terrain: TerrainHeight, region: Rect2, attempts: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var placed: Array[Dictionary] = []
	var sea: float = terrain.sea_level
	for n in attempts:
		var x: float = rng.randf_range(region.position.x, region.end.x)
		var z: float = rng.randf_range(region.position.y, region.end.y)
		var h: float = terrain.height_at(x, z)
		var slope: float = terrain.slope_at(x, z)
		var moist: float = moisture_at_world(terrain, x, z)
		var grid_density: float = density_at_world(terrain, x, z)
		var kind: String = ""
		var density: float = 0.0
		if h < sea + 0.3:
			kind = ""  # in the water or on the wet shore: nothing
		elif slope > 0.30:
			kind = "rock"  # what is left when soil and plants lose
			density = clampf((slope - 0.18) * 2.2, 0.0, 0.9)
		elif moist > 0.45 and slope < 0.08 and h < sea + 22.0:
			kind = "tree"  # moist, gentle, below the treeline
			density = clampf((moist - 0.4) * 1.8, 0.0, 1.0) * clampf(1.0 - slope / 0.08, 0.0, 1.0)
		elif moist > 0.22 and slope < 0.20:
			kind = "shrub"  # the tough cousin: drier, steeper tolerated
			density = 0.55 * clampf(1.0 - slope / 0.20, 0.0, 1.0)
		elif slope > 0.16:
			kind = "rock"
			density = 0.4
		# The published grid vetoes PLANTS where the biome wants none
		# (ocean / rock / snow density is 0.0) and scales the rest.
		# Rocks are exempt: a rock on a rock biome is not a plant.
		if kind == "tree" or kind == "shrub":
			if grid_density <= 0.0:
				continue
			density *= 0.3 + 0.7 * grid_density
		if kind != "" and rng.randf() < density:
			placed.append({
				"position": Vector3(x, h, z),
				"kind": kind,
				"scale": rng.randf_range(0.8, 1.3),
				"yaw": rng.randf_range(0.0, TAU),
			})
	return placed
