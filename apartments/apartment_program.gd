class_name ApartmentProgram
extends Resource
## The multi-unit contract: a footprint, a floor count, and a MIX of
## unit kinds in, a budgeted block program out. Two budgets, stacked:
## (1) which homes, how many of each (the mix, §31.3); (2) which rooms
## each kind gets (the templates below — Ch 26's spec shape, Ch 29's
## minimums, unchanged). Circulation is NOT in any unit's budget past
## a 3 m² entry hall: the core (§31.4) carries it, shared.

const KIND_STUDIO := "studio"
const KIND_ONE_BED := "one_bed"
const KIND_TWO_BED := "two_bed"
const KIND_FAMILY := "family"
const KINDS: Array = [KIND_STUDIO, KIND_ONE_BED, KIND_TWO_BED, KIND_FAMILY]

# Nominal areas are the mix's accounting unit: a floor's saleable area
# is divided among kinds at these prices before any slot is drawn.
const NOMINAL_AREA: Dictionary = {
	KIND_STUDIO: 34.0, KIND_ONE_BED: 52.0, KIND_TWO_BED: 72.0, KIND_FAMILY: 92.0,
}

@export var footprint: Vector2 = Vector2(18.0, 12.0)
@export var floor_count: int = 4
var mix: Dictionary = {} # kind -> share (0..1), as given by the designer
var units_per_floor: Array = [] # kind Strings, one entry per unit slot on a floor

static func _room(p_name: String, p_type: String, zone: String, target: float, min_area: float) -> Dictionary:
	return {"name": p_name, "type": p_type, "zone": zone, "target": target, "min": min_area}

static func template_for(kind: String) -> Array:
	# Local names are unprefixed ("living"); Ch 32 prefixes them with
	# the unit id when it stamps them into a floor plan.
	match kind:
		KIND_STUDIO:
			return [
				_room("hall", "hall", "circulation", 3.0, 3.0),
				_room("living", "living", "social", 17.0, 14.0),
				_room("kitchen", "kitchen", "service", 7.0, 6.0),
				_room("bathroom", "bathroom", "private", 4.5, 3.5),
			]
		KIND_ONE_BED:
			return [
				_room("hall", "hall", "circulation", 3.5, 3.0),
				_room("living", "living", "social", 19.0, 14.0),
				_room("kitchen", "kitchen", "service", 8.0, 6.0),
				_room("bedroom_1", "bedroom", "private", 12.0, 8.0),
				_room("bathroom", "bathroom", "private", 5.0, 3.5),
			]
		KIND_TWO_BED:
			return [
				_room("hall", "hall", "circulation", 4.0, 3.0),
				_room("living", "living", "social", 21.0, 14.0),
				_room("kitchen", "kitchen", "service", 9.0, 6.0),
				_room("dining", "dining", "social", 10.0, 8.0),
				_room("bedroom_1", "bedroom", "private", 12.0, 8.0),
				_room("bedroom_2", "bedroom", "private", 10.0, 8.0),
				_room("bathroom", "bathroom", "private", 5.5, 3.5),
				_room("wc", "wc", "service", 2.0, 1.2),
			]
		KIND_FAMILY:
			return [
				_room("hall", "hall", "circulation", 4.5, 3.0),
				_room("living", "living", "social", 23.0, 14.0),
				_room("kitchen_dining", "kitchen_dining", "service", 16.0, 14.0),
				_room("bedroom_1", "bedroom", "private", 13.0, 8.0),
				_room("bedroom_2", "bedroom", "private", 11.0, 8.0),
				_room("bedroom_3", "bedroom", "private", 10.0, 8.0),
				_room("bathroom", "bathroom", "private", 6.0, 3.5),
				_room("wc", "wc", "service", 2.0, 1.2),
			]
	return []

static func build(p_footprint: Vector2, p_floor_count: int, p_mix: Dictionary) -> ApartmentProgram:
	var p: ApartmentProgram = ApartmentProgram.new()
	p.footprint = p_footprint
	p.floor_count = p_floor_count
	p.mix = p_mix.duplicate()
	p.units_per_floor = mix_to_slots(p_footprint, p_mix)
	return p

# How many unit slots does one floor hold? The floor's saleable area
# divided by the mix's average nominal area. Saleable is what is left
# after ALL circulation is paid for (§31.4): the core band (~16% of
# the plate) plus every unit's own hall strip (~14%) — a factor of
# 0.69, not the core rooms' rent alone.
static func slot_count_for(footprint: Vector2, mix: Dictionary) -> int:
	var saleable: float = footprint.x * footprint.y * 0.69
	var average: float = 0.0
	var share_total: float = 0.0
	for kind in KINDS:
		var share: float = float(mix.get(kind, 0.0))
		average += share * float(NOMINAL_AREA[kind])
		share_total += share
	if share_total <= 0.0 or average <= 0.0:
		return 0
	average /= share_total
	return clampi(int(round(saleable / average)), 2, 8)
# Shares -> whole homes, by largest remainder. The result ALWAYS sums
# to the slot count; ties favour the larger kind (scarcer homes first).
static func mix_to_slots(footprint: Vector2, mix: Dictionary) -> Array:
	var slots: int = slot_count_for(footprint, mix)
	var counts: Dictionary = {}
	var remainders: Array = []
	var assigned: int = 0
	for kind in KINDS:
		var exact: float = float(mix.get(kind, 0.0)) * float(slots)
		var whole: int = int(floor(exact))
		counts[kind] = whole
		assigned += whole
		remainders.append({"kind": kind, "frac": exact - float(whole)})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["frac"]) - float(b["frac"])) > 0.0001:
			return float(a["frac"]) > float(b["frac"])
		return float(NOMINAL_AREA[a["kind"]]) > float(NOMINAL_AREA[b["kind"]]))
	var r: int = 0
	while assigned < slots and r < remainders.size():
		counts[remainders[r]["kind"]] = int(counts[remainders[r]["kind"]]) + 1
		assigned += 1
		r += 1
	# Emit largest-first: slot order around the core is social geography
	# (big homes claim the quiet corners; Ch 32 places slots in order).
	var out: Array = []
	var largest_first: Array = [KIND_FAMILY, KIND_TWO_BED, KIND_ONE_BED, KIND_STUDIO]
	for kind in largest_first:
		for i in int(counts.get(kind, 0)):
			out.append(kind)
	return out

# The core, as a program element: sized, placed, and returned as data
# BEFORE any unit slot is drawn. Point block: one central core, units
# around it. Corridor: the same core stretched into a hall spine.
# service_wall_x is the vertical plane the wet rooms stack against
# (Ch 32's stamping constraint reads it from here, nowhere else).
static func core_for(typology: String, footprint: Vector2) -> Dictionary:
	var cx: float = footprint.x * 0.5
	var cy: float = footprint.y * 0.5
	if typology == "corridor":
		return {
			"typology": "corridor",
			"stair_rect": Rect2(cx - 2.6, cy - 1.1, 2.6, 2.2),
			"lift_rect": Rect2(cx, cy - 1.1, 1.8, 2.2),
			"hall_rect": Rect2(0, cy - 1.1, footprint.x, 2.2),
			"service_wall_x": cx - 2.6,
			"entrance_x": cx,
		}
	return {
		"typology": "point",
		"stair_rect": Rect2(cx - 2.7, cy - 1.6, 2.7, 3.2),
		"lift_rect": Rect2(cx, cy - 1.6, 1.9, 3.2),
		"hall_rect": Rect2(0, cy - 1.6, footprint.x, 3.2),
		"service_wall_x": cx - 2.7,
		"entrance_x": cx,
	}
