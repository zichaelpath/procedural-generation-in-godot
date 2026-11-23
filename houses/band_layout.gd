class_name BandLayout
extends RefCounted
## V2 layout: a FIXED architectural topology, parameterised.
##   north band : private rooms (bedrooms + bathroom) in a row
##   middle band: the hall corridor, full width (WC carved from its west end)
##   south band : social rooms (living, kitchen, dining) at the entrance edge,
##                split by the entrance vestibule — a strip of hall reaching
##                the south wall, so the front door opens into circulation,
##                never into a room.
## Randomness lives in DIMENSIONS only, drawn from the caller's RNG stream.
## Whole families of zoning violations are impossible by construction.

static func generate(specs: Array, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var private_depth: float = clampf(size.y * rng.randf_range(0.30, 0.36), 3.0, 4.4)
	var hall_depth: float = rng.randf_range(1.25, 1.5)
	var social_depth: float = size.y - private_depth - hall_depth
	var private_specs: Array = []
	var social_specs: Array = []
	var wc_spec: Dictionary = {}
	for spec in specs:
		var spec_type: String = spec["type"]
		# FIX (Ch 29/30): the program's hall line item is skipped here —
		# the corridor is created by this layout (below), exactly as
		# _partition() (Listing 30.9) already skips type "hall". As
		# printed, Listing 29.5 routes the hall spec into the social
		# band, producing a stray "hall_2" room no door rule connects,
		# so DoorGraph.all_reachable() could never pass.
		if spec_type == "hall":
			continue
		elif spec_type == "wc":
			wc_spec = spec
		elif spec_type == "bathroom" or spec_type == "bedroom" or spec_type == "master":
			private_specs.append(spec)
		else:
			social_specs.append(spec)
	var rooms: Array = []
	var name_counts: Dictionary = {}
	# Private band across the north edge.
	var private_band: Rect2 = Rect2(0.0, 0.0, size.x, private_depth)
	rooms.append_array(_lay_row(private_specs, private_band, name_counts))
	# Hall band: WC at the west end (guest WC by the entrance), hall takes
	# the rest of the row and owns all circulation in the house.
	var hall_y: float = private_depth
	if not wc_spec.is_empty():
		var wc_width: float = clampf(float(wc_spec["target"]) / hall_depth, 1.2, 1.8)
		rooms.append(_make_room(wc_spec, Rect2(0.0, hall_y, wc_width, hall_depth), name_counts))
		rooms.append(_make_room({"type": "hall", "zone": "circulation", "target": 0.0, "min": 0.0},
			Rect2(wc_width, hall_y, size.x - wc_width, hall_depth), name_counts))
	else:
		rooms.append(_make_room({"type": "hall", "zone": "circulation", "target": 0.0, "min": 0.0},
			Rect2(0.0, hall_y, size.x, hall_depth), name_counts))
	# Social band across the south (entrance) edge, split in two by the
	# entrance vestibule.
	var entrance_x: float = size.x * rng.randf_range(0.35, 0.65)
	var social_y: float = hall_y + hall_depth
	var vestibule_width: float = 1.4
	var vx0: float = clampf(entrance_x - vestibule_width * 0.5, 0.0, size.x - vestibule_width)
	var vx1: float = vx0 + vestibule_width
	entrance_x = vx0 + vestibule_width * 0.5
	var split: Dictionary = _split_specs(social_specs, vx0 / size.x)
	rooms.append_array(_lay_row(split["left"], Rect2(0.0, social_y, vx0, social_depth), name_counts))
	rooms.append_array(_lay_row(split["right"], Rect2(vx1, social_y, size.x - vx1, social_depth), name_counts))
	rooms.append({"name": "hall_entry", "type": "hall", "zone": "circulation",
		"rect": Rect2(vx0, social_y, vestibule_width, social_depth), "target": 0.0, "min": 0.0})
	return {
		"footprint": Rect2(0.0, 0.0, size.x, size.y),
		"rooms": rooms,
		"doors": [],
		"windows": [],
		"entrance_room": "hall",
		"meta": {
			"private_depth": private_depth,
			"hall_depth": hall_depth,
			"entrance_x": entrance_x,
			"topology": "bands",
		},
	}

# Split a band's room specs between two segments, roughly in proportion
# to the segments' widths (rooms are never split — whole rooms only).
static func _split_specs(band_specs: Array, left_fraction: float) -> Dictionary:
	var total_target: float = 0.0
	for spec in band_specs:
		total_target += float(spec["target"])
	var left: Array = []
	var right: Array = []
	var left_target: float = 0.0
	for spec in band_specs:
		if left_target + float(spec["target"]) * 0.5 <= total_target * left_fraction:
			left.append(spec)
			left_target += float(spec["target"])
		else:
			right.append(spec)
	# Both segments must receive at least one room when there are specs
	# to spare — an empty segment would leave an untiled hole in the plan.
	if band_specs.size() >= 2:
		if left.is_empty():
			left.append(right.pop_front())
		if right.is_empty():
			right.append(left.pop_back())
	return {"left": left, "right": right}

# Lay one band's rooms in a row: each room's desired width is the width
# that would give it its target area at this band depth; widths are then
# scaled so the row fills the band exactly, and the last room takes the
# remainder so shared edges snap shut with no floating-point gaps.
static func _lay_row(row_specs: Array, band: Rect2, name_counts: Dictionary) -> Array:
	var rooms: Array = []
	if row_specs.is_empty():
		return rooms
	var desired_total: float = 0.0
	for spec in row_specs:
		desired_total += float(spec["target"]) / band.size.y
	var cursor_x: float = band.position.x
	for i in row_specs.size():
		var spec: Dictionary = row_specs[i]
		var width: float = band.size.x * (float(spec["target"]) / band.size.y) / desired_total
		if i == row_specs.size() - 1:
			width = band.end.x - cursor_x
		rooms.append(_make_room(spec, Rect2(cursor_x, band.position.y, width, band.size.y), name_counts))
		cursor_x += width
	return rooms

# Room names are unique: repeated types are numbered (bedroom_1,
# bedroom_2); a type that occurs once keeps its bare name (hall, living).
static func _make_room(spec: Dictionary, rect: Rect2, name_counts: Dictionary) -> Dictionary:
	var room_type: String = spec["type"]
	var seen: int = int(name_counts.get(room_type, 0)) + 1
	name_counts[room_type] = seen
	var room_name: String = room_type
	if room_type == "bedroom" or seen > 1:
		room_name = "%s_%d" % [room_type, seen]
	return {
		"name": room_name,
		"type": room_type,
		"zone": spec["zone"],
		"rect": rect,
		"target": float(spec.get("target", 0.0)),
		"min": float(spec.get("min", 0.0)),
	}

# --- Two storeys, one wall plan (Ch 30) ---------------------------------
# Slot geometry is rolled ONCE, sized by the larger of the two floors'
# demands per slot; each floor's room types are then stamped onto the
# shared slots. Wet rooms stack exactly; at most ONE bathroom per
# floor (a second is demoted to a WC at stamping time); the stair
# strip is reserved before any slot is laid.
const STAIR_W: float = 1.05

static func generate_two_storey(ground_specs: Array, upper_specs: Array, size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var band_w: float = size.x - STAIR_W
	var private_depth: float = clampf(size.y * rng.randf_range(0.30, 0.36), 3.0, 4.4)
	var hall_depth: float = rng.randf_range(1.25, 1.5)
	var entrance_x: float = band_w * rng.randf_range(0.35, 0.65)
	var slots: Dictionary = _roll_slots(ground_specs, upper_specs, band_w, size.y, private_depth, hall_depth, entrance_x)
	var ground: Dictionary = _assign_floor(slots, ground_specs, size, false)
	var upper: Dictionary = _assign_floor(slots, upper_specs, size, true)
	return {
		"footprint": Rect2(0.0, 0.0, size.x, size.y),
		"floors": [ground, upper],
		"stair_rect": Rect2(band_w, 0.0, STAIR_W, size.y),
		"meta": {"storeys": 2},
	}

static func _band_of(spec: Dictionary) -> String:
	if spec.has("band"):
		return spec["band"]
	var spec_type: String = spec["type"]
	if spec_type == "bedroom" or spec_type == "master" or spec_type == "bathroom":
		return "private"
	return "social"

static func _partition(specs: Array) -> Dictionary:
	var privates: Array = []
	var socials: Array = []
	var wc_spec: Dictionary = {}
	for spec in specs:
		if spec["type"] == "wc":
			wc_spec = spec
		elif spec["type"] == "hall":
			continue
		elif _band_of(spec) == "private":
			privates.append(spec)
		else:
			socials.append(spec)
	return {"private": privates, "social": socials, "wc": wc_spec}

static func _merged_specs(a: Array, b: Array) -> Array:
	# Pairwise maximum targets: each shared slot is sized for the
	# needier of the two floors that will occupy it.
	var merged: Array = []
	var counts: Dictionary = {}
	for i in maxi(a.size(), b.size()):
		var target: float = 0.0
		if i < a.size():
			target = maxf(target, float(a[i]["target"]))
		if i < b.size():
			target = maxf(target, float(b[i]["target"]))
		merged.append({"type": "bedroom", "zone": "private", "target": target, "min": 0.0})
	return merged

static func _roll_slots(ground_specs: Array, upper_specs: Array, band_w: float, depth: float, private_depth: float, hall_depth: float, entrance_x: float) -> Dictionary:
	var ground_parts: Dictionary = _partition(ground_specs)
	var upper_parts: Dictionary = _partition(upper_specs)
	var counts: Dictionary = {}
	var north: Array = _lay_row(_merged_specs(ground_parts["private"], upper_parts["private"]),
		Rect2(0.0, 0.0, band_w, private_depth), counts)
	var hall_y: float = private_depth
	var wc_width: float = 0.0
	if not ground_parts["wc"].is_empty() or not upper_parts["wc"].is_empty():
		wc_width = 1.5
	var wc_rect: Rect2 = Rect2(0.0, hall_y, wc_width, hall_depth) if wc_width > 0.0 else Rect2()
	var hall_rect: Rect2 = Rect2(wc_width, hall_y, band_w - wc_width, hall_depth)
	var social_y: float = hall_y + hall_depth
	var social_depth: float = depth - social_y
	var vestibule_width: float = 1.4
	var vx0: float = clampf(entrance_x - vestibule_width * 0.5, 0.0, band_w - vestibule_width)
	var merged_social: Array = _merged_specs(ground_parts["social"], upper_parts["social"])
	var split: Dictionary = _split_specs(merged_social, vx0 / band_w)
	var counts_left: Dictionary = {}
	var counts_right: Dictionary = {}
	var south_left: Array = _lay_row(split["left"], Rect2(0.0, social_y, vx0, social_depth), counts_left)
	var south_right: Array = _lay_row(split["right"], Rect2(vx0 + vestibule_width, social_y, band_w - vx0 - vestibule_width, social_depth), counts_right)
	return {
		"north": north, "wc": wc_rect, "hall": hall_rect,
		"south_left": south_left, "south_right": south_right,
		"vestibule": Rect2(vx0, social_y, vestibule_width, social_depth),
		"entrance_x": vx0 + vestibule_width * 0.5,
	}

static func _room_from_spec(spec: Dictionary, rect: Rect2) -> Dictionary:
	return {
		"name": spec["name"], "type": spec["type"], "zone": spec["zone"],
		"rect": rect, "target": float(spec.get("target", 0.0)), "min": float(spec.get("min", 0.0)),
	}

static func _assign_floor(slots: Dictionary, specs: Array, size: Vector2, is_upper: bool) -> Dictionary:
	var parts: Dictionary = _partition(specs)
	var rooms: Array = []
	var bathrooms: int = 0
	# North band: stamp this floor's private specs onto the shared slots.
	var privates: Array = parts["private"]
	for i in privates.size():
		var spec: Dictionary = privates[i]
		if spec["type"] == "bathroom":
			bathrooms += 1
			if bathrooms > 1:
				# One full bathroom per floor. A second is demoted to a
				# WC at stamping time — same slot, smaller promise.
				spec = {"name": "wc", "type": "wc", "zone": "service",
					"target": spec["target"], "min": 1.2}
		rooms.append(_room_from_spec(spec, slots["north"][i]["rect"])) # FIX (Ch 30): _lay_row returns room Dictionaries (Listing 29.5), not Rect2s — Listing 30.9 passes them as Rect2
	# Hall band: WC slot if this floor has one, else the hall widens.
	var hall_rect: Rect2 = slots["hall"]
	if not parts["wc"].is_empty():
		rooms.append(_room_from_spec(parts["wc"], slots["wc"]))
	else:
		var wc_rect: Rect2 = slots["wc"]
		if wc_rect.size.x > 0.0:
			hall_rect = Rect2(wc_rect.position.x, wc_rect.position.y, hall_rect.end.x - wc_rect.position.x, wc_rect.size.y)
	rooms.append({"name": "hall", "type": "hall", "zone": "circulation", "rect": hall_rect, "target": 0.0, "min": 0.0})
	# The stair strip: a room on both floors, so the graph, the
	# validator, and the builder all see the same circulation.
	rooms.append({"name": "stairs", "type": "stairs", "zone": "circulation",
		"rect": Rect2(size.x - STAIR_W, 0.0, STAIR_W, size.y), "target": 0.0, "min": 0.0})
	# South band: this floor's social specs, in order, across the split.
	var social_rects: Array = []
	social_rects.append_array(slots["south_left"])
	social_rects.append_array(slots["south_right"])
	var socials: Array = parts["social"]
	for i in socials.size():
		rooms.append(_room_from_spec(socials[i], social_rects[i]["rect"])) # FIX (Ch 30): as above — slot entries are room Dictionaries
	rooms.append({"name": "hall_entry", "type": "hall", "zone": "circulation", "rect": slots["vestibule"], "target": 0.0, "min": 0.0})
	return {
		"footprint": Rect2(0.0, 0.0, size.x, size.y),
		"rooms": rooms,
		"doors": [],
		"windows": [],
		"entrance_room": "hall",
		"meta": {
			"topology": "bands",
			"entrance_x": slots["entrance_x"],
			"upper_floor": is_upper,
			"no_entrance": is_upper,
		},
	}
