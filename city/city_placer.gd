class_name CityPlacer
extends Node3D

## Walks parcels, negotiates use against size, calls the certified
## generators of Parts V-VII, and stands their buildings on the
## land. First law (§40.2): the parcel sizes the building; the
## building never stretches to the parcel. Surrenders step DOWN a
## use (office -> apartment -> house -> green) and are ledgered.
##
## Project integration notes (the real Parts V–VII APIs, verified
## against their stage scripts — the negotiation is Listing 40.2's):
## - The solvers return WRAPPERS: HouseSolver.solve() -> {"plan"},
##   BlockSolver.solve() -> {"block"}, OfficeSolver.solve() ->
##   {"tower"}. The listing reads the block/tower dictionaries
##   directly off the result; the wrapper keys are unwrapped here.
## - The office core comes from OfficeProgram.core_for() (Part
##   VII's own), not ApartmentProgram.core_for() as printed.
## - House plans need WindowPlacer.place_windows() before
##   HouseBuilder will find plan["windows"] (the block/office
##   solvers run it internally; HouseSolver does not — Part V's
##   stage calls it in its build step).
## - Solver attempt budgets are parameters (house_attempts etc.):
##   Chapter 41's own preview bargain — a draft city may spend fewer
##   attempts; the stage sets them per step. Houses are built
##   unfurnished (with_furniture = false): at city scale the
##   furniture is invisible from every camera the book uses, and
##   Chapter 30's furnished audit lives in Part V's stage.
## - use_cap is Chapter 41's borough character, layered over the
##   field: a borough whose character is "house" never proposes
##   above house, whatever the gradient says.
## - max_buildings (0 = no cap) is Chapter 42's draft-assembly
##   budget: placement stops, in deterministic parcel order, once
##   the cap is placed; the summary reports how many were skipped.

const SIDE_CLEARANCE: float = 1.5
const FRONT_SETBACK: float = 2.0
const FLOOR_HEIGHT: float = 3.1 # Parts VI-VII's storey, reused

var _terrain: TerrainHeight
var _zoning: Zoning
var _master_seed: int

# The ledger: use -> {"placed": int, "surrendered": int}
var ledger: Dictionary = {}

# Stage-set build budgets (see header notes).
var house_attempts: int = 400
var apartment_attempts: int = 400
var office_attempts: int = 300
var apartment_max_floors: int = 4
var office_max_floors: int = 7
var max_buildings: int = 0
var build_facades: bool = true

# Borough character cap ("" = the field alone decides).
var use_cap: String = ""

# The placed house the stage's street-level camera visits: the
# FLATTEST house parcel (a street shot needs street and house at
# one height), as {centre: Vector3, perp: Vector2, axis: Vector2}.
var street_focus: Dictionary = {}
var _focus_slope: float = 1.0e9

# Every successful build, for the stage's camera work:
# {centre: Vector3, perp: Vector2, axis: Vector2, use: String}.
var built_centres: Array[Dictionary] = []

# The plate the last successful build used (set by the _build_*
# functions), so _build can plinth exactly what stands.
var _last_plate: Vector2 = Vector2.ZERO
var _plinth_mat: StandardMaterial3D


func _init(terrain: TerrainHeight, zoning: Zoning,
		master_seed: int) -> void:
	_terrain = terrain
	_zoning = zoning
	_master_seed = master_seed
	_plinth_mat = StandardMaterial3D.new()
	_plinth_mat.albedo_color = Color(0.42, 0.42, 0.44)
	_plinth_mat.roughness = 1.0


func place_all(parcels: Array[Dictionary]) -> Dictionary:
	ledger.clear()
	var placed_count: int = 0
	var skipped_cap: int = 0
	for parcel in parcels:
		if not bool(parcel["fronting"]):
			continue # interior: green by Chapter 39's label
		if max_buildings > 0 and placed_count >= max_buildings:
			skipped_cap += 1
			continue
		var centre_local: Vector2 = parcel["local_rect"].get_center()
		var world_centre: Vector2 = BlockParcels._to_world(
			parcel["frame"], centre_local)
		var proposed: String = _zoning.use_at(
			world_centre.x, world_centre.y)
		proposed = _apply_cap(proposed)
		var built: bool = _place_one(parcel, proposed, world_centre)
		if built:
			placed_count += 1
	return {"placed": placed_count, "ledger": ledger,
		"skipped_cap": skipped_cap}


func _rank(use: String) -> int:
	match use:
		"office":
			return 3
		"apartment":
			return 2
		"house":
			return 1
	return 0


func _apply_cap(proposed: String) -> String:
	if use_cap == "":
		return proposed
	if _rank(proposed) > _rank(use_cap):
		return use_cap
	return proposed


func _place_one(parcel: Dictionary, proposed: String,
		world_centre: Vector2) -> bool:
	var use: String = proposed
	while use != "green":
		if _fits(parcel, use):
			var ok: bool = _build(parcel, use, world_centre)
			if ok:
				parcel["use"] = use
				_count(use, "placed")
				return true
			_count(use, "surrendered")
		use = _step_down(use)
	parcel["use"] = "green"
	return false


func _step_down(use: String) -> String:
	match use:
		"office":
			return "apartment"
		"apartment":
			return "house"
	return "green"


func _fits(parcel: Dictionary, use: String) -> bool:
	var band: Dictionary = BlockParcels.TARGETS[use]
	var w: Vector2 = band["w"]
	var d: Vector2 = band["d"]
	return parcel["local_rect"].size.x >= w.x \
		and parcel["local_rect"].size.y >= d.x


func _count(use: String, key: String) -> void:
	if not ledger.has(use):
		ledger[use] = {"placed": 0, "surrendered": 0}
	ledger[use][key] = int(ledger[use][key]) + 1


# The buildable footprint inside the parcel: clearances off the
# sides and rear, setback off the frontage edge (local z = 0).
func _footprint_for(parcel: Dictionary, use: String) -> Rect2:
	var local: Rect2 = parcel["local_rect"]
	var band: Dictionary = BlockParcels.TARGETS[use]
	var max_w: float = float(band["w"].y)
	var max_d: float = float(band["d"].y)
	var w: float = minf(local.size.x - SIDE_CLEARANCE * 2.0, max_w)
	var d: float = minf(local.size.y - FRONT_SETBACK - 1.0, max_d)
	# The footprint is further capped to the GENERATOR'S honest
	# range — the sizes Parts V-VII's own stages certify at (house
	# plates 10x8..12.5x10; apartment plates ~19.5 m square; office
	# plates inside the 18-24 m daylight depth band, 38 m wide).
	# The listings' band maxima describe the PARCEL a use fits, not
	# a plate the solver can certify: outside the envelope the
	# solvers do not slow down gracefully, they fall off a cliff
	# (an in-range program accepts in 1-2 attempts; a 26x24
	# apartment plate burns 5,000 attempts over 34 s and still
	# surrenders). A smaller building on the lot is the chapter's
	# own rule — the parcel sizes the building.
	match use:
		"house":
			w = minf(w, 13.0)
			d = minf(d, 12.0)
		"apartment":
			w = minf(w, 22.0)
			d = minf(d, 22.0)
		"office":
			w = minf(w, 38.0)
			d = minf(d, 22.0)
	var x: float = (local.size.x - w) * 0.5
	# The footprint rect is in the BLOCK frame (parcel["frame"]),
	# so it must carry the parcel's own position: without it every
	# parcel in a block builds at the frame origin and the block's
	# buildings stack on one corner (the overlap fix's placer half).
	return Rect2(local.position + Vector2(x, FRONT_SETBACK),
		Vector2(w, d))


func _build(parcel: Dictionary, use: String,
		world_centre: Vector2) -> bool:
	var fp: Rect2 = _footprint_for(parcel, use)
	var parcel_seed: int = _master_seed + int(parcel["block"]) * 1000 \
		+ int(parcel["local_rect"].position.x)
	var host := Node3D.new()
	host.name = "Parcel_%d_%s" % [int(parcel["block"]), use]
	var frame: Dictionary = parcel["frame"]
	var origin_world: Vector2 = BlockParcels._to_world(
		frame, fp.position)
	host.position = Vector3(origin_world.x,
		_terrain.height_at(world_centre.x, world_centre.y),
		origin_world.y)
	host.rotation.y = -atan2(frame["axis"].y, frame["axis"].x)
	add_child(host)
	var ok: bool = false
	match use:
		"house":
			ok = _build_house(host, fp, parcel_seed)
		"apartment":
			ok = _build_apartment(host, fp, parcel_seed, world_centre)
		"office":
			ok = _build_office(host, fp, parcel_seed, world_centre)
	if not ok:
		remove_child(host)
		host.queue_free()
		return false
	_add_plinth(host)
	built_centres.append({
		"centre": Vector3(world_centre.x,
			_terrain.height_at(world_centre.x, world_centre.y),
			world_centre.y),
		"perp": frame["perp"], "axis": frame["axis"],
		"use": use})
	if use == "house":
		var slope: float = _terrain.slope_at(
			world_centre.x, world_centre.y)
		if slope < _focus_slope:
			_focus_slope = slope
			street_focus = {
				"centre": Vector3(world_centre.x,
					_terrain.height_at(world_centre.x,
						world_centre.y),
					world_centre.y),
				"perp": frame["perp"], "axis": frame["axis"]}
	return true


# Chapter 40's own troubleshooting fix for sloped parcels — "a
# plinth in the host": a concrete stem wall from the building's
# base plane down past the lowest facet under its plate, so no
# certified building ever hangs off a hillside in the renders.
func _add_plinth(host: Node3D) -> void:
	if _last_plate == Vector2.ZERO:
		return
	var plate: Vector2 = _last_plate
	var min_y: float = 1.0e9
	var t: Transform3D = host.transform
	for c in [Vector2.ZERO, Vector2(plate.x, 0.0), plate,
			Vector2(0.0, plate.y)]:
		var w: Vector3 = t * Vector3(c.x, 0.0, c.y)
		min_y = minf(min_y, RoadBuilder.facet_height(
			_terrain, w.x, w.z))
	var bottom: float = min_y - 0.25 - host.position.y
	var h: float = maxf(0.0 - bottom, 0.3)
	var box := BoxMesh.new()
	box.size = Vector3(plate.x + 0.3, h, plate.y + 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _plinth_mat
	mi.position = Vector3(plate.x * 0.5, -h * 0.5, plate.y * 0.5)
	mi.name = "Plinth"
	host.add_child(mi)


# The plates Part V's own stage certifies houses at. The solver's
# accept map over (width, depth) is an archipelago, not a range —
# 12x9 accepts in 2 attempts for every seed probed, 13x12 in none
# of 5,000 — so the placer builds on the proven plates and lets
# the LOT be bigger than the house, which is what lots are.
const HOUSE_PLATES: Array[Vector2] = [Vector2(12.5, 10.0),
	Vector2(12.0, 9.0), Vector2(10.8, 10.0), Vector2(10.0, 8.0)]


func _build_house(host: Node3D, fp: Rect2, seed: int) -> bool:
	var fitting: Array[Vector2] = []
	for plate in HOUSE_PLATES:
		if fp.size.x >= plate.x and fp.size.y >= plate.y:
			fitting.append(plate)
	if fitting.is_empty():
		return false
	var plate: Vector2 = fitting[seed % fitting.size()]
	_last_plate = plate
	var program: HouseProgram = HouseProgram.build(
		plate.x, plate.y)
	var result: Dictionary = HouseSolver.solve(
		program.rooms, plate, seed, house_attempts)
	if result["plan"].is_empty():
		return false
	var plan: Dictionary = result["plan"]
	WindowPlacer.place_windows(plan)
	var house: Dictionary = {"footprint": Rect2(Vector2.ZERO, plate),
		"floors": [plan], "meta": {"building_use": "house"}}
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		seed, SeedBank.STREAM_BUILDINGS)
	var roof_group: Node3D = HouseBuilder.build(host, house, false, rng)
	RoofBuilder.build(roof_group,
		Rect2(Vector2.ZERO, plate), "gable")
	return true


func _build_apartment(host: Node3D, fp: Rect2, seed: int,
		world_centre: Vector2) -> bool:
	var cap: float = _zoning.height_cap_at(
		world_centre.x, world_centre.y, "apartment")
	var floors: int = clampi(int(cap / FLOOR_HEIGHT), 3,
		apartment_max_floors)
	# Part VI's default mix — SHARES summing to 1.0, family
	# included (Listing 40.2's counts were this file's misreading;
	# ApartmentProgram.mix_to_slots() prices shares).
	var mix: Dictionary = {"studio": 0.25, "one_bed": 0.35,
		"two_bed": 0.25, "family": 0.15}
	# Part VI's certified plate, exactly: 19.5 m square accepts in
	# one attempt at every probed seed; 26x24 surrenders after
	# 5,000. A parcel that cannot hold the plate steps down a use.
	if fp.size.x < 19.5 or fp.size.y < 19.5:
		return false
	var plate := Vector2(19.5, 19.5)
	_last_plate = plate
	var program: ApartmentProgram = ApartmentProgram.build(
		plate, floors, mix)
	var core: Dictionary = ApartmentProgram.core_for("point", plate)
	var result: Dictionary = BlockSolver.solve(program, core, seed,
		apartment_attempts)
	if result["block"].is_empty():
		return false
	var block: Dictionary = result["block"]
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		seed, SeedBank.STREAM_BUILDINGS)
	var roof_group: Node3D = HouseBuilder.build(host, block, false, rng)
	if build_facades:
		FacadeBuilder.build_facade(host, block)
	RoofBuilder.build(roof_group,
		Rect2(Vector2.ZERO, plate), "flat")
	return true


func _build_office(host: Node3D, fp: Rect2, seed: int,
		world_centre: Vector2) -> bool:
	var cap: float = _zoning.height_cap_at(
		world_centre.x, world_centre.y, "office")
	var floors: int = clampi(int(cap / FLOOR_HEIGHT), 4,
		office_max_floors)
	# Part VII's certified plate and load: 38x22 m, 50 seats per
	# typical floor (the default tower's own brief) accepts in one
	# attempt at floors 4-7 for every probed seed; 80 seats to a
	# floor surrenders after 5,000. Smaller office parcels step
	# down — the negotiation working as designed.
	if fp.size.x < 38.0 or fp.size.y < 22.0:
		return false
	var plate := Vector2(38.0, 22.0)
	_last_plate = plate
	var kinds: Array = ["lobby"]
	var seats: Array = [0]
	for i in range(floors - 1):
		kinds.append("typical")
		seats.append(50)
	var program: OfficeProgram = OfficeProgram.build(
		plate, kinds, seats)
	var core: Dictionary = OfficeProgram.core_for("point", plate)
	var result: Dictionary = OfficeSolver.solve(program, core, seed,
		office_attempts)
	if result["tower"].is_empty():
		return false
	var tower: Dictionary = result["tower"]
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		seed, SeedBank.STREAM_BUILDINGS)
	var roof_group: Node3D = HouseBuilder.build(host, tower, false, rng)
	var top_plan: Dictionary = tower["floors"][(tower["floors"] as Array).size() - 1]
	RoofBuilder.build(roof_group, top_plan["footprint"], "flat")
	return true
