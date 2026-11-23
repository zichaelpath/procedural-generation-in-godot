class_name BSPGenerator
extends RefCounted
## Binary space partitioning, stage 1: split the map rectangle into a
## tree. Internal nodes are regions, leaves are room sites. Rooms and
## corridors arrive in Listings 21.2 / 21.3. The tree is plain
## Dictionaries so it can be printed and inspected:
## {rect:Rect2i, left:Dictionary, right:Dictionary} — a leaf is a
## Dictionary with no "left" key.

var min_leaf: int = 9       # never let a child be born smaller than this
var max_depth: int = 6      # hard cap on tree size
var min_ratio: float = 0.35 # cut position window, as a fraction of length
var max_ratio: float = 0.65

var min_room: int = 4        # designer minimum room dimension
var max_margin: int = 3      # largest inset the stream may choose per side

var corridor_width: int = 1

var root: Dictionary = {}
var _rng: RandomNumberGenerator

func build_tree(master_seed: int, width: int, height: int) -> Dictionary:
	_rng = SeedBank.stream_for(master_seed, SeedBank.STREAM_DUNGEON)
	root = _split(Rect2i(0, 0, width, height), 0)
	return root

func _split(rect: Rect2i, depth: int) -> Dictionary:
	var node: Dictionary = {"rect": rect}
	if depth >= max_depth:
		return node
	# Cut along the long axis; square-ish rects ask the stream.
	var vertical: bool
	if rect.size.x > rect.size.y * 1.25:
		vertical = true
	elif rect.size.y > rect.size.x * 1.25:
		vertical = false
	else:
		vertical = _rng.randf() < 0.5
	var length: int = rect.size.x if vertical else rect.size.y
	# THE GUARD: both children must be at least min_leaf long on the
	# cut axis. The ratio window is clamped BY the guard, not beside it.
	var lo: int = maxi(min_leaf, int(length * min_ratio))
	var hi: int = mini(length - min_leaf, int(length * max_ratio))
	if lo > hi:
		return node  # cannot cut without birthing a sliver — this is a leaf
	var cut: int = _rng.randi_range(lo, hi)
	var a: Rect2i
	var b: Rect2i
	if vertical:
		a = Rect2i(rect.position, Vector2i(cut, rect.size.y))
		b = Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y))
	else:
		a = Rect2i(rect.position, Vector2i(rect.size.x, cut))
		b = Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut))
	node["left"] = _split(a, depth + 1)
	node["right"] = _split(b, depth + 1)
	return node

func leaves() -> Array:
	var out: Array = []
	_collect_leaves(root, out)
	return out

func _collect_leaves(node: Dictionary, out: Array) -> void:
	if node.is_empty():
		return
	if not node.has("left"):
		out.append(node)
		return
	_collect_leaves(node["left"], out)
	_collect_leaves(node["right"], out)

## Carve one room per leaf into data and register its metadata.
## Margins are stream-drawn but floored so a room never drops below
## min_room in either dimension. The largest leaf's room is forced
## big and tagged "grand": landmarks are enforced, not hoped for.
func carve_rooms(data: DungeonData) -> void:
	# Find the largest leaf FIRST, so its room can be forced + tagged.
	# Selection before execution: a phase's decisions must precede
	# the work they constrain.
	var biggest: Dictionary = {}
	var biggest_area: int = -1
	for leaf in leaves():
		var r: Rect2i = leaf["rect"]
		if r.size.x * r.size.y > biggest_area:
			biggest_area = r.size.x * r.size.y
			biggest = leaf
	for leaf in leaves():
		var lr: Rect2i = leaf["rect"]
		var is_grand: bool = leaf == biggest
		var room_rect: Rect2i
		if is_grand:
			# At least 70% of the leaf in each dimension, centred-ish.
			var w: int = maxi(min_room, int(lr.size.x * 0.7))
			var h: int = maxi(min_room, int(lr.size.y * 0.7))
			w = mini(w, lr.size.x - 2)
			h = mini(h, lr.size.y - 2)
			var ox: int = _rng.randi_range(1, maxi(1, lr.size.x - w - 1))
			var oy: int = _rng.randi_range(1, maxi(1, lr.size.y - h - 1))
			room_rect = Rect2i(lr.position + Vector2i(ox, oy), Vector2i(w, h))
		else:
			# Per-side margins, clamped so the room keeps min_room.
			var mx: int = mini(max_margin, (lr.size.x - min_room) / 2)
			var my: int = mini(max_margin, (lr.size.y - min_room) / 2)
			var left: int = _rng.randi_range(1, maxi(1, mx))
			var top: int = _rng.randi_range(1, maxi(1, my))
			var right: int = _rng.randi_range(1, maxi(1, mx))
			var bottom: int = _rng.randi_range(1, maxi(1, my))
			room_rect = Rect2i(
				lr.position + Vector2i(left, top),
				Vector2i(lr.size.x - left - right, lr.size.y - top - bottom))
		for y in range(room_rect.position.y, room_rect.position.y + room_rect.size.y):
			for x in range(room_rect.position.x, room_rect.position.x + room_rect.size.x):
				data.set_tile(Vector2i(x, y), DungeonData.Tile.FLOOR)
		var tags: Array = ["grand"] if is_grand else []
		leaf["room_id"] = data.add_room(room_rect, tags)

## The full pipeline in one call: split -> rooms -> corridors.
## From here on, every generator in this part gets the same
## treatment: generate, render, report.
func generate(master_seed: int, width: int, height: int) -> DungeonData:
	build_tree(master_seed, width, height)
	var data := DungeonData.new()
	data.setup(width, height)
	carve_rooms(data)
	_connect(root, data)
	# Entrance: the first leaf's room. Its centre is the start tile.
	var first_leaf: Dictionary = leaves()[0]
	data.entrance_room = int(first_leaf["room_id"])
	data.start_tile = data.room_by_id(data.entrance_room)["center"]
	return data

## Returns the room id representing this subtree. Connects the two
## child representatives, records the edge, passes one rep upward.
func _connect(node: Dictionary, data: DungeonData) -> int:
	if not node.has("left"):
		return int(node["room_id"])
	var rep_a: int = _connect(node["left"], data)
	var rep_b: int = _connect(node["right"], data)
	var centre_a: Vector2i = data.room_by_id(rep_a)["center"]
	var centre_b: Vector2i = data.room_by_id(rep_b)["center"]
	var corner: Vector2i = _carve_corridor(data, centre_a, centre_b)
	data.edges.append({"a": rep_a, "b": rep_b, "door_tile": corner, "locked_key": ""})
	return rep_a

## Carves an L between two points (order chosen by the stream) and
## returns the corner tile — the natural home of this connection's door.
func _carve_corridor(data: DungeonData, from: Vector2i, to: Vector2i) -> Vector2i:
	var horizontal_first: bool = _rng.randf() < 0.5
	var corner: Vector2i
	if horizontal_first:
		corner = Vector2i(to.x, from.y)
	else:
		corner = Vector2i(from.x, to.y)
	_carve_line(data, from, corner)
	_carve_line(data, corner, to)
	return corner

func _carve_line(data: DungeonData, a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var pos: Vector2i = a
	while true:
		_carve_width(data, pos)
		if pos == b:
			break
		pos += step

func _carve_width(data: DungeonData, pos: Vector2i) -> void:
	# Monotonic carving: only WALL ever changes, and only into CORRIDOR.
	if data.get_tile(pos) == DungeonData.Tile.WALL:
		data.set_tile(pos, DungeonData.Tile.CORRIDOR)
	if corridor_width >= 2:
		var side: Vector2i = pos + Vector2i(0, 1)
		if data.get_tile(side) == DungeonData.Tile.WALL:
			data.set_tile(side, DungeonData.Tile.CORRIDOR)
