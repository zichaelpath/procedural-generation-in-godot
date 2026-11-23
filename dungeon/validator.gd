class_name DungeonValidator
extends RefCounted
## The gate: four checks over any DungeonData, each PASS or a
## NAMED CULPRIT. A validator that prints numbers is a colleague;
## one that prints "invalid" is a rumour.

static func validate(data: DungeonData) -> Dictionary:
	var results: Array = []
	# 1. Tile reachability: flood from the start tile must reach
	# every passable tile. (The field-note check, mechanised.)
	var reached: Dictionary = data.reachable_tiles(data.start_tile)
	var unreached: Array = []
	for y in range(data.height):
		for x in range(data.width):
			var pos := Vector2i(x, y)
			if data.is_passable(pos) and not reached.has(pos):
				unreached.append(pos)
	if unreached.is_empty():
		results.append({"check": "reachability", "pass": true,
			"detail": "%d passable tiles, all reached" % reached.size()})
	else:
		results.append({"check": "reachability", "pass": false,
			"detail": "%d tiles unreached, first at %s; regions %s" % [
				unreached.size(), str(unreached[0]), str(data.region_report())]})
	# 2. Room reachability (the graph face of check 1).
	if data.rooms.is_empty():
		results.append({"check": "rooms", "pass": true, "detail": "no rooms asserted (cave/WFC output)"})
	else:
		var dist: Dictionary = data.bfs_room_distances(data.entrance_room)
		var missing: Array = []
		for room in data.rooms:
			if not dist.has(int(room["id"])):
				missing.append(int(room["id"]))
		if missing.is_empty():
			results.append({"check": "rooms", "pass": true,
				"detail": "all %d rooms reached" % data.rooms.size()})
		else:
			results.append({"check": "rooms", "pass": false,
				"detail": "rooms unreached: %s" % str(missing)})
	# 3. Spawn sanity: manifest cells passable, unique, not doorways.
	var seen_cells: Dictionary = {}
	var spawn_problem: String = ""
	for manifest_name in ["dressing", "spawns"]:
		for item in data.meta.get(manifest_name, []):
			var cell: Vector2i = item["cell"]
			if not data.is_passable(cell):
				spawn_problem = "%s %s on impassable %s" % [manifest_name, str(item["kind"]), str(cell)]
			elif seen_cells.has(cell):
				spawn_problem = "two placements share %s" % str(cell)
			elif not Dressing._is_clear_doorway(data, cell):
				spawn_problem = "%s %s blocks a doorway at %s" % [manifest_name, str(item["kind"]), str(cell)]
			seen_cells[cell] = true
	results.append({"check": "spawns", "pass": spawn_problem == "",
		"detail": "manifests clean" if spawn_problem == "" else spawn_problem})
	# 4. Completability, with the secret-door rider: the solver's
	# verdict (truth), plus the design judgement it does not make.
	if data.roles.is_empty():
		results.append({"check": "completability", "pass": true, "detail": "no mission annotated"})
	else:
		var verdict: Dictionary = MissionPlanner.new().is_completable(data)
		var detail: String = "witness order: %s" % str(verdict["order"])
		if bool(verdict["completable"]):
			# Rider: remove secret edges; the boss must still be
			# reachable, or progress is gated on a secret.
			var boss: int = -1
			for id in data.roles.keys():
				if str(data.roles[id]) == "boss":
					boss = int(id)
			var adj: Dictionary = {}
			for room in data.rooms:
				adj[int(room["id"])] = []
			for edge in data.edges:
				if str(edge.get("kind", "open")) == "secret":
					continue
				(adj[int(edge["a"])] as Array).append(int(edge["b"]))
				(adj[int(edge["b"])] as Array).append(int(edge["a"]))
			var seen_rooms: Dictionary = {data.entrance_room: true}
			var queue: Array[int] = [data.entrance_room]
			while not queue.is_empty():
				var cur: int = queue[0]
				queue.remove_at(0)
				for n in adj.get(cur, []):
					if not seen_rooms.has(int(n)):
						seen_rooms[int(n)] = true
						queue.append(int(n))
			if boss >= 0 and not seen_rooms.has(boss):
				results.append({"check": "completability", "pass": false,
					"detail": "boss reachable ONLY through a secret door"})
			else:
				results.append({"check": "completability", "pass": true, "detail": detail})
		else:
			results.append({"check": "completability", "pass": false,
				"detail": "solver found no finishing order"})
	var all_pass: bool = true
	for r in results:
		if not bool(r["pass"]):
			all_pass = false
		print("VALIDATE ", "PASS " if bool(r["pass"]) else "FAIL ",
			str(r["check"]), " — ", str(r["detail"]))
	return {"pass": all_pass, "results": results}
