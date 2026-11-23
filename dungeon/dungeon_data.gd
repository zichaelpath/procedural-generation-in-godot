class_name DungeonData
extends RefCounted
## The dungeon as pure data. No nodes, no rendering. Generators WRITE
## this; builders, minimaps, and validators READ it. Tiles are excavated
## from solid wall: every cell starts as WALL and carvers cut FLOOR /
## CORRIDOR / DOOR into it. Indexing convention (never break it):
## tiles[y][x], always via get_tile / set_tile with a Vector2i — raw
## 2D indexing stays inside this class.

enum Tile { WALL, FLOOR, CORRIDOR, DOOR }

var width: int = 0
var height: int = 0
var tiles: Array = []        # tiles[y] -> Array of Tile ints
var rooms: Array = []        # {id:int, rect:Rect2i, center:Vector2i, tags:Array}
var edges: Array = []        # {a:int, b:int, door_tile:Vector2i, locked_key:String}
var keys: Array = []         # {key_id:String, room_id:int} — filled in Ch 24
var roles: Dictionary = {}   # room_id -> role String — filled in Ch 24
var meta: Dictionary = {}    # extension slot: dressing / spawns live here (Ch 25)
var entrance_room: int = -1
var start_tile: Vector2i = Vector2i(-1, -1)

func setup(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	tiles.clear()
	for y in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(Tile.WALL)
		tiles.append(row)
	rooms.clear()
	edges.clear()
	keys.clear()
	roles.clear()
	meta.clear()
	entrance_room = -1
	start_tile = Vector2i(-1, -1)

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height

func get_tile(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return Tile.WALL  # outside the map is solid rock — callers rely on it
	return int(tiles[pos.y][pos.x])

func set_tile(pos: Vector2i, tile: int) -> void:
	if in_bounds(pos):
		tiles[pos.y][pos.x] = tile

func is_passable(pos: Vector2i) -> bool:
	return get_tile(pos) != Tile.WALL

func floor_count() -> int:
	var n: int = 0
	for y in range(height):
		for x in range(width):
			if get_tile(Vector2i(x, y)) != Tile.WALL:
				n += 1
	return n

func room_at(pos: Vector2i) -> int:
	for room in rooms:
		if (room["rect"] as Rect2i).has_point(pos):
			return int(room["id"])
	return -1

func room_by_id(room_id: int) -> Dictionary:
	for room in rooms:
		if int(room["id"]) == room_id:
			return room
	return {}

func add_room(rect: Rect2i, tags: Array = []) -> int:
	var id: int = rooms.size()
	rooms.append({
		"id": id,
		"rect": rect,
		"center": rect.get_center(),
		"tags": tags.duplicate(),
	})
	return id

# --- ASCII round trip: the part's favourite debugging tool ---------------

func from_ascii(lines: PackedStringArray) -> void:
	setup(lines[0].length(), lines.size())
	for y in range(lines.size()):
		var line: String = lines[y]
		for x in range(line.length()):
			var tile: int = Tile.WALL
			match line[x]:
				".":
					tile = Tile.FLOOR
				"+":
					tile = Tile.CORRIDOR
				"D":
					tile = Tile.DOOR
			set_tile(Vector2i(x, y), tile)

func to_ascii() -> String:
	var out: String = ""
	for y in range(height):
		for x in range(width):
			match get_tile(Vector2i(x, y)):
				Tile.WALL:
					out += "#"
				Tile.FLOOR:
					out += "."
				Tile.CORRIDOR:
					out += "+"
				Tile.DOOR:
					out += "D"
		out += "\n"
	return out

## Labels every maximal set of mutually reachable passable tiles
## with one region id. Returns an Array indexed [y][x] of ints:
## -1 for wall, otherwise the region id. Movement is 4-way —
## regions that touch only at a corner are DIFFERENT regions,
## because the player cannot walk through a corner either.
func label_floor_regions() -> Array:
	var labels: Array = []
	for y in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(-1)
		labels.append(row)
	var next_id: int = 0
	for y in range(height):
		for x in range(width):
			var start := Vector2i(x, y)
			if not is_passable(start) or int(labels[y][x]) != -1:
				continue
			var stack: Array[Vector2i] = [start]
			labels[y][x] = next_id
			while not stack.is_empty():
				var pos: Vector2i = stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = pos + dir
					if in_bounds(q) and is_passable(q) and int(labels[q.y][q.x]) == -1:
						labels[q.y][q.x] = next_id
						stack.append(q)
			next_id += 1
	return labels

## Region sizes as a report: [{id:int, size:int}, ...] sorted
## largest first. This is the cave's connectivity receipt.
func region_report() -> Array:
	var labels: Array = label_floor_regions()
	var sizes: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var id: int = int(labels[y][x])
			if id >= 0:
				sizes[id] = int(sizes.get(id, 0)) + 1
	var report: Array = []
	for id in sizes.keys():
		report.append({"id": int(id), "size": int(sizes[id])})
	report.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["size"]) > int(b["size"]))
	return report

## Every passable tile reachable from `from` (4-way flood). The
## tile-level reachability primitive the validator (Ch 25) and the
## hybrid's re-checks are built on.
func reachable_tiles(from: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not is_passable(from):
		return seen
	var stack: Array[Vector2i] = [from]
	seen[from] = true
	while not stack.is_empty():
		var pos: Vector2i = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = pos + dir
			if in_bounds(q) and is_passable(q) and not seen.has(q):
				seen[q] = true
				stack.append(q)
	return seen

# --- The room graph: helpers over rooms + edges (Ch 23) -------------------

## room_id -> Array of neighbouring room_ids, built from edges.
func adjacency() -> Dictionary:
	var adj: Dictionary = {}
	for room in rooms:
		adj[int(room["id"])] = []
	for edge in edges:
		var a: int = int(edge["a"])
		var b: int = int(edge["b"])
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	return adj

## How many connections a room has. Degree 1 = dead end.
func degree(room_id: int, adj: Dictionary = {}) -> int:
	var use: Dictionary = adj if not adj.is_empty() else adjacency()
	return (use.get(room_id, []) as Array).size()

## Breadth-first step counts from one room: room_id -> distance.
## Unreached rooms are ABSENT from the result — absence is the
## disconnected signal, and callers test for it directly.
func bfs_room_distances(from_id: int) -> Dictionary:
	var adj: Dictionary = adjacency()
	var dist: Dictionary = {from_id: 0}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var current: int = queue[0]
		queue.remove_at(0)
		for next in adj.get(current, []):
			var n: int = int(next)
			if not dist.has(n):
				dist[n] = int(dist[current]) + 1
				queue.append(n)
	return dist

## The room path from A to B (BFS with parents), as an Array of
## room ids including both ends. Empty Array = no route exists.
func room_path(from_id: int, to_id: int) -> Array:
	if from_id == to_id:
		return [from_id]
	var adj: Dictionary = adjacency()
	var parent: Dictionary = {from_id: -1}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var current: int = queue[0]
		queue.remove_at(0)
		if current == to_id:
			break
		for next in adj.get(current, []):
			var n: int = int(next)
			if not parent.has(n):
				parent[n] = current
				queue.append(n)
	if not parent.has(to_id):
		return []
	var path: Array = []
	var at: int = to_id
	while at != -1:
		path.push_front(at)
		at = int(parent[at])
	return path

## The dungeon's pacing fingerprint, as data: {rooms, edges,
## dead_ends, max_degree, diameter}. Diameter = the longest
## shortest room path — the sprawl, measured, not guessed.
func graph_stats() -> Dictionary:
	var adj: Dictionary = adjacency()
	var dead_ends: int = 0
	var max_degree: int = 0
	for room in rooms:
		var d: int = (adj[int(room["id"])] as Array).size()
		if d == 1:
			dead_ends += 1
		max_degree = maxi(max_degree, d)
	var diameter: int = 0
	for room in rooms:
		var dist: Dictionary = bfs_room_distances(int(room["id"]))
		for id in dist.keys():
			diameter = maxi(diameter, int(dist[id]))
	return {
		"rooms": rooms.size(),
		"edges": edges.size(),
		"dead_ends": dead_ends,
		"max_degree": max_degree,
		"diameter": diameter,
	}

## Cheapest-attachment spanning growth: start from the entrance
## room (or the first room) and repeatedly attach the unconnected
## room whose centre is closest to ANY connected room. Returns the
## attachments in growth order: {from:int, to:int, cost:float}.
## N rooms -> exactly N-1 attachments, zero loops, no RNG: ties go
## to the lowest room ids, so the same rooms grow the same tree.
func spanning_growth() -> Array:
	var result: Array = []
	if rooms.is_empty():
		return result
	var start: int = entrance_room
	if start < 0 or room_by_id(start).is_empty():
		start = int(rooms[0]["id"])
	var connected: Dictionary = {}
	connected[start] = true
	while result.size() < rooms.size() - 1:
		var best_from: int = -1
		var best_to: int = -1
		var best_cost: float = INF
		for room in rooms:
			var candidate: int = int(room["id"])
			if connected.has(candidate):
				continue
			var candidate_centre: Vector2i = room["center"]
			for other in rooms:
				var anchor: int = int(other["id"])
				if not connected.has(anchor):
					continue
				var anchor_centre: Vector2i = other["center"]
				var cost: float = Vector2(anchor_centre).distance_to(Vector2(candidate_centre))
				if cost < best_cost or (cost == best_cost and (candidate < best_to or (candidate == best_to and anchor < best_from))):
					best_cost = cost
					best_from = anchor
					best_to = candidate
		if best_to == -1:
			break  # no attachment exists — the short list IS the report
		connected[best_to] = true
		result.append({"from": best_from, "to": best_to, "cost": best_cost})
	return result

# --- Doors as first-class edge data (Ch 24) -------------------------------
# Adds FIELDS to the existing edge dictionaries (kind, key_room);
# the Ch 20 record is extended, never replaced. locked_key stays
# as the key's name for locked doors, kept in sync by set_door().

## Gives every edge its kind + key_room fields. Idempotent: call
## after any generator, before door-aware systems run.
func build_door_records() -> void:
	for edge in edges:
		if not edge.has("kind"):
			edge["kind"] = "locked" if str(edge["locked_key"]) != "" else "open"
		if not edge.has("key_room"):
			var kr: int = -1
			for k in keys:
				if str(k["key_id"]) == str(edge["locked_key"]):
					kr = int(k["room_id"])
			edge["key_room"] = kr

## The one sanctioned door edit: sets kind (and key, for locked
## doors) on the edge between a and b, keeping locked_key in sync.
func set_door(a: int, b: int, kind: String, key_id: String = "") -> void:
	for edge in edges:
		var ea: int = int(edge["a"])
		var eb: int = int(edge["b"])
		if (ea == a and eb == b) or (ea == b and eb == a):
			edge["kind"] = kind
			edge["locked_key"] = key_id if kind == "locked" else ""
			if kind == "locked":
				var kr: int = -1
				for k in keys:
					if str(k["key_id"]) == key_id:
						kr = int(k["room_id"])
				edge["key_room"] = kr
			return

## The edge dictionary between two rooms, or {} if none.
func door_between(a: int, b: int) -> Dictionary:
	for edge in edges:
		var ea: int = int(edge["a"])
		var eb: int = int(edge["b"])
		if (ea == a and eb == b) or (ea == b and eb == a):
			return edge
	return {}

## The door law, in exactly one place: from room_id, holding
## held_keys, which rooms may I step into? Locked needs its key;
## one-way respects the recorded a->b direction; secret passes
## (completability is a graph question — discovery is the
## presentation layer's problem, Ch 25's validator flags secrets
## on the only route instead of forbidding them here).
func passable_neighbours(room_id: int, held_keys: Array) -> Array:
	var out: Array = []
	for edge in edges:
		var ea: int = int(edge["a"])
		var eb: int = int(edge["b"])
		var kind: String = str(edge.get("kind", "open"))
		if kind == "one_way":
			if ea == room_id:
				out.append(eb)
			continue
		var other: int = -1
		if ea == room_id:
			other = eb
		elif eb == room_id:
			other = ea
		if other < 0:
			continue
		if kind == "locked" and not held_keys.has(str(edge["locked_key"])):
			continue
		out.append(other)
	return out
