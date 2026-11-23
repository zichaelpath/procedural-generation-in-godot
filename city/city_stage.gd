@tool
class_name CityStage
extends Node3D

## Part VIII's stage. Steps (fixed in Chapter 37, never renumbered):
##  0 probe      1 plain grid     2 warped + grown   3 ribbons+junctions
##  4 A* logic   5 highway built  6 blocks           7 parcels
##  8 zoning     9 placed city   10 V3 boroughs     11 Montreal
## Every step rebuilds from the master seed; nothing persists between
## steps except the terrain, which is the Part II contract object.
##
## Integration notes (project harness — the chapters' plain runtime
## script cannot be screenshotted by the book's tools, so this file
## carries the same glue as the terrain/houses stages):
## - @tool + rebuild() are the capture harness's interface
##   (tools/book_capture.gd sets step/seed, then calls rebuild();
##   the book_stage editor plugin does the same and forces step=2,
##   so ENGINE shots for other steps use tools/capture_engine2.sh's
##   directive file: _arrange_from_directive() applies the real step
##   after the plugin, re-selects the root (or the requested node),
##   frames the editor camera per step, and writes
##   /tmp/book_stage_arranged.txt.
## - rebuild() is memoised on (step, master_seed): the harness's
##   repeated rebuild calls do not re-run the city.
## - The terrain is rebuilt per step (the listings build it once in
##   _ready()): steps 4-5 need a river + ridge between the towns,
##   step 10 a 960 m island, step 11 the real 24 km Montreal grid.
##   Each step's terrain is still the one Part II contract object,
##   shared by every system in that step.
## - Camera poses are per step, in _position_camera_for_step():
##   "preset" frames the step's first listed render, "low" its
##   second (bridge / skyline / diagonal shots). Poses for steps 5
##   and 11 "low" are computed from the built bridge's midpoint.
## - Steps 4-5's terrain shaping (_shape_highway_terrain) carves a
##   meandering river band and raises a diagonal ridge between the
##   two towns BEFORE the network exists, then refresh_climate()
##   re-derives the biomes the router prices. The chapters assume
##   this geography (§38.1's field has a river and a slope band);
##   on the plain island field there is neither between the towns.

@export var step: int = 1:
	set(value):
		step = value
		if _built:
			rebuild()
@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if _built:
			rebuild()

var terrain: TerrainHeight
var network: RoadNetwork

var _built: bool = false
var _built_key: String = ""
var _bridge_focus: Vector3 = Vector3.ZERO
var _shore_route: Dictionary = {} # step 11: {route, fin} once routed
var _has_bridge_focus: bool = false
var _street_focus: Dictionary = {}

@onready var _terrain_host: Node3D = $TerrainHost
@onready var _roads_host: Node3D = $Roads
@onready var _blocks_host: Node3D = $Blocks
@onready var _buildings_host: Node3D = $Buildings
@onready var _camera: Camera3D = $CameraRig/Camera
@onready var _title: Label = $UI/TitleLabel
@onready var _flow: Label = $UI/FlowLabel
@onready var _cert: Label = $UI/CertLabel

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"


func _ready() -> void:
	_built = true
	rebuild()
	if Engine.is_editor_hint() and FileAccess.file_exists(DIRECTIVE_PATH):
		_arrange_from_directive()


func rebuild() -> void:
	if not _built or _terrain_host == null:
		return
	var key: String = "%d:%d" % [step, master_seed]
	if key == _built_key:
		return
	_built_key = key
	_has_bridge_focus = false
	_street_focus = {}
	regenerate()
	_position_camera_for_step("preset")
	if Engine.is_editor_hint():
		_own_generated()


## The capture harness calls this after rebuild(); it re-applies the
## current step's pose for the requested preset name.
func apply_camera_preset_by_name(preset_name: String) -> void:
	_position_camera_for_step(preset_name)


func regenerate() -> void:
	for host in [_terrain_host, _roads_host, _blocks_host, _buildings_host]:
		for child in host.get_children():
			host.remove_child(child)
			child.free()
	_setup_terrain_for_step(step)
	network = RoadNetwork.new(terrain)
	match step:
		0:
			_title.text = "Step 0 — terrain contract probe"
			_flow.text = "height_at / slope_at / biome_at_world — Part II contract"
			_cert.text = ""
			_probe()
		1:
			_title.text = "Step 1 — plain grid, dual representation"
			network.generate_grid(Rect2(-160, -160, 320, 320),
				52.0, 74.0, master_seed)
			_draw_logic_roads()
			_draw_roads()
			_report()
		2:
			_title.text = "Step 2 — warped grid + goal-grown roads"
			network.generate_grid(Rect2(-160, -160, 320, 320),
				52.0, 74.0, master_seed)
			network.warp_nodes(26.0, master_seed)
			network.generate_grown(Vector2(-150, 130),
				Vector2(150, -130), 9, master_seed)
			network.rebuild_segments()
			_draw_logic_roads()
			_draw_roads()
			_report()
		3:
			_title.text = "Step 3 — ribbons + junction index"
			network.generate_grid(Rect2(-160, -160, 320, 320),
				52.0, 74.0, master_seed)
			network.warp_nodes(26.0, master_seed)
			network.generate_grown(Vector2(-150, 130),
				Vector2(150, -130), 9, master_seed)
			network.rebuild_segments()
			_draw_logic_roads()
			_draw_roads()
			_draw_junction_furniture()
			_report_junctions()
		4:
			_title.text = "Step 4 — cost field + A* route (logic only)"
			_two_towns()
			var router := HighwayRouter.new(terrain)
			router.add_blocker(Rect2(-300, -60, 110, 120), 15.0)
			router.add_blocker(Rect2(190, -60, 110, 120), 15.0)
			var route: Dictionary = router.find_route(
				Vector2(-185, 0), Vector2(185, 0))
			_draw_logic_roads()
			_draw_roads()
			_draw_cost_field(router)
			if route.is_empty():
				_cert.text = "no route at any price"
				_flow.text = ""
			else:
				_draw_route_debug(route)
				_cert.text = "total=%.0f elevation=%.0f slope=%.0f water=%.0f" % [
					route["total"], route["terms"]["elevation"],
					route["terms"]["slope"], route["terms"]["water"]]
				_flow.text = "the DECISION, before geometry — step 5 builds it"
				print("route bill: total=%.0f elevation=%.0f slope=%.0f water=%.0f (slope_cells=%d water_cells=%d)" % [
					route["total"], route["terms"]["elevation"],
					route["terms"]["slope"], route["terms"]["water"],
					route["terms"]["slope_cells"],
					route["terms"]["water_cells"]])
		5:
			_title.text = "Step 5 — highway built, bridges finalised"
			_two_towns()
			var router2 := HighwayRouter.new(terrain)
			router2.add_blocker(Rect2(-300, -60, 110, 120), 15.0)
			router2.add_blocker(Rect2(190, -60, 110, 120), 15.0)
			var route2: Dictionary = router2.find_route(
				Vector2(-185, 0), Vector2(185, 0))
			if route2.is_empty():
				_cert.text = "no route at any price"
				_flow.text = ""
			else:
				var fin: Dictionary = router2.finalise(route2["points"])
				network.add_logic_road(route2["points"], "highway")
				network.rebuild_segments()
				_draw_logic_roads()
				_draw_roads()
				_draw_highway(route2, fin)
		6:
			_title.text = "Step 6 — blocks from the road graph"
			network.generate_grid(Rect2(-160, -160, 320, 320),
				52.0, 74.0, master_seed)
			network.rebuild_segments()
			_draw_roads()
			var bp := BlockParcels.new(network, terrain)
			var blocks: Array[Dictionary] = bp.extract_grid_blocks()
			_draw_blocks(blocks)
			var c: Dictionary = bp.census(blocks)
			_cert.text = "blocks=%d area min=%.0f med=%.0f max=%.0f nonrect=%d" % [
				c["count"], c["min"], c["median"], c["max"],
				c["non_rectangular"]]
			_flow.text = "the road reserve is carved off every block edge"
			print("block census: ", c)
		7:
			_title.text = "Step 7 — parcels + frontage"
			network.generate_grid(Rect2(-160, -160, 320, 320),
				52.0, 74.0, master_seed)
			network.rebuild_segments()
			_draw_roads()
			var bp2 := BlockParcels.new(network, terrain)
			var blocks2: Array[Dictionary] = bp2.extract_grid_blocks()
			var all_parcels: Array[Dictionary] = []
			for bi in range(blocks2.size()):
				if blocks2[bi]["kind"] == "land":
					all_parcels.append_array(
						bp2.subdivide_block(blocks2[bi], master_seed, bi))
			_draw_parcels(all_parcels)
			var fronting: int = 0
			for p in all_parcels:
				if bool(p["fronting"]):
					fronting += 1
			_cert.text = "parcels=%d fronting=%d interior=%d" % [
				all_parcels.size(), fronting,
				all_parcels.size() - fronting]
			_flow.text = "interior parcels are labelled, never buildable"
		8:
			_title.text = "Step 8 — zoning + placement decisions"
			var land: Dictionary = _land_pipeline()
			_draw_roads()
			_draw_zoned(land["parcels"])
			_cert.text = "decisions only — step 9 builds this exact map"
			_flow.text = "uses: office/apartment/house/green by field"
		9:
			_title.text = "Step 9 — the placed city"
			var land2: Dictionary = _land_pipeline()
			_draw_roads()
			var placer := CityPlacer.new(terrain, land2["zoning"],
				master_seed)
			_buildings_host.add_child(placer)
			var summary: Dictionary = placer.place_all(
				land2["parcels"])
			_street_focus = placer.street_focus
			_cert.text = "placed=%d ledger=%s" % [
				summary["placed"], str(summary["ledger"])]
			_flow.text = "the parcel sizes the building — surrenders step down"
			print("placement ledger: ", summary["ledger"])
		10:
			_title.text = "Step 10 — the V3 borough city"
			var city := BoroughCity.new(network, terrain, master_seed)
			city.generate()
			var bridges: Array[Dictionary] = city.apply_seams()
			city.add_diagonal_avenue()
			city.add_connectors()
			var reserve10: Dictionary = city.reserve_roads()
			var overlaps10: int = city.count_block_overlaps()
			network.rebuild_segments()
			print("step10 fix: connectors=", city.connector_routes.size(),
				" reserve=", reserve10, " overlaps=", overlaps10)
			_draw_borough_roads(city)
			_draw_seam_bridges(bridges)
			# The zoning field rescales with the territory —
			# Chapter 42's set_radii seam, applied here at 960 m:
			# Ch40's 120/260 m radii on this world would propose
			# offices on a handful of downtown parcels only.
			var zoning := Zoning.new(terrain, Vector2(0, 40),
				master_seed)
			zoning.set_radii(290.0, 620.0)
			var parcels10: Array[Dictionary] = []
			var bp10 := BlockParcels.new(network, terrain)
			for bi in range(city.borough_blocks.size()):
				parcels10.append_array(bp10.subdivide_block(
					city.borough_blocks[bi], master_seed, bi))
			var placed10: int = _place_by_borough(city, parcels10,
				zoning, 420, 250)
			var c10: Dictionary = bp10.census(city.borough_blocks)
			_cert.text = "blocks=%d nonrect=%d placed=%d overlaps=%d" % [
				c10["count"], c10["non_rectangular"], placed10,
				overlaps10]
			_flow.text = "five territories, five rotations — gaps stay green, connectors join"
			print("borough census: ", c10)
		11:
			_title.text = "Step 11 — Montreal, assembled"
			var assembler := MontrealAssembler.new()
			if not assembler.setup(
					"res://terrain/data/montreal_heightmap.png"):
				_cert.text = "LANDMARK TEST FAILED — no city built"
				_flow.text = ""
				return
			terrain = assembler.terrain
			_build_terrain_picture()
			network = RoadNetwork.new(terrain)
			var city11 := BoroughCity.new(network, terrain, master_seed)
			city11.set_borough_table(assembler.borough_table())
			city11.set_shore_test(func(p: Vector2) -> bool:
				return terrain.biome_at_world(p.x, p.y) != 0)
			city11.set_landmark_exclusion(assembler.hill_park())
			# The landmark exclusion is a seam-style land refusal:
			# apply it to the block list directly (Ch 42 has no
			# rect seams — the river is the terrain's own).
			city11.generate()
			_refuse_landmark_blocks(city11, assembler.hill_park())
			city11.add_connectors()
			var downtown: Vector2 = assembler.borough_table()[0]["centre"]
			_route_south_shore_highway(assembler, downtown)
			var reserve11: Dictionary = city11.reserve_roads()
			var overlaps11: int = city11.count_block_overlaps()
			network.rebuild_segments()
			print("step11 fix: connectors=", city11.connector_routes.size(),
				" reserve=", reserve11, " overlaps=", overlaps11)
			_draw_borough_roads(city11)
			var bp11 := BlockParcels.new(network, terrain)
			var parcels11: Array[Dictionary] = []
			for bi in range(city11.borough_blocks.size()):
				parcels11.append_array(bp11.subdivide_block(
					city11.borough_blocks[bi], master_seed, bi))
			var zoning11 := Zoning.new(terrain, downtown, master_seed)
			zoning11.set_radii(900.0, 2400.0) # real scale, §42.2
			var placed11: int = _place_by_borough(city11, parcels11,
				zoning11, 380, 250)
			_draw_south_shore_highway()
			var c11: Dictionary = bp11.census(city11.borough_blocks)
			_cert.text = "Montreal: blocks=%d placed=%d overlaps=%d" % [
				c11["count"], placed11, overlaps11]
			print("montreal census: ", c11)
			print("landmark (recheck): height=", snappedf(
				assembler.lookout_height, 0.1), " biome=",
				assembler.lookout_biome, " — verified before generation")
		_:
			_title.text = "Step %d — built in a later chapter" % step


# --- Terrain setups -----------------------------------------------------------

func _setup_terrain_for_step(p_step: int) -> void:
	match p_step:
		4, 5:
			terrain = _make_island(800.0, 128, 30.0)
			_shape_highway_terrain()
		10:
			terrain = _make_island(960.0, 160, 42.0)
		11:
			# Placeholder island; the step-11 arm replaces it with
			# the assembler's real terrain before anything is built.
			terrain = _make_island(400.0, 128, 30.0)
			return # the arm builds the real picture itself
		_:
			terrain = _make_island(400.0, 128, 30.0)
	_build_terrain_picture()


func _make_island(world_size: float, cells: int,
		height_scale: float) -> TerrainHeight:
	var config := WorldConfig.new()
	config.master_seed = master_seed
	config.sea_level = 5.0 # Part I's terrain value (Listing 5.1)
	config.terrain_world_size = world_size
	config.terrain_cells = cells
	config.terrain_height_scale = height_scale
	var t := TerrainHeight.new()
	t.erode_droplets = 0 # the stage gates erosion off (Ch 11's rule)
	t.thermal_iterations = 0
	t.generate(config)
	return t


# Steps 4-5 geography (see header note): a meandering river band on
# x ~= 0 running the world's full length, narrowest toward the south
# (half-width ~9 m near z = -140, ~16 m at the centre), and a
# diagonal ridge crossing the direct corridor east of the river, so
# the straight line is priced HIGH and the winner bends (§38.1).
func _shape_highway_terrain() -> void:
	var w: int = terrain.row_width()
	for iz in range(w):
		for ix in range(w):
			var wp: Vector2 = terrain.grid_to_world(ix, iz)
			var i: int = terrain.index(ix, iz)
			var river_cx: float = 18.0 * sin(wp.y * 0.011)
			var halfw: float = 12.5 + 3.5 * sin(wp.y * 0.02 + 1.3)
			var d_river: float = absf(wp.x - river_cx)
			if d_river < halfw + 7.0:
				var t: float = clampf(
					(halfw + 7.0 - d_river) / 7.0, 0.0, 1.0)
				var target: float = terrain.sea_level - 3.0
				terrain.heights[i] = lerpf(terrain.heights[i],
					target, smoothstep(0.0, 1.0, t))
			# The ridge: a raised band along the line through
			# (60, 10) with direction (0.6, 0.8), 52 m wide.
			var rel: Vector2 = wp - Vector2(60.0, 10.0)
			var along: float = rel.dot(Vector2(0.6, 0.8))
			var across: float = absf(rel.dot(Vector2(-0.8, 0.6)))
			if across < 24.0 and absf(along) < 95.0:
				var bump: float = cos(clampf(across / 24.0, 0.0, 1.0)
					* PI * 0.5)
				var ends: float = cos(clampf(along / 95.0, -1.0, 1.0)
					* PI * 0.5)
				# 19 m over a 24 m half-width: crest grade ~1.24,
				# slope_at ~0.37 — over the router's 0.22 limit, so
				# the band prices as violations (red in the wash),
				# not merely as elevation. At 15 m / 30 m it peaked
				# at ~0.21 and the "slope band" was a rumour.
				terrain.heights[i] += 19.0 * bump * ends
	terrain.refresh_climate()


func _build_terrain_picture() -> void:
	for child in _terrain_host.get_children():
		_terrain_host.remove_child(child)
		child.free()
	var builder := TerrainMesh.new()
	builder.use_biome_colors = true
	builder.name = "TerrainPicture"
	_terrain_host.add_child(builder)
	builder.rebuild(terrain)
	# The water surface: one translucent plane at sea level, so
	# rivers and the shoreline read as water in renders (the mesh
	# colours the ground UNDER it).
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain.world_size, terrain.world_size)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.32, 0.52, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.35
	water.material_override = mat
	water.position.y = terrain.sea_level
	water.name = "WaterPlane"
	_terrain_host.add_child(water)


# --- Chapter 37 helpers -------------------------------------------------------

func _probe() -> void:
	# The contract, exercised in the open: three questions, three
	# answers, printed — height, slope (1 - cos of the normal's tilt,
	# Part II's definition), biome. If these lie, nothing above them
	# can be trusted, so the stage's step 0 is the lie detector.
	var spots: Array[Vector2] = [Vector2(0, 0), Vector2(120, -80),
		Vector2(-140, 60)]
	for s in spots:
		print("probe ", s, " h=", snappedf(terrain.height_at(s.x, s.y), 0.01),
			" slope=", snappedf(terrain.slope_at(s.x, s.y), 0.001),
			" biome=", terrain.biome_at_world(s.x, s.y))


func _draw_roads() -> void:
	var builder := RoadBuilder.new()
	builder.name = "RoadBuilder"
	_roads_host.add_child(builder)
	builder.build_network(network, terrain)


func _draw_logic_roads() -> void:
	# The logic representation, drawn faint UNDER the segments:
	# full-length polylines running through every junction (§37.1).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for road in network.logic_roads:
		var pts: PackedVector3Array = road["points"]
		for i in range(pts.size() - 1):
			_draped_line(st, pts[i], pts[i + 1], 1.1, 0.16)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.82, 0.85)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.name = "LogicRoads"
	_roads_host.add_child(mi)


# A thin ribbon following the rendered facets (+lift): used for
# the logic overlay, whose legs run a whole street length between
# nodes — a single chord would dive under the terrain mid-block.
# At 0.16 it rides just above the draw segments (0.10), so the
# render shows both representations at once: full-length pale
# centrelines over clipped asphalt.
func _draped_line(st: SurfaceTool, a: Vector3, b: Vector3,
		width: float, lift: float) -> void:
	var dist: float = Vector2(b.x - a.x, b.z - a.z).length()
	var steps: int = clampi(int(ceil(dist / 3.0)), 1, 24)
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side: Vector3 = dir.cross(Vector3.UP) * (width * 0.5)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in range(steps + 1):
		var p: Vector3 = a.lerp(b, float(i) / float(steps))
		var l: Vector3 = p - side
		var r: Vector3 = p + side
		l.y = RoadBuilder.facet_height(terrain, l.x, l.z) + lift
		r.y = RoadBuilder.facet_height(terrain, r.x, r.z) + lift
		if i > 0:
			st.set_normal(Vector3.UP)
			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(prev_r)
			st.add_vertex(prev_r)
			st.add_vertex(l)
			st.add_vertex(r)
		prev_l = l
		prev_r = r


func _flat_quad(st: SurfaceTool, a: Vector3, b: Vector3,
		width: float, lift: float) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.01:
		return
	var side: Vector3 = flat.normalized().cross(Vector3.UP) \
		* (width * 0.5)
	st.set_normal(Vector3.UP)
	st.add_vertex(a - side + Vector3(0.0, lift, 0.0))
	st.add_vertex(b - side + Vector3(0.0, lift, 0.0))
	st.add_vertex(a + side + Vector3(0.0, lift, 0.0))
	st.add_vertex(a + side + Vector3(0.0, lift, 0.0))
	st.add_vertex(b - side + Vector3(0.0, lift, 0.0))
	st.add_vertex(b + side + Vector3(0.0, lift, 0.0))


func _draw_junction_furniture() -> void:
	# One dot per junction of degree >= 3, coloured by the mask's
	# verdict (§37.4): amber = T (a sign), red = crossroads (lights).
	var group := Node3D.new()
	group.name = "JunctionFurniture"
	_roads_host.add_child(group)
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.55, 0.55)
	var mat_t := StandardMaterial3D.new()
	mat_t.albedo_color = Color(0.95, 0.65, 0.15)
	var mat_x := StandardMaterial3D.new()
	mat_x.albedo_color = Color(0.9, 0.25, 0.2)
	for i in range(network.nodes.size()):
		var d: int = network.junction_degree(i)
		if d < 3:
			continue
		var dot := MeshInstance3D.new()
		dot.mesh = box
		dot.material_override = mat_x if d >= 4 else mat_t
		dot.position = network.nodes[i] + Vector3(0.0, 0.42, 0.0)
		dot.name = "Junction_%d" % i
		group.add_child(dot)


func _report() -> void:
	var msg: String = "nodes=%d logic=%d segments=%d" % [
		network.nodes.size(), network.logic_roads.size(),
		network.segments.size()]
	print(msg)
	_cert.text = msg


func _report_junctions() -> void:
	var counts: Dictionary = {2: 0, 3: 0, 4: 0}
	for i in range(network.nodes.size()):
		var d: int = network.junction_degree(i)
		if counts.has(d):
			counts[d] += 1
	var msg: String = "junctions: through/corner=%d T=%d cross=%d" % [
		counts[2], counts[3], counts[4]]
	print(msg)
	_cert.text = msg
	_flow.text = "mask per node — furniture & blocks read this index"


# --- Chapter 38 helpers -------------------------------------------------------

func _two_towns() -> void:
	# Two Chapter 37 grids, 370 m apart, sharing one network — the
	# highway's job is to make them one city system.
	network.generate_grid(Rect2(-300, -60, 110, 120), 30.0, 44.0,
		master_seed)
	network.merge_grid(Rect2(190, -60, 110, 120), 30.0, 44.0,
		master_seed)


func _draw_cost_field(router: HighwayRouter) -> void:
	# The priced landscape as a colour wash: green cheap, yellow
	# dearer, red = slope violation, blue = water (bridge debt),
	# near-black = blocker. Drawn from the router's own terms.
	var region := Rect2(-188, -150, 376, 300)
	var cell: float = HighwayRouter.CELL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ix: int = 0
	while float(ix) * cell < region.size.x:
		var iz: int = 0
		while float(iz) * cell < region.size.y:
			var cx: float = region.position.x + float(ix) * cell + cell * 0.5
			var cz: float = region.position.y + float(iz) * cell + cell * 0.5
			var terms: Dictionary = router.debug_terms(cx, cz)
			var col: Color
			if bool(terms["blocked"]):
				col = Color(0.07, 0.07, 0.08)
			elif bool(terms["water"]):
				col = Color(0.15, 0.35, 0.75)
			elif float(terms["slope"]) > HighwayRouter.SLOPE_LIMIT:
				col = Color(0.85, 0.25, 0.2)
			else:
				var t: float = clampf(float(terms["slope"])
					/ HighwayRouter.SLOPE_LIMIT, 0.0, 1.0)
				col = Color(0.35, 0.75, 0.35).lerp(
					Color(0.95, 0.85, 0.3), t)
			_cost_cell(st, cx, cz, cell, col)
			iz += 1
		ix += 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	mi.name = "CostFieldDebug"
	_roads_host.add_child(mi)


func _cost_cell(st: SurfaceTool, cx: float, cz: float, cell: float,
		col: Color) -> void:
	var h: float = cell * 0.5
	var corners: Array[Vector2] = [Vector2(-h, -h), Vector2(h, -h),
		Vector2(h, h), Vector2(-h, h)]
	var y: float = RoadBuilder.facet_height(terrain, cx, cz)
	for c in corners:
		y = maxf(y, RoadBuilder.facet_height(terrain, cx + c.x,
			cz + c.y))
	y += 0.12
	var vs: Array[Vector3] = []
	for c in corners:
		vs.append(Vector3(cx + c.x, y, cz + c.y))
	st.set_color(col)
	st.set_normal(Vector3.UP)
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.add_vertex(vs[idx])


func _draw_route_debug(route: Dictionary) -> void:
	# The winning polyline as a bright ribbon at logic level: step 4
	# shows the DECISION before step 5 spends geometry on it.
	# (Listing 38.3 draws a LINE_STRIP; a 2.5 m ribbon is the same
	# data, readable at render scale.)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: PackedVector3Array = route["points"]
	for i in range(pts.size() - 1):
		_flat_quad(st, pts[i], pts[i + 1], 2.5, 1.1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.98, 0.95)
	mat.roughness = 0.6
	mi.material_override = mat
	mi.name = "RouteDebug"
	_roads_host.add_child(mi)


func _draw_highway(route: Dictionary, fin: Dictionary) -> void:
	var builder := RoadBuilder.new()
	builder.name = "HighwayBuilder"
	_roads_host.add_child(builder)
	builder.build_highway(builder, route["points"], fin, terrain)
	var bridges: int = 0
	for span in fin["spans"]:
		if span["kind"] == "bridge":
			bridges += 1
			if not _has_bridge_focus:
				var pts: PackedVector3Array = route["points"]
				var mid: Vector3 = pts[int(span["from"])].lerp(
					pts[int(span["to"])], 0.5)
				mid.y = float(span["deck_y"])
				_bridge_focus = mid
				_has_bridge_focus = true
	_flow.text = "spans=%d bridges=%d — finalisation paid the water debt" % [
		fin["spans"].size(), bridges]
	_cert.text = "total=%.0f water_cells=%d bridges=%d" % [
		route["total"], route["terms"]["water_cells"], bridges]


# --- Chapter 39 helpers -------------------------------------------------------

func _draw_blocks(blocks: Array[Dictionary]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blocks:
		var poly: PackedVector2Array = b["polygon"]
		_fan_plate(st, poly, _plate_y(poly))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.42)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.name = "BlockDebug"
	_blocks_host.add_child(mi)


func _draw_parcels(parcels: Array[Dictionary]) -> void:
	# Two meshes: fronting parcels (warm) and interior (green) — the
	# colour split IS the data split Chapter 40 consumes.
	for want_fronting in [true, false]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in parcels:
			if bool(p["fronting"]) != want_fronting:
				continue
			var poly: PackedVector2Array = p["polygon"]
			_fan_plate(st, poly, _plate_y(poly))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.62, 0.3) if want_fronting \
			else Color(0.35, 0.6, 0.35)
		mat.roughness = 1.0
		mi.material_override = mat
		mi.name = "ParcelsFronting" if want_fronting else "ParcelsInterior"
		_blocks_host.add_child(mi)


func _poly_centre(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(poly.size())


# Debug overlays are drawn as flat PLATES at the polygon's highest
# facet + a margin: draping a 60 m block fan at its centre height
# lets the rendered terrain facets pierce it everywhere else (the
# mesh is planar facets; height_at is bilinear — see RoadBuilder.
# facet_height). A plate floats a few centimetres over the high
# corner and reads clean from the book's top-down cameras.
func _plate_y(poly: PackedVector2Array) -> float:
	# Max facet height over the polygon's INTERIOR (8 m sampling of
	# its bounding box), not just its corners: a 60 m block can hide
	# a whole hill between its corners, and the plate must clear it.
	var y: float = -1.0e9
	for p in poly:
		y = maxf(y, RoadBuilder.facet_height(terrain, p.x, p.y))
	var lo: Vector2 = poly[0]
	var hi: Vector2 = poly[0]
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var gx: float = lo.x
	while gx <= hi.x:
		var gz: float = lo.y
		while gz <= hi.y:
			if Geometry2D.is_point_in_polygon(Vector2(gx, gz), poly):
				y = maxf(y, RoadBuilder.facet_height(terrain, gx, gz))
			gz += 8.0
		gx += 8.0
	return y + 0.15


func _fan_plate(st: SurfaceTool, poly: PackedVector2Array,
		y: float) -> void:
	for i in range(1, poly.size() - 1):
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(poly[0].x, y, poly[0].y))
		st.add_vertex(Vector3(poly[i].x, y, poly[i].y))
		st.add_vertex(Vector3(poly[i + 1].x, y, poly[i + 1].y))


# --- Chapter 40 helpers -------------------------------------------------------

# The shared land pipeline for steps 8-9: roads -> blocks ->
# parcels -> zoning assignment. ONE function, so the audit (8) and
# the build (9) can never drift into two different cities.
func _land_pipeline() -> Dictionary:
	network.generate_grid(Rect2(-160, -160, 320, 320), 52.0, 74.0,
		master_seed)
	network.rebuild_segments()
	var bp := BlockParcels.new(network, terrain)
	var blocks: Array[Dictionary] = bp.extract_grid_blocks()
	var parcels: Array[Dictionary] = []
	for bi in range(blocks.size()):
		if blocks[bi]["kind"] == "land":
			parcels.append_array(bp.subdivide_block(
				blocks[bi], master_seed, bi))
	var zoning := Zoning.new(terrain, Vector2(0, 0), master_seed)
	for parcel in parcels:
		if bool(parcel["fronting"]):
			var c: Vector2 = BlockParcels._to_world(parcel["frame"],
				parcel["local_rect"].get_center())
			parcel["use"] = zoning.use_at(c.x, c.y)
	return {"parcels": parcels, "zoning": zoning, "blocks": blocks}


func _draw_zoned(parcels: Array[Dictionary]) -> void:
	var colours: Dictionary = {
		"office": Color(0.85, 0.35, 0.3),
		"apartment": Color(0.9, 0.65, 0.25),
		"house": Color(0.95, 0.85, 0.55),
		"green": Color(0.35, 0.6, 0.35), "": Color(0.5, 0.5, 0.5)}
	for use in colours.keys():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in parcels:
			var u: String = p["use"]
			if not bool(p["fronting"]):
				u = "green"
			if u != use:
				continue
			var poly: PackedVector2Array = p["polygon"]
			_fan_plate(st, poly, _plate_y(poly))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colours[use]
		mat.roughness = 1.0
		mi.material_override = mat
		mi.name = "ParcelsZoned_%s" % use
		_blocks_host.add_child(mi)


# --- Chapters 41-42 helpers ---------------------------------------------------

# Placement shared by steps 10-11: parcels grouped by borough via
# the block ranges, one placer per borough with its character as
# the use cap, one shared building budget (0 = uncapped... the
# budget here is the chapters' draft-assembly bargain, spent in
# borough-table order — downtown first).
# The street shot's subject, picked by SIGHT LINE: for each built
# house, pose the street camera and measure how far the terrain
# rises above the lens-to-house line. On this relief a swell
# between camera and subject eats the frame (two honest attempts
# proved it), so the winner is the house the camera can actually
# SEE — most neighbours first among the clear sight lines.
func _densest_focus(placer: CityPlacer) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = [1, -1.0e9]
	for cand in placer.built_centres:
		if String(cand["use"]) != "house":
			continue
		var c: Vector3 = cand["centre"]
		var perp: Vector2 = cand["perp"]
		var axis: Vector2 = cand["axis"]
		var cam: Vector3 = c - Vector3(perp.x, 0.0, perp.y) * 19.0 \
			+ Vector3(axis.x, 0.0, axis.y) * 9.0
		cam.y = terrain.height_at(cam.x, cam.z) + 2.6
		var look: Vector3 = c + Vector3(axis.x, 0.0, axis.y) * 4.0 \
			+ Vector3(0.0, 2.0, 0.0)
		var obstruction: float = -1.0e9
		for k in range(1, 12):
			var t: float = float(k) / 12.0
			var p: Vector3 = cam.lerp(look, t)
			obstruction = maxf(obstruction,
				terrain.height_at(p.x, p.z) - p.y)
		var neighbours: int = 0
		for other in placer.built_centres:
			var o: Vector3 = other["centre"]
			if Vector2(o.x - c.x, o.z - c.z).length() < 55.0:
				neighbours += 1
		# Clear beats clustered; clustered breaks clear ties.
		var key: Array = [1 if obstruction < 0.5 else 0,
			-obstruction if obstruction >= 0.5 else float(neighbours)]
		if key[0] > best_key[0] or (key[0] == best_key[0]
				and key[1] > best_key[1]):
			best_key = key
			best = cand
	if best.is_empty():
		return placer.street_focus
	return best


func _place_by_borough(city: BoroughCity, parcels: Array[Dictionary],
		zoning: Zoning, budget: int, attempts: int) -> int:
	var by_block: Dictionary = {}
	for parcel in parcels:
		var b: int = int(parcel["block"])
		if not by_block.has(b):
			by_block[b] = []
		by_block[b].append(parcel)
	# The budget is shared by PARCEL SHARE, not spent in table
	# order — otherwise downtown eats it all and the rim boroughs
	# stand empty in a shot that claims a whole city.
	var total_parcels: int = parcels.size()
	var total_placed: int = 0
	var ledgers: Dictionary = {}
	for range_i in range(city.block_ranges.size()):
		var rng_rec: Dictionary = city.block_ranges[range_i]
		var borough: Dictionary = _borough_named(city,
			String(rng_rec["name"]))
		var group: Array[Dictionary] = []
		for bi in range(int(rng_rec["first"]), int(rng_rec["last"]) + 1):
			if by_block.has(bi):
				group.append_array(by_block[bi])
		if group.is_empty():
			continue
		var placer := CityPlacer.new(terrain, zoning, master_seed)
		placer.use_cap = String(borough.get("character", ""))
		placer.house_attempts = attempts
		placer.apartment_attempts = attempts
		placer.office_attempts = attempts
		placer.build_facades = false # borough scale: massing reads
		if budget > 0 and total_parcels > 0:
			var quota: int = int(round(float(budget)
				* float(group.size()) / float(total_parcels)))
			placer.max_buildings = clampi(quota, 8, budget)
		placer.name = "Placer_%s" % String(rng_rec["name"])
		_buildings_host.add_child(placer)
		var summary: Dictionary = placer.place_all(group)
		total_placed += int(summary["placed"])
		ledgers[String(rng_rec["name"])] = summary["ledger"]
		if _street_focus.is_empty() and not placer.street_focus.is_empty():
			_street_focus = placer.street_focus
	print("borough placement ledgers: ", ledgers)
	return total_placed


func _borough_named(city: BoroughCity, bname: String) -> Dictionary:
	for borough in city.borough_table():
		if String(borough["name"]) == bname:
			return borough
	return {}


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


func _draw_borough_roads(city: BoroughCity) -> void:
	# One builder per borough (the ENGINE shot's tree reads the
	# recipe), drawing that borough's slice of the ONE globally
	# derived segment set; roads added after the boroughs (seam
	# crossings, the diagonal) get their own "Seams" builder.
	var covered: Dictionary = {}
	for range_rec in city.road_ranges:
		var filter: Array = []
		for ri in range(int(range_rec["first"]),
				int(range_rec["last"]) + 1):
			filter.append(ri)
			covered[ri] = true
		var builder := RoadBuilder.new()
		builder.name = "Borough_%s" % String(range_rec["name"])
		_roads_host.add_child(builder)
		builder.build_network(network, terrain, filter)
	var rest: Array = []
	for ri in range(network.logic_roads.size()):
		if not covered.has(ri):
			rest.append(ri)
	if not rest.is_empty():
		var seams := RoadBuilder.new()
		seams.name = "Seams"
		_roads_host.add_child(seams)
		seams.build_network(network, terrain, rest)


func _draw_seam_bridges(bridges: Array[Dictionary]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bridge in bridges:
		var a: Vector2 = bridge["from"]
		var b: Vector2 = bridge["to"]
		var deck_y: float = bridge["deck_y"]
		var side := Vector3(4.5, 0.0, 0.0)
		var a3 := Vector3(a.x, deck_y, a.y)
		var b3 := Vector3(b.x, deck_y, b.y)
		st.set_normal(Vector3.UP)
		st.add_vertex(a3 - side)
		st.add_vertex(b3 - side)
		st.add_vertex(a3 + side)
		st.add_vertex(a3 + side)
		st.add_vertex(b3 - side)
		st.add_vertex(b3 + side)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.32)
	mat.roughness = 0.9
	mi.material_override = mat
	mi.name = "SeamBridges"
	_roads_host.add_child(mi)


func _route_south_shore_highway(assembler: MontrealAssembler,
		downtown: Vector2) -> void:
	# Routing half of the old _south_shore_highway, split so the
	# stage can route BEFORE reserve_roads(): the highway is a
	# logic road like any other, and its reserve band is carved out
	# of the land in the same unified pass. Data only — the draw
	# half (_draw_south_shore_highway) runs after placement, where
	# the old combined call stood.
	_shore_route = {}
	var shore: Vector2 = assembler._latlon(45.4700, -73.4900)
	var router := HighwayRouter.new(terrain)
	var route: Dictionary = router.find_route(downtown + Vector2(900, 500),
		shore)
	if route.is_empty():
		print("south-shore route: none at any price")
		return
	var fin: Dictionary = router.finalise(route["points"])
	network.add_logic_road(route["points"], "highway")
	_shore_route = {"route": route, "fin": fin}
	print("south-shore bill: ", route["terms"])


func _draw_south_shore_highway() -> void:
	# Draw half: build the routed highway, pick the bridge focus,
	# and set the flow line — from the data _route_south_shore_
	# highway stored before the reserve pass.
	if _shore_route.is_empty():
		return
	var route: Dictionary = _shore_route["route"]
	var fin: Dictionary = _shore_route["fin"]
	var builder := RoadBuilder.new()
	builder.name = "SouthShoreHighway"
	_roads_host.add_child(builder)
	builder.build_highway(builder, route["points"], fin, terrain)
	for span in fin["spans"]:
		if span["kind"] == "bridge" and not _has_bridge_focus:
			var pts: PackedVector3Array = route["points"]
			var mid: Vector3 = pts[int(span["from"])].lerp(
				pts[int(span["to"])], 0.5)
			mid.y = float(span["deck_y"])
			_bridge_focus = mid
			_has_bridge_focus = true
	if not _has_bridge_focus:
		# On the shipped SRTM clip the winning route threads the
		# island chain (Sainte-Hélène / Notre-Dame / the Seaway
		# shore) without entering a single OCEAN cell — the cost
		# field crossed dry, so finalisation owes no bridge. The
		# camera focus falls back to the route's narrows: the
		# point with the most open water within 90 m.
		var pts2: PackedVector3Array = route["points"]
		var best_near: int = 2
		for i in range(pts2.size()):
			var near: int = 0
			for a in range(12):
				var ang: float = TAU * float(a) / 12.0
				var q: Vector2 = Vector2(pts2[i].x, pts2[i].z) \
					+ Vector2(cos(ang), sin(ang)) * 90.0
				if terrain.biome_at_world(q.x, q.y) == 0:
					near += 1
			if near > best_near:
				best_near = near
				_bridge_focus = pts2[i]
				_has_bridge_focus = true
	_flow.text = "highway spans=%d water_cells=%d — the island chain crossed dry" % [
		fin["spans"].size(), route["terms"]["water_cells"]]


# --- Camera poses ---------------------------------------------------------------

func _position_camera_for_step(preset_name: String) -> void:
	if _camera == null:
		return
	_camera.far = 60000.0 if step == 11 else 9000.0
	# City-scale shots sit 300-900 m out; at the default 0.05 near
	# plane the depth buffer cannot resolve a 0.1 m road lift at
	# that range and the ribbons z-fight into the terrain.
	_camera.near = 1.0
	var pos: Vector3
	var look: Vector3
	if preset_name == "low":
		match step:
			5:
				if _has_bridge_focus:
					pos = _bridge_focus + Vector3(-27.0, 8.0, 24.0)
					look = _bridge_focus
				else:
					pos = Vector3(-60.0, 16.0, 74.0)
					look = Vector3(10.0, 6.0, 0.0)
			9:
				pos = Vector3(-165.0, 92.0, 185.0)
				look = Vector3(0.0, 12.0, 0.0)
			10:
				pos = Vector3(-150.0, 95.0, 215.0)
				look = Vector3(30.0, 8.0, 30.0)
			11:
				if _has_bridge_focus:
					# Low on the highway at its river narrows,
					# looking back NW: water beside the road,
					# the downtown skyline behind it.
					pos = _bridge_focus + Vector3(150.0, 30.0, 125.0)
					look = _bridge_focus + Vector3(0.0, 4.0, 0.0)
				else:
					pos = Vector3(5200.0, 1500.0, 3400.0)
					look = Vector3(3000.0, 100.0, 1500.0)
			_:
				pos = Vector3(0.0, 40.0, 58.0)
				look = Vector3.ZERO
	else:
		match step:
			0:
				pos = Vector3(150.0, 120.0, 195.0)
				look = Vector3(0.0, 8.0, 0.0)
			1, 6, 8:
				pos = Vector3(0.0, 345.0, 26.0)
				look = Vector3.ZERO
			2:
				pos = Vector3(-125.0, 100.0, 155.0)
				look = Vector3(0.0, 5.0, 0.0)
			3:
				pos = Vector3(-125.0, 100.0, 155.0)
				look = Vector3(0.0, 5.0, 0.0)
			4:
				pos = Vector3(0.0, 445.0, 30.0)
				look = Vector3.ZERO
			5:
				pos = Vector3(-165.0, 46.0, 122.0)
				look = Vector3(60.0, 4.0, 5.0)
			7:
				pos = Vector3(-108.0, 82.0, 130.0)
				look = Vector3(0.0, 4.0, 0.0)
			9:
				if not _street_focus.is_empty():
					var c: Vector3 = _street_focus["centre"]
					var perp: Vector2 = _street_focus["perp"]
					var axis: Vector2 = _street_focus["axis"]
					# On the street in front of the house, eye
					# height sampled from the ground under the
					# camera — a fixed offset from the parcel's
					# height strands the lens inside a swell.
					# Kerbside in front of the flattest house:
					# eye height sampled from the ground under
					# the camera, subject centred. (Two fancier
					# framings — densest cluster, sight-line
					# optimisation — both lost to this island's
					# swells; the simple pose is the one that
					# reads as a street.)
					pos = c - Vector3(perp.x, 0.0, perp.y) * 16.0 \
						+ Vector3(axis.x, 0.0, axis.y) * 10.0
					pos.y = terrain.height_at(pos.x, pos.z) + 1.8
					look = c + Vector3(0.0, 2.2, 0.0)
				else:
					pos = Vector3(-95.0, 30.0, 105.0)
					look = Vector3(10.0, 6.0, 0.0)
			10:
				pos = Vector3(0.0, 730.0, 30.0)
				look = Vector3(0.0, 0.0, 10.0)
			11:
				pos = Vector3(7600.0, 4800.0, 7600.0)
				look = Vector3(1200.0, 0.0, 800.0)
			_:
				pos = Vector3(0.0, 40.0, 58.0)
				look = Vector3.ZERO
	_camera.position = pos
	if pos.distance_squared_to(look) > 0.001:
		_camera.look_at(look, Vector3.UP)


# --- Editor arrangement for ENGINE captures ------------------------------------
# tools/capture_engine2.sh writes a directive file before launching
# the editor; after the shared book_stage plugin has done its own
# arrangement (step=2, root selected), this applies the shot's real
# step / selection and writes the arranged file the wrapper polls
# for. No directive file = no arrangement (normal use).

func _arrange_from_directive() -> void:
	await get_tree().create_timer(6.0).timeout
	var txt: String = FileAccess.get_file_as_string(DIRECTIVE_PATH)
	var want_step: int = step
	var want_select: String = ""
	for line in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
	step = want_step # setter rebuilds at the requested step
	var node: Node = self
	if want_select != "" and want_select != "root":
		var found: Node = find_child(want_select, true, false)
		if found != null:
			node = found
	EditorInterface.set_main_screen_editor("3D")
	_frame_editor_camera()
	_expand_scene_tree()
	_open_output_panel()
	# Selection goes LAST and twice: expanding the tree / switching
	# screens can drop it to the root (the terrain stage's lesson).
	_select_in_editor(node)
	await get_tree().create_timer(1.0).timeout
	_select_in_editor(node)
	var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("arranged step=%d select=%s\n" % [step, want_select])
		f.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)


func _frame_editor_camera() -> void:
	# Frame the editor's own 3D camera on the step's subject, at the
	# render pose pulled back a little (the editor viewport shares
	# its panel with the docks, so it sees less of the frame).
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var pos: Vector3
	var look: Vector3
	match step:
		0:
			pos = Vector3(170.0, 135.0, 220.0)
			look = Vector3(0.0, 8.0, 0.0)
		1, 6, 7, 8:
			pos = Vector3(0.0, 330.0, 60.0)
			look = Vector3.ZERO
		4:
			pos = Vector3(0.0, 430.0, 70.0)
			look = Vector3.ZERO
		10:
			pos = Vector3(0.0, 700.0, 80.0)
			look = Vector3(0.0, 0.0, 10.0)
		11:
			# Downtown + Mount Royal fill the editor frame (the whole
			# 24 km island cannot, at editor far planes).
			pos = Vector3(3950.0, 1250.0, 2350.0)
			look = Vector3(1900.0, 120.0, 500.0)
		_:
			pos = Vector3(0.0, 175.0, 305.0)
			look = Vector3.ZERO
	cam.near = 1.0 # depth precision at city range (see rebuild)
	var t := Transform3D.IDENTITY.translated(pos)
	t = t.looking_at(look, Vector3.UP)
	cam.global_transform = t


func _select_in_editor(node: Node) -> void:
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


func _open_output_panel() -> void:
	# Press the editor's "Output" bottom-panel button (there is no
	# public API for the built-in panels; the button is findable).
	# The bottom-panel buttons are toggles: set_pressed shows the
	# panel; a bare "pressed" emit does not latch it.
	# Part II's exact semantics: scan the WHOLE base control, keep
	# the LAST "Output" button (the first match in DFS order is a
	# different, hidden one), then latch it if it toggles, else
	# fire it. A diagnostic file proves the code path ran.
	var target: Button = null
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			if (n as Button).text == "Output":
				target = n as Button
		for ch in n.get_children():
			stack.append(ch)
	# Note: in the 4.7 editor the bottom-panel tab strip is not
	# reachable as Buttons from the base control (a full scan finds
	# ~970 Buttons, none labelled "Output"), so this latch is best
	# effort — the delivered engine shots across the book show the
	# panel's tab bar, with the prints in the Output log itself.
	if target != null:
		if target.toggle_mode:
			target.set_pressed(true)
		else:
			target.emit_signal("pressed")


func _own_generated() -> void:
	# Generated children get the edited scene as owner in the editor
	# ONLY (so the Scene dock shows them in ENGINE shots); runtime
	# builds never set owner, per the project rule that generated
	# nodes are never baked into the .tscn on save.
	var edited_root: Node = get_tree().edited_scene_root
	if edited_root == null or edited_root != self:
		return
	_own_recursive(self, edited_root)


func _own_recursive(node: Node, edited_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = edited_root
		_own_recursive(child, edited_root)


func _expand_scene_tree() -> void:
	# Best effort: expand the Scene dock tree so the authored tree
	# (and the built hosts' children) is visible in the shot.
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var trees: Array[Tree] = []
	_collect_trees(base, trees)
	for t in trees:
		var root_item: TreeItem = t.get_root()
		if root_item != null and root_item.get_text(0) == name:
			_expand_item(root_item)


func _collect_trees(node: Node, out: Array[Tree]) -> void:
	if node is Tree:
		out.append(node as Tree)
	for child in node.get_children():
		_collect_trees(child, out)


func _expand_item(item: TreeItem) -> void:
	item.set_collapsed(false)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_expand_item(child)
		child = child.get_next()
