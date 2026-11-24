extends Node3D

## Clearance harness for the Part VIII city (stage steps 10 and 11).
## Replicates city_stage.gd's step orchestration exactly as
## tools/audit_city.gd does (same build path, minus placement —
## placement cannot move a road or a height), then measures the
## terrain-vs-ribbon clearance the chapters never counted:
## for every DRAW segment of the built network, sample the
## centreline every ~2 m; at each sample evaluate the ribbon as
## ONE planar quad over the whole segment (corners = segment end
## nodes offset +/- side * half_width, corner heights =
## terrain.height_at at the corner XZ — the model of RoadBuilder
## in the brief: ends + midpoint sampling cannot follow a swell
## between its samples) and compare the terrain at the centre and
## at both ribbon edges against that plane. A sample "pokes" when
## terrain - ribbon > 0.05 m at any of the three offsets.
## Run: godot --headless --path . res://tools/audit_clearance.tscn -- step=10
## Output: CLEARANCE_JSON block on stdout + /tmp/clearance_step<N>.json
## The build mirrors the CURRENT stage order — when city_stage.gd
## gains terrain grading in arms 10/11, this replica gains the
## same TerrainGrader call in the same position (after
## reserve_roads(), before rebuild_segments()).

const SEED: int = 20261119
const POKE_EPS: float = 0.05 # m — above this the terrain is through the asphalt
const SAMPLE_STEP: float = 2.0 # m along the centreline

var _step: int = 10
var _terrain: TerrainHeight
var _network: RoadNetwork
var _build_ms: int = 0
var _grading_stats: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("step="):
			_step = int(arg.trim_prefix("step="))
	print("clearance: building step ", _step, " ...")
	var t0: int = Time.get_ticks_msec()
	if _step == 11:
		_build_step11()
	else:
		_build_step10()
	_build_ms = Time.get_ticks_msec() - t0
	print("clearance: build done in ", _build_ms, " ms, measuring ...")
	var report: Dictionary = _measure()
	report["step"] = _step
	report["build_ms"] = _build_ms
	report["grading"] = _grading_stats
	var text: String = JSON.stringify(report, "  ")
	print("CLEARANCE_JSON_BEGIN")
	print(text)
	print("CLEARANCE_JSON_END")
	var f := FileAccess.open("/tmp/clearance_step%d.json" % _step,
		FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	get_tree().quit()


# --- Step pipelines (audit_city.gd's replicas, data side only) ---------------

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
	_grading_stats = TerrainGrader.grade_city(
		_terrain, _network, city.borough_table())
	_network.rebuild_segments()


func _build_step11() -> void:
	var assembler := MontrealAssembler.new()
	if not assembler.setup("res://terrain/data/montreal_heightmap.png"):
		push_error("clearance: Montreal setup failed")
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
	var downtown: Vector2 = assembler.borough_table()[0]["centre"]
	var shore: Vector2 = assembler._latlon(45.4700, -73.4900)
	var router := HighwayRouter.new(_terrain)
	var route: Dictionary = router.find_route(
		downtown + Vector2(900, 500), shore)
	if not route.is_empty():
		_network.add_logic_road(route["points"], "highway")
	city.reserve_roads()
	_grading_stats = TerrainGrader.grade_city(
		_terrain, _network, city.borough_table())
	_network.rebuild_segments()


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


# --- The clearance measurement -------------------------------------------------

static func ribbon_half_width(kind: String) -> float:
	# The drawn widths: RoadBuilder.STREET_WIDTH / AVENUE_WIDTH for
	# streets and avenues; the highway spans are built 9.0 m wide
	# (RoadBuilder._quad_at_grade via build_highway).
	match kind:
		"avenue":
			return RoadBuilder.AVENUE_WIDTH * 0.5
		"highway":
			return 4.5
		_:
			return RoadBuilder.STREET_WIDTH * 0.5


## Measure one built network against its terrain. Static so the
## capstone harness (audit_capstone_clearance.gd) runs the identical
## measurement on the world builder's network.
static func measure(network: RoadNetwork,
		terrain: TerrainHeight) -> Dictionary:
	var total: int = 0
	var pokes: int = 0
	var pokes_near_junction: int = 0
	var pokes_midsegment: int = 0
	var max_poke: float = 0.0
	var worst: Dictionary = {}
	for seg in network.segments:
		var road_i: int = int(seg["road"])
		var kind: String = String(network.logic_roads[road_i]["kind"])
		var half: float = ribbon_half_width(kind)
		var a3: Vector3 = network.nodes[int(seg["a"])]
		var b3: Vector3 = network.nodes[int(seg["b"])]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var d: Vector2 = b - a
		var len: float = d.length()
		if len < 0.01:
			continue
		var side: Vector2 = Vector2(-d.y, d.x) / len * half
		# The ribbon quad's four corners and their sampled heights.
		var c_al: Vector2 = a + side
		var c_ar: Vector2 = a - side
		var c_bl: Vector2 = b + side
		var c_br: Vector2 = b - side
		var h_al: float = terrain.height_at(c_al.x, c_al.y)
		var h_ar: float = terrain.height_at(c_ar.x, c_ar.y)
		var h_bl: float = terrain.height_at(c_bl.x, c_bl.y)
		var h_br: float = terrain.height_at(c_br.x, c_br.y)
		var steps: int = maxi(1, int(ceil(len / SAMPLE_STEP)))
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var centre: Vector2 = a.lerp(b, t)
			for off in [-1.0, 0.0, 1.0]:
				var p: Vector2 = centre + side * off
				var u: float = (off + 1.0) * 0.5
				var ribbon_h: float = lerpf(
					lerpf(h_al, h_bl, t), lerpf(h_ar, h_br, t), u)
				var excess: float = terrain.height_at(p.x, p.y) \
					- ribbon_h
				total += 1
				if excess > max_poke:
					max_poke = excess
					worst = {"segment": seg, "road": road_i,
						"kind": kind, "t": snappedf(t, 0.01),
						"offset": off,
						"at": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)],
						"excess_m": snappedf(excess, 0.001)}
				if excess > POKE_EPS:
					pokes += 1
					# Junction bucket: the sample's centre lies
					# within 10 m of either segment end node —
					# where crossing corridors' profiles meet.
					if centre.distance_to(a) <= 10.0 \
							or centre.distance_to(b) <= 10.0:
						pokes_near_junction += 1
					else:
						pokes_midsegment += 1
	return {
		"samples": total,
		"poke_samples": pokes,
		"poke_pct": snappedf(100.0 * float(pokes) / float(maxi(total, 1)), 0.001),
		"max_poke_m": snappedf(max_poke, 0.001),
		"poke_near_junction": pokes_near_junction,
		"poke_midsegment": pokes_midsegment,
		"worst": worst,
		"segments": network.segments.size(),
	}


func _measure() -> Dictionary:
	return measure(_network, _terrain)
