class_name HighwayRouter
extends RefCounted

## Prices a landscape, then searches it. The route between two towns
## is BOUGHT: every cell of the cost field carries a price built from
## four terms (length, elevation change, slope, blockers), and A*
## returns the cheapest complete route — never the merely shortest.
## Data-first: find_route() returns a Dictionary, builds nothing.
##
## Project integration note: Listing 38.1's open list is a linear
## scan, with the binary heap named in §38.2 as "the scale upgrade".
## Chapter 42's search field is ~600 cells long and the linear scan
## is quadratic in the explored set, so the heap is implemented
## here: same costs, same admissible heuristic, same winner (ties
## may resolve in a different order). The listing's structure —
## open set, came-from map, g-scores — is unchanged.

const CELL: float = 10.0 # search grid pitch (m) — coarse on purpose

# The weights ARE the design. Named, in the open, argued in §38.1.
const W_ELEVATION: float = 4.0 # per metre of height change
const W_SLOPE: float = 900.0 # per slope-violating cell entered
const W_WATER: float = 260.0 # per water cell entered (bridge debt)
const SLOPE_LIMIT: float = 0.22 # slope_at() units (1 - cos tilt)

var _terrain: TerrainHeight
var _blockers: Array[Rect2] = [] # expanded city footprints


func _init(terrain: TerrainHeight) -> void:
	_terrain = terrain


func add_blocker(rect: Rect2, margin: float) -> void:
	_blockers.append(rect.grow(margin))


func _is_blocked(x: float, z: float) -> bool:
	for rect in _blockers:
		if rect.has_point(Vector2(x, z)):
			return true
	return false


## Price of ENTERING the cell at world (x, z) from height `from_h`.
## INF means: do not enter, ever (a blocker that is not water).
func cell_cost(x: float, z: float, from_h: float,
		ignore_blockers: bool = false) -> float:
	if not ignore_blockers and _is_blocked(x, z):
		return INF
	var h: float = _terrain.height_at(x, z)
	var cost: float = CELL # the length term: one cell of travel
	cost += absf(h - from_h) * W_ELEVATION
	if _terrain.slope_at(x, z) > SLOPE_LIMIT:
		cost += W_SLOPE
	if _terrain.biome_at_world(x, z) == 0:
		cost += W_WATER # crossable — at bridge prices (§38.3)
	return cost


## The cost field's raw ingredients at one point, for the stage's
## debug wash (step 4 draws the field from these, not from prices
## it recomputes itself).
func debug_terms(x: float, z: float) -> Dictionary:
	return {
		"blocked": _is_blocked(x, z),
		"water": _terrain.biome_at_world(x, z) == 0,
		"slope": _terrain.slope_at(x, z),
	}


## A* over the cost field, 8-connected, from `from` to `to` in world
## XZ. Returns {points, total, terms} — the polyline (y from the
## contract), the winning price, and the price BROKEN DOWN by term,
## because a route you cannot itemise is a route you cannot defend.
func find_route(from: Vector2, to: Vector2) -> Dictionary:
	var start := Vector2i(roundi(from.x / CELL), roundi(from.y / CELL))
	var goal := Vector2i(roundi(to.x / CELL), roundi(to.y / CELL))
	var came: Dictionary = {} # cell -> previous cell
	var g_score: Dictionary = {start: 0.0}
	var closed: Dictionary = {}
	# Binary heap of [f, cell] pairs (the §38.2 scale upgrade).
	var heap: Array = []
	_heap_push(heap, [float(_heuristic(start, goal)), start])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var current: Vector2i = entry[1]
		if closed.has(current):
			continue
		if current == goal:
			var terms: Dictionary = {"elevation": 0.0, "slope": 0.0,
				"water": 0.0}
			return _finish(came, goal, float(g_score[goal]), terms)
		closed[current] = true
		var cx: float = float(current.x) * CELL
		var cz: float = float(current.y) * CELL
		var ch: float = _terrain.height_at(cx, cz)
		for d in _neighbours():
			var next: Vector2i = current + d
			if closed.has(next):
				continue
			var nx: float = float(next.x) * CELL
			var nz: float = float(next.y) * CELL
			# The search's endpoints — and their one-cell apron —
			# are exempt from blockers. Listing 38.3 places the
			# endpoints on the town edge, INSIDE the grown
			# footprint's margin: costed as walls, not only could
			# the goal cell never be entered, every neighbour of
			# both endpoints is inside a footprint too, so the
			# search could not even leave its start (§38.4's first
			# troubleshooting entry names this trap; the apron is
			# the town-edge splice §38.3 describes, priced as the
			# town's own ground).
			var exempt: bool = next == goal or next == start \
				or next.distance_squared_to(goal) <= 2 \
				or next.distance_squared_to(start) <= 2
			var step: float = cell_cost(nx, nz, ch, exempt)
			if step == INF:
				continue
			if d.x != 0 and d.y != 0:
				step *= 1.41421356 # diagonal steps travel farther
			var tentative: float = float(g_score[current]) + step
			if tentative < float(g_score.get(next, INF)):
				g_score[next] = tentative
				came[next] = current
				_heap_push(heap, [tentative + _heuristic(next, goal), next])
	return {} # no route at any price — an answer, not a crash


func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		while true:
			var left: int = i * 2 + 1
			var right: int = left + 1
			var smallest: int = i
			if left < heap.size() and float(heap[left][0]) < float(heap[smallest][0]):
				smallest = left
			if right < heap.size() and float(heap[right][0]) < float(heap[smallest][0]):
				smallest = right
			if smallest == i:
				break
			var tmp: Array = heap[smallest]
			heap[smallest] = heap[i]
			heap[i] = tmp
			i = smallest
	return top


func _heuristic(cell: Vector2i, goal: Vector2i) -> float:
	# Straight-line distance in cost units (1 per metre at minimum):
	# admissible — it never overestimates, so A* stays optimal.
	return Vector2(cell).distance_to(Vector2(goal)) * CELL


func _neighbours() -> Array[Vector2i]:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
		Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1),
		Vector2i(-1, 1), Vector2i(-1, -1)]


func _finish(came: Dictionary, goal: Vector2i, total: float,
		terms: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = []
	var cursor: Vector2i = goal
	cells.append(cursor)
	while came.has(cursor):
		cursor = came[cursor]
		cells.append(cursor)
	cells.reverse()
	var points := PackedVector3Array()
	for cell in cells:
		var x: float = float(cell.x) * CELL
		var z: float = float(cell.y) * CELL
		points.append(Vector3(x, _terrain.height_at(x, z), z))
	# Itemise the bill on the winning route (recomputed here, per
	# the listing's walkthrough: an exact invoice, not accumulators
	# threaded through the search).
	terms = _itemise(points)
	return {"points": points, "total": total, "terms": terms}


func _itemise(points: PackedVector3Array) -> Dictionary:
	var elevation: float = 0.0
	var slope_cells: int = 0
	var water_cells: int = 0
	for i in range(1, points.size()):
		elevation += absf(points[i].y - points[i - 1].y) * W_ELEVATION
		if _terrain.slope_at(points[i].x, points[i].z) > SLOPE_LIMIT:
			slope_cells += 1
		if _terrain.biome_at_world(points[i].x, points[i].z) == 0:
			water_cells += 1
	return {"elevation": elevation, "slope": float(slope_cells) * W_SLOPE,
		"water": float(water_cells) * W_WATER,
		"slope_cells": slope_cells, "water_cells": water_cells}


## The finalisation pass: walk the smoothed route and divide it into
## spans. Land spans stay ribbons; a maximal run of water spans
## becomes ONE bridge (flat deck at the higher bank's grade). Returns
## {spans: [{kind: "ribbon"|"bridge", from: int, to: int}], grade}.
## `points` is the A* polyline; grade is computed here (§38.2).
func finalise(points: PackedVector3Array) -> Dictionary:
	var grade: PackedFloat32Array = _grade(points)
	var spans: Array[Dictionary] = []
	var i: int = 0
	while i < points.size() - 1:
		if _is_water(points[i + 1]):
			var j: int = i + 1
			while j < points.size() - 1 and _is_water(points[j + 1]):
				j += 1
			# Water run is spans i..j-1 (points i..j). The deck sits
			# at the higher bank's grade so neither approach dives.
			spans.append({"kind": "bridge", "from": i, "to": j,
				"deck_y": maxf(grade[i], grade[j]) + 1.2})
			i = j
		else:
			spans.append({"kind": "ribbon", "from": i, "to": i + 1,
				"deck_y": 0.0})
			i += 1
	return {"spans": spans, "grade": grade}


func _is_water(p: Vector3) -> bool:
	return _terrain.biome_at_world(p.x, p.z) == 0


# Civilised grade (§38.2): a centred moving average of terrain
# heights along the route. The road cuts rises and embanks dips
# instead of following every 10 m bump of the raw field.
func _grade(points: PackedVector3Array) -> PackedFloat32Array:
	var grade := PackedFloat32Array()
	grade.resize(points.size())
	const RADIUS: int = 3
	for i in range(points.size()):
		var sum: float = 0.0
		var count: int = 0
		for k in range(maxi(0, i - RADIUS),
				mini(points.size(), i + RADIUS + 1)):
			sum += points[k].y
			count += 1
		grade[i] = sum / float(count)
	return grade
