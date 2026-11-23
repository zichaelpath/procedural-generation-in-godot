class_name DoorGraph
extends RefCounted
## Everything graph-shaped about doors: where shared walls are,
## which of them get doors (the ConnectionTable decides), and the
## room graph those doors create. Doors are data:
## {a, b, center, horizontal, width} — a/b are room indices in the
## classic pass below, room NAMES in Ch 29's hall-centred pass.

const MIN_SHARED_WALL: float = 0.9
const DOOR_WIDTH: float = 0.9
const OPENING_WIDTH: float = 1.7
const CORNER_CLEARANCE: float = 0.45

static func shared_segment(a: Rect2, b: Rect2) -> Dictionary:
	# The shared wall as geometry: {length, horizontal, fixed, from,
	# to} for this chapter, plus {center, start, vertical} — the same
	# segment in the form Ch 29's graph and Ch 30's builder consume.
	# One function, one segment, every consumer.
	var tol: float = 0.02
	if absf(a.end.x - b.position.x) < tol or absf(b.end.x - a.position.x) < tol:
		var x: float = a.end.x if absf(a.end.x - b.position.x) < tol else b.end.x
		var from_y: float = maxf(a.position.y, b.position.y)
		var to_y: float = minf(a.end.y, b.end.y)
		return {"length": to_y - from_y, "horizontal": false, "fixed": x, "from": from_y, "to": to_y,
			"center": Vector2(x, (from_y + to_y) * 0.5), "start": Vector2(x, from_y), "vertical": true}
	if absf(a.end.y - b.position.y) < tol or absf(b.end.y - a.position.y) < tol:
		var y: float = a.end.y if absf(a.end.y - b.position.y) < tol else b.end.y
		var from_x: float = maxf(a.position.x, b.position.x)
		var to_x: float = minf(a.end.x, b.end.x)
		return {"length": to_x - from_x, "horizontal": true, "fixed": y, "from": from_x, "to": to_x,
			"center": Vector2((from_x + to_x) * 0.5, y), "start": Vector2(from_x, y), "vertical": false}
	return {"length": 0.0, "horizontal": false, "fixed": 0.0, "from": 0.0, "to": 0.0,
		"center": Vector2.ZERO, "start": Vector2.ZERO, "vertical": false}

static func place_doors(rooms: Array, respect_table: bool = true) -> Array:
	var doors: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var seg: Dictionary = shared_segment(rooms[i]["rect"], rooms[j]["rect"])
			if float(seg["length"]) < MIN_SHARED_WALL:
				continue
			var v: int = ConnectionTable.verdict(rooms[i]["name"], rooms[j]["name"])
			if respect_table and v == ConnectionTable.FORBIDDEN:
				continue
			var width: float = DOOR_WIDTH
			if v == ConnectionTable.PREFERRED and _is_flow_pair(rooms[i]["name"], rooms[j]["name"]):
				width = OPENING_WIDTH
			var mid: float = (float(seg["from"]) + float(seg["to"])) * 0.5
			var lo: float = float(seg["from"]) + CORNER_CLEARANCE + width * 0.5
			var hi: float = float(seg["to"]) - CORNER_CLEARANCE - width * 0.5
			if lo > hi:
				continue # the door physically does not fit this wall
			var c: float = clampf(mid, lo, hi)
			var center: Vector2 = Vector2(c, float(seg["fixed"])) if bool(seg["horizontal"]) else Vector2(float(seg["fixed"]), c)
			doors.append({"a": i, "b": j, "center": center, "horizontal": bool(seg["horizontal"]), "width": width})
	return doors

static func _is_flow_pair(name_a: String, name_b: String) -> bool:
	var types: Array = [ConnectionTable.type_of(name_a), ConnectionTable.type_of(name_b)]
	types.sort()
	return types == ["dining", "kitchen"] or types == ["dining", "living"]

static func build_graph(room_count: int, doors: Array) -> Array:
	var graph: Array = []
	graph.resize(room_count)
	for i in room_count:
		graph[i] = []
	for d in doors:
		graph[int(d["a"])].append(int(d["b"]))
		graph[int(d["b"])].append(int(d["a"]))
	return graph

static func entrance_index(rooms: Array) -> int:
	# The entrance room is the hall when the program has one.
	for i in rooms.size():
		if String(rooms[i]["name"]).begins_with("hall"):
			return i
	return 0

static func bfs_reachable(graph: Array, start: int) -> Array:
	var visited: Array = []
	visited.resize(graph.size())
	for i in graph.size():
		visited[i] = false
	var queue: Array = [start]
	visited[start] = true
	while not queue.is_empty():
		var node: int = int(queue.pop_front())
		for next in graph[node]:
			if not visited[int(next)]:
				visited[int(next)] = true
				queue.append(int(next))
	return visited

static func ensure_connected(rooms: Array, doors: Array) -> Array:
	# Mutates `doors` (appends rescues) and returns report lines.
	# A rescue must (a) join the stranded room to the REACHED part of
	# the house, (b) respect the connection table — no exceptions,
	# (c) use the longest available shared wall. If no legal rescue
	# exists, it says so instead of cutting an illegal door.
	var report: Array = []
	var start: int = entrance_index(rooms)
	while true:
		var graph: Array = build_graph(rooms.size(), doors)
		var visited: Array = bfs_reachable(graph, start)
		var stranded: int = -1
		for i in rooms.size():
			if not visited[i]:
				stranded = i
				break
		if stranded == -1:
			report.append("Connectivity: all %d rooms reachable." % rooms.size())
			return report
		var best: int = -1
		var best_len: float = 0.0
		for j in rooms.size():
			if j == stranded or not visited[j]:
				continue
			var seg: Dictionary = shared_segment(rooms[stranded]["rect"], rooms[j]["rect"])
			if float(seg["length"]) < MIN_SHARED_WALL:
				continue
			if ConnectionTable.verdict(rooms[stranded]["name"], rooms[j]["name"]) == ConnectionTable.FORBIDDEN:
				continue
			if float(seg["length"]) > best_len:
				best_len = float(seg["length"])
				best = j
		if best == -1:
			report.append("Connectivity FAILED: %s has no legal rescue door." % rooms[stranded]["name"])
			return report
		var seg2: Dictionary = shared_segment(rooms[stranded]["rect"], rooms[best]["rect"])
		var mid: float = (float(seg2["from"]) + float(seg2["to"])) * 0.5
		var lo: float = float(seg2["from"]) + CORNER_CLEARANCE + DOOR_WIDTH * 0.5
		var hi: float = float(seg2["to"]) - CORNER_CLEARANCE - DOOR_WIDTH * 0.5
		var c: float = clampf(mid, lo, hi)
		var center: Vector2 = Vector2(c, float(seg2["fixed"])) if bool(seg2["horizontal"]) else Vector2(float(seg2["fixed"]), c)
		doors.append({"a": stranded, "b": best, "center": center, "horizontal": bool(seg2["horizontal"]), "width": DOOR_WIDTH})
		report.append("Rescue: %s connected to %s via %.1f m wall." % [rooms[stranded]["name"], rooms[best]["name"], best_len])
	return report # unreachable (the loop returns) — GDScript's return-path analysis requires it

# --- Hall-centred door graph (Ch 29) -----------------------------------
# Rooms are nodes (by NAME), doors are edges. Bedrooms, master,
# bathroom, WC open ONLY onto the hall; kitchen<->dining is a wide
# OPENING, not a door; the entrance exists ONLY in the hall —
# asserted, never assumed.
const ENTRANCE_WIDTH: float = 1.0
const DOOR_MARGIN: float = 0.3

static func _room_named(plan: Dictionary, room_name: String) -> Dictionary:
	for room in plan["rooms"]:
		if room["name"] == room_name:
			return room
	return {}

static func _rooms_of_type_v2(plan: Dictionary, room_type: String) -> Array:
	var found: Array = []
	for room in plan["rooms"]:
		if room["type"] == room_type:
			found.append(room)
	return found

static func _add_door_v2(doors: Array, a: Dictionary, b: Dictionary, kind: String, width: float) -> void:
	var segment: Dictionary = shared_segment(a["rect"], b["rect"])
	if float(segment["length"]) < width + DOOR_MARGIN:
		return # wall segment too short for a usable door: propose nothing here
	doors.append({"a": a["name"], "b": b["name"], "kind": kind, "width": width,
		"center": segment["center"], "vertical": segment["vertical"]})

static func build_doors(plan: Dictionary) -> Array:
	# The entrance is asserted, never assumed.
	if plan["entrance_room"] != "hall":
		push_error("DoorGraph: entrance_room is '%s', not 'hall' — plan rejected" % plan["entrance_room"])
		plan["doors"] = []
		return []
	var doors: Array = []
	var hall: Dictionary = _room_named(plan, "hall")
	if hall.is_empty():
		push_error("DoorGraph: no hall room in plan — plan rejected")
		plan["doors"] = []
		return []
	# The entrance vestibule is hall space: it joins the corridor.
	var entry: Dictionary = _room_named(plan, "hall_entry")
	if not entry.is_empty():
		_add_door_v2(doors, entry, hall, "door", DOOR_WIDTH)
	# A stair room (Ch 30 two-storey plans) joins the hall like the vestibule.
	var stairs: Dictionary = _room_named(plan, "stairs")
	if not stairs.is_empty():
		_add_door_v2(doors, stairs, hall, "door", DOOR_WIDTH)
	# Private rooms open ONLY onto the hall.
	for private_room in plan["rooms"]:
		var room_type: String = private_room["type"]
		if room_type == "bedroom" or room_type == "master" or room_type == "bathroom" or room_type == "wc":
			_add_door_v2(doors, private_room, hall, "door", DOOR_WIDTH)
	# Hall opens to the social end.
	for living in _rooms_of_type_v2(plan, "living"):
		_add_door_v2(doors, hall, living, "door", DOOR_WIDTH)
	for kd in _rooms_of_type_v2(plan, "kitchen_dining"):
		_add_door_v2(doors, hall, kd, "door", DOOR_WIDTH)
	# FIX (Ch 30): a family room is social living space and must open
	# onto the hall like the living room — Listing 29.7 names no door
	# rule for type "family", so Ch 30's two-storey ground floor
	# (Listing 30.12) could never satisfy all_reachable().
	for fam in _rooms_of_type_v2(plan, "family"):
		_add_door_v2(doors, hall, fam, "door", DOOR_WIDTH)
	# Separate kitchen and dining: hall reaches the dining room, and
	# the kitchen joins it by a wide open-plan opening, not a door.
	var kitchens: Array = _rooms_of_type_v2(plan, "kitchen")
	var dinings: Array = _rooms_of_type_v2(plan, "dining")
	if not kitchens.is_empty() and not dinings.is_empty():
		_add_door_v2(doors, hall, dinings[0], "door", DOOR_WIDTH)
		_add_door_v2(doors, kitchens[0], dinings[0], "opening", OPENING_WIDTH)
	# Living and the kitchen-dining zone share a wide opening, too.
	for living in _rooms_of_type_v2(plan, "living"):
		for kd in _rooms_of_type_v2(plan, "kitchen_dining"):
			_add_door_v2(doors, living, kd, "opening", OPENING_WIDTH)
	# Entrance: in the hall's vestibule, on the south wall, at entrance_x.
	# (Ch 30: upper floors skip this via meta["no_entrance"].)
	if not bool(plan["meta"].get("no_entrance", false)):
		var footprint: Rect2 = plan["footprint"]
		var entrance_x: float = float(plan["meta"]["entrance_x"])
		doors.append({"a": "hall_entry", "b": "EXTERIOR", "kind": "entrance", "width": ENTRANCE_WIDTH,
			"center": Vector2(entrance_x, footprint.end.y), "vertical": false})
	plan["doors"] = doors
	return doors

# Breadth-first search from the hall over the door graph (EXTERIOR ignored:
# the entrance is how the graph talks to the street, not a room you can
# stand in — including it would let the search step outside and back in).
static func all_reachable(plan: Dictionary) -> bool:
	var doors: Array = plan["doors"]
	var visited: Array = ["hall"]
	var frontier: Array = ["hall"]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for door in doors:
			var other: String = ""
			if door["a"] == current:
				other = door["b"]
			elif door["b"] == current:
				other = door["a"]
			if other != "" and other != "EXTERIOR" and not visited.has(other):
				visited.append(other)
				frontier.append(other)
	for room in plan["rooms"]:
		if not visited.has(room["name"]):
			return false
	return true
