class_name GeomorphAssembler
extends RefCounted
## Grows a dungeon from GeomorphLibrary rooms by frontier
## expansion: pick an open socket, find a library room with a
## matching socket on the opposite side, stamp it if it fits.
## Unfillable sockets are SEALED (door cells back to wall) and
## growth continues — placed-vs-requested is printed as a receipt.

const MAP_W: int = 64
const MAP_H: int = 48
# Directions as [dx, dy, opposite]: 0=N, 1=E, 2=S, 3=W.
const DIRS4: Array = [[0, -1, 2], [1, 0, 3], [0, 1, 0], [-1, 0, 1]]

func assemble(master_seed: int, target_rooms: int = 9) -> DungeonData:
	var rng: RandomNumberGenerator = SeedBank.stream_for(master_seed, SeedBank.STREAM_DUNGEON)
	var data := DungeonData.new()
	data.setup(MAP_W, MAP_H)
	var placed: Array = []    # stamped rects, for overlap tests
	var frontier: Array = []  # {cell:Vector2i, dir:int, room_id:int}
	var pool: Array = GeomorphLibrary.rooms()
	# Seed room at the map centre.
	var first: Dictionary = _weighted_room(pool, rng)
	var origin := Vector2i(MAP_W / 2 - _room_size(first).x / 2, MAP_H / 2 - _room_size(first).y / 2)
	var first_id: int = _stamp_room(data, placed, frontier, first, origin)
	data.entrance_room = first_id
	data.start_tile = data.room_by_id(first_id)["center"]
	var guard: int = 0
	while data.rooms.size() < target_rooms and not frontier.is_empty() and guard < 400:
		guard += 1
		var socket: Dictionary = frontier[rng.randi_range(0, frontier.size() - 1)]
		frontier.erase(socket)
		if not _try_attach(data, placed, frontier, pool, rng, socket):
			_seal(data, socket)  # no room fits here: close the door
	print("Geomorphs: placed ", data.rooms.size(), " of ", target_rooms, " requested")
	return data

func _try_attach(data: DungeonData, placed: Array, frontier: Array, pool: Array, rng: RandomNumberGenerator, socket: Dictionary) -> bool:
	var need_dir: int = int(DIRS4[int(socket["dir"])][2])  # candidate's facing side
	# Candidate order comes from the stream (a drawn-key sort), never
	# Array.shuffle() — that draws the global RNG and would break
	# the seed contract the moment order matters. It always matters.
	var order: Array = _stream_shuffled(pool, rng)
	for candidate in order:
		var sockets: Array = _scan_sockets(candidate["rows"])
		for cs in sockets:
			if int(cs["dir"]) != need_dir:
				continue
			var size: Vector2i = _room_size(candidate)
			var origin: Vector2i = _aligned_origin(socket, cs, size)
			var rect := Rect2i(origin, size)
			if not _fits(data, placed, rect, int(socket["room_id"])):
				continue
			var new_id: int = _stamp_room(data, placed, frontier, candidate, origin)
			# The candidate socket that made this connection is now a
			# LIVE door, not an open frontier socket: drop its entry,
			# or a later pick would fail to attach there and _seal()
			# would wall the connection shut (graph/tile split).
			var used_cell: Vector2i = origin + Vector2i(int(cs["x"]), int(cs["y"]))
			for entry in frontier.duplicate():
				if (entry["cell"] as Vector2i) == used_cell:
					frontier.erase(entry)
			# The connection is an edge; the shared socket cell is
			# its door tile. Graph and tiles, same breath (Ch 23).
			data.edges.append({"a": int(socket["room_id"]), "b": new_id,
				"door_tile": socket["cell"], "locked_key": ""})
			return true
	return false

func _stamp_room(data: DungeonData, placed: Array, frontier: Array, def: Dictionary, origin: Vector2i) -> int:
	var rows: Array = def["rows"]
	var size: Vector2i = _room_size(def)
	for y in range(size.y):
		var row: String = rows[y]
		for x in range(size.x):
			var tile: int = DungeonData.Tile.WALL
			match row[x]:
				".":
					tile = DungeonData.Tile.FLOOR
				"D":
					tile = DungeonData.Tile.DOOR
			if tile != DungeonData.Tile.WALL:
				data.set_tile(origin + Vector2i(x, y), tile)
	var rect := Rect2i(origin, size)
	var id: int = data.add_room(rect, [str(def["name"])])
	placed.append(rect)
	for s in _scan_sockets(rows):
		var cell: Vector2i = origin + Vector2i(int(s["x"]), int(s["y"]))
		frontier.append({"cell": cell, "dir": int(s["dir"]), "room_id": id})
	return id

func _fits(data: DungeonData, placed: Array, rect: Rect2i, owner_id: int = -1) -> bool:
	if rect.position.x < 1 or rect.position.y < 1:
		return false
	if rect.position.x + rect.size.x > data.width - 1 or rect.position.y + rect.size.y > data.height - 1:
		return false
	for i in range(placed.size()):
		var p: Rect2i = placed[i]
		# FIX (build): the listing grew EVERY placed rect by 1, but a
		# socket-attached candidate's rect always ABUTS its owner's
		# rect (its socket cell lands exactly one step beyond the
		# owner's), so the grown test rejected every attachment —
		# assembly placed 1 of 9 rooms on every seed. The owner may
		# be abutted (that abutment IS the connection); the one-cell
		# rock margin still applies against every other room.
		var margin: int = 0 if i == owner_id else 1
		if rect.intersects(p.grow(margin)):
			return false  # one cell of rock between geomorphs, always
	return true

func _aligned_origin(socket: Dictionary, candidate_socket: Dictionary, size: Vector2i) -> Vector2i:
	# The candidate's socket cell must land exactly one step beyond
	# the frontier socket, in the frontier socket's direction.
	var dir: int = int(socket["dir"])
	var step := Vector2i(int(DIRS4[dir][0]), int(DIRS4[dir][1]))
	var target_cell: Vector2i = (socket["cell"] as Vector2i) + step
	return target_cell - Vector2i(int(candidate_socket["x"]), int(candidate_socket["y"]))

## Finds border 'D' cells and their outward directions.
func _scan_sockets(rows: Array) -> Array:
	var out: Array = []
	var h: int = rows.size()
	var w: int = (rows[0] as String).length()
	for y in range(h):
		var row: String = rows[y]
		for x in range(w):
			if row[x] != "D":
				continue
			var dir: int = -1
			if y == 0:
				dir = 0
			elif x == w - 1:
				dir = 1
			elif y == h - 1:
				dir = 2
			elif x == 0:
				dir = 3
			if dir >= 0:
				out.append({"x": x, "y": y, "dir": dir})
	return out

func _seal(data: DungeonData, socket: Dictionary) -> void:
	data.set_tile(socket["cell"], DungeonData.Tile.WALL)

func _room_size(def: Dictionary) -> Vector2i:
	var rows: Array = def["rows"]
	return Vector2i((rows[0] as String).length(), rows.size())

func _weighted_room(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for def in pool:
		total += float(def.get("weight", 1.0))
	var roll: float = rng.randf() * total
	for def in pool:
		roll -= float(def.get("weight", 1.0))
		if roll <= 0.0:
			return def
	return pool[pool.size() - 1]

func _stream_shuffled(pool: Array, rng: RandomNumberGenerator) -> Array:
	var keyed: Array = []
	for def in pool:
		keyed.append({"key": rng.randf(), "def": def})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["key"]) < float(b["key"]))
	var out: Array = []
	for k in keyed:
		out.append(k["def"])
	return out
