class_name Population
extends RefCounted
## Population reads the same metadata as dressing and emits the
## spawn manifest into data.meta["spawns"]: loot scaled by graph
## distance (the walk is the price), enemies budgeted by room
## area and scaled by depth, exactly one boss — roles are
## singular by construction (Ch 24).

static func populate(data: DungeonData, rng: RandomNumberGenerator, enemy_budget_multiplier: float = 1.0) -> Array:
	var spawns: Array = []
	var occupied: Dictionary = {}
	for item in data.meta.get("dressing", []):
		occupied[item["cell"]] = true
	var dist: Dictionary = data.bfs_room_distances(data.entrance_room)
	for room in data.rooms:
		var id: int = int(room["id"])
		var role: String = str(data.roles.get(id, "normal"))
		var depth: int = int(dist.get(id, 0))
		var cells: Array = Dressing._room_floor_cells(data, room["rect"])
		var safe: Array = []
		for cell in cells:
			if Dressing._is_clear_doorway(data, cell) and not occupied.has(cell):
				safe.append(cell)
		if safe.is_empty():
			continue
		if role == "boss":
			var cell: Vector2i = safe[rng.randi_range(0, safe.size() - 1)]
			occupied[cell] = true
			spawns.append({"kind": "boss", "cell": cell, "room_id": id, "tier": 3})
		elif role == "treasure":
			var loot_count: int = 1 + depth / 3
			for n in mini(loot_count, safe.size()):
				var cell2: Vector2i = safe[rng.randi_range(0, safe.size() - 1)]
				if occupied.has(cell2):
					continue
				occupied[cell2] = true
				spawns.append({"kind": "loot", "cell": cell2, "room_id": id,
					"tier": 1 if depth < 3 else (2 if depth < 6 else 3)})
		elif role == "normal":
			var area: int = (room["rect"] as Rect2i).size.x * (room["rect"] as Rect2i).size.y
			var enemies: int = int(round(float(area) / 18.0 * (0.6 + float(depth) * 0.15) * enemy_budget_multiplier))
			var placed_e: int = 0
			for cell in safe:
				if placed_e >= enemies:
					break
				if rng.randf() < 0.5:
					continue
				occupied[cell] = true
				spawns.append({"kind": "enemy", "cell": cell, "room_id": id,
					"tier": 1 if depth < 4 else 2})
				placed_e += 1
	data.meta["spawns"] = spawns
	print("Population: ", spawns.size(), " spawns")
	return spawns
