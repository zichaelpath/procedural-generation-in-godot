class_name ApartmentRules
extends RefCounted
## The block judge. Per floor it reuses Ch 29's rule FAMILIES
## (minimums, proportions, window clearance) — statements about
## rooms, true in any building. It deliberately does NOT call
## HouseRules.validate_plan(): two house zoning rules are about a
## house's street entrance, which a unit does not have. Block rules
## (wet stack, one bath, service cluster, bedroom-over-corridor)
## are this file's own. Violations carry their numbers, always.

static func validate_block(block: Dictionary) -> Dictionary:
	var violations: Array = []
	var warnings: Array = []
	var floors: Array = block["floors"]
	for plan in floors:
		violations.append_array(HouseRules.check_minimums(plan))
		var proportions: Dictionary = HouseRules.check_proportions(plan)
		violations.append_array(proportions["violations"])
		warnings.append_array(proportions["warnings"])
		violations.append_array(HouseRules.check_window_split_clearance(plan))
		violations.append_array(_check_unit_clusters(plan))
	violations.append_array(_check_wet_stack(block))
	violations.append_array(_check_bed_over_corridor(block))
	return {"violations": violations, "warnings": warnings}

static func _check_unit_clusters(plan: Dictionary) -> Array:
	var violations: Array = []
	var by_unit: Dictionary = {}
	for room in plan["rooms"]:
		var unit_id: String = String(room.get("unit", ""))
		if unit_id == "":
			continue
		if not by_unit.has(unit_id):
			by_unit[unit_id] = []
		by_unit[unit_id].append(room)
	for unit_id in by_unit.keys():
		var rooms: Array = by_unit[unit_id]
		var bathrooms: Array = []
		var kitchens: Array = []
		for room in rooms:
			if room["type"] == "bathroom":
				bathrooms.append(room)
			if room["type"] == "kitchen" or room["type"] == "kitchen_dining":
				kitchens.append(room)
		if bathrooms.size() > 1:
			violations.append("ONE_BATH %s has %d bathrooms (at most one per unit)" % [unit_id, bathrooms.size()])
		if not bathrooms.is_empty() and not kitchens.is_empty():
			var bath_rect: Rect2 = bathrooms[0]["rect"]
			var kitchen_rect: Rect2 = kitchens[0]["rect"]
			if HouseRules._shared_length(bath_rect, kitchen_rect) < 0.5:
				violations.append("SERVICE %s kitchen is not clustered with its bathroom (wet rooms share one wall run)" % unit_id)
	return violations

static func _check_wet_stack(block: Dictionary) -> Array:
	var violations: Array = []
	var floors: Array = block["floors"]
	if floors.size() < 2:
		return violations
	var reference: Dictionary = {}
	for room in floors[0]["rooms"]:
		if room["type"] == "bathroom":
			reference[String(room["unit"])] = room["rect"]
	for f in range(1, floors.size()):
		for room in floors[f]["rooms"]:
			if room["type"] == "bathroom":
				var key: String = String(room["unit"])
				# Units are keyed per floor by id; compare by SLOT index
				# embedded in the id's last two digits instead.
				var slot_key: String = key.substr(key.length() - 2)
				var matched: bool = false
				for ref_key in reference.keys():
					if String(ref_key).substr(String(ref_key).length() - 2) == slot_key:
						matched = (reference[ref_key] as Rect2).is_equal_approx(room["rect"])
				if not matched:
					violations.append("WET_STACK floor %d unit %s bathroom moved off the shared wet slot" % [f + 1, key])
	return violations

static func _check_bed_over_corridor(block: Dictionary) -> Array:
	var violations: Array = []
	if String(block["core"]["typology"]) != "corridor":
		return violations
	var floors: Array = block["floors"]
	var hall: Rect2 = block["core"]["hall_rect"]
	var grown: Rect2 = hall.grow(0.05)
	for f in range(1, floors.size()):
		for room in floors[f]["rooms"]:
			if room["type"] == "bedroom" and grown.intersects(room["rect"]):
				violations.append("NO_BED_OVER_CORRIDOR %s on floor %d overlaps the corridor below" % [room["name"], f + 1])
	return violations
# --- Balcony rules (Ch 33) ---------------------------------------------
# Graded separately from validate_block(): a block is legal before
# its facade exists. The judge re-derives every fact from the plans,
# never from the builder's say-so.
static func check_balconies(block: Dictionary, balconies: Array) -> Array:
	var violations: Array = []
	var floors: Array = block["floors"]
	var footprint: Rect2 = block["footprint"]
	for balcony in balconies:
		var plan: Dictionary = floors[int(balcony["floor"])]
		var room: Dictionary = {}
		for candidate in plan["rooms"]:
			if candidate["name"] == balcony["room"]:
				room = candidate
		if room.is_empty():
			violations.append("BALCONY %s names a room that does not exist on floor %d" % [balcony["room"], int(balcony["floor"]) + 1])
			continue
		if room["type"] != "living" and room["type"] != "bedroom":
			violations.append("BALCONY_TYPE %s is a %s (balconies belong to living rooms and bedrooms)" % [room["name"], room["type"]])
		var rect: Rect2 = room["rect"]
		var wall: String = balcony["wall"]
		var on_wall: bool = false
		match wall:
			"N": on_wall = absf(rect.position.y - footprint.position.y) < 0.02
			"S": on_wall = absf(rect.end.y - footprint.end.y) < 0.02
			"W": on_wall = absf(rect.position.x - footprint.position.x) < 0.02
			"E": on_wall = absf(rect.end.x - footprint.end.x) < 0.02
		if not on_wall:
			violations.append("BALCONY_WALL %s does not touch the %s exterior" % [room["name"], wall])
		var aligned: bool = false
		for window in plan["windows"]:
			if window["room"] == room["name"]:
				var c: Vector2 = window["center"]
				var b: Vector2 = balcony["center"]
				if c.distance_to(b) < 0.3:
					aligned = true
		if not aligned:
			violations.append("BALCONY_ALIGN %s balcony centre is not on any of its windows (within 0.3 m)" % room["name"])
	return violations
