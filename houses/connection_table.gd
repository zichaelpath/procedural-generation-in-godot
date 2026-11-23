class_name ConnectionTable
extends RefCounted
## Architecture's social rules as data (Marson & Musse's connection
## table). For every room-type pair: may a door exist between them?
## The generator and the validator both read THIS table, so they can
## never silently disagree. Verdicts: FORBIDDEN / ALLOWED / PREFERRED.

const FORBIDDEN := 0
const ALLOWED := 1
const PREFERRED := 2

const MIN_SHARED_WALL: float = 0.9 # a door needs ~0.9 m of wall, not a corner point

const TABLE: Dictionary = {
	"bathroom|bedroom": ALLOWED,
	"bathroom|dining": FORBIDDEN,
	"bathroom|kitchen": FORBIDDEN,
	"bathroom|living": FORBIDDEN,
	"bathroom|wc": ALLOWED,
	"bedroom|bedroom": ALLOWED,
	"bedroom|dining": FORBIDDEN,
	"bedroom|kitchen": FORBIDDEN,
	"bedroom|living": FORBIDDEN,
	"bedroom|wc": ALLOWED,
	"dining|kitchen": PREFERRED,
	"dining|living": PREFERRED,
	"kitchen|living": ALLOWED,
	"living|wc": ALLOWED,
	"dining|wc": FORBIDDEN,
	"kitchen|wc": FORBIDDEN,
}

static func type_of(room_name: String) -> String:
	# The one place that decides what type a room is. Keep it that way.
	if room_name.begins_with("bedroom"):
		return "bedroom"
	if room_name == "master":
		return "bedroom" # a master is a bedroom with better PR
	if room_name.begins_with("bath"):
		return "bathroom"
	if room_name.begins_with("kitchen"):
		return "kitchen" # kitchen_dining counts as kitchen (accepted simplification)
	if room_name.begins_with("dining"):
		return "dining"
	if room_name.begins_with("living"):
		return "living"
	if room_name.begins_with("hall"):
		return "hall"
	if room_name == "wc":
		return "wc"
	return room_name

static func verdict(name_a: String, name_b: String) -> int:
	var ta: String = type_of(name_a)
	var tb: String = type_of(name_b)
	if ta == "hall" or tb == "hall":
		return PREFERRED # the hall is the lobby: it wants every door
	var key: String = ta + "|" + tb if ta < tb else tb + "|" + ta
	return int(TABLE.get(key, ALLOWED))

static func shared_wall_length(a: Rect2, b: Rect2) -> float:
	var tol: float = 0.02
	if absf(a.end.x - b.position.x) < tol or absf(b.end.x - a.position.x) < tol:
		return minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if absf(a.end.y - b.position.y) < tol or absf(b.end.y - a.position.y) < tol:
		return minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	return 0.0

static func adjacencies(rooms: Array) -> Array:
	# Array of {a: int, b: int, shared: float} for pairs with a real wall.
	var out: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var shared: float = shared_wall_length(rooms[i]["rect"], rooms[j]["rect"])
			if shared >= MIN_SHARED_WALL:
				out.append({"a": i, "b": j, "shared": shared})
	return out

static func score_plan(rooms: Array) -> Dictionary:
	var violations: Array = []
	var preferred_found: Array = []
	var pairs: Array = adjacencies(rooms)
	for p in pairs:
		var na: String = rooms[int(p["a"])]["name"]
		var nb: String = rooms[int(p["b"])]["name"]
		var v: int = verdict(na, nb)
		if v == FORBIDDEN:
			violations.append(na + " <-> " + nb)
		elif v == PREFERRED:
			preferred_found.append(na + " <-> " + nb)
	return {"violations": violations, "preferred_found": preferred_found, "checked": pairs.size()}
