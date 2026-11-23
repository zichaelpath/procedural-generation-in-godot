class_name Dressing
extends RefCounted
## Dressing reads METADATA — role, tags, area, graph distance —
## and emits a placement manifest into data.meta["dressing"].
## It spawns nothing: a renderer consumes the manifest. Rules:
## never block a doorway, never claim a cell twice.

static func dress(data: DungeonData, rng: RandomNumberGenerator) -> Array:
	var items: Array = []
	var occupied: Dictionary = {}
	for p in data.meta.get("pillars", []):
		occupied[p] = true
		items.append({"kind": "pillar", "cell": p})
	var dist: Dictionary = data.bfs_room_distances(data.entrance_room)
	for room in data.rooms:
		var id: int = int(room["id"])
		var rect: Rect2i = room["rect"]
		var role: String = str(data.roles.get(id, "normal"))
		var cells: Array = _room_floor_cells(data, rect)
		# Torches: two per room on wall-adjacent floor, more if grand.
		var torch_count: int = 4 if (room["tags"] as Array).has("grand") else 2
		var torches: int = 0
		for cell in cells:
			if torches >= torch_count:
				break
			if _is_clear_doorway(data, cell) and not occupied.has(cell) and _touches_wall(data, cell):
				occupied[cell] = true
				items.append({"kind": "torch", "cell": cell, "room_id": id})
				torches += 1
		# Props by role: treasure rooms get the goods, cave-tagged
		# rooms get rubble, the boss room gets its throne-side braziers.
		var prop_kind: String = ""
		var prop_count: int = 0
		if role == "treasure":
			prop_kind = "chest"
			prop_count = 2
		elif (room["tags"] as Array).has("cave"):
			prop_kind = "rubble"
			prop_count = 3
		elif role == "boss":
			prop_kind = "brazier"
			prop_count = 2
		var placed_props: int = 0
		var shuffled: Array = cells.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Vector2i = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		for cell in shuffled:
			if placed_props >= prop_count:
				break
			if _is_clear_doorway(data, cell) and not occupied.has(cell):
				occupied[cell] = true
				items.append({"kind": prop_kind, "cell": cell, "room_id": id})
				placed_props += 1
	data.meta["dressing"] = items
	print("Dressing: ", items.size(), " placements")
	return items

static func _room_floor_cells(data: DungeonData, rect: Rect2i) -> Array:
	var out: Array = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if data.get_tile(pos) == DungeonData.Tile.FLOOR:
				out.append(pos)
	return out

static func _is_clear_doorway(data: DungeonData, cell: Vector2i) -> bool:
	for edge in data.edges:
		var door: Vector2i = edge["door_tile"]
		if abs(door.x - cell.x) <= 1 and abs(door.y - cell.y) <= 1:
			return false
	return true

static func _touches_wall(data: DungeonData, cell: Vector2i) -> bool:
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if data.get_tile(cell + dir) == DungeonData.Tile.WALL:
			return true
	return false
