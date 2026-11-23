class_name OfficeProgram
extends Resource
## The corporate contract: a floor plate, a list of floor kinds, and
## a headcount per floor in — a budgeted tower program out. Two
## budgets, stacked, as in Part VI: (1) how many people, on which
## floors (the headcount, §34.3); (2) which rooms each floor kind
## gets (the templates below — Ch 26's spec shape, office types).
## Circulation and services are NOT in any tenancy's gift: the core
## and the service cluster (§34.4) carry them, shared by the floor.

const KIND_LOBBY := "lobby"
const KIND_TYPICAL := "typical"
const KIND_COLLABORATION := "collaboration"
const KIND_EXECUTIVE := "executive"
const KINDS: Array = [KIND_LOBBY, KIND_TYPICAL, KIND_COLLABORATION, KIND_EXECUTIVE]

# The headcount arithmetic (§34.3), as named constants so the worked
# example in the text and the code can never drift apart.
const SQM_PER_PERSON: float = 12.0 # net usable m² per person, all-in
const PLATE_EFFICIENCY: float = 0.80 # net / gross: core+services take ~20%
const DESK_RATIO: float = 1.0 # desks owed per assigned seat (no hot-desking fudge)

@export var footprint: Vector2 = Vector2(38.0, 22.0)
var floor_kinds: Array = [] # one kind String per floor, ground first
var seats_per_floor: Array = [] # one int per floor: people that floor must seat
var core_typology: String = "point"

static func _room(p_name: String, p_type: String, zone: String, target: float, min_area: float) -> Dictionary:
	return {"name": p_name, "type": p_type, "zone": zone, "target": target, "min": min_area}

static func template_for(kind: String) -> Array:
	# Local names are unprefixed ("meeting_1"); Ch 35 prefixes them
	# with the tenancy id when it stamps them into a floor plan.
	match kind:
		KIND_TYPICAL:
			return [
				_room("open_plan", "open_plan", "social", 430.0, 20.0),
				_room("meeting_1", "meeting", "social", 26.0, 8.0),
				_room("meeting_2", "meeting", "social", 18.0, 8.0),
				_room("focus_1", "focus", "private", 9.0, 6.0),
				_room("focus_2", "focus", "private", 9.0, 6.0),
				_room("kitchenette", "kitchenette", "service", 33.0, 6.0),
				_room("server", "server", "service", 13.0, 6.0),
				_room("storage", "storage", "service", 13.0, 3.0),
				_room("wc", "wc", "service", 24.0, 3.5),
			]
		KIND_COLLABORATION:
			return [
				_room("open_plan", "open_plan", "social", 300.0, 20.0),
				_room("breakout", "breakout", "social", 130.0, 20.0),
				_room("meeting_1", "meeting", "social", 26.0, 8.0),
				_room("meeting_2", "meeting", "social", 18.0, 8.0),
				_room("meeting_3", "meeting", "social", 12.0, 8.0),
				_room("focus_1", "focus", "private", 9.0, 6.0),
				_room("kitchenette", "kitchenette", "service", 33.0, 6.0),
				_room("server", "server", "service", 13.0, 6.0),
				_room("storage", "storage", "service", 13.0, 3.0),
				_room("wc", "wc", "service", 24.0, 3.5),
			]
		KIND_EXECUTIVE:
			return [
				_room("open_plan", "open_plan", "social", 300.0, 20.0),
				_room("boardroom", "meeting", "social", 40.0, 8.0),
				_room("office_1", "office", "private", 16.0, 9.0),
				_room("office_2", "office", "private", 16.0, 9.0),
				_room("office_3", "office", "private", 16.0, 9.0),
				_room("focus_1", "focus", "private", 9.0, 6.0),
				_room("kitchenette", "kitchenette", "service", 33.0, 6.0),
				_room("server", "server", "service", 13.0, 6.0),
				_room("storage", "storage", "service", 13.0, 3.0),
				_room("wc", "wc", "service", 24.0, 3.5),
			]
		KIND_LOBBY:
			return [
				_room("lobby", "lobby", "circulation", 90.0, 20.0),
				_room("open_plan", "open_plan", "social", 300.0, 20.0),
				_room("meeting_1", "meeting", "social", 26.0, 8.0),
				_room("meeting_2", "meeting", "social", 18.0, 8.0),
				_room("focus_1", "focus", "private", 9.0, 6.0),
				_room("kitchenette", "kitchenette", "service", 33.0, 6.0),
				_room("server", "server", "service", 13.0, 6.0),
				_room("storage", "storage", "service", 13.0, 3.0),
				_room("wc", "wc", "service", 24.0, 3.5),
			]
	return []

static func build(p_footprint: Vector2, p_floor_kinds: Array, p_seats: Array, p_typology: String = "point") -> OfficeProgram:
	var p: OfficeProgram = OfficeProgram.new()
	p.footprint = p_footprint
	p.floor_kinds = p_floor_kinds.duplicate()
	p.seats_per_floor = p_seats.duplicate()
	p.core_typology = p_typology
	return p

func floor_count() -> int:
	return floor_kinds.size()

func headcount_total() -> int:
	var total: int = 0
	for seats in seats_per_floor:
		total += int(seats)
	return total

# The default tower of this part: 240 staff on a 38 x 22 m plate.
# Ground lobby, four typical floors, a collaboration floor, and an
# executive floor under the setback Chapter 36 adds.
static func default_tower() -> OfficeProgram:
	return build(Vector2(38.0, 22.0),
		[KIND_LOBBY, KIND_TYPICAL, KIND_TYPICAL, KIND_TYPICAL, KIND_TYPICAL, KIND_COLLABORATION, KIND_EXECUTIVE],
		[0, 50, 50, 50, 50, 16, 24])

# People -> plate. Given a total headcount and a number of WORK
# floors (lobby/executive floors are briefed separately), size one
# plate: net = people-per-floor x SQM_PER_PERSON; gross = net /
# efficiency; depth is clamped to the daylight band (18-24 m) and
# the width absorbs the rest, rounded UP to a whole metre.
static func plate_for_headcount(total_people: int, work_floors: int) -> Vector2:
	var per_floor: float = float(total_people) / float(maxi(work_floors, 1))
	var net: float = per_floor * SQM_PER_PERSON
	var gross: float = net / PLATE_EFFICIENCY
	var depth: float = clampf(sqrt(gross / 1.7), 18.0, 24.0)
	var width: float = ceilf(gross / depth)
	return Vector2(width, depth)

# The plate's accounts, as data: what the core and services take,
# what is left to work in, and how many people that honestly seats.
# core_area is measured from the core Dictionary (Ch 31's shape),
# never estimated twice in two places.
static func plate_budget(footprint: Vector2, core: Dictionary) -> Dictionary:
	var gross: float = footprint.x * footprint.y
	var core_area: float = (core["stair_rect"] as Rect2).get_area() + (core["lift_rect"] as Rect2).get_area()
	var net: float = gross * PLATE_EFFICIENCY
	return {"gross": gross, "core_area": core_area, "net": net,
		"efficiency": PLATE_EFFICIENCY, "capacity": int(floor(net / SQM_PER_PERSON))}

# The core, carried over from Part VI: ApartmentProgram.core_for()
# returns {typology, stair_rect, lift_rect, hall_rect,
# service_wall_x, entrance_x} for both typologies, and an office
# core is the same element with a bigger lobby in front of it
# (the lobby is a stamped room, Ch 35 — not a core change). The
# origin parameter exists for Chapter 36's setback floor, whose
# plate sits inside the tower's footprint at an offset.
#
# CONTRACT PIN (2026-11-19, ~23:04): Part VI's own solver fix
# widened the POINT core's hall_rect to a full-footprint band
# (Rect2(0, cy-1.6, footprint.x, 3.2)) — right for apartment
# corridors, but it breaks every office invariant Ch 35 states:
# the fields are computed around a compact central core block,
# so the east field's area went negative (-71.9 m²) and the
# core_hall's aspect (11.87) broke the office cap on all 5000
# solver attempts. Ch 31's point core — the one Ch 34/35 were
# written against, and the one this part's verified renders
# show — has the hall EXACTLY equal to stair + lift. The point
# core is therefore built locally with that geometry (same
# stair/lift sizes Part VI still uses); the corridor typology
# still delegates, its full-width hall being the definition of
# that variant.
static func core_for(typology: String, footprint: Vector2, origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var core: Dictionary
	if typology == "point":
		var cx: float = footprint.x * 0.5
		var cy: float = footprint.y * 0.5
		core = {
			"typology": "point",
			"stair_rect": Rect2(cx - 2.7, cy - 1.6, 2.7, 3.2),
			"lift_rect": Rect2(cx, cy - 1.6, 1.9, 3.2),
			"hall_rect": Rect2(cx - 2.7, cy - 1.6, 4.6, 3.2),
			"service_wall_x": cx - 2.7,
			"entrance_x": cx,
		}
	else:
		core = ApartmentProgram.core_for(typology, footprint)
	if origin != Vector2.ZERO:
		core["stair_rect"] = Rect2((core["stair_rect"] as Rect2).position + origin, (core["stair_rect"] as Rect2).size)
		core["lift_rect"] = Rect2((core["lift_rect"] as Rect2).position + origin, (core["lift_rect"] as Rect2).size)
		core["hall_rect"] = Rect2((core["hall_rect"] as Rect2).position + origin, (core["hall_rect"] as Rect2).size)
		core["service_wall_x"] = float(core["service_wall_x"]) + origin.x
		core["entrance_x"] = float(core["entrance_x"]) + origin.x
	return core
