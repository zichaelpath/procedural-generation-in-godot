class_name OfficeLayout
extends RefCounted
## One plate's geometry, rolled ONCE per tower: core (from the
## program) -> bands (facade N/S, middle) -> facade slots (jittered
## weights) + fields + service slots (fixed offsets from the core —
## structural, never jittered). Floors differ only by STAMPING
## (§35.2). Every floor plan is a Ch 26 plan plus a "desks" slot.

const FACADE_DEPTH: float = 4.8 # a meeting room: table + chairs + passing space
const FACADE_NORTH_TARGETS: Array = [26.0, 9.0, 9.0, 18.0]
const FACADE_SOUTH_TARGETS: Array = [18.0, 9.0, 9.0, 26.0]

static func roll_plate(program: OfficeProgram, core: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var fp: Rect2 = Rect2(Vector2.ZERO, program.footprint)
	var mid_y: float = FACADE_DEPTH
	var mid_h: float = fp.size.y - FACADE_DEPTH * 2.0
	var core_hall: Rect2 = core["hall_rect"]
	var svc_x: float = float(core["service_wall_x"])
	# West service column: WC / corridor / WC, stacked on the service
	# wall (the core's west face). Fixed offsets — structural.
	var wc_w: float = 2.6
	var west_col_x: float = svc_x - wc_w
	var roll: Dictionary = {}
	roll["footprint"] = fp
	roll["core"] = core
	roll["field_west"] = Rect2(0, mid_y, west_col_x, mid_h)
	roll["wc_north"] = Rect2(west_col_x, mid_y, wc_w, core_hall.position.y - mid_y)
	roll["corridor_west"] = Rect2(west_col_x, core_hall.position.y, wc_w, core_hall.size.y)
	roll["wc_south"] = Rect2(west_col_x, core_hall.end.y, wc_w, mid_y + mid_h - core_hall.end.y)
	roll["field_core_north"] = Rect2(core_hall.position.x, mid_y, core_hall.size.x, core_hall.position.y - mid_y)
	roll["field_core_south"] = Rect2(core_hall.position.x, core_hall.end.y, core_hall.size.x, mid_y + mid_h - core_hall.end.y)
	# East service zone: kitchenette over corridor+print over
	# server+storage, against the core's east face.
	var east_x: float = core_hall.end.x
	var east_w: float = 5.8
	roll["kitchenette"] = Rect2(east_x, mid_y, east_w, core_hall.position.y - mid_y)
	roll["corridor_east"] = Rect2(east_x, core_hall.position.y, 3.4, core_hall.size.y)
	roll["print"] = Rect2(east_x + 3.4, core_hall.position.y, east_w - 3.4, core_hall.size.y)
	roll["server"] = Rect2(east_x, core_hall.end.y, east_w * 0.5, mid_y + mid_h - core_hall.end.y)
	roll["storage"] = Rect2(east_x + east_w * 0.5, core_hall.end.y, east_w * 0.5, mid_y + mid_h - core_hall.end.y)
	roll["field_east"] = Rect2(east_x + east_w, mid_y, fp.size.x - east_x - east_w, mid_h)
	# Facade slots: the roll's ONLY jitter (±4% on slot weights).
	roll["facade_north"] = _facade_slots(FACADE_NORTH_TARGETS, Rect2(0, 0, fp.size.x, FACADE_DEPTH), rng)
	roll["facade_south"] = _facade_slots(FACADE_SOUTH_TARGETS, Rect2(0, fp.size.y - FACADE_DEPTH, fp.size.x, FACADE_DEPTH), rng)
	return roll

static func _facade_slots(targets: Array, band: Rect2, rng: RandomNumberGenerator) -> Array:
	var specs: Array = []
	for i in targets.size():
		var jittered: float = float(targets[i]) * rng.randf_range(0.96, 1.04)
		specs.append({"name": "slot_%d" % i, "type": "bedroom", "zone": "private", "target": jittered, "min": 0.0})
	var counts: Dictionary = {}
	var packed: Array = BandLayout._lay_row(specs, band, counts)
	var out: Array = []
	for entry in packed:
		out.append(entry["rect"])
	return out

# Stamp one floor: assign a kind, then map the kind onto the roll's
# slots BY ROLE, under the §35.2 constraint rules. Names are
# tenancy-prefixed ("f03_meeting_1"); shared rooms keep plain names.
static func stamp_floor(roll: Dictionary, floor_index: int, kind: String, core: Dictionary) -> Dictionary:
	var tenancy_id: String = "F%02d" % (floor_index + 1)
	var prefix: String = tenancy_id.to_lower() + "_"
	var rooms: Array = []
	rooms.append({"name": "core_hall", "type": "hall", "zone": "circulation", "unit": "",
		"rect": core["hall_rect"], "target": 0.0, "min": 0.0})
	rooms.append({"name": "stairs", "type": "stairs", "zone": "circulation", "unit": "",
		"rect": core["stair_rect"], "target": 0.0, "min": 0.0})
	rooms.append({"name": "lift", "type": "lift", "zone": "circulation", "unit": "",
		"rect": core["lift_rect"], "target": 0.0, "min": 0.0})
	var counters: Dictionary = {}
	var put := func(local_name: String, room_type: String, zone: String, rect: Rect2, target: float, min_area: float, shared: bool) -> void:
		rooms.append({"name": local_name if shared else prefix + local_name, "type": room_type, "zone": zone,
			"unit": "" if shared else tenancy_id, "rect": rect, "target": target, "min": min_area})
	# Services first — fixed slots, fixed types, every kind (§35.2 rule 2).
	put.call("wc_1", "wc", "service", roll["wc_north"], 12.0, 3.5, true)
	put.call("wc_2", "wc", "service", roll["wc_south"], 12.0, 3.5, true)
	put.call("corridor_west", "hall", "circulation", roll["corridor_west"], 0.0, 3.0, true)
	put.call("corridor_east", "hall", "circulation", roll["corridor_east"], 0.0, 3.0, true)
	put.call("kitchenette", "kitchenette", "service", roll["kitchenette"], 26.0, 6.0, false)
	put.call("server", "server", "service", roll["server"], 13.0, 6.0, true)
	put.call("storage_1", "storage", "service", roll["storage"], 13.0, 3.0, true)
	put.call("storage_2", "storage", "service", roll["print"], 8.0, 3.0, true)
	# Fields (§35.2 rule 3): open work space, lobby, or breakout — never enclosed.
	var field_types: Dictionary = {"field_west": "open_plan", "field_east": "open_plan",
		"field_core_north": "open_plan", "field_core_south": "open_plan"}
	if kind == OfficeProgram.KIND_COLLABORATION:
		field_types["field_east"] = "breakout"
	if kind == OfficeProgram.KIND_LOBBY:
		field_types["field_core_north"] = "lobby"
		field_types["field_core_south"] = "lobby"
	for field_name in field_types.keys():
		var ftype: String = field_types[field_name]
		var fname: String = field_name
		if ftype == "lobby":
			fname = "lobby_north" if field_name == "field_core_north" else "lobby_south"
		elif ftype == "breakout":
			fname = "breakout"
		put.call(fname, ftype, "circulation" if ftype == "lobby" else "social", roll[field_name],
			90.0 if ftype == "lobby" else 200.0, 20.0, false)
	# Facades (§35.2 rule 1): enclosed rooms live here and only here.
	var north_types: Array = ["meeting", "focus", "focus", "meeting"]
	var south_types: Array = ["meeting", "focus", "focus", "meeting"]
	match kind:
		OfficeProgram.KIND_COLLABORATION:
			north_types = ["meeting", "meeting", "focus", "meeting"]
			south_types = ["meeting", "focus", "meeting", "meeting"]
		OfficeProgram.KIND_EXECUTIVE:
			north_types = ["meeting", "office", "office", "office"]
			south_types = ["office", "office", "focus", "meeting"]
	for i in 4:
		_stamp_facade(put, counters, north_types[i], roll["facade_north"][i], kind, i == 0)
		_stamp_facade(put, counters, south_types[i], roll["facade_south"][i], kind, false)
	if kind == OfficeProgram.KIND_LOBBY:
		# Rule 4: the south slot holding the entrance becomes lobby.
		var entrance_x: float = float(core["entrance_x"])
		for room in rooms:
			if room["type"] == "meeting" or room["type"] == "focus":
				var rect: Rect2 = room["rect"]
				if absf(rect.end.y - (roll["footprint"] as Rect2).end.y) < 0.02 and entrance_x >= rect.position.x and entrance_x <= rect.end.x:
					room["name"] = prefix + "lobby_entry"
					room["type"] = "lobby"
					room["zone"] = "circulation"
					room["min"] = 20.0
	var plan: Dictionary = {"footprint": roll["footprint"], "rooms": rooms, "doors": [], "windows": [], "desks": [],
		"entrance_room": "core_hall",
		"meta": {"office_floor": true, "floor_index": floor_index, "plate_kind": kind,
			"no_entrance": floor_index > 0, "headcount": 0}}
	return plan

static func _stamp_facade(put: Callable, counters: Dictionary, room_type: String, rect: Rect2, kind: String, is_first_north: bool) -> void:
	var n: int = int(counters.get(room_type, 0)) + 1
	counters[room_type] = n
	var local_name: String = "%s_%d" % [room_type, n]
	if kind == OfficeProgram.KIND_EXECUTIVE and room_type == "meeting" and is_first_north:
		local_name = "boardroom"
	var target: float = 18.0
	var min_area: float = 8.0
	if room_type == "focus":
		target = 9.0
		min_area = 6.0
	elif room_type == "office":
		target = 16.0
		min_area = 9.0
	put.call(local_name, room_type, "private" if room_type == "focus" or room_type == "office" else "social",
		rect, target, min_area, false)

# Desk density per floor kind: how much of the field's grid survives.
static func desk_density_for(kind: String) -> float:
	match kind:
		OfficeProgram.KIND_COLLABORATION:
			return 0.55
		OfficeProgram.KIND_EXECUTIVE:
			return 0.50
	return 1.0

# Assemble the OFFICE BLOCK: roll once, stamp every floor. Upper
# floors keep their program-assigned kinds (a tower's brief is per
# floor, unlike an apartment's mix) — the variation IS the brief.
static func generate_tower(program: OfficeProgram, core: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var roll: Dictionary = roll_plate(program, core, rng)
	var floors: Array = []
	var tenancies: Array = []
	for f in program.floor_count():
		var kind: String = program.floor_kinds[f]
		var plan: Dictionary = stamp_floor(roll, f, kind, core)
		plan["meta"]["headcount"] = int(program.seats_per_floor[f])
		floors.append(plan)
		var room_names: Array = []
		var area: float = 0.0
		for room in plan["rooms"]:
			if String(room.get("unit", "")) != "":
				room_names.append(room["name"])
				area += (room["rect"] as Rect2).get_area()
		tenancies.append({"id": "F%02d" % (f + 1), "kind": kind, "floor": f, "slot": 0,
			"room_names": room_names, "area": area, "headcount": int(program.seats_per_floor[f])})
	return {"footprint": roll["footprint"], "floors": floors, "stair_rect": core["stair_rect"],
		"core": core, "units": tenancies,
		"meta": {"building_use": "office", "headcount_total": program.headcount_total(),
			"plate": OfficeProgram.plate_budget(program.footprint, core),
			"floor_kinds": program.floor_kinds.duplicate()}}

# Doors for one office floor. Hub = core_hall. Preference order is
# policy, stated here: circulation first, then an open field, then
# the kitchenette (the floor's social service room); never into a
# WC, server, or storage room from a work room. Geometry is Ch 28's
# DoorGraph.shared_segment(), reused; rooms are read by "type".
const NEVER_DOOR_INTO: Array = ["wc", "server", "storage", "stairs", "lift"]

static func build_floor_doors(plan: Dictionary, core: Dictionary) -> Array:
	var doors: Array = []
	var rooms: Array = plan["rooms"]
	var circulation: Array = []
	var fields: Array = []
	for room in rooms:
		if room["type"] == "hall" or room["type"] == "stairs" or room["type"] == "lift":
			circulation.append(room)
		if room["type"] == "open_plan" or room["type"] == "lobby" or room["type"] == "breakout":
			fields.append(room)
	for room in rooms:
		if circulation.has(room):
			continue
		var done: bool = false
		for host in circulation:
			if _add_office_door(doors, room, host, "door", 0.95):
				done = true
				break
		if not done:
			for host in fields:
				if host["name"] != room["name"] and _add_office_door(doors, room, host, "door", 0.95):
					done = true
					break
		if not done:
			for host in rooms:
				if host["type"] == "kitchenette" and _add_office_door(doors, room, host, "door", 0.95):
					done = true
					break
		if not done and not NEVER_DOOR_INTO.has(room["type"]):
			push_error("OfficeLayout: %s found no legal door host — floor will fail reachability" % room["name"])
	# Fields open onto circulation where they touch it (in addition to
	# any door a field received as a host above).
	for field in fields:
		for host in circulation:
			_add_office_door(doors, field, host, "opening", 1.6)
	# Circulation interconnects (FIX — see below): the loops above
	# never door a circulation room from either side (circulation
	# rooms are skipped as sources and only fields door into them),
	# so as printed the corridor stubs — which share full segments
	# with the core hall — and the core's own stair/lift would strand:
	# no tower could ever pass the solver's reachability assertion.
	# Connect every circulation room to the core hall where a real
	# shared segment exists (corridors, galleries), and connect the
	# stair and lift — whose rectangles are CONTAINED in the hall
	# rectangle (Ch 31's point core: hall = stair + lift exactly),
	# so no shared segment exists — to their hall explicitly. The
	# containment doors' centres sit inside the core, on no wall
	# segment, so the builder cuts nothing for them; they record
	# the physical fact that the stair and lift open into the hall.
	var core_hall: Dictionary = {}
	for room in rooms:
		if room["name"] == "core_hall":
			core_hall = room
	if not core_hall.is_empty():
		for host in circulation:
			if host["name"] != "core_hall":
				_add_office_door(doors, host, core_hall, "opening", 1.6)
		for room in rooms:
			if room["name"] == "stairs" or room["name"] == "lift":
				var already: bool = false
				for existing in doors:
					if (existing["a"] == room["name"] and existing["b"] == "core_hall") or (existing["a"] == "core_hall" and existing["b"] == room["name"]):
						already = true
				if not already:
					doors.append({"a": room["name"], "b": "core_hall", "kind": "opening", "width": 1.6,
						"center": (room["rect"] as Rect2).get_center(), "vertical": false})
	# The street entrance: ground floor only, into the room that
	# holds entrance_x on the south edge (a lobby room, by §35.2 rule 4).
	if not bool(plan["meta"].get("no_entrance", false)):
		var entrance_x: float = float(core["entrance_x"])
		var footprint: Rect2 = plan["footprint"]
		for room in rooms:
			var rect: Rect2 = room["rect"]
			if absf(rect.end.y - footprint.end.y) < 0.02 and entrance_x >= rect.position.x and entrance_x <= rect.end.x:
				doors.append({"a": room["name"], "b": "EXTERIOR", "kind": "entrance", "width": 1.6,
					"center": Vector2(entrance_x, footprint.end.y), "vertical": false})
	plan["doors"] = doors
	return doors

static func _add_office_door(doors: Array, a: Dictionary, b: Dictionary, kind: String, width: float) -> bool:
	for existing in doors:
		if (existing["a"] == a["name"] and existing["b"] == b["name"]) or (existing["a"] == b["name"] and existing["b"] == a["name"]):
			return true # already connected: counts as done, adds nothing
	var segment: Dictionary = DoorGraph.shared_segment(a["rect"], b["rect"])
	if float(segment["length"]) < width + 0.3:
		return false
	doors.append({"a": a["name"], "b": b["name"], "kind": kind, "width": width,
		"center": segment["center"], "vertical": segment["vertical"]})
	return true

# --- The display tower (Ch 36) ---------------------------------------
# Presentation decisions applied BEFORE the passes run, then judged
# by the same OfficeRules as any tower (the stage validates and
# refuses on violations). Two decisions: the atrium (floor 1 loses
# its two core fields to voids + gallery strips) and the setback
# (the top floor re-rolled on a smaller, centred plate).
const SETBACK_INSET: Vector2 = Vector2(2.0, 1.5)
const GALLERY_DEPTH: float = 1.4

static func generate_display_tower(program: OfficeProgram, core: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tower: Dictionary = generate_tower(program, core, rng)
	_apply_atrium(tower)
	_apply_setback(tower, program, rng)
	return tower

static func _apply_atrium(tower: Dictionary) -> void:
	var floors: Array = tower["floors"]
	if floors.size() < 2:
		return
	var plan: Dictionary = floors[1]
	var kept: Array = []
	var voids: Array = []
	for room in plan["rooms"]:
		var is_core_field: bool = room["type"] == "open_plan" and (room["name"].ends_with("field_core_north") or room["name"].ends_with("field_core_south"))
		if not is_core_field:
			kept.append(room)
			continue
		var rect: Rect2 = room["rect"]
		var gallery: Rect2
		var void_rect: Rect2
		if room["name"].ends_with("field_core_north"):
			void_rect = Rect2(rect.position, Vector2(rect.size.x, rect.size.y - GALLERY_DEPTH))
			gallery = Rect2(rect.position + Vector2(0, rect.size.y - GALLERY_DEPTH), Vector2(rect.size.x, GALLERY_DEPTH))
			kept.append({"name": "gallery_north", "type": "hall", "zone": "circulation", "unit": "",
				"rect": gallery, "target": 0.0, "min": 0.0})
		else:
			gallery = Rect2(rect.position, Vector2(rect.size.x, GALLERY_DEPTH))
			void_rect = Rect2(rect.position + Vector2(0, GALLERY_DEPTH), Vector2(rect.size.x, rect.size.y - GALLERY_DEPTH))
			kept.append({"name": "gallery_south", "type": "hall", "zone": "circulation", "unit": "",
				"rect": gallery, "target": 0.0, "min": 0.0})
		voids.append(void_rect)
	plan["rooms"] = kept
	plan["meta"]["atrium_voids"] = voids

static func _apply_setback(tower: Dictionary, program: OfficeProgram, rng: RandomNumberGenerator) -> void:
	var floors: Array = tower["floors"]
	if floors.size() < 2:
		return
	var top: int = floors.size() - 1
	var setback_size: Vector2 = program.footprint - SETBACK_INSET * 2.0
	var sub_program: OfficeProgram = OfficeProgram.build(setback_size, [program.floor_kinds[top]], [program.seats_per_floor[top]], program.core_typology)
	var sub_core: Dictionary = OfficeProgram.core_for(program.core_typology, setback_size)
	var sub_roll: Dictionary = roll_plate(sub_program, sub_core, rng)
	var plan: Dictionary = stamp_floor(sub_roll, top, program.floor_kinds[top], sub_core)
	plan["meta"]["headcount"] = int(program.seats_per_floor[top])
	_shift_plan(plan, SETBACK_INSET)
	plan["meta"]["setback"] = true
	floors[top] = plan
	tower["meta"]["setback_floor"] = top

static func _shift_plan(plan: Dictionary, offset: Vector2) -> void:
	plan["footprint"] = Rect2((plan["footprint"] as Rect2).position + offset, (plan["footprint"] as Rect2).size)
	for room in plan["rooms"]:
		room["rect"] = Rect2((room["rect"] as Rect2).position + offset, (room["rect"] as Rect2).size)
