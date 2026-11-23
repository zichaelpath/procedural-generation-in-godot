class_name BlockLayout
extends RefCounted
## One floor's geometry, rolled ONCE per block: core (from the
## program) -> unit slots (rows around the core) -> room slots
## (a per-class profile inside each unit slot, sized by the neediest
## kind that may occupy the slot). Floors differ only by STAMPING
## (§32.2). Every floor plan is a Ch 26 plan; rooms carry "unit".

const PROFILES: Dictionary = {
	"small": [
		{"role": "main", "target": 19.0}, {"role": "flex", "target": 12.0},
		{"role": "entry", "target": 3.5}, {"role": "service", "target": 8.0}, {"role": "wet", "target": 5.0},
	],
	"large": [
		{"role": "main", "target": 23.0}, {"role": "bed_a", "target": 13.0}, {"role": "flex", "target": 11.0},
		{"role": "entry", "target": 4.5}, {"role": "service", "target": 16.0}, {"role": "wet", "target": 6.0}, {"role": "dining", "target": 11.0},
	],
}
# Inside a unit slot: three strips, Ch 29's band topology at unit
# scale — living row on the exterior side, service row against the
# core band, and the unit's own hall strip between them, touching
# every room, so §32.4's door pass can hub on it. LIVING_SHARE is
# the living row's share of the depth the hall strip leaves behind;
# small slots run a deeper living row because the studio's merged
# room and the one-bed's bedroom both live there.
const HALL_DEPTH: float = 1.4
const LIVING_SHARE: Dictionary = {"small": 0.63, "large": 0.54}
# A slot is sized by the NEEDIEST kind of its class (§32.1): every
# small slot is weighted as a one-bed, every large slot as a family,
# whatever kind floor 1 stamps on it — a studio slot must still fit
# the one-bed it may become on floor 3.
const CLASS_WEIGHT: Dictionary = {"small": 52.0, "large": 92.0}

static func slot_class_of(kind: String) -> String:
	return "small" if kind == ApartmentProgram.KIND_STUDIO or kind == ApartmentProgram.KIND_ONE_BED else "large"

static func roll_slots(program: ApartmentProgram, core: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var fp: Rect2 = Rect2(Vector2.ZERO, program.footprint)
	var hall: Rect2 = core["hall_rect"]
	# Kinds alternate rows as the mix list descends (largest first):
	# north takes slots 0, 2, …, south takes 1, 3, …, so each row
	# mixes large and small homes instead of one row starving.
	# A shallow +/-4% jitter on slot weights is the ONLY randomness
	# in the roll: dimensions vary, topology never does.
	var kinds: Array = program.units_per_floor
	var north_kinds: Array = []
	var south_kinds: Array = []
	for i in kinds.size():
		if i % 2 == 0:
			north_kinds.append(kinds[i])
		else:
			south_kinds.append(kinds[i])
	var north_band: Rect2 = Rect2(0, 0, fp.size.x, hall.position.y)
	var south_band: Rect2 = Rect2(0, hall.end.y, fp.size.x, fp.size.y - hall.end.y)
	var slots: Array = []
	slots.append_array(_unit_slots(north_kinds, north_band, rng, false))
	slots.append_array(_unit_slots(south_kinds, south_band, rng, true))
	for slot in slots:
		slot["rooms"] = _room_slots(slot)
	return {"footprint": fp, "slots": slots, "core": core}

static func _unit_slots(kinds: Array, band: Rect2, rng: RandomNumberGenerator, is_south: bool) -> Array:
	var out: Array = []
	if kinds.is_empty() or band.size.y <= 0.5:
		return out
	var total: float = 0.0
	var weights: Array = []
	for kind in kinds:
		var w: float = float(CLASS_WEIGHT[slot_class_of(kind)]) * rng.randf_range(0.96, 1.04)
		weights.append(w)
		total += w
	var x: float = band.position.x
	for i in kinds.size():
		var w: float = band.size.x * float(weights[i]) / total
		if i == kinds.size() - 1:
			w = band.end.x - x # last slot takes the remainder: edges snap shut
		out.append({"kind": kinds[i], "class": slot_class_of(kinds[i]),
			"rect": Rect2(x, band.position.y, w, band.size.y), "south": is_south})
		x += w
	return out

static func _room_slots(slot: Dictionary) -> Array:
	# Three strips inside the unit slot, packed with
	# BandLayout._lay_row borrowed as a pure row-packer (we keep its
	# rectangles, in order). Service row sits nearest the core, so
	# the wet slot's edge lands on the service wall and the entry
	# vestibule touches the core hall; the hall strip sits between
	# the rows and touches every room in the unit.
	var rect: Rect2 = slot["rect"]
	var profile: Array = PROFILES[slot["class"]]
	var living: Array = []
	var service: Array = []
	for entry in profile:
		if entry["role"] == "main" or entry["role"] == "flex" or entry["role"] == "bed_a":
			living.append(entry)
		else:
			service.append(entry)
	var hall_depth: float = minf(HALL_DEPTH, rect.size.y * 0.25)
	var rest: float = rect.size.y - hall_depth
	var living_depth: float = rest * float(LIVING_SHARE[slot["class"]])
	var service_depth: float = rest - living_depth
	var living_band: Rect2
	var hall_band: Rect2
	var service_band: Rect2
	if slot["south"]:
		service_band = Rect2(rect.position, Vector2(rect.size.x, service_depth))
		hall_band = Rect2(rect.position + Vector2(0, service_depth), Vector2(rect.size.x, hall_depth))
		living_band = Rect2(rect.position + Vector2(0, service_depth + hall_depth), Vector2(rect.size.x, living_depth))
	else:
		living_band = Rect2(rect.position, Vector2(rect.size.x, living_depth))
		hall_band = Rect2(rect.position + Vector2(0, living_depth), Vector2(rect.size.x, hall_depth))
		service_band = Rect2(rect.position + Vector2(0, living_depth + hall_depth), Vector2(rect.size.x, service_depth))
	var counts: Dictionary = {}
	var packed: Array = []
	packed.append_array(BandLayout._lay_row(_as_specs(living), living_band, counts))
	packed.append_array(BandLayout._lay_row(_as_specs(service), service_band, counts))
	var by_role: Dictionary = {}
	var ordered: Array = []
	ordered.append_array(living)
	ordered.append_array(service)
	for i in ordered.size():
		by_role[ordered[i]["role"]] = packed[i]["rect"]
	by_role["hall"] = hall_band
	var out: Array = []
	for entry in profile:
		out.append({"role": entry["role"], "rect": by_role[entry["role"]]})
	out.append({"role": "hall", "rect": hall_band})
	return out

static func _as_specs(entries: Array) -> Array:
	var specs: Array = []
	for entry in entries:
		specs.append({"type": "bedroom", "zone": "private", "target": float(entry["target"]), "min": 0.0})
	return specs
# Stamp one floor: assign a kind to each unit slot (same-class swaps
# only, drawn by the caller), then map the kind's template onto the
# slot's room slots BY ROLE, under the §32.2 constraint rules.
static func stamp_floor(roll: Dictionary, floor_index: int, kinds_by_slot: Array, core: Dictionary) -> Dictionary:
	var rooms: Array = []
	rooms.append({"name": "core_hall", "type": "hall", "zone": "circulation", "unit": "",
		"rect": core["hall_rect"], "target": 0.0, "min": 0.0})
	rooms.append({"name": "stairs", "type": "stairs", "zone": "circulation", "unit": "",
		"rect": core["stair_rect"], "target": 0.0, "min": 0.0})
	rooms.append({"name": "lift", "type": "lift", "zone": "circulation", "unit": "",
		"rect": core["lift_rect"], "target": 0.0, "min": 0.0})
	var units: Array = []
	var slots: Array = roll["slots"]
	for s in slots.size():
		var slot: Dictionary = slots[s]
		var kind: String = kinds_by_slot[s]
		var unit_id: String = "U%d%02d" % [floor_index + 1, s + 1]
		var stamped: Array = _stamp_unit(slot, kind, unit_id)
		rooms.append_array(stamped)
		var area: float = 0.0
		for room in stamped:
			area += (room["rect"] as Rect2).get_area()
		units.append({"id": unit_id, "kind": kind, "floor": floor_index, "slot": s,
			"room_names": stamped.map(func(r: Dictionary) -> String: return String(r["name"])), "area": area})
	return {"plan": {"footprint": roll["footprint"], "rooms": rooms, "doors": [], "windows": [],
		"entrance_room": "core_hall", "meta": {"apartment_floor": true, "floor_index": floor_index,
		"no_entrance": floor_index > 0}}, "units": units}

static func _stamp_unit(slot: Dictionary, kind: String, unit_id: String) -> Array:
	var by_role: Dictionary = {}
	for room_slot in slot["rooms"]:
		by_role[room_slot["role"]] = room_slot["rect"]
	var prefix: String = unit_id.to_lower() + "_"
	var out: Array = []
	var bathrooms: int = 0
	var put := func(local_name: String, room_type: String, zone: String, rect: Rect2, target: float, min_area: float) -> void:
		out.append({"name": prefix + local_name, "type": room_type, "zone": zone, "unit": unit_id,
			"rect": rect, "target": target, "min": min_area})
	# The hall strip IS the unit's hall; a WC is carved from its
	# east end when the kind's template asks for one (Ch 29's carve,
	# on the strip — the entry slot is a narrow vestibule and cannot
	# be carved: in the first drafts it was, and the hall's area
	# went negative; and the carve sits east so the strip's west
	# end keeps its full overlap with the vestibule). The entry
	# slot is stamped as the vestibule (hall_entry, Ch 29's name)
	# that carries the front door.
	var strip: Rect2 = by_role["hall"]
	var template: Array = ApartmentProgram.template_for(kind)
	var wants_wc: bool = false
	for spec in template:
		if spec["type"] == "wc":
			wants_wc = true
	if wants_wc:
		var wc_w: float = clampf(2.0 / strip.size.y, 1.2, 1.8)
		put.call("wc", "wc", "service", Rect2(strip.end.x - wc_w, strip.position.y, wc_w, strip.size.y), 2.0, 1.2)
		strip = Rect2(strip.position, Vector2(strip.size.x - wc_w, strip.size.y))
	put.call("hall", "hall", "circulation", strip, 3.5, 3.0)
	put.call("hall_entry", "hall", "circulation", by_role["entry"], 3.5, 3.0)
	match kind:
		ApartmentProgram.KIND_STUDIO:
			# main + flex MERGE into one living room (union rectangle).
			var merged: Rect2 = (by_role["main"] as Rect2).merge(by_role["flex"])
			put.call("living", "living", "social", merged, 17.0, 14.0)
			put.call("kitchen", "kitchen", "service", by_role["service"], 7.0, 6.0)
		ApartmentProgram.KIND_ONE_BED:
			put.call("living", "living", "social", by_role["main"], 19.0, 14.0)
			put.call("kitchen", "kitchen", "service", by_role["service"], 8.0, 6.0)
			put.call("bedroom_1", "bedroom", "private", by_role["flex"], 12.0, 8.0)
		ApartmentProgram.KIND_TWO_BED:
			put.call("living", "living", "social", by_role["main"], 21.0, 14.0)
			put.call("kitchen", "kitchen", "service", by_role["service"], 9.0, 6.0)
			put.call("dining", "dining", "social", by_role["dining"], 10.0, 8.0)
			put.call("bedroom_1", "bedroom", "private", by_role["bed_a"], 12.0, 8.0)
			put.call("bedroom_2", "bedroom", "private", by_role["flex"], 10.0, 8.0)
		ApartmentProgram.KIND_FAMILY:
			put.call("living", "living", "social", by_role["main"], 23.0, 14.0)
			put.call("kitchen_dining", "kitchen_dining", "service", by_role["service"], 16.0, 14.0)
			put.call("bedroom_1", "bedroom", "private", by_role["bed_a"], 13.0, 8.0)
			put.call("bedroom_2", "bedroom", "private", by_role["dining"], 11.0, 8.0)
			put.call("bedroom_3", "bedroom", "private", by_role["flex"], 10.0, 8.0)
	# The wet slot is stamped LAST and only ever as a bathroom: rule 1
	# and rule 2 enforced by there being exactly one wet stamp, here.
	bathrooms += 1
	put.call("bathroom", "bathroom", "private", by_role["wet"], 5.5, 3.5)
	return out

# Assemble the BLOCK: roll once, stamp every floor. Upper floors swap
# kinds within each slot's class (rng from the buildings stream), so
# the households vary while the walls never do.
static func generate_block(program: ApartmentProgram, core: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var roll: Dictionary = roll_slots(program, core, rng)
	var floors: Array = []
	var all_units: Array = []
	for f in program.floor_count:
		var kinds_by_slot: Array = []
		for slot in roll["slots"]:
			var kind: String = slot["kind"]
			if f > 0:
				var classmates: Array = []
				for candidate in ApartmentProgram.KINDS:
					if slot_class_of(candidate) == slot["class"]:
						classmates.append(candidate)
				kind = classmates[rng.randi_range(0, classmates.size() - 1)]
			kinds_by_slot.append(kind)
		var stamped: Dictionary = stamp_floor(roll, f, kinds_by_slot, core)
		floors.append(stamped["plan"])
		all_units.append_array(stamped["units"])
	return {"footprint": roll["footprint"], "floors": floors, "stair_rect": core["stair_rect"],
		"core": core, "units": all_units, "meta": {"typology": core["typology"], "floors": program.floor_count}}
# Doors for one apartment floor. The core's own doors come first:
# stairs and lift open off the core hall. Inside a unit, the front
# door exists ONLY between the unit's vestibule and the core hall;
# the vestibule opens onto the unit's hall strip, and the strip —
# which touches every room in the unit — is the hub (Ch 29's
# pattern, shrunk). Rooms are read by their "type" FIELD — names
# are prefixed, so type_of() is not used.
static func build_floor_doors(plan: Dictionary) -> Array:
	var doors: Array = []
	var rooms: Array = plan["rooms"]
	var by_name: Dictionary = {}
	for room in rooms:
		by_name[room["name"]] = room
	var core_hall: Dictionary = by_name.get("core_hall", {})
	if core_hall.is_empty():
		push_error("BlockLayout: no core_hall in floor plan — doors refused")
		plan["doors"] = []
		return []
	for core_name in ["stairs", "lift"]:
		if by_name.has(core_name):
			_add_core_door(doors, core_hall, by_name[core_name], rooms)
	var units: Dictionary = {}
	for room in rooms:
		var unit_id: String = String(room.get("unit", ""))
		if unit_id != "":
			if not units.has(unit_id):
				units[unit_id] = []
			units[unit_id].append(room)
	for unit_id in units.keys():
		var unit_rooms: Array = units[unit_id]
		var strip: Dictionary = {}
		var vestibule: Dictionary = {}
		for room in unit_rooms:
			if room["name"].ends_with("_hall_entry"):
				vestibule = room
			elif room["name"].ends_with("_hall"):
				strip = room
		if strip.is_empty() or vestibule.is_empty():
			push_error("BlockLayout: unit %s has no hall strip or vestibule — front door refused" % unit_id)
			continue
		_add_apartment_door(doors, vestibule, core_hall, "door", 0.95)
		_add_apartment_door(doors, vestibule, strip, "door", 0.85)
		for room in unit_rooms:
			if room["name"] == strip["name"] or room["name"] == vestibule["name"]:
				continue
			_add_apartment_door(doors, strip, room, "door", 0.85)
	plan["doors"] = doors
	return doors

static func _add_core_door(doors: Array, hall: Dictionary, room: Dictionary, rooms: Array) -> void:
	var segment: Dictionary = DoorGraph.shared_segment(hall["rect"], room["rect"])
	if float(segment["length"]) >= 1.25:
		doors.append({"a": hall["name"], "b": room["name"], "kind": "door", "width": 0.95,
			"center": segment["center"], "vertical": segment["vertical"]})
		return
	# The stair and lift stand INSIDE the lobby's outline (Ch 31's
	# core rects overlap it), so they share no wall segment with
	# it. Their door sits on the edge that faces lobby space: the
	# first edge whose outward side is inside the hall rect and
	# not inside another core room.
	var rect: Rect2 = room["rect"]
	var hall_rect: Rect2 = hall["rect"]
	var edges: Array = [
		{"center": Vector2(rect.position.x, rect.get_center().y), "vertical": true, "probe": Vector2(rect.position.x - 0.05, rect.get_center().y)},
		{"center": Vector2(rect.end.x, rect.get_center().y), "vertical": true, "probe": Vector2(rect.end.x + 0.05, rect.get_center().y)},
		{"center": Vector2(rect.get_center().x, rect.position.y), "vertical": false, "probe": Vector2(rect.get_center().x, rect.position.y - 0.05)},
		{"center": Vector2(rect.get_center().x, rect.end.y), "vertical": false, "probe": Vector2(rect.get_center().x, rect.end.y + 0.05)},
	]
	for edge in edges:
		var probe: Vector2 = edge["probe"]
		if not hall_rect.has_point(probe):
			continue
		var blocked: bool = false
		for other in rooms:
			if String(other.get("unit", "")) == "" and other["name"] != room["name"] and other["name"] != hall["name"]:
				if (other["rect"] as Rect2).has_point(probe):
					blocked = true
		if not blocked:
			doors.append({"a": hall["name"], "b": room["name"], "kind": "door", "width": 0.95,
				"center": edge["center"], "vertical": edge["vertical"]})
			return

static func _add_apartment_door(doors: Array, a: Dictionary, b: Dictionary, kind: String, width: float) -> void:
	var segment: Dictionary = DoorGraph.shared_segment(a["rect"], b["rect"])
	if float(segment["length"]) < width + 0.3:
		return
	doors.append({"a": a["name"], "b": b["name"], "kind": kind, "width": width,
		"center": segment["center"], "vertical": segment["vertical"]})

static func floor_fully_reachable(plan: Dictionary) -> bool:
	var visited: Array = ["core_hall"]
	var frontier: Array = ["core_hall"]
	while not frontier.is_empty():
		var current: String = String(frontier.pop_back())
		for door in plan["doors"]:
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
