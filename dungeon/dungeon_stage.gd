@tool
class_name DungeonStage
extends Node2D
## Part IV's stage. One scene, twenty fixed steps (see the chapter):
## each step shows one claim about dungeons, and later chapters add
## their steps to THIS file without renumbering anything.
##
## Steps: 0 = hand-drawn tour (line / loop / hub, keys 1/2/3),
## 1 = ASCII fixture round-trip, 2 = BSP partition, 3 = BSP rooms
## (unconnected), 4 = full BSP dungeon, 5 = BSP + room-graph overlay,
## 6 = cellular cave (raw), 7 = cellular cave (cleaned to one region),
## 8 = drunkard tunnels, 9 = hybrid (BSP rooms, cave guts),
## 10 = room graph + spanning growth, 11 = mission roles,
## 12 = lock & key + solver verdict, 13 = backbone verified + loops
## added back, priced, 14 = doors as edges (locked / secret /
## one-way), 15 = WFC toy 6x6 (Space steps the collapse),
## 16 = WFC dungeon 24x24, 17 = geomorph assembly,
## 18 = dressed + populated dungeon, 19 = minimap + validation
## report (part finale).
##
## Integration notes (project harness, same pattern as the terrain
## and plants stages — the chapters' plain runtime script cannot be
## screenshotted by the book's tools):
## - @tool + rebuild() are the capture harness's interface
##   (tools/book_capture.gd sets step/seed, then calls rebuild();
##   the book_stage editor plugin does the same). The step/master_seed
##   setters rebuild live once the stage is built.
## - Editor ENGINE captures use tools/capture_engine2.sh's directive
##   file (the shared plugin always arranges step=2 first); the stage
##   applies the directive's real step afterwards and writes
##   /tmp/book_stage_arranged.txt, and selects the 2D main screen —
##   this is a Node2D stage, so the plugin's 3D default would show
##   an empty viewport.
## - show_graph defaults to true: the Ch 23/24 RENDER captions
##   require the graph overlay ON (steps 12 and 13); G still toggles.
## - tour_index defaults to 2 (the Hub): the Ch 20 RENDER caption is
##   the Hub; keys 1/2/3 still switch the tour exactly as listed.
## - The Overlay draws manifest markers at steps 16/18/19 (pillars,
##   dressing, spawns) because the Ch 25 captions require them in
##   frame; the stage turns the overlay's markers_only mode on there.
## - dungeon_builder.gd, dungeon_overlay.gd and minimap.gd are
##   @tool: non-tool scripts on scene nodes are placeholder
##   instances in the editor, so the stage could not call render()
##   / show_data() / set_dungeon() on them and the ENGINE shots
##   would show an empty viewport (the Ch 5 stage note's lesson,
##   one node deeper). The arrange step also expands the Output
##   panel — Part IV's ENGINE captions require its receipt lines
##   in frame, and the default layout starts collapsed.
## - The arrange step prefers a private directive file
##   (/tmp/p4_stage_directive.txt) over the shared one: with four
##   workers capturing at once, the shared directive, arranged
##   file and editor log are all racy (a foreign step=9 and a
##   plants-stage frame both landed in dungeon shots through
##   them). The Output panel is expanded by a simulated click on
##   its tab — Godot 4.7's EditorBottomPanel draws its own tabs;
##   no "Output" Button exists in the control tree.
## - Extra receipt prints serve the ENGINE captions verbatim: step 4
##   prints passable tiles, step 10 also prints the graph stats line,
##   step 12 prints a COMPLETABLE — order line, step 19 prints the
##   region report and the pipeline receipt. No listing print was
##   removed or altered.

@export var step: int = 0:
	set(value):
		step = value
		if _built:
			rebuild()
@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if _built:
			rebuild()
@export var tour_index: int = 2

const TILE_SIZE: int = 28

# '#' wall, '.' floor, 'D' door, 'E' entrance, 'B' boss, 'T' treasure
const MAPS: Array = [
	{
		"name": "1 — The Line",
		"flow": "Critical path: the whole map. Loops: 0. Dead ends: 0 — treasure would have to sit ON the path. Chokepoint: every door, identically.",
		"rows": [
			"#############",
			"#E..D..D..B#",
			"#############",
		],
	},
	{
		"name": "2 — The Loop",
		"flow": "Critical path: same length as the Line. Loops: 2. The middle room is reachable two ways, so it becomes a landmark.",
		"rows": [
			"#########",
			"#E..#..B#",
			"#.D.D.D.#",
			"#...#..T#",
			"#########",
		],
	},
	{
		"name": "3 — The Hub",
		"flow": "One central landmark room; every other room is a spoke. Orientation: perfect. Critical path: fuzzy by design.",
		"rows": [
			"#########",
			"#T#...#B#",
			"###.D.###",
			"#...D...#",
			"###.D.###",
			"#E#...#.#",
			"#########",
		],
	},
]

const FIXTURE: PackedStringArray = [
	"############",
	"#....#.....#",
	"#....D.....#",
	"#....#..+..#",
	"##D###..+..#",
	"#....#..+..#",
	"#....##D####",
	"#..........#",
	"#..........#",
	"############",
]

const MAP_W: int = 60
const MAP_H: int = 40
const CELL: int = 14

var current: int = 0
var config: WorldConfig = null
var data: DungeonData = null
var gen: BSPGenerator = null
var seed_offset: int = 0
var show_graph: bool = true
var wfc_toy: WfcGenerator = null

var _built: bool = false

@onready var builder: DungeonBuilder = $Builder
@onready var overlay: DungeonOverlay = $Overlay
@onready var minimap: Minimap = $UI/Minimap
@onready var title_label: Label = $UI/TitleLabel
@onready var flow_label: Label = $UI/FlowLabel
@onready var legend_label: Label = $UI/LegendLabel

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"

func _ready() -> void:
	_built = true
	rebuild()
	if Engine.is_editor_hint() and (FileAccess.file_exists(DIRECTIVE_PATH)
			or FileAccess.file_exists("/tmp/p4_stage_directive.txt")):
		_arrange_from_directive()

func _sync_config() -> void:
	if config == null:
		config = WorldConfig.new()
	config.master_seed = master_seed

func _master_seed() -> int:
	return config.master_seed + seed_offset

## The capture harness's entry point: rebuild the current step from
## the current exports. Dispatches to the chapters' own regenerate
## functions; each step owns exactly one display path.
func rebuild() -> void:
	if not _built or builder == null:
		return
	_sync_config()
	# Framing: the full-size steps sit below the UI labels; the two
	# small WFC grids (steps 15/16) are centred by their branches.
	if builder != null:
		builder.position = Vector2(8, 76)
	if overlay != null:
		overlay.position = Vector2(8, 76)
	# Per-step display ownership: overlay and minimap start hidden;
	# the branches that own them turn them back on.
	if overlay != null:
		overlay.visible = false
		overlay.markers_only = false
	if minimap != null:
		minimap.visible = false
	if step == 0:
		legend_label.text = "Keys 1/2/3 switch dungeons.  E entrance · B boss · T treasure · D door"
		_show_tour(clampi(tour_index, 0, MAPS.size() - 1))
	elif step == 1:
		title_label.text = "Data model test fixture"
		flow_label.text = "Hand-authored 12x10. The console ASCII must match the string in the script."
		legend_label.text = "R re-render"
		_load_fixture()
	elif step >= 2 and step <= 4:
		legend_label.text = "R next seed · Space master seed"
		_regenerate_dungeon()
	elif step == 5 or step == 10 or step == 13:
		legend_label.text = "R next seed · Space master seed · G graph overlay"
		_regenerate_graph()
	elif step >= 6 and step <= 9:
		legend_label.text = "R next seed · Space master seed"
		_regenerate_caves()
	elif step == 11 or step == 12 or step == 14:
		legend_label.text = "R next seed · Space master seed · G graph overlay"
		_regenerate_mission()
	elif step >= 15 and step <= 19:
		if step == 15:
			legend_label.text = "Space collapse one cell · R fresh toy"
		elif step == 19:
			legend_label.text = "R next seed · Space master seed · C cartographer minimap"
		else:
			legend_label.text = "R next seed · Space master seed"
		_regenerate_constraints()
	queue_redraw()

## 2D stage: there is no Camera3D preset to apply. The book_capture
## harness calls this when present; framing is the scene layout's
## job (Builder/Overlay sit below the UI labels, whole map in view).
func apply_camera_preset_by_name(_preset_name: String) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = (event as InputEventKey).keycode
	if step == 0:
		if k == KEY_1:
			_show_tour(0)
		elif k == KEY_2:
			_show_tour(1)
		elif k == KEY_3:
			_show_tour(2)
	elif step == 1:
		if k == KEY_R:
			_load_fixture()
	elif step == 15:
		if k == KEY_SPACE:
			_step_wfc_toy()
		elif k == KEY_R:
			seed_offset = 0
			_regenerate_constraints()
	elif step >= 2 and step <= 19:
		if k == KEY_R:
			seed_offset += 1
			rebuild()
		elif k == KEY_SPACE:
			seed_offset = 0
			rebuild()
		elif k == KEY_G and (step == 5 or step == 10 or step == 11 or step == 12 or step == 13 or step == 14):
			show_graph = not show_graph
			if show_graph and data != null:
				overlay.show_data(data, DungeonBuilder.CELL)
			else:
				overlay.visible = false
		elif k == KEY_C and step == 19 and minimap != null:
			minimap.reveal_all = not minimap.reveal_all
			minimap.queue_redraw()

# --- Step 0: the hand-drawn tour (Listing 20.1) ---------------------------

func _show_tour(index: int) -> void:
	current = index
	title_label.text = str(MAPS[index]["name"])
	flow_label.text = str(MAPS[index]["flow"])
	queue_redraw()

func _draw() -> void:
	if step == 2:
		_draw_partition()
		return
	if step != 0:
		return
	var rows: Array = MAPS[current]["rows"]
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			var rect := Rect2(Vector2(x, y) * TILE_SIZE + Vector2(40, 110), Vector2.ONE * (TILE_SIZE - 2))
			var col := Color(0.16, 0.16, 0.2)  # wall
			match row[x]:
				".":
					col = Color(0.55, 0.48, 0.38)  # floor
				"D":
					col = Color(0.9, 0.55, 0.2)  # door / chokepoint
				"E":
					col = Color(0.3, 0.8, 0.35)
				"B":
					col = Color(0.85, 0.25, 0.25)
				"T":
					col = Color(0.95, 0.8, 0.25)
			draw_rect(rect, col)

# --- Step 1: the ASCII fixture (Listing 20.4) ------------------------------

func _load_fixture() -> void:
	data = DungeonData.new()
	data.from_ascii(FIXTURE)
	builder.render(data)
	builder.print_ascii(data)
	print("Passable tiles: ", data.floor_count())

# --- Steps 2-4: BSP (Listing 21.4) ------------------------------------------

func _regenerate_dungeon() -> void:
	gen = BSPGenerator.new()
	if step == 2:
		gen.build_tree(_master_seed(), MAP_W, MAP_H)
		var lv: Array = gen.leaves()
		var smallest: int = 1 << 30
		for leaf in lv:
			var r: Rect2i = leaf["rect"]
			smallest = mini(smallest, mini(r.size.x, r.size.y))
		title_label.text = "BSP partition viewer"
		flow_label.text = "Leaves: %d · narrowest leaf side: %d" % [lv.size(), smallest]
		print("seed ", _master_seed(), " -> ", lv.size(), " leaves")
		queue_redraw()
		return
	if step == 3:
		gen.build_tree(_master_seed(), MAP_W, MAP_H)
		data = DungeonData.new()
		data.setup(MAP_W, MAP_H)
		gen.carve_rooms(data)
		title_label.text = "BSP rooms (unconnected islands — corridors are step 4)"
	else:
		data = gen.generate(_master_seed(), MAP_W, MAP_H)
		title_label.text = "BSP dungeon — fully walkable"
	builder.render(data)
	flow_label.text = "Rooms: %d · Edges: %d · Passable tiles: %d" % [
		data.rooms.size(), data.edges.size(), data.floor_count()]
	print("seed ", _master_seed(), " · rooms ", data.rooms.size(),
		" · edges ", data.edges.size(), " · passable ", data.floor_count(),
		" (rooms-1 = ", data.rooms.size() - 1, ")")

func _draw_partition() -> void:
	if gen == null:
		return
	var palette: Array = [
		Color(0.35, 0.45, 0.6), Color(0.45, 0.6, 0.4), Color(0.6, 0.5, 0.35),
		Color(0.55, 0.4, 0.55), Color(0.4, 0.55, 0.55), Color(0.6, 0.42, 0.42),
	]
	var i: int = 0
	for leaf in gen.leaves():
		var r: Rect2i = leaf["rect"]
		var rect := Rect2(Vector2(r.position) * CELL + Vector2(40, 110), Vector2(r.size) * CELL)
		draw_rect(rect, palette[i % palette.size()])
		draw_rect(rect, Color.BLACK, false, 2.0)
		i += 1

# --- Steps 6-9: caves, drunkard, hybrid (Listing 22.5) ----------------------

func _regenerate_caves() -> void:
	if step == 6 or step == 7:
		var cave := CaveGenerator.new()
		if step == 6:
			data = cave.generate(_master_seed(), MAP_W, MAP_H)
			title_label.text = "Cellular cave — raw (count the pockets)"
		else:
			data = cave.generate_clean(_master_seed(), MAP_W, MAP_H)
			title_label.text = "Cellular cave — cleaned to one region"
		builder.render(data)
		var report: Array = data.region_report()
		flow_label.text = "Regions: %d · largest: %d · passable: %d" % [
			report.size(), int(report[0]["size"]) if not report.is_empty() else 0, data.floor_count()]
		print("seed ", _master_seed(), " cave regions: ", report)
	elif step == 8:
		data = DungeonData.new()
		data.setup(MAP_W, MAP_H)
		var rng: RandomNumberGenerator = SeedBank.stream_for(_master_seed(), SeedBank.STREAM_DUNGEON)
		var starts: Array[Vector2i] = [Vector2i(6, 6), Vector2i(30, 20), Vector2i(52, 32)]
		for s in starts:
			WalkTunneller.carve(data, rng, s, 90)
		title_label.text = "Drunkard's walk — three tunnels through solid rock"
		builder.render(data)
		flow_label.text = "Passable tiles: %d (three budgets of 90 new tiles, plus crossings)" % data.floor_count()
	elif step == 9:
		data = HybridGenerator.new().generate(_master_seed(), MAP_W, MAP_H)
		title_label.text = "Hybrid — BSP rooms, cave guts, one cave pocket"
		builder.render(data)
		var report2: Array = data.region_report()
		flow_label.text = "Rooms: %d · Regions: %d (must be 1) · Passable: %d" % [
			data.rooms.size(), report2.size(), data.floor_count()]

# --- Steps 5, 10, 13: graph, spanning growth, loops (Listing 23.5) ----------

func _regenerate_graph() -> void:
	data = BSPGenerator.new().generate(_master_seed(), MAP_W, MAP_H)
	builder.render(data)
	if step == 5:
		title_label.text = "BSP dungeon + room graph"
		var s: Dictionary = data.graph_stats()
		flow_label.text = "Rooms %d · dead ends %d · max degree %d · diameter %d" % [
			s["rooms"], s["dead_ends"], s["max_degree"], s["diameter"]]
		print("seed ", _master_seed(), " stats: ", s)
	elif step == 10:
		title_label.text = "Spanning growth — the backbone, in order"
		var growth: Array = data.spanning_growth()
		var total: float = 0.0
		for att in growth:
			total += float(att["cost"])
		flow_label.text = "Attachments: %d (rooms-1 = %d) · total cost %.1f cells" % [
			growth.size(), data.rooms.size() - 1, total]
		print("seed ", _master_seed(), " growth: ", growth.size(),
			" attachments, total cost ", snappedf(total, 0.1))
		print("seed ", _master_seed(), " stats: ", data.graph_stats())
	elif step == 13:
		title_label.text = "Backbone verified, then two loops, priced"
		var rng: RandomNumberGenerator = SeedBank.stream_for(_master_seed(), SeedBank.STREAM_DUNGEON)
		var report: Dictionary = LoopSurgeon.backbone_report(data)
		print("BACKBONE ", report)
		var receipt1: Dictionary = LoopSurgeon.add_one_loop_priced(data, rng)
		var receipt2: Dictionary = LoopSurgeon.add_one_loop_priced(data, rng)
		builder.render(data)
		flow_label.text = "Backbone loops %d · after surgery: loops %d · story %d -> %d rooms" % [
			int(report["loops"]), LoopSurgeon.loop_count(data),
			int(receipt1["path_before"]), int(receipt2["path_after"])]
		print("LOOP 1 ", receipt1)
		print("LOOP 2 ", receipt2)
	if show_graph:
		overlay.show_data(data, DungeonBuilder.CELL)

# --- Steps 11, 12, 14: mission, lock & key, doors (Listing 24.4) ------------

func _regenerate_mission() -> void:
	data = BSPGenerator.new().generate(_master_seed(), MAP_W, MAP_H)
	var planner := MissionPlanner.new()
	planner.annotate(data)
	if step == 11:
		title_label.text = "Mission roles — the graph is the quest"
		builder.render(data)
		var path: Array = planner.critical_path(data)
		flow_label.text = "Critical path: %d rooms · roles in Output" % path.size()
	elif step == 12:
		title_label.text = "Lock & key — placed by construction, proven by solver"
		var placed: bool = planner.lock_and_key(data, "brass")
		data.build_door_records()
		builder.render(data)
		var verdict: Dictionary = planner.is_completable(data)
		flow_label.text = "Lock placed: %s · Completable: %s" % [placed, verdict["completable"]]
		print("SOLVER ", verdict)
		if bool(verdict["completable"]):
			print("COMPLETABLE — order: ", verdict["order"])
		else:
			print("NOT COMPLETABLE — no finishing order exists")
	elif step == 14:
		title_label.text = "Doors as edges — locked, secret, one-way"
		planner.lock_and_key(data, "brass")
		data.build_door_records()
		# Promote two more doors by hand, so all four kinds show:
		# a secret shortcut off the entrance, a one-way drop
		# halfway along the path.
		var path2: Array = planner.critical_path(data)
		if path2.size() >= 4:
			data.set_door(int(path2[1]), int(path2[2]), "secret")
			data.set_door(int(path2[path2.size() / 2]), int(path2[path2.size() / 2 + 1]), "one_way")
		builder.render(data)
		var verdict2: Dictionary = planner.is_completable(data)
		flow_label.text = "Doors: %d · Completable with all kinds: %s" % [
			data.edges.size(), verdict2["completable"]]
		print("SOLVER (doors) ", verdict2)
	if show_graph:
		overlay.show_data(data, DungeonBuilder.CELL)

# --- Steps 15-19: WFC, geomorphs, dressing, finale (Listing 25.9) -----------

func _regenerate_constraints() -> void:
	if step == 15:
		title_label.text = "WFC toy — Space collapses one cell"
		var stream: RandomNumberGenerator = SeedBank.stream_for(_master_seed(), SeedBank.STREAM_DUNGEON)
		wfc_toy = WfcGenerator.new(_toy_tiles(), 6, 6, stream)
		_render_wfc_toy()
	elif step == 16:
		title_label.text = "WFC dungeon — constraints, not construction"
		# Centre the 24x24 grid in the frame (it is a quarter of the
		# full-size maps' extent; at the shared origin it would sit
		# small in the corner of its own render).
		builder.position = Vector2(448, 158)
		overlay.position = Vector2(448, 158)
		data = WfcGenerator.generate_dungeon(_master_seed(), 24)
		builder.render(data)
		flow_label.text = "Retries: %d · passable: %d · pillars: %d" % [
			int(data.meta.get("wfc_retries", 0)), data.floor_count(),
			(data.meta.get("pillars", []) as Array).size()]
		print("WFC seed ", _master_seed(), " retries ", data.meta.get("wfc_retries", 0))
		# Caption contract: pillar cells are marked in this render.
		overlay.markers_only = true
		overlay.show_data(data, DungeonBuilder.CELL)
	elif step == 17:
		title_label.text = "Geomorphs — hand-made rooms, algorithmic assembly"
		data = GeomorphAssembler.new().assemble(_master_seed(), 9)
		builder.render(data)
		flow_label.text = "Rooms placed: %d · edges: %d" % [data.rooms.size(), data.edges.size()]
	elif step == 18 or step == 19:
		# THE COMPLETE PIPELINE, in order, named:
		# structure -> surgery -> graph -> loops -> mission ->
		# doors -> dressing -> population -> (19) minimap + gate.
		data = HybridGenerator.new().generate(_master_seed(), MAP_W, MAP_H)
		var planner := MissionPlanner.new()
		planner.annotate(data)
		var rng: RandomNumberGenerator = SeedBank.stream_for(_master_seed(), SeedBank.STREAM_DUNGEON)
		LoopSurgeon.add_loops(data, rng, 2)
		planner.lock_and_key(data, "brass")
		data.build_door_records()
		Dressing.dress(data, rng)
		Population.populate(data, rng)
		builder.render(data)
		title_label.text = "The complete dungeon — every system in the part"
		flow_label.text = "Rooms %d · loops %d · dressing %d · spawns %d" % [
			data.rooms.size(), LoopSurgeon.loop_count(data),
			(data.meta["dressing"] as Array).size(), (data.meta["spawns"] as Array).size()]
		# Caption contract: dressing + spawn markers in frame.
		overlay.markers_only = true
		overlay.show_data(data, DungeonBuilder.CELL)
		if step == 19:
			minimap.visible = true
			minimap.set_dungeon(data)
			print("FINALE pipeline: hybrid structure -> mission annotate -> 2 loops -> lock & key -> door records -> dressing -> population -> minimap -> validate")
			print("FINALE regions: ", data.region_report())
			var report: Dictionary = DungeonValidator.validate(data)
			print("FINALE seed ", _master_seed(), " validation: ",
				"ALL PASS" if bool(report["pass"]) else "FAILURES PRESENT")

## Step 15's input, as a function: _unhandled_input()'s step-15
## branch calls this on Space (one collapse) and calls
## _regenerate_constraints() on R (a fresh toy, same seed).
func _step_wfc_toy() -> void:
	if wfc_toy == null:
		return
	wfc_toy.collapse_step()
	_render_wfc_toy()

func _render_wfc_toy() -> void:
	data = DungeonData.new()
	data.setup(6, 6)
	for y in range(6):
		for x in range(6):
			var idx: int = wfc_toy._idx(x, y)
			var tile: int = DungeonData.Tile.FLOOR
			if int(wfc_toy.collapsed[idx]) >= 0:
				var def: Dictionary = wfc_toy.tile_defs[int(wfc_toy.collapsed[idx])]
				tile = DungeonData.Tile.WALL if str(def["kind"]) == "wall" else DungeonData.Tile.FLOOR
			data.set_tile(Vector2i(x, y), tile)
	builder.render(data)
	var remaining: int = 0
	for c in wfc_toy.collapsed:
		if int(c) == -1:
			remaining += 1
	flow_label.text = "Undecided cells: %d · contradiction: %s" % [remaining, wfc_toy.contradiction]

func _toy_tiles() -> Array:
	var w: String = "wall"
	var f: String = "floor"
	return [
		{"name": "solid", "kind": "wall", "sockets": [w, w, w, w], "weight": 1.0},
		{"name": "open", "kind": "floor", "sockets": [f, f, f, f], "weight": 3.0},
		{"name": "edge_n", "kind": "wall", "sockets": [w, f, f, f], "weight": 1.0},
		{"name": "edge_e", "kind": "wall", "sockets": [f, w, f, f], "weight": 1.0},
		{"name": "edge_s", "kind": "wall", "sockets": [f, f, w, f], "weight": 1.0},
		{"name": "edge_w", "kind": "wall", "sockets": [f, f, f, w], "weight": 1.0},
		{"name": "corner_ne", "kind": "wall", "sockets": [w, w, f, f], "weight": 0.7},
		{"name": "corner_se", "kind": "wall", "sockets": [f, w, w, f], "weight": 0.7},
		{"name": "corner_sw", "kind": "wall", "sockets": [f, f, w, w], "weight": 0.7},
		{"name": "corner_nw", "kind": "wall", "sockets": [w, f, f, w], "weight": 0.7},
	]

## The ENGINE captions for this part require the Output panel's
## receipt lines IN the frame; the project's default editor layout
## starts with the bottom panel collapsed (tab strip only). Press
## the Output tab once to expand it before the grab.
func _expand_output_panel() -> void:
	# Godot 4.7's bottom panel tabs are drawn and hit-tested by the
	# internal EditorBottomPanel control itself — a full tree dump
	# (202 buttons) contains no "Output" Button to press. The
	# faithful equivalent of the reader's click on the Output tab
	# is a simulated click pushed through the editor window's
	# viewport at the tab's position (first tab in the bottom
	# strip of the 1920x1080 editor window).
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var vp: Viewport = base.get_viewport()
	var pos := Vector2(320, 1056)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev)

# --- Editor arrangement for ENGINE captures ---------------------------------
# tools/capture_engine2.sh writes a directive file before launching
# the editor; after the shared book_stage plugin has done its own
# arrangement (step=2, root selected), this applies the shot's real
# step / selection and writes the arranged file the wrapper polls
# for. No directive file = no arrangement (normal use).

func _arrange_from_directive() -> void:
	await get_tree().create_timer(6.0).timeout
	# Prefer this part's PRIVATE directive: the shared directive
	# file is rewritten by every worker's capture wrapper, and a
	# foreign step (a plants step=9) landed in a dungeon shot
	# through it during a busy capture window.
	var path: String = DIRECTIVE_PATH
	if FileAccess.file_exists("/tmp/p4_stage_directive.txt"):
		path = "/tmp/p4_stage_directive.txt"
	var txt: String = FileAccess.get_file_as_string(path)
	var want_step: int = step
	var want_select: String = ""
	for line in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
	step = want_step  # setter rebuilds at the requested step
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	var node: Node = self
	if want_select != "" and want_select != "root":
		var found: Node = find_child(want_select, true, false)
		if found != null:
			node = found
	sel.add_node(node)
	EditorInterface.set_main_screen_editor("2D")
	_expand_output_panel()
	# Rebuild once more AFTER expanding: the fresh receipt lines
	# land in the now-visible Output log and auto-scroll it to the
	# receipts (the first build's prints predate the expansion).
	rebuild()
	var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("arranged step=%d select=%s\n" % [step, want_select])
		f.close()
	# Private handshake for this part's own capture wrapper: the
	# shared arranged file and editor log are racy when several
	# workers capture at once, so the wrapper waits on this file
	# and its distinctive content instead.
	var priv: FileAccess = FileAccess.open("/tmp/p4_stage_arranged.txt",
		FileAccess.WRITE)
	if priv != null:
		priv.store_string("dungeons arranged step=%d select=%s\n"
			% [step, want_select])
		priv.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)
