class_name HouseProgram
extends Resource
## The generator's contract: footprint in, budgeted room list out.
## Each room spec is a Dictionary {name, type, zone, target, min} —
## target is the wish in m² (and the layout weight), min is the floor
## the Chapter 29 validator will enforce. See Ch 26 §26.2 for why the
## hall is a paid line item and why targets sum to less than the area.

const ZONE_SOCIAL := "social"
const ZONE_PRIVATE := "private"
const ZONE_SERVICE := "service"
const ZONE_CIRCULATION := "circulation"

@export var footprint: Vector2 = Vector2(10.8, 10.0)
var rooms: Array = []

static func room_count_for_area(area: float) -> int:
	# Real housing runs at roughly one room per 14–16 m² of floor.
	return clampi(int(round(area / 15.0)), 5, 9)

static func build(width: float, depth: float) -> HouseProgram:
	var p: HouseProgram = HouseProgram.new()
	p.footprint = Vector2(width, depth)
	var area: float = width * depth
	if area < 95.0:
		p.rooms = _small()
	elif area < 115.0:
		p.rooms = _medium()
	else:
		p.rooms = _large()
	return p

func total_target() -> float:
	var s: float = 0.0
	for r in rooms:
		s += float(r["target"])
	return s

static func _room(p_name: String, p_type: String, zone: String, target: float, min_area: float) -> Dictionary:
	return {"name": p_name, "type": p_type, "zone": zone, "target": target, "min": min_area}

static func _small() -> Array:
	# ~80 m², 6 spaces. Kitchen and dining stay combined at this size.
	return [
		_room("hall", "hall", ZONE_CIRCULATION, 6.0, 3.0),
		_room("living", "living", ZONE_SOCIAL, 20.0, 14.0),
		_room("kitchen_dining", "kitchen_dining", ZONE_SERVICE, 17.0, 14.0),
		_room("bedroom_1", "bedroom", ZONE_PRIVATE, 12.0, 8.0),
		_room("bedroom_2", "bedroom", ZONE_PRIVATE, 10.0, 8.0),
		_room("bathroom", "bathroom", ZONE_PRIVATE, 5.5, 3.5),
	]

static func _medium() -> Array:
	# ~108 m², 8 spaces. Kitchen/dining split; a separate WC appears.
	return [
		_room("hall", "hall", ZONE_CIRCULATION, 6.0, 3.0),
		_room("living", "living", ZONE_SOCIAL, 24.0, 14.0),
		_room("kitchen", "kitchen", ZONE_SERVICE, 11.0, 6.0),
		_room("dining", "dining", ZONE_SOCIAL, 13.0, 8.0),
		_room("bedroom_1", "bedroom", ZONE_PRIVATE, 13.0, 8.0),
		_room("bedroom_2", "bedroom", ZONE_PRIVATE, 11.0, 8.0),
		_room("bathroom", "bathroom", ZONE_PRIVATE, 6.0, 3.5),
		_room("wc", "wc", ZONE_PRIVATE, 2.0, 1.2),
	]

static func _large() -> Array:
	# ~125 m², 9 spaces — the cap. Spare area grows real rooms;
	# it never invents filler rooms.
	return [
		_room("hall", "hall", ZONE_CIRCULATION, 6.0, 3.0),
		_room("living", "living", ZONE_SOCIAL, 26.0, 14.0),
		_room("kitchen", "kitchen", ZONE_SERVICE, 12.0, 6.0),
		_room("dining", "dining", ZONE_SOCIAL, 14.0, 8.0),
		_room("bedroom_1", "bedroom", ZONE_PRIVATE, 14.0, 8.0),
		_room("bedroom_2", "bedroom", ZONE_PRIVATE, 11.0, 8.0),
		_room("bedroom_3", "bedroom", ZONE_PRIVATE, 10.0, 8.0),
		_room("bathroom", "bathroom", ZONE_PRIVATE, 6.5, 3.5),
		_room("wc", "wc", ZONE_PRIVATE, 2.0, 1.2),
	]
