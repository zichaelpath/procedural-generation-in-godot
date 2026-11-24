@tool
class_name WorldBuilder
extends Node3D

## The capstone orchestrator. It owns NO randomness: every stage
## draws from its named SeedBank stream or a manifest stored pair.
## It owns the ORDER, the hosts, and the reports. Stages consume the
## published products of earlier stages and nothing beneath them —
## the module contract of every part, at world scale.
##
## Integration adaptations vs Listing 43.4 as printed (call sites
## only — no generator forked; see Part IX build report):
##  * Ch 15's scatter fusion lives in ChunkManager's streaming path;
##    build_fixed_grid() does not run it. Step 2 therefore runs the
##    same published fusion (ChunkScatter.fill_chunk + build_holder,
##    neighbour points from the manager's own helper) per chunk.
##  * The city is generated the way Ch 41's stage generates it:
##    generate() + apply_seams() + add_diagonal_avenue() +
##    add_connectors() + reserve_roads(), then one global
##    rebuild_segments().
##  * RoadBuilder as built is a Node3D drawn into itself:
##    build_network(network, terrain), not build(network, host).
##  * Draw segments as built are {"a","b","road"} node indices
##    (Ch 37), not {"from","to"} pairs; _segment_ends() reads both.
##  * BlockParcels.subdivide_block() as built takes a block index.
##  * Zoning as built is constructed (terrain, centre, seed) —
##    centre = downtown's centre, as Ch 41's stage passes it.
##  * @tool (not in the printed listing): without it the editor
##    replaces this scene node with a placeholder instance and the
##    stage cannot call generate_all() for Ch 43/44's in-editor
##    Output shots (the Return Test and profiler run in the editor).
##  * Buildings placement uses Part VIII's own stage-10 assembly
##    (per-borough placers, character caps, attempts 900, facades
##    off, budget 420 by parcel share): a single default placer
##    ran the stage past 11 minutes unfinished (measured).

var config: WorldConfig
var terrain: TerrainHeight
var manifest: WorldManifest
var stage_times: Dictionary = {} # stage name -> milliseconds (Ch 44)
## Ch 44 garnish knob, set by the stage from WorldQuality's tier:
## 1.0 = every rolled scatter entry stands; lower thins the STAND
## (never the rolls — the chunk's stored pair and its full scatter
## list are the seed's content; how many trees the holder stands
## is presentation, §44.4's test).
var scatter_density_scale: float = 1.0


## Build a chunk's scatter holder, thinning the stood entries to
## the tier's density when the tier asks. The thinning roll comes
## from the chunk's own stored pair ("scatter_thin"), so the same
## subset stands on every regeneration; data.scatter itself is
## restored untouched before returning.
func _build_holder_thinned(data: ChunkData) -> Node:
	if scatter_density_scale >= 0.999 or data.scatter.is_empty():
		return ChunkScatter.build_holder(data, config)
	var rng: RandomNumberGenerator = data.stream_from_stored("scatter_thin")
	var full: Array[Dictionary] = data.scatter
	var kept: Array[Dictionary] = []
	for entry: Dictionary in full:
		if rng.randf() < scatter_density_scale:
			kept.append(entry)
	data.scatter = kept
	var holder: Node = ChunkScatter.build_holder(data, config)
	data.scatter = full
	return holder

var network: RoadNetwork
var parcels: Array[Dictionary] = []
var placement_ledger: Dictionary = {}
var entrances: Array[Dictionary] = []
var dungeon_proofs: Array[String] = []

@onready var root: Node3D = $WorldRoot
@onready var chunk_manager: ChunkManager = get_parent().get_node("ChunkManager") as ChunkManager


func generate_all(max_step: int, p_config: WorldConfig) -> void:
	config = p_config
	_clear_world()
	manifest = WorldManifest.new(config.master_seed)
	print("=== WorldBuilder: master seed ", config.master_seed, " ===")
	print("[tree] world root pair (", manifest.root_seed_a, ", ",
		manifest.root_seed_b, ") — full tree: diagrams/d-world-seed-tree.png")
	print("[tree] stream registry: world (root pair) · terrain/ (chunk pairs) · water (no stream: a level) · plants/scatter · roads · city/ (borough grids) · parcel/ · zoning · buildings · houses · dressing · dungeon/ (entrance pairs)")
	if max_step >= 1:
		_stage_terrain_water()
	if max_step >= 2:
		_stage_chunks_plants()
	if max_step >= 3:
		_stage_roads()
	if max_step >= 4:
		_stage_parcels_zoning()
	if max_step >= 5:
		_stage_buildings()
	if max_step >= 6:
		_stage_entrances()


func _clear_world() -> void:
	parcels.clear()
	entrances.clear()
	dungeon_proofs.clear()
	placement_ledger.clear()
	stage_times.clear()
	for host_name: String in ["Terrain", "Water", "Plants", "Roads", "Buildings", "Entrances"]:
		var host: Node3D = root.get_node(host_name) as Node3D
		for child: Node in host.get_children():
			child.queue_free()
	if chunk_manager != null:
		for coord: Variant in chunk_manager.chunks.keys():
			(chunk_manager.chunks[coord] as Node).queue_free()
		chunk_manager.chunks.clear()
		chunk_manager.data_cache.clear()


func _stage_terrain_water() -> void:
	var t0: int = Time.get_ticks_msec()
	terrain = TerrainHeight.new()
	terrain.use_noise_field(config)
	terrain.clear_city_edits()
	var water := MeshInstance3D.new()
	water.name = "WaterPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(config.chunk_size_m * 40.0, config.chunk_size_m * 40.0)
	water.mesh = plane
	water.position = Vector3(0.0, terrain.sea_level, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.32, 0.52, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	water.material_override = mat
	(root.get_node("Water") as Node3D).add_child(water)
	stage_times["terrain_water"] = Time.get_ticks_msec() - t0
	print("[stage] terrain+water: noise field live, sea level ",
		snappedf(terrain.sea_level, 0.1), " (", stage_times["terrain_water"], " ms)")


func _stage_chunks_plants() -> void:
	var t0: int = Time.get_ticks_msec()
	chunk_manager.setup(terrain, config)
	chunk_manager.build_fixed_grid()
	# Ch 15's fusion, run for the fixed grid exactly as the
	# manager's streaming path runs it (fill data, then holder).
	for coord: Variant in chunk_manager.chunks.keys():
		var data: ChunkData = chunk_manager.data_cache[coord]
		if data.scatter.is_empty():
			ChunkScatter.fill_chunk(data, config, chunk_manager._neighbour_scatter_points(coord))
		var chunk: TerrainChunk = chunk_manager.chunks[coord] as TerrainChunk
		var old_holder: Node = chunk.get_node_or_null(ChunkScatter.HOLDER_NAME)
		if old_holder != null:
			chunk.remove_child(old_holder)
			old_holder.free()
		chunk.add_child(_build_holder_thinned(data))
	# Record every built chunk's OWN stored pair (Ch 13) — read back,
	# never re-rolled (§43.2's honesty rule).
	var scatter_total: int = 0
	for coord: Variant in chunk_manager.data_cache.keys():
		var data: ChunkData = chunk_manager.data_cache[coord]
		scatter_total += data.scatter.size()
		manifest.record_fact(
			"terrain/%d,%d" % [data.coord.x, data.coord.y], "chunk", "world",
			data.stored_seed_a, data.stored_seed_b,
			"ChunkData stored pair (Ch 13)")
	stage_times["chunks_plants"] = Time.get_ticks_msec() - t0
	print("[stage] chunks+plants: ", chunk_manager.chunks.size(),
		" chunks built, ", scatter_total, " scatter entries (Ch 15 hook) (",
		stage_times["chunks_plants"], " ms)")


## The Ch 41 city sequence, in one place so the roads stage and the
## parcels stage can never grow different cities — the canonical
## sequence: generate -> seams -> diagonal -> connectors ->
## reserve. (Generation itself now clips blocks and streets to each
## borough's shrunk territory; connectors join the territories;
## reserve_roads() carves every road's reserve band out of the
## land.) Segments are re-derived by the caller, once, globally
## (Ch 37's rule).
func _make_city(net: RoadNetwork) -> BoroughCity:
	var city := BoroughCity.new(net, terrain, config.master_seed)
	city.generate()
	city.apply_seams()
	city.add_diagonal_avenue()
	city.add_connectors()
	city.reserve_roads()
	return city


func _stage_roads() -> void:
	var t0: int = Time.get_ticks_msec()
	network = RoadNetwork.new(terrain)
	var city := _make_city(network)
	network.rebuild_segments()
	# Terraces register BEFORE the ribbons are drawn: RoadBuilder
	# drapes facet_height(), which on this function-backed field is
	# height_at() itself — edits included — so the asphalt lies on
	# the terraced surface the chunks are about to rebuild to.
	_register_road_edits()
	var roads_host: Node3D = root.get_node("Roads") as Node3D
	var builder := RoadBuilder.new()
	roads_host.add_child(builder)
	builder.build_network(network, terrain)
	for borough: Dictionary in BoroughCity.BOROUGHS:
		manifest.record_fact(
			"city/" + str(borough["name"]), "borough", "world",
			config.master_seed + str(borough["name"]).hash(), 0,
			"Ch 41 grid seed derivation: master + name hash")
	_rebuild_edited_chunks()
	stage_times["roads"] = Time.get_ticks_msec() - t0
	print("[stage] roads: ", network.logic_roads.size(), " logic roads, ",
		network.segments.size(), " draw segments, ",
		terrain.city_edit_count(), " terrain edits registered (",
		stage_times["roads"], " ms)")


## A draw segment's world-space ends, from whichever representation
## the network published (Ch 37's node indices, or from/to pairs).
func _segment_ends(segment: Dictionary) -> Array[Vector2]:
	if segment.has("from") and segment.has("to"):
		return [segment["from"] as Vector2, segment["to"] as Vector2]
	var na: Vector3 = network.nodes[int(segment["a"])]
	var nb: Vector3 = network.nodes[int(segment["b"])]
	return [Vector2(na.x, na.z), Vector2(nb.x, nb.z)]


## The city answers the terrain back (§43.3): terrace every draw
## segment, capturing endpoint heights from the PRE-EDIT surface
## first — a segment's surveyed heights must not include its own
## edit, or the terrace chases its own tail uphill.
func _register_road_edits() -> void:
	for segment: Dictionary in network.segments:
		var ends: Array[Vector2] = _segment_ends(segment)
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var ha: float = terrain._base_height_at(a.x, a.y)
		var hb: float = terrain._base_height_at(b.x, b.y)
		# Terrace width follows the ribbon it carries (fix round
		# 2): the flat band must cover the whole ribbon plus a 2 m
		# margin, or the ribbon's own edge rides the blend slope
		# and the unedited ground pokes through it — avenues are
		# 11 m wide, so the old one-width 5.5 m terrace left their
		# edges unflattened. Streets: 3.5 + 2 = 5.5 (unchanged);
		# avenues: 5.5 + 2 = 7.5. Blend stays 6.0 m.
		var kind: String = String(
			network.logic_roads[int(segment["road"])]["kind"])
		var half: float = TerrainGrader.ribbon_half_width(kind) + 2.0
		terrain.terrace_road_segment(a, b, half, ha, hb, 6.0)


func _rebuild_edited_chunks() -> void:
	var bounds: Rect2 = terrain.city_edit_bounds()
	var rebuilt: int = 0
	for coord: Variant in chunk_manager.chunks.keys():
		var c: Vector2i = coord
		var origin: Vector2 = chunk_manager.chunk_to_world_origin(c)
		var chunk_rect := Rect2(origin, Vector2(config.chunk_size_m, config.chunk_size_m))
		if not bounds.intersects(chunk_rect):
			continue
		chunk_manager.data_cache.erase(c)
		var data: ChunkData = chunk_manager.get_or_generate_data(c)
		var chunk: TerrainChunk = chunk_manager.chunks[c] as TerrainChunk
		chunk.build_from_data(data, config, chunk_manager.terrain_material)
		# The rebuilt chunk's scatter was filled from pre-edit grids;
		# refill it from the fresh data so trees stand on the new
		# ground (Ch 15 fusion, same published calls as step 2).
		ChunkScatter.fill_chunk(data, config, chunk_manager._neighbour_scatter_points(c))
		var old_holder: Node = chunk.get_node_or_null(ChunkScatter.HOLDER_NAME)
		if old_holder != null:
			chunk.remove_child(old_holder)
			old_holder.free()
		chunk.add_child(_build_holder_thinned(data))
		rebuilt += 1
	print("[stage] roads: rebuilt ", rebuilt, " edited chunks (of ",
		chunk_manager.chunks.size(), ")")


func _stage_parcels_zoning() -> void:
	var t0: int = Time.get_ticks_msec()
	parcels.clear()
	# BoroughCity.generate() already ran (roads stage) against the
	# SHARED network. Its blocks are the subdivision input, exactly
	# as CityStage feeds them (Ch 41–42) — but generate() APPENDS
	# logic roads to whatever network the instance holds, so the
	# block list is rebuilt here against a THROWAWAY network: same
	# seed, same scratch grids, identical blocks, and the shared
	# network is never touched twice.
	var scratch_network := RoadNetwork.new(terrain)
	var city := _make_city(scratch_network)
	for bi: int in range(city.borough_blocks.size()):
		var block: Dictionary = city.borough_blocks[bi]
		var bp := BlockParcels.new(scratch_network, terrain)
		var lots: Array[Dictionary] = bp.subdivide_block(block, config.master_seed, bi)
		for lot: Dictionary in lots:
			lot["borough"] = block.get("borough", "")
			parcels.append(lot)
	# Flatten each fronting parcel's plot BEFORE buildings stand on
	# it: the parcel's frame (Ch 39) supplies centre, size, and yaw;
	# the target is the pre-edit height at its centre.
	for parcel: Dictionary in parcels:
		if not bool(parcel.get("fronting", false)):
			continue
		var frame: Dictionary = parcel["frame"]
		var centre_local: Vector2 = (parcel["local_rect"] as Rect2).get_center()
		var centre: Vector2 = BlockParcels._to_world(frame, centre_local)
		var size: Vector2 = (parcel["local_rect"] as Rect2).size
		var yaw: float = -atan2(frame["axis"].y, frame["axis"].x)
		terrain.flatten_plot(centre, size * 0.5, yaw,
			terrain._base_height_at(centre.x, centre.y), 6.0)
		manifest.record_fact(
			"parcel/%d_%d" % [int(parcel.get("block", 0)), parcels.find(parcel)],
			"parcel", "city/" + str(parcel.get("borough", "")),
			config.master_seed + int(parcel.get("block", 0)) * 1000 + int(centre_local.x), 0,
			"Ch 40 parcel seed derivation, recorded")
	_rebuild_edited_chunks()
	stage_times["parcels_zoning"] = Time.get_ticks_msec() - t0
	print("[stage] parcels+zoning: ", parcels.size(), " parcels, ",
		terrain.city_edit_count(), " total terrain edits (",
		stage_times["parcels_zoning"], " ms)")


func _stage_buildings() -> void:
	var t0: int = Time.get_ticks_msec()
	var zoning := Zoning.new(terrain, Vector2(0.0, 40.0), config.master_seed)
	# Placement follows Part VIII's own stage-10 assembly
	# (city_stage.gd _place_by_borough): one placer per borough with
	# the borough's character as use cap, facades off ("borough
	# scale: massing reads"), and a budget of 420 shared by parcel
	# share. A single placer at the class defaults (attempts
	# 1500/1200/1200, facades on) ran this stage past 11 minutes
	# without finishing (measured 2026-11-19) — the chapters' own
	# assembly bargain is the faithful reading of §43.5's
	# "buildings (Part VIII assembly)".
	var scratch_network := RoadNetwork.new(terrain)
	var city := _make_city(scratch_network)
	var groups: Dictionary = {}
	for parcel: Dictionary in parcels:
		var bname: String = str(parcel.get("borough", ""))
		if not groups.has(bname):
			groups[bname] = []
		groups[bname].append(parcel)
	var total_placed: int = 0
	var total_skipped: int = 0
	placement_ledger = {}
	for entry: Variant in city.borough_table():
		var borough: Dictionary = entry
		var bname: String = str(borough["name"])
		if not groups.has(bname):
			continue
		var group: Array[Dictionary] = []
		group.append_array(groups[bname])
		if group.is_empty():
			continue
		var placer := CityPlacer.new(terrain, zoning, config.master_seed)
		placer.use_cap = str(borough.get("character", ""))
		# Attempt/floor budgets: measured 2026-11-19, the Parts V–VII
		# solvers accept NOTHING at placer footprints (0/148 parcels
		# at attempts 300 — see Part IX report), so budgets only set
		# how long the surrender ladder takes. 60 attempts keeps a
		# full generation near six minutes; floor caps trim the
		# per-attempt cost of the two heavy solvers.
		placer.house_attempts = 60
		placer.apartment_attempts = 60
		placer.office_attempts = 60
		placer.office_max_floors = 6
		placer.apartment_max_floors = 4
		placer.build_facades = false
		if not parcels.is_empty():
			var quota: int = int(round(420.0 * float(group.size()) / float(parcels.size())))
			placer.max_buildings = clampi(quota, 8, 420)
		placer.name = "Placer_%s" % bname
		(root.get_node("Buildings") as Node3D).add_child(placer)
		var bt0: int = Time.get_ticks_msec()
		print("[stage] buildings: placing ", bname, " (", group.size(), " parcels, cap ", placer.max_buildings, ")…")
		var result: Dictionary = placer.place_all(group)
		print("[stage] buildings: ", bname, " placed ", int(result.get("placed", 0)), " (", Time.get_ticks_msec() - bt0, " ms)")
		total_placed += int(result.get("placed", 0))
		total_skipped += int(result.get("skipped_cap", 0))
		var led: Dictionary = result.get("ledger", {})
		for use: String in led.keys():
			var e: Dictionary = led[use]
			if not placement_ledger.has(use):
				placement_ledger[use] = {"placed": 0, "surrendered": 0}
			placement_ledger[use]["placed"] = int(placement_ledger[use]["placed"]) + int(e.get("placed", 0))
			placement_ledger[use]["surrendered"] = int(placement_ledger[use]["surrendered"]) + int(e.get("surrendered", 0))
	stage_times["buildings"] = Time.get_ticks_msec() - t0
	print("[stage] buildings: ", total_placed, " placed, ledger ",
		placement_ledger, ", skipped_cap ", total_skipped, " (", stage_times["buildings"], " ms)")
	# Name every placed building's spot — at city scale the placed
	# set is small enough to list, and Ch 44's cameras need a real
	# address to stand on.
	for placer_node: Node in (root.get_node("Buildings") as Node3D).get_children():
		for host_node: Node in placer_node.get_children():
			if host_node is Node3D and host_node.name.begins_with("Parcel_"):
				var hp: Vector3 = (host_node as Node3D).position
				print("[stage] buildings: placed ", host_node.name, " at (", snappedf(hp.x, 0.1), ", ", snappedf(hp.z, 0.1), ")")


func _stage_entrances() -> void:
	var t0: int = Time.get_ticks_msec()
	var placer := DungeonEntrances.new()
	entrances = placer.place_entrances(
		parcels, terrain, manifest, root.get_node("Entrances") as Node3D, config)
	dungeon_proofs = placer.proofs
	stage_times["entrances"] = Time.get_ticks_msec() - t0
	print("[stage] entrances: ", entrances.size(), " minted, proofs ",
		dungeon_proofs, " (", stage_times["entrances"], " ms)")
