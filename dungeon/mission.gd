class_name MissionPlanner
extends RefCounted
## Mission structure as annotation: roles read off the room graph
## (BFS distances), stored in data.roles. The planner never touches
## a tile — mission is a READING of a dungeon that already exists.

## Assigns entrance / boss / treasure / normal into data.roles.
## Boss = farthest room from the entrance BY GRAPH DISTANCE.
## Treasure = dead ends OFF the critical path, farthest first:
## a dead end must be paid for (Ch 20), and a dead end on the path
## is not a detour, so it does not qualify.
func annotate(data: DungeonData) -> void:
	data.roles.clear()
	if data.rooms.is_empty() or data.entrance_room < 0:
		return
	var dist: Dictionary = data.bfs_room_distances(data.entrance_room)
	var boss: int = data.entrance_room
	var boss_dist: int = -1
	for room in data.rooms:
		var id: int = int(room["id"])
		if dist.has(id) and int(dist[id]) > boss_dist:
			boss_dist = int(dist[id])
			boss = id
	var path: Array = data.room_path(data.entrance_room, boss)
	var on_path: Dictionary = {}
	for id in path:
		on_path[int(id)] = true
	var adj: Dictionary = data.adjacency()
	var treasure_candidates: Array = []
	for room in data.rooms:
		var id: int = int(room["id"])
		if id == data.entrance_room or id == boss or on_path.has(id):
			continue
		if (adj[id] as Array).size() == 1:
			treasure_candidates.append(id)
	treasure_candidates.sort_custom(func(a: int, b: int) -> bool:
		return int(dist.get(a, 0)) > int(dist.get(b, 0)))
	for room in data.rooms:
		var id: int = int(room["id"])
		if id == data.entrance_room:
			data.roles[id] = "entrance"
		elif id == boss:
			data.roles[id] = "boss"
		elif treasure_candidates.has(id):
			data.roles[id] = "treasure"
		else:
			data.roles[id] = "normal"
	print("Mission: entrance ", data.entrance_room, " -> boss ", boss,
		" (path ", path.size(), " rooms); treasure rooms: ", treasure_candidates)

## The story, exactly: entrance room to boss room, in order.
func critical_path(data: DungeonData) -> Array:
	var boss: int = -1
	for id in data.roles.keys():
		if str(data.roles[id]) == "boss":
			boss = int(id)
	if boss < 0 or data.entrance_room < 0:
		return []
	return data.room_path(data.entrance_room, boss)

## Locks one critical-path edge (second half) with `key_id`, and
## places the key in a room reachable WITHOUT that edge and off
## the path — by construction, never behind its own lock. Returns
## true if a legal placement existed on this dungeon.
func lock_and_key(data: DungeonData, key_id: String = "brass") -> bool:
	var path: Array = critical_path(data)
	if path.size() < 3:
		return false  # too short to gate: a 2-room story has no "late"
	# Candidate lock edges: consecutive path pairs in the 2nd half.
	var lock_a: int = -1
	var lock_b: int = -1
	for i in range(path.size() - 1):
		if i >= (path.size() - 1) / 2:
			lock_a = int(path[i])
			lock_b = int(path[i + 1])
			break
	# Reachable WITHOUT the locked edge: the key's legal world.
	var adj: Dictionary = data.adjacency()
	var reach: Dictionary = {data.entrance_room: 0}
	var queue: Array[int] = [data.entrance_room]
	while not queue.is_empty():
		var current: int = queue[0]
		queue.remove_at(0)
		for next in adj.get(current, []):
			var n: int = int(next)
			if (current == lock_a and n == lock_b) or (current == lock_b and n == lock_a):
				continue  # the locked edge does not exist for this walk
			if not reach.has(n):
				reach[n] = int(reach[current]) + 1
				queue.append(n)
	var on_path: Dictionary = {}
	for id in path:
		on_path[int(id)] = true
	# Prefer a treasure room, then any dead end, then any branch.
	var key_room: int = -1
	for want_treasure in [true, false]:
		for id in reach.keys():
			var rid: int = int(id)
			if on_path.has(rid) or rid == data.entrance_room:
				continue
			var is_treasure: bool = str(data.roles.get(rid, "")) == "treasure"
			if want_treasure and not is_treasure:
				continue
			if (adj[rid] as Array).size() == 1 or not want_treasure:
				key_room = rid
				break
		if key_room >= 0:
			break
	if key_room < 0:
		return false  # no legal key room: this dungeon declines a lock
	# Write it: the edge record carries the lock; the key list
	# carries the key. Both are data (Ch 20's model, unchanged).
	for edge in data.edges:
		if (int(edge["a"]) == lock_a and int(edge["b"]) == lock_b) or (int(edge["a"]) == lock_b and int(edge["b"]) == lock_a):
			edge["locked_key"] = key_id
	data.keys.append({"key_id": key_id, "room_id": key_room})
	print("Lock: edge ", lock_a, "-", lock_b, " needs '", key_id,
		"'; key in room ", key_room, " (reachable without the lock)")
	return true

## The proof: state-space BFS over (room, keys held). Returns a
## Dictionary: {"completable": bool, "order": Array} where order
## is one witness — the rooms in first-visit order on a finishing
## walk. An empty order with completable=false is a verdict, and
## the dungeon that produced it is a bug report, not bad luck.
func is_completable(data: DungeonData) -> Dictionary:
	var start_keys: Array = _keys_in_room(data, data.entrance_room)
	var start_state: String = _state_name(data.entrance_room, start_keys)
	var seen: Dictionary = {start_state: true}
	var queue: Array = [{"room": data.entrance_room, "keys": start_keys, "order": [data.entrance_room]}]
	while not queue.is_empty():
		var state: Dictionary = queue[0]
		queue.remove_at(0)
		var room: int = int(state["room"])
		var held: Array = state["keys"]
		if str(data.roles.get(room, "")) == "boss":
			return {"completable": true, "order": state["order"]}
		for next in data.passable_neighbours(room, held):
			var n: int = int(next)
			var new_keys: Array = held.duplicate()
			for k in _keys_in_room(data, n):
				if not new_keys.has(k):
					new_keys.append(k)
			var name: String = _state_name(n, new_keys)
			if seen.has(name):
				continue
			seen[name] = true
			var order: Array = (state["order"] as Array).duplicate()
			if not order.has(n):
				order.append(n)
			queue.append({"room": n, "keys": new_keys, "order": order})
	return {"completable": false, "order": []}

func _keys_in_room(data: DungeonData, room_id: int) -> Array:
	var out: Array = []
	for k in data.keys:
		if int(k["room_id"]) == room_id:
			out.append(str(k["key_id"]))
	return out

func _state_name(room: int, keys: Array) -> String:
	var sorted: Array = keys.duplicate()
	sorted.sort()
	return str(room) + "|" + ",".join(sorted)
