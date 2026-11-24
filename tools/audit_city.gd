extends Node3D

## Audit harness for the Part VIII city (stage steps 10 and 11).
## Replicates city_stage.gd's step orchestration using the real
## generator classes (BoroughCity, BlockParcels, Zoning, CityPlacer),
## then measures what the chapters never counted:
##   - block <-> block polygon overlaps, split by same/cross borough
##   - block intrusion into a neighbouring borough's territory
##     (territory = nearest-centre partition of the city area)
##   - building <-> building overlaps, from the placed buildings'
##     own plinth footprints (ground truth of what stands)
##   - building <-> road overlaps (drawn asphalt widths per kind)
##   - road-graph reachability between boroughs
## Run: godot --headless --path . res://tools/audit_city.tscn -- step=10
## Output: AUDIT_JSON block on stdout + /tmp/audit_step<N>.json

const SEED: int = 20261119
const EPS_AREA: float = 0.05 # m^2 — below this, contact is a survey artefact

var _step: int = 10
var _terrain: TerrainHeight
var _network: RoadNetwork
var _boroughs: Array = []
var _blocks: Array[Dictionary] = []
var _footprints: Array[Dictionary] = []
var _placers: Array[CityPlacer] = []
var _placed_total: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("step="):
			_step = int(arg.trim_prefix("step="))
	print("audit: building step ", _step, " ...")
	if _step == 11:
		_build_step11()
	else:
		_build_step10()
	print("audit: build done, measuring ...")
	var report: Dictionary = _audit()
	report["placed_total"] = _placed_total
	var text: String = JSON.stringify(report, "  ")
	print("AUDIT_JSON_BEGIN")
	print(text)
	print("AUDIT_JSON_END")
	var f := FileAccess.open("/tmp/audit_step%d.json" % _step,
		FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	get_tree().quit()


# --- Step pipelines (city_stage.gd's arms, data side only) -------------------

func _make_island(world_size: float, cells: int,
		height_scale: float) -> TerrainHeight:
	var config := WorldConfig.new()
	config.master_seed = SEED
	config.sea_level = 5.0 # Part I's terrain value (Listing 5.1)
	config.terrain_world_size = world_size
	config.terrain_cells = cells
	config.terrain_height_scale = height_scale
	var t := TerrainHeight.new()
	t.erode_droplets = 0
	t.thermal_iterations = 0
	t.generate(config)
	return t


func _build_step10() -> void:
	_terrain = _make_island(960.0, 160, 42.0)
	_network = RoadNetwork.new(_terrain)
	var city := BoroughCity.new(_network, _terrain, SEED)
	city.generate()
	city.apply_seams()
	city.add_diagonal_avenue()
	city.add_connectors()
	city.reserve_roads()
	TerrainGrader.grade_city(_terrain, _network, city.borough_table())
	_network.rebuild_segments()
	_boroughs = city.borough_table()
	_blocks = city.borough_blocks
	var zoning := Zoning.new(_terrain, Vector2(0, 40), SEED)
	zoning.set_radii(290.0, 620.0)
	var bp := BlockParcels.new(_network, _terrain)
	var parcels: Array[Dictionary] = []
	for bi in range(city.borough_blocks.size()):
		parcels.append_array(bp.subdivide_block(
			city.borough_blocks[bi], SEED, bi))
	_placed_total = _place_by_borough(city, parcels, zoning, 420, 250)


func _build_step11() -> void:
	var assembler := MontrealAssembler.new()
	if not assembler.setup("res://terrain/data/montreal_heightmap.png"):
		push_error("audit: Montreal setup failed")
		return
	_terrain = assembler.terrain
	_network = RoadNetwork.new(_terrain)
	var city := BoroughCity.new(_network, _terrain, SEED)
	city.set_borough_table(assembler.borough_table())
	city.set_shore_test(func(p: Vector2) -> bool:
		return _terrain.biome_at_world(p.x, p.y) != 0)
	city.set_landmark_exclusion(assembler.hill_park())
	city.generate()
	_refuse_landmark_blocks(city, assembler.hill_park())
	city.add_connectors()
	# The south-shore highway is routed BEFORE placement (the
	# stage's new order), so its reserve band is carved by
	# reserve_roads() like every other road's. Logic road only —
	# the audit measures data, it draws nothing.
	var downtown: Vector2 = assembler.borough_table()[0]["centre"]
	var shore: Vector2 = assembler._latlon(45.4700, -73.4900)
	var router := HighwayRouter.new(_terrain)
	var route: Dictionary = router.find_route(
		downtown + Vector2(900, 500), shore)
	if not route.is_empty():
		_network.add_logic_road(route["points"], "highway")
	city.reserve_roads()
	TerrainGrader.grade_city(_terrain, _network, city.borough_table())
	_network.rebuild_segments()
	_boroughs = city.borough_table()
	_blocks = city.borough_blocks
	var bp := BlockParcels.new(_network, _terrain)
	var parcels: Array[Dictionary] = []
	for bi in range(city.borough_blocks.size()):
		parcels.append_array(bp.subdivide_block(
			city.borough_blocks[bi], SEED, bi))
	var zoning := Zoning.new(_terrain, downtown, SEED)
	zoning.set_radii(900.0, 2400.0)
	_placed_total = _place_by_borough(city, parcels, zoning, 380, 250)


# --- Stage helpers, replicated (city_stage.gd) --------------------------------

func _borough_named(city: BoroughCity, bname: String) -> Dictionary:
	for borough in city.borough_table():
		if String(borough["name"]) == bname:
			return borough
	return {}


func _place_by_borough(city: BoroughCity, parcels: Array[Dictionary],
		zoning: Zoning, budget: int, attempts: int) -> int:
	var by_block: Dictionary = {}
	for parcel in parcels:
		var b: int = int(parcel["block"])
		if not by_block.has(b):
			by_block[b] = []
		by_block[b].append(parcel)
	var total_parcels: int = parcels.size()
	var total_placed: int = 0
	for range_i in range(city.block_ranges.size()):
		var rng_rec: Dictionary = city.block_ranges[range_i]
		var borough: Dictionary = _borough_named(city,
			String(rng_rec["name"]))
		var group: Array[Dictionary] = []
		for bi in range(int(rng_rec["first"]),
				int(rng_rec["last"]) + 1):
			if by_block.has(bi):
				group.append_array(by_block[bi])
		if group.is_empty():
			continue
		var placer := CityPlacer.new(_terrain, zoning, SEED)
		placer.use_cap = String(borough.get("character", ""))
		placer.house_attempts = attempts
		placer.apartment_attempts = attempts
		placer.office_attempts = attempts
		placer.build_facades = false
		if budget > 0 and total_parcels > 0:
			var quota: int = int(round(float(budget)
				* float(group.size()) / float(total_parcels)))
			placer.max_buildings = clampi(quota, 8, budget)
		placer.name = "Placer_%s" % String(rng_rec["name"])
		add_child(placer)
		_placers.append(placer)
		var summary: Dictionary = placer.place_all(group)
		total_placed += int(summary["placed"])
		print("audit placement ", rng_rec["name"], ": ", summary)
	return total_placed


func _refuse_landmark_blocks(city: BoroughCity,
		exclusion: Dictionary) -> void:
	var centre: Vector2 = exclusion["centre"]
	var radius: float = float(exclusion["radius"])
	var kept: Array[Dictionary] = []
	for block in city.borough_blocks:
		if (block["centre"] as Vector2).distance_to(centre) < radius:
			continue
		kept.append(block)
	city.borough_blocks = kept
	city._rebuild_block_ranges()


# --- Geometry helpers -----------------------------------------------------------

func _aabb(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for pt in p:
		r = r.expand(pt)
	return r


func _intersect_area(a: PackedVector2Array,
		b: PackedVector2Array) -> float:
	var total: float = 0.0
	for piece in Geometry2D.intersect_polygons(a, b):
		total += BlockParcels._polygon_area(piece)
	return total


func _nearest(centres: Array, point: Vector2) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(centres.size()):
		var d: float = point.distance_squared_to(centres[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _voronoi_cell(centre: Vector2, centres: Array,
		bounds: Rect2) -> PackedVector2Array:
	# NOTE: built on intersect_polygons only. In this Godot 4.7.2,
	# clip_polygons/exclude_polygons return their inputs as separate
	# pieces (verified empirically, /tmp/geo_test3-4.gd); intersect
	# and merge behave as documented.
	var cell := PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y)])
	var big: float = bounds.size.length() * 2.0
	for other in centres:
		if other == centre:
			continue
		var mid: Vector2 = (centre + other) * 0.5
		var dir: Vector2 = (other - centre).normalized()
		var perp := Vector2(-dir.y, dir.x)
		# The half-plane of points nearer `centre` than `other`, as
		# a big rectangle straddling the bisector.
		var half := PackedVector2Array([
			mid + perp * big - dir * big,
			mid - perp * big - dir * big,
			mid - perp * big + dir * 1.0,
			mid + perp * big + dir * 1.0])
		var clipped: Array = Geometry2D.intersect_polygons(cell, half)
		if clipped.is_empty():
			return PackedVector2Array()
		var best_piece: PackedVector2Array = clipped[0]
		var best_area: float = -1.0
		for piece in clipped:
			var a: float = BlockParcels._polygon_area(piece)
			if a > best_area:
				best_area = a
				best_piece = piece
		cell = best_piece
	return cell


func _collect_footprints() -> void:
	_footprints.clear()
	for placer in _placers:
		for host in placer.get_children():
			if not (host is Node3D):
				continue
			var plinth := host.get_node_or_null("Plinth") \
				as MeshInstance3D
			if plinth == null:
				continue
			var box := plinth.mesh as BoxMesh
			if box == null:
				continue
			var plate := Vector2(box.size.x - 0.3, box.size.z - 0.3)
			var t: Transform3D = (host as Node3D).global_transform
			var poly := PackedVector2Array()
			for c in [Vector2.ZERO, Vector2(plate.x, 0.0), plate,
					Vector2(0.0, plate.y)]:
				var w: Vector3 = t * Vector3(c.x, 0.0, c.y)
				poly.append(Vector2(w.x, w.z))
			_footprints.append({"poly": poly, "name": host.name})


func _road_polygons() -> Array:
	var polys: Array = []
	for seg in _network.segments:
		var kind: String = String(
			_network.logic_roads[int(seg["road"])]["kind"])
		var half: float = 5.5 if kind == "avenue" \
			or kind == "highway" else 3.5
		var a3: Vector3 = _network.nodes[int(seg["a"])]
		var b3: Vector3 = _network.nodes[int(seg["b"])]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var d: Vector2 = b - a
		if d.length() < 0.01:
			continue
		var perp: Vector2 = Vector2(-d.y, d.x).normalized() * half
		polys.append(PackedVector2Array(
			[a + perp, b + perp, b - perp, a - perp]))
	return polys


# --- The audit ------------------------------------------------------------------

func _audit() -> Dictionary:
	_collect_footprints()
	var rep: Dictionary = {}
	rep["step"] = _step
	var per_borough: Dictionary = {}
	for b in _blocks:
		var n: String = String(b["borough"])
		per_borough[n] = int(per_borough.get(n, 0)) + 1
	rep["blocks_total"] = _blocks.size()
	rep["blocks_per_borough"] = per_borough

	# Block <-> block overlaps.
	var block_aabbs: Array[Rect2] = []
	for b in _blocks:
		block_aabbs.append(_aabb(b["polygon"]))
	var cross_pairs: int = 0
	var cross_area: float = 0.0
	var same_pairs: int = 0
	var same_area: float = 0.0
	var cross_by_pair: Dictionary = {}
	for i in range(_blocks.size()):
		for j in range(i + 1, _blocks.size()):
			if not block_aabbs[i].intersects(block_aabbs[j]):
				continue
			var area: float = _intersect_area(
				_blocks[i]["polygon"], _blocks[j]["polygon"])
			if area <= EPS_AREA:
				continue
			if String(_blocks[i]["borough"]) \
					== String(_blocks[j]["borough"]):
				same_pairs += 1
				same_area += area
			else:
				cross_pairs += 1
				cross_area += area
				var key: String = "%s|%s" % [
					String(_blocks[i]["borough"]),
					String(_blocks[j]["borough"])]
				var rec: Dictionary = cross_by_pair.get(
					key, {"pairs": 0, "area": 0.0})
				rec["pairs"] = int(rec["pairs"]) + 1
				rec["area"] = float(rec["area"]) + area
				cross_by_pair[key] = rec
	rep["block_overlap_pairs_cross_borough"] = cross_pairs
	rep["block_overlap_area_cross_m2"] = snappedf(cross_area, 0.1)
	rep["block_overlap_pairs_same_borough"] = same_pairs
	rep["block_overlap_area_same_m2"] = snappedf(same_area, 0.1)
	for k in cross_by_pair.keys():
		cross_by_pair[k]["area"] = snappedf(
			float(cross_by_pair[k]["area"]), 0.1)
	rep["block_overlap_cross_by_pair"] = cross_by_pair

	# Exact-duplicate blocks (same vertex set, any order): the
	# signature of the broken diagonal clip stamping copies.
	var seen: Dictionary = {}
	var dupes: int = 0
	for b in _blocks:
		var keys: Array = []
		for p in b["polygon"]:
			keys.append("%d,%d" % [roundi(p.x * 10.0),
				roundi(p.y * 10.0)])
		keys.sort()
		var sig: String = ",".join(keys)
		if seen.has(sig):
			dupes += 1
		seen[sig] = true
	rep["duplicate_blocks"] = dupes

	# Territory intrusion vs the nearest-centre partition.
	var centres: Array = []
	var names: Array = []
	for b in _boroughs:
		centres.append(b["centre"])
		names.append(String(b["name"]))
	var bounds: Rect2 = block_aabbs[0]
	for r in block_aabbs:
		bounds = bounds.merge(r)
	bounds = bounds.grow(60.0)
	var cells: Array = []
	var cell_area_sum: float = 0.0
	for i in range(centres.size()):
		var cell: PackedVector2Array = _voronoi_cell(
			centres[i], centres, bounds)
		cells.append(cell)
		cell_area_sum += BlockParcels._polygon_area(cell)
		if not Geometry2D.is_point_in_polygon(centres[i], cell):
			rep["voronoi_warning"] = "centre outside its own cell"
	rep["voronoi_cell_area_sum"] = snappedf(cell_area_sum, 0.1)
	rep["voronoi_bounds_area"] = snappedf(bounds.get_area(), 0.1)
	var intrusion_blocks: int = 0
	var intrusion_area: float = 0.0
	var intrusion_pairs: Dictionary = {}
	for b in _blocks:
		# The owner is the block's BOROUGH, not whichever cell its
		# centre happens to fall in — a block whose centre crossed
		# the bisector is still foreign land everywhere it lies
		# outside its own borough's cell.
		var owner: int = names.find(String(b["borough"]))
		var bad: float = 0.0
		for i in range(centres.size()):
			if i == owner:
				continue
			var area: float = _intersect_area(b["polygon"], cells[i])
			if area > 0.5:
				bad += area
				var key: String = "%s>%s" % [names[owner], names[i]]
				intrusion_pairs[key] = float(
					intrusion_pairs.get(key, 0.0)) + area
		if bad > 0.5:
			intrusion_blocks += 1
			intrusion_area += bad
	rep["territory_intrusion_blocks"] = intrusion_blocks
	rep["territory_intrusion_area_m2"] = snappedf(intrusion_area, 0.1)
	var pairs_snapped: Dictionary = {}
	for k in intrusion_pairs.keys():
		pairs_snapped[k] = snappedf(float(intrusion_pairs[k]), 0.1)
	rep["territory_intrusion_by_pair"] = pairs_snapped

	# Building <-> building overlaps (placed footprints).
	rep["buildings_placed"] = _footprints.size()
	var fp_aabbs: Array[Rect2] = []
	for fp in _footprints:
		fp_aabbs.append(_aabb(fp["poly"]))
	var bb_pairs: int = 0
	var bb_area: float = 0.0
	var bb_involved: Dictionary = {}
	for i in range(_footprints.size()):
		for j in range(i + 1, _footprints.size()):
			if not fp_aabbs[i].intersects(fp_aabbs[j]):
				continue
			var area: float = _intersect_area(
				_footprints[i]["poly"], _footprints[j]["poly"])
			if area <= EPS_AREA:
				continue
			bb_pairs += 1
			bb_area += area
			bb_involved[i] = true
			bb_involved[j] = true
	rep["building_overlap_pairs"] = bb_pairs
	rep["building_overlap_area_m2"] = snappedf(bb_area, 0.1)
	rep["buildings_in_building_overlaps"] = bb_involved.size()

	# Building <-> road overlaps (drawn asphalt).
	var roads: Array = _road_polygons()
	rep["road_segments"] = roads.size()
	var road_aabbs: Array[Rect2] = []
	for rp in roads:
		road_aabbs.append(_aabb(rp))
	var br_pairs: int = 0
	var br_area: float = 0.0
	var br_involved: Dictionary = {}
	for i in range(_footprints.size()):
		for j in range(roads.size()):
			if not fp_aabbs[i].intersects(road_aabbs[j]):
				continue
			var area: float = _intersect_area(
				_footprints[i]["poly"], roads[j])
			if area <= EPS_AREA:
				continue
			br_pairs += 1
			br_area += area
			br_involved[i] = true
	rep["building_road_overlap_pairs"] = br_pairs
	rep["building_road_overlap_area_m2"] = snappedf(br_area, 0.1)
	rep["buildings_on_roads"] = br_involved.size()

	# Reachability over the segment graph.
	rep["reachability"] = _reachability(centres, names)
	return rep


func _reachability(centres: Array, names: Array) -> Dictionary:
	var adj: Dictionary = {}
	for seg in _network.segments:
		var a: int = int(seg["a"])
		var b: int = int(seg["b"])
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	var comp: Dictionary = {}
	var ncomp: int = 0
	for n in adj.keys():
		if comp.has(n):
			continue
		ncomp += 1
		var stack: Array = [n]
		comp[n] = ncomp
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			for nb in adj[cur]:
				if not comp.has(nb):
					comp[nb] = ncomp
					stack.append(nb)
	var counts: Dictionary = {}
	for n in comp.keys():
		counts[comp[n]] = int(counts.get(comp[n], 0)) + 1
	var main_comp: int = -1
	var main_size: int = -1
	for c in counts.keys():
		if int(counts[c]) > main_size:
			main_size = int(counts[c])
			main_comp = c
	var result: Dictionary = {"components": ncomp, "boroughs": {}}
	var all_ok: bool = true
	for bi in range(centres.size()):
		var total: int = 0
		var inmain: int = 0
		for n in adj.keys():
			var p: Vector3 = _network.nodes[n]
			if _nearest(centres, Vector2(p.x, p.z)) == bi:
				total += 1
				if comp[n] == main_comp:
					inmain += 1
		result["boroughs"][names[bi]] = {
			"nodes": total, "in_main_component": inmain}
		if total == 0 or inmain < total:
			all_ok = false
	result["all_boroughs_connected"] = all_ok
	return result
