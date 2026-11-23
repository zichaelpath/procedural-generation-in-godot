class_name HouseRules
extends RefCounted
## The golden rules, minus the mysticism: minimums distilled from
## furniture sizes and bodies, enforced by a standalone validator.
## It generates nothing; it grades. Every violation is a STRING that
## carries its numbers — a message you must re-measure is a bad
## message. Hard violations and soft warnings are kept in separate
## lists forever (§29.3): illegal plan vs uninspiring plan.

const MINIMUMS: Dictionary = {
	"living": {"min_area": 14.0},
	"kitchen": {"min_area": 6.0},
	"kitchen_dining": {"min_area": 14.0}, # explicit: never judge a combined room as a kitchen
	"dining": {"min_area": 8.0},
	"bedroom": {"min_area": 8.0, "min_short_side": 2.6},
	"master": {"min_area": 9.0, "min_short_side": 2.6},
	"bathroom": {"min_area": 3.5},
	"wc": {"min_area": 1.2},
	"family": {"min_area": 8.0},
	"hall": {"min_area": 3.0, "min_short_side": 1.2}, # the hall's short side IS its corridor depth
}

static func check_minimums(plan: Dictionary) -> Array:
	var violations: Array = []
	for room in plan["rooms"]:
		if not room.has("rect"):
			continue
		var room_name: String = room["name"]
		var rule: Dictionary = MINIMUMS.get(room["type"], {})
		if rule.is_empty():
			continue
		var rect: Rect2 = room["rect"]
		var area: float = rect.get_area()
		if rule.has("min_area") and area < float(rule["min_area"]) - 0.001:
			violations.append("MINIMUM %s area %.1f m² < minimum %.1f m²" % [room_name, area, float(rule["min_area"])])
		if rule.has("min_short_side"):
			var short_side: float = minf(rect.size.x, rect.size.y)
			if short_side < float(rule["min_short_side"]) - 0.001:
				violations.append("MINIMUM %s short side %.2f m < minimum %.2f m (area alone lies)" % [room_name, short_side, float(rule["min_short_side"])])
	return violations

# --- Proportion rules -------------------------------------------------
# Hard cap: NO room may be skinnier than this, whatever its type.
const ASPECT_HARD_MAX: float = 1.8
# Soft band: living spaces in real houses cluster inside this range.
# Outside it is a warning ("uninspiring"), never a violation ("illegal").
const LIVING_BAND_MIN: float = 1.3
const LIVING_BAND_MAX: float = 1.7
const LIVING_TYPES: Array = ["living", "dining", "kitchen_dining", "family"]

static func aspect_of(rect: Rect2) -> float:
	var long_side: float = maxf(rect.size.x, rect.size.y)
	var short_side: float = minf(rect.size.x, rect.size.y)
	if short_side <= 0.01:
		return 99.0 # degenerate rectangle: report as terrible, never divide by zero
	return long_side / short_side

static func check_proportions(plan: Dictionary) -> Dictionary:
	var violations: Array = []
	var warnings: Array = []
	for room in plan["rooms"]:
		# FIX (Ch 29): circulation is exempt from the aspect cap. As
		# printed, Listing 29.3 applies the 1.8 cap to EVERY room, but
		# Listing 29.5's hall corridor is full-width by construction
		# (~10.5 x 1.4 m, aspect ~7.7) and the vestibule is 1.4 m wide
		# by construction — no band plan could EVER pass, and the
		# solver would be unsatisfiable. Corridors and stairs are
		# governed by the MINIMUMS table (min_short_side) instead.
		if String(room.get("zone", "")) == "circulation":
			continue
		var room_name: String = room["name"]
		var room_type: String = room["type"]
		var aspect: float = aspect_of(room["rect"])
		if aspect > ASPECT_HARD_MAX + 0.001:
			violations.append("PROPORTION %s aspect %.2f exceeds hard cap %.2f" % [room_name, aspect, ASPECT_HARD_MAX])
		elif LIVING_TYPES.has(room_type) and (aspect < LIVING_BAND_MIN or aspect > LIVING_BAND_MAX):
			warnings.append("PROPORTION %s aspect %.2f outside golden band %.1f-%.1f (legal, uninspiring)" % [room_name, aspect, LIVING_BAND_MIN, LIVING_BAND_MAX])
	return {"violations": violations, "warnings": warnings}

# --- Zoning rules ------------------------------------------------------
# Two rooms are neighbours only if they share a wall SEGMENT of usable
# length. Corner-touching is not adjacency (Ch 28's lesson, kept).
const ADJACENCY_MIN: float = 0.5

static func _shared_length(a: Rect2, b: Rect2) -> float:
	if absf(a.end.x - b.position.x) < 0.02 or absf(b.end.x - a.position.x) < 0.02:
		var overlap_y: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
		return maxf(overlap_y, 0.0)
	if absf(a.end.y - b.position.y) < 0.02 or absf(b.end.y - a.position.y) < 0.02:
		var overlap_x: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
		return maxf(overlap_x, 0.0)
	return 0.0

static func _adjacent(a: Rect2, b: Rect2) -> bool:
	return _shared_length(a, b) >= ADJACENCY_MIN

static func _rooms_of_type(plan: Dictionary, room_type: String) -> Array:
	var found: Array = []
	for room in plan["rooms"]:
		if room["type"] == room_type:
			found.append(room)
	return found

static func _rooms_of_zone(plan: Dictionary, zone: String) -> Array:
	var found: Array = []
	for room in plan["rooms"]:
		if room["zone"] == zone:
			found.append(room)
	return found

static func check_zoning(plan: Dictionary) -> Array:
	var violations: Array = []
	var rooms: Array = plan["rooms"]
	var footprint: Rect2 = plan["footprint"]
	# Rule 1: every bathroom must share a wall with the bedroom cluster
	# (wet rooms cluster with beds, not with social rooms).
	var bedrooms: Array = []
	bedrooms.append_array(_rooms_of_type(plan, "bedroom"))
	bedrooms.append_array(_rooms_of_type(plan, "master"))
	for bath in _rooms_of_type(plan, "bathroom"):
		var against_cluster: bool = false
		for bed in bedrooms:
			if _adjacent(bath["rect"], bed["rect"]):
				against_cluster = true
		if not against_cluster:
			violations.append("ZONING %s is not against the bedroom cluster (wet rooms cluster with beds, not with social rooms)" % bath["name"])
	# Rule 2: kitchen must touch dining. A combined kitchen_dining room
	# satisfies the relationship by construction, so it passes itself.
	var kitchens: Array = _rooms_of_type(plan, "kitchen")
	var dinings: Array = _rooms_of_type(plan, "dining")
	if not kitchens.is_empty() and not dinings.is_empty():
		var kitchen: Dictionary = kitchens[0]
		var dining: Dictionary = dinings[0]
		if not _adjacent(kitchen["rect"], dining["rect"]):
			violations.append("ZONING %s is not adjacent to %s (food travels the shortest path in a real house)" % [kitchen["name"], dining["name"]])
	# Rule 3: no private room on the entrance edge (the south edge).
	# Failure Lab II written as law. (Ch 30 exempts upper floors via meta.)
	var is_upper: bool = bool(plan.get("meta", {}).get("upper_floor", false))
	if not is_upper:
		for room in rooms:
			var rect: Rect2 = room["rect"]
			if room["zone"] == "private" and absf(rect.end.y - footprint.end.y) < 0.02:
				violations.append("ZONING %s (private) touches the entrance edge; guests would arrive inside the private zone" % room["name"])
	# Rule 4: the social zone must be one connected patch. Circulation
	# (the hall) counts as a bridge — guests may pass through the hall,
	# just never through a private room, to move within the social zone.
	var social: Array = _rooms_of_zone(plan, "social")
	if social.size() > 1:
		var walkable: Array = []
		walkable.append_array(social)
		walkable.append_array(_rooms_of_zone(plan, "circulation"))
		var visited: Array = [social[0]]
		var frontier: Array = [social[0]]
		while not frontier.is_empty():
			var current: Dictionary = frontier.pop_back()
			for other in walkable:
				if not visited.has(other) and _adjacent(current["rect"], other["rect"]):
					visited.append(other)
					frontier.append(other)
		var social_reached: int = 0
		for room in social:
			if visited.has(room):
				social_reached += 1
		if social_reached < social.size():
			violations.append("ZONING social zone is split (%d of %d social rooms reachable from %s without crossing a private room)" % [social_reached, social.size(), social[0]["name"]])
	return violations

# --- Window clearance ---------------------------------------------------
# A room split (a shared wall between two rooms) may never pass through
# a window: no split line within half the window's width of its centre.
static func check_window_split_clearance(plan: Dictionary) -> Array:
	var violations: Array = []
	var windows: Array = plan.get("windows", [])
	if windows.is_empty():
		return violations
	var rooms: Array = plan["rooms"]
	for window in windows:
		var center: Vector2 = window["center"]
		var half: float = float(window["width"]) * 0.5
		var on_vertical_wall: bool = window["wall"] == "N" or window["wall"] == "S"
		for room in rooms:
			if room["name"] == window["room"]:
				continue
			var rect: Rect2 = room["rect"]
			if on_vertical_wall:
				# A vertical split line at x = rect edge, spanning the window's y.
				for edge_x in [rect.position.x, rect.end.x]:
					if absf(edge_x - center.x) < half and center.y >= rect.position.y - 0.02 and center.y <= rect.end.y + 0.02:
						violations.append("WINDOW %s in %s is crossed by a wall split at x=%.2f (window centre %.2f, half-width %.2f)" % [window["room"], window["room"], edge_x, center.x, half])
			else:
				for edge_y in [rect.position.y, rect.end.y]:
					if absf(edge_y - center.y) < half and center.x >= rect.position.x - 0.02 and center.x <= rect.end.x + 0.02:
						violations.append("WINDOW %s in %s is crossed by a wall split at y=%.2f (window centre %.2f, half-width %.2f)" % [window["room"], window["room"], edge_y, center.y, half])
	return violations

static func validate_plan(plan: Dictionary) -> Dictionary:
	var violations: Array = []
	violations.append_array(check_minimums(plan))
	var proportions: Dictionary = check_proportions(plan)
	violations.append_array(proportions["violations"])
	violations.append_array(check_zoning(plan))
	violations.append_array(check_window_split_clearance(plan))
	return {"violations": violations, "warnings": proportions["warnings"]}
