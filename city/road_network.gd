class_name RoadNetwork
extends RefCounted

## A city road network, stored twice on purpose (Ch 37 §37.1):
##   logic_roads — full-length polylines, overlapping at junctions.
##                 Routing, reachability and cost searches read THESE.
##   segments    — short pieces clipped between junctions, never
##                 overlapping. Rendering reads THESE. Segments are
##                 DERIVED by rebuild_segments() and never edited.
## Generation is data-first: this class builds no nodes and no meshes.
##
## Project integration notes (adaptations, named per the book's rule):
## - rebuild_segments() skips road pairs whose XZ bounding boxes do
##   not overlap. A pure broadphase: the derived segments are exactly
##   the listing's; only the wasted intersection tests are removed.
##   (Ch 37 names the spatial index as the scale upgrade; Ch 42's
##   24 km network needs the first step of it.)
## - warp_nodes(): Listing 37.4's polyline rewrite compares _key()
##   of each OLD polyline point against _key() of the MOVED node —
##   after a warp of up to `strength` metres those keys can never
##   match, so as printed the rewrite is a no-op and the warp tears
##   (the chapter's own Exercise 2 symptom, in the listing itself).
##   Fixed minimally: the old-key -> node map is captured BEFORE any
##   node moves, and polylines are rewritten through it. Same intent,
##   same structure; reported in the Part VIII discrepancy notes.
## - merge_grid() is Listing 38.3's walkthrough specification,
##   implemented here: generate_grid()'s body minus the clear()
##   calls, second grid's index keys offset by +100 columns.

var nodes: Array[Vector3] = []
var logic_roads: Array[Dictionary] = []
var segments: Array[Dictionary] = []

# Grid-family bookkeeping, filled only by generate_grid(): the node
# index at each (column, row), so Chapter 39 can read blocks straight
# off the grid instead of walking a planar graph.
var grid_index: Dictionary = {} # Vector2i -> int (node index)

var _terrain: TerrainHeight


func _init(terrain: TerrainHeight) -> void:
	_terrain = terrain


func ground_height(x: float, z: float) -> float:
	# The terrain contract (Part II): every y in this network comes
	# from height_at(). The network never stores its own heights.
	return _terrain.height_at(x, z)


func add_node(p: Vector3) -> int:
	nodes.append(p)
	return nodes.size() - 1


func add_logic_road(points: PackedVector3Array, kind: String) -> int:
	logic_roads.append({"points": points, "kind": kind})
	return logic_roads.size() - 1


## The plain grid, done properly: spacing is SAMPLED per street from
## the roads stream (cumulative offsets), never a fixed pitch — a
## fixed pitch is the "textbook grid" failure of §37.5's field note.
## Roads run along the border of the region too, so edge blocks close.
func generate_grid(region: Rect2, pitch_min: float, pitch_max: float,
		master_seed: int) -> void:
	nodes.clear()
	logic_roads.clear()
	grid_index.clear()
	_append_grid(region, pitch_min, pitch_max, master_seed, 0)
	rebuild_segments()


## Chapter 38's merge: a second grid APPENDED to this network (the
## stage's two towns share one network). Index keys are offset so
## the second town's cells cannot collide with the first's.
func merge_grid(region: Rect2, pitch_min: float, pitch_max: float,
		master_seed: int) -> void:
	var col_offset: int = 0
	if not grid_index.is_empty():
		var max_ix: int = 0
		for key in grid_index.keys():
			max_ix = maxi(max_ix, (key as Vector2i).x)
		col_offset = max_ix + 100
	_append_grid(region, pitch_min, pitch_max, master_seed, col_offset)
	rebuild_segments()


func _append_grid(region: Rect2, pitch_min: float, pitch_max: float,
		master_seed: int, col_offset: int) -> void:
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		master_seed, SeedBank.STREAM_ROADS)
	var xs: Array[float] = _sampled_axis(
		region.position.x, region.end.x, pitch_min, pitch_max, rng)
	var zs: Array[float] = _sampled_axis(
		region.position.y, region.end.y, pitch_min, pitch_max, rng)
	var base: Dictionary = {}
	for iz in range(zs.size()):
		for ix in range(xs.size()):
			var p := Vector3(xs[ix], 0.0, zs[iz])
			p.y = ground_height(p.x, p.z)
			var idx: int = add_node(p)
			grid_index[Vector2i(ix + col_offset, iz)] = idx
			base[Vector2i(ix, iz)] = idx
	# One logic road per column and per row, full length, through
	# every junction — overlaps are the logic representation's job.
	for ix in range(xs.size()):
		var column := PackedVector3Array()
		for iz in range(zs.size()):
			column.append(nodes[int(base[Vector2i(ix, iz)])])
		add_logic_road(column, "street")
	for iz in range(zs.size()):
		var row := PackedVector3Array()
		for ix in range(xs.size()):
			row.append(nodes[int(base[Vector2i(ix, iz)])])
		add_logic_road(row, "street")


func _sampled_axis(start: float, finish: float, pitch_min: float,
		pitch_max: float, rng: RandomNumberGenerator) -> Array[float]:
	var axis: Array[float] = [start]
	var cursor: float = start
	while true:
		cursor += rng.randf_range(pitch_min, pitch_max)
		if cursor >= finish - pitch_min * 0.5:
			break
		axis.append(cursor)
	axis.append(finish)
	return axis


## THE derivation. Every crossing of every pair of logic roads
## becomes a node; every road is cut at its crossings; the pieces are
## the draw segments. Pure function of logic_roads: call it after any
## change to the logic representation, and only ever then.
func rebuild_segments() -> void:
	segments.clear()
	# Register every polyline point as a node (grids already did;
	# grown roads add theirs here).
	var point_node: Dictionary = {} # Vector2i(x100,z100) -> int
	for i in range(nodes.size()):
		point_node[_key(nodes[i])] = i
	var cuts: Array = [] # per road: Array of [t: float, node: int]
	for r in range(logic_roads.size()):
		cuts.append([])
		var pts: PackedVector3Array = logic_roads[r]["points"]
		for i in range(pts.size()):
			var k: Vector2i = _key(pts[i])
			if not point_node.has(k):
				var p: Vector3 = pts[i]
				p.y = ground_height(p.x, p.z)
				point_node[k] = add_node(p)
			cuts[r].append([float(i), point_node[k]])
	# Crossings between different roads: segment/segment intersection
	# in the XZ plane. The bounding-box broadphase only skips pairs
	# that cannot cross; the tests that run are the listing's.
	var boxes: Array[Rect2] = []
	for r in range(logic_roads.size()):
		boxes.append(_road_aabb(logic_roads[r]["points"]))
	for a in range(logic_roads.size()):
		for b in range(a + 1, logic_roads.size()):
			if not boxes[a].intersects(boxes[b]):
				continue
			_cross_roads(a, b, cuts, point_node)
	# Emit the clipped pieces, in order along each road.
	for r in range(logic_roads.size()):
		var road_cuts: Array = cuts[r]
		road_cuts.sort_custom(func(p: Array, q: Array) -> bool:
			return p[0] < q[0])
		for i in range(road_cuts.size() - 1):
			var na: int = road_cuts[i][1]
			var nb: int = road_cuts[i + 1][1]
			if na != nb:
				segments.append({"a": na, "b": nb, "road": r})


func _road_aabb(pts: PackedVector3Array) -> Rect2:
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


func _cross_roads(a: int, b: int, cuts: Array,
		point_node: Dictionary) -> void:
	var pa: PackedVector3Array = logic_roads[a]["points"]
	var pb: PackedVector3Array = logic_roads[b]["points"]
	for i in range(pa.size() - 1):
		for j in range(pb.size() - 1):
			var hit: Dictionary = _segment_hit(
				pa[i], pa[i + 1], pb[j], pb[j + 1])
			if hit.is_empty():
				continue
			var p: Vector3 = hit["point"]
			p.y = ground_height(p.x, p.z)
			var k: Vector2i = _key(p)
			if not point_node.has(k):
				point_node[k] = add_node(p)
			var ni: int = point_node[k]
			cuts[a].append([float(i) + float(hit["t"]), ni])
			cuts[b].append([float(j) + float(hit["u"]), ni])


# XZ-plane segment intersection. Returns {} for parallel/missing,
# else {point, t (along a), u (along b)} with t,u strictly inside.
func _segment_hit(a0: Vector3, a1: Vector3, b0: Vector3,
		b1: Vector3) -> Dictionary:
	var r := Vector2(a1.x - a0.x, a1.z - a0.z)
	var s := Vector2(b1.x - b0.x, b1.z - b0.z)
	var denom: float = r.x * s.y - r.y * s.x
	if absf(denom) < 0.000001:
		return {}
	var qp := Vector2(b0.x - a0.x, b0.z - a0.z)
	var t: float = (qp.x * s.y - qp.y * s.x) / denom
	var u: float = (qp.x * r.y - qp.y * r.x) / denom
	if t <= 0.001 or t >= 0.999 or u <= 0.001 or u >= 0.999:
		return {}
	return {"point": a0.lerp(a1, t), "t": t, "u": u}


func _key(p: Vector3) -> Vector2i:
	# Nodes are keyed on a 1 cm grid: grown roads that share an
	# endpoint must land on the SAME node, not two near-identical ones.
	return Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))


## Junction classification by 4-bit connection mask (§37.4): bit i is
## set when a segment leaves this node in compass direction i
## (0 = north/-z, 1 = east/+x, 2 = south/+z, 3 = west/-x), quantised
## to the nearest compass point. 2 bits = through or corner,
## 3 bits = T, 4 bits = crossroads.
func connection_mask(node_index: int) -> int:
	var mask: int = 0
	var origin: Vector3 = nodes[node_index]
	for seg in segments:
		var other: int = -1
		if int(seg["a"]) == node_index:
			other = int(seg["b"])
		elif int(seg["b"]) == node_index:
			other = int(seg["a"])
		if other < 0:
			continue
		var d: Vector3 = nodes[other] - origin
		var angle: float = atan2(d.x, -d.z) # 0 at north, clockwise
		var dir: int = int(round(angle / (PI * 0.5))) % 4
		if dir < 0:
			dir += 4
		mask |= 1 << dir
	return mask


func junction_degree(node_index: int) -> int:
	var degree: int = 0
	var m: int = connection_mask(node_index)
	for bit in range(4):
		if m & (1 << bit) != 0:
			degree += 1
	return degree


## Bend every registered node by a seeded offset field, then refresh
## heights from the contract. Logic roads keep their point ORDER —
## the streets are the same streets, surveyed by a drunk theodolite.
## Call BEFORE rebuild_segments().
## (FIX vs Listing 37.4 as printed: the old-key map is captured
## BEFORE the move — see the header note.)
func warp_nodes(strength: float, master_seed: int) -> void:
	var noise_x: FastNoiseLite = SeedBank.noise_for(
		master_seed, SeedBank.STREAM_ROADS + "_warp_x", 0.006, 2)
	var noise_z: FastNoiseLite = SeedBank.noise_for(
		master_seed, SeedBank.STREAM_ROADS + "_warp_z", 0.006, 2)
	# Where each node WAS, keyed the way _key() keys it: the rewrite
	# below finds polyline points by their pre-warp positions.
	var old_key_to_node: Dictionary = {}
	for i in range(nodes.size()):
		old_key_to_node[_key(nodes[i])] = i
	for i in range(nodes.size()):
		var p: Vector3 = nodes[i]
		p.x += noise_x.get_noise_2d(p.x, p.z) * strength
		p.z += noise_z.get_noise_2d(p.x, p.z) * strength
		p.y = ground_height(p.x, p.z)
		nodes[i] = p
	# The logic polylines share the nodes' positions: rewrite them
	# from the pre-warp key map so warped points and roads cannot
	# diverge.
	for r in range(logic_roads.size()):
		var pts: PackedVector3Array = logic_roads[r]["points"]
		for i in range(pts.size()):
			var k: Vector2i = _key(pts[i])
			if old_key_to_node.has(k):
				pts[i] = nodes[int(old_key_to_node[k])]
		logic_roads[r]["points"] = pts


## Goal-grown roads (Parish & Muller pattern): from `from` toward
## `to`, step by step. Global goal = the target. Local constraints =
## contour preference + water veto + slope veto, all answered by the
## terrain contract. Each accepted step becomes a logic-road point.
func generate_grown(from: Vector2, to: Vector2, step_len: float,
		master_seed: int) -> void:
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		master_seed, SeedBank.STREAM_ROADS + "_grown")
	var points := PackedVector3Array()
	var cursor := Vector3(from.x, 0.0, from.y)
	cursor.y = ground_height(cursor.x, cursor.z)
	points.append(cursor)
	var guard: int = 0
	while cursor.distance_to(Vector3(to.x, cursor.y, to.y)) > step_len \
			and guard < 400:
		guard += 1
		var toward: Vector2 = (to - Vector2(cursor.x, cursor.z)) \
			.normalized()
		var best: Vector3 = cursor
		var best_cost: float = INF
		# Try the goal direction and four deflections; score each by
		# progress + climbing + a whisper of seeded jitter.
		for k in range(-2, 3):
			var dir: Vector2 = toward.rotated(float(k) * 0.22)
			var cand := Vector3(cursor.x + dir.x * step_len, 0.0,
				cursor.z + dir.y * step_len)
			cand.y = ground_height(cand.x, cand.z)
			if _terrain.biome_at_world(cand.x, cand.z) == 0:
				continue # biome 0 is open water (Part I) — veto
			var climb: float = absf(cand.y - cursor.y)
			var slope: float = _terrain.slope_at(cand.x, cand.z)
			if slope > 0.35:
				continue # too steep to build on — veto
			var progress: float = cand.distance_to(
				Vector3(to.x, cand.y, to.y))
			var cost: float = progress + climb * 6.0 \
				+ rng.randf_range(0.0, 1.5)
			if cost < best_cost:
				best_cost = cost
				best = cand
		if best == cursor:
			break # every direction vetoed: the road dies honestly
		points.append(best)
		cursor = best
	if points.size() >= 2:
		add_logic_road(points, "street")
