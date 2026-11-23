@tool
class_name ApartmentStage
extends Node3D
## Part VI's stage. Nine fixed steps (Ch 31 header): 0–4 are 2D plan
## steps shown in PlanLab, 5–8 are 3D steps shown in World. Later
## chapters add their steps to THIS file without renumbering.
##
## Integration notes (project harness, same pattern as the dungeon
## and plants stages — the chapters' plain runtime script cannot be
## screenshotted by the book's tools):
## - @tool + rebuild() are the capture harness's interface
##   (tools/book_capture.gd sets step/seed, then calls rebuild();
##   the book_stage editor plugin does the same). The step /
##   master_seed setters rebuild live once the stage is built, and
##   rebuild() is memoised on (step, seed, typology) so the harness's
##   repeated calls do not re-solve.
## - The plugin forces step=2 before any ENGINE grab; the real step
##   is applied afterwards from tools/capture_engine2.sh's directive
##   file (see _arrange_from_directive), which also picks the 2D main
##   screen for plan steps (a CanvasLayer plan does not draw in the
##   3D viewport) and the 3D screen + a framed editor camera for
##   world steps, expands the Output panel (the Ch 32 ENGINE
##   captions require the slot-roll log / block certificate in
##   frame), and — for the Ch 33 facade shot — selects FacadeGroup
##   once so the Scene dock expands Block_0's tree, then re-selects
##   the root so the Inspector shows step / master_seed.
## - In the editor only, built nodes under Street are given this
##   stage as owner so the built block's tree (Floor_*, FacadeGroup,
##   RoofGroup) is visible in the Scene dock for ENGINE shots. The
##   capture wrappers never save the scene, so nothing bakes in.
## - A code-built WorldEnvironment (BookEnv, unowned, not in the
##   .tscn tree the Ch 31 caption lists) supplies sky + ambient for
##   the 3D steps; Listing 31.3's scene recipe has no environment
##   node and bare directional light renders near-black in shadow.
## - Step 2/3 print the slot roll ONCE per roll (slot classes + each
##   slot's wet rect, read back off floor 1's stamped bathrooms —
##   the wet slot is shared, so floor 1's bathrooms sit exactly on
##   it): the Ch 32 ENGINE caption's placement proof.

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

var _built: bool = false
var _built_key: String = ""

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"

var current_seed: int = 0
var typology: String = "point"
var active_program: ApartmentProgram = null
var active_core: Dictionary = {}
var active_block: Dictionary = {} # Ch 32: the full BLOCK dictionary
var active_floor: int = 0
var active_plan: Dictionary = {}
var active_footprint: Rect2 = Rect2(0, 0, 19.5, 19.5)

@onready var viewer: PlanViewer = $PlanLab/PlanViewer
@onready var plan_lab: CanvasLayer = $PlanLab
@onready var world: Node3D = $World
@onready var street_node: Node3D = $World/Street
@onready var camera: Camera3D = $World/CameraRig/Camera
@onready var title_label: Label = $UI/TitleLabel
@onready var flow_label: Label = $UI/FlowLabel
@onready var cert_label: Label = $UI/CertLabel

func _ready() -> void:
	_built = true
	current_seed = master_seed
	_ensure_environment()
	rebuild()
	if Engine.is_editor_hint() and FileAccess.file_exists(DIRECTIVE_PATH):
		_arrange_from_directive()


## The capture harness's entry point: rebuild the current step from
## the current exports. Clears the street (built blocks are derived
## data) and dispatches to the chapters' _show_step().
func rebuild() -> void:
	if not _built or viewer == null:
		return
	current_seed = master_seed
	var key: String = str(step) + ":" + str(master_seed) + ":" + typology
	if key == _built_key:
		return
	for child in street_node.get_children():
		street_node.remove_child(child)
		child.free()
	active_block = {}
	block_roof_group = null
	_show_step()
	if Engine.is_editor_hint():
		_own_built_nodes()
	_built_key = key


func _ensure_environment() -> void:
	if get_node_or_null("BookEnv") != null:
		return
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "BookEnv"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	we.environment = env
	add_child(we)


## Editor only: own the built subtree so it appears in the Scene
## dock (see header). Never called at runtime; wrappers never save.
func _own_built_nodes() -> void:
	var stack: Array = [street_node]
	while not stack.is_empty():
		var n: Node = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		for child in n.get_children():
			if child.owner == null:
				child.owner = self
			stack.append(child)


func apply_camera_preset_by_name(_preset_name: String) -> void:
	# The harness probes for this method; Part VI frames its cameras
	# per step in the chapter code itself, so there is no preset to
	# apply — the step's own camera placement stands.
	pass

func _show_step() -> void:
	var is_3d: bool = step >= 5
	plan_lab.visible = not is_3d
	world.visible = is_3d
	cert_label.text = ""
	match step:
		0:
			title_label.text = "The multi-unit program — shares in, whole homes out (1/2/3 = point / corridor / family-heavy mix)"
			_show_mix(0)
		1:
			title_label.text = "Core & typology lab — circulation placed first (T = typology)"
			_show_core()
		2:
			title_label.text = "One stamped floor — geometry rolled once, kinds stamped per floor (F = next floor)"
			_roll_and_stamp(0)
		3:
			title_label.text = "Per-unit variation — same walls, re-stamped kinds per floor (F = next floor, R = re-roll)"
			_roll_and_stamp(3)
		4:
			title_label.text = "Solved block + assertion certificate (R = solve, V = validate raw)"
			_solve_block()
		5:
			title_label.text = "Extruded block — Part V's builder, unmodified (dollhouse)"
			_build_block()
		6:
			title_label.text = "Balconies & facade rhythm — the exterior read off the plan"
			_run_facade()
		7:
			title_label.text = "Furnished floor — stood in the core hall"
			_run_furnished_floor()
		8:
			title_label.text = "A street of apartment blocks — parcels-lite"
			_run_street()
		_:
			title_label.text = "Step %d is built in a later chapter of Part VI" % step
			flow_label.text = ""

func _mix_for(index: int) -> Dictionary:
	match index:
		1:
			return {"studio": 0.15, "one_bed": 0.30, "two_bed": 0.35, "family": 0.20}
		2:
			return {"studio": 0.10, "one_bed": 0.25, "two_bed": 0.30, "family": 0.35}
	return {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15}

func _show_mix(index: int) -> void:
	var mix: Dictionary = _mix_for(index)
	active_program = ApartmentProgram.build(active_footprint.size, 4, mix)
	# Step 0 reuses Ch 26's budget-bar view: one bar per SLOT (a whole
	# home), sized by the kind's nominal area — shares made visible.
	var bars: Array = []
	for i in active_program.units_per_floor.size():
		var kind: String = active_program.units_per_floor[i]
		bars.append({"name": "slot_%d %s" % [i + 1, kind], "type": kind, "zone": "social",
			"target": float(ApartmentProgram.NOMINAL_AREA[kind]), "min": 0.0})
	viewer.set_specs(bars, active_footprint)
	flow_label.text = "Mix %d — %d slots/floor by largest remainder: %s" % [index, bars.size(), ", ".join(active_program.units_per_floor)]

func _show_core() -> void:
	active_core = ApartmentProgram.core_for(typology, active_footprint.size)
	if active_program == null:
		active_program = ApartmentProgram.build(active_footprint.size, 4, _mix_for(0))
	# Draw the core as rooms on an otherwise empty plan: the core IS
	# circulation-zone rooms in the floor plan's own data shape.
	var rooms: Array = [
		{"name": "stairs", "type": "stairs", "zone": "circulation", "unit": "", "rect": active_core["stair_rect"], "target": 0.0, "min": 0.0},
		{"name": "lift", "type": "lift", "zone": "circulation", "unit": "", "rect": active_core["lift_rect"], "target": 0.0, "min": 0.0},
		{"name": "core_hall", "type": "hall", "zone": "circulation", "unit": "", "rect": active_core["hall_rect"], "target": 0.0, "min": 0.0},
	]
	active_plan = {"footprint": active_footprint, "rooms": rooms, "doors": [], "windows": [], "entrance_room": "core_hall", "meta": {}}
	viewer.set_plan(rooms, active_footprint)
	flow_label.text = "Typology: %s — core rent %.1f m²/floor; service wall at x = %.1f" % [typology,
		(active_core["stair_rect"] as Rect2).get_area() + (active_core["lift_rect"] as Rect2).get_area(),
		float(active_core["service_wall_x"])]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if step == 0:
			match event.keycode:
				KEY_1: _show_mix(0)
				KEY_2: _show_mix(1)
				KEY_3: _show_mix(2)
		elif step == 1:
			if event.keycode == KEY_T:
				typology = "corridor" if typology == "point" else "point"
				_show_core()
		elif step == 2 or step == 3:
			if event.keycode == KEY_F:
				if not active_block.is_empty():
					var count: int = (active_block["floors"] as Array).size()
					_show_floor((active_floor + 1) % count)
			elif step == 3 and event.keycode == KEY_R:
				current_seed += 1 # re-roll: a fresh buildings stream
				_roll_and_stamp(active_floor)
		elif step == 4:
			if event.keycode == KEY_R:
				_solve_block()
			elif event.keycode == KEY_V:
				_validate_raw()


## Step 4's V key: grade one raw (unsolved) roll in the open, so the
## solver's accepts can be compared against what it rejects.
func _validate_raw() -> void:
	var program: ApartmentProgram = _default_program()
	var rng: RandomNumberGenerator = SeedBank.stream_for(current_seed, SeedBank.STREAM_BUILDINGS)
	var block: Dictionary = BlockLayout.generate_block(program, active_core, rng)
	for plan in block["floors"]:
		BlockLayout.build_floor_doors(plan)
		WindowPlacer.place_windows(plan)
	var verdict: Dictionary = ApartmentRules.validate_block(block)
	if verdict["violations"].is_empty():
		print("RAW BLOCK VALIDATION: 0 violations — this roll would have been accepted")
		cert_label.text = "Raw roll validation: 0 violations."
	else:
		for v in verdict["violations"]:
			print("RAW ", v)
		cert_label.text = "Raw roll validation: %d violations (see Output). R solves." % verdict["violations"].size()


var block_roof_group: Node3D = null

func _default_program() -> ApartmentProgram:
	if active_program == null:
		active_program = ApartmentProgram.build(active_footprint.size, 4, _mix_for(0))
	if active_core.is_empty():
		active_core = ApartmentProgram.core_for(typology, active_footprint.size)
	return active_program

func _roll_and_stamp(floor_index: int) -> void:
	var program: ApartmentProgram = _default_program()
	var rng: RandomNumberGenerator = SeedBank.stream_for(current_seed, SeedBank.STREAM_BUILDINGS)
	var block: Dictionary = BlockLayout.generate_block(program, active_core, rng)
	active_block = block
	_print_slot_roll()
	_show_floor(floor_index)


## The roll, in the open (Ch 32 ENGINE placement proof): slot count,
## per-slot class, and each slot's wet rect — printed ONCE per roll,
## read back off floor 1's stamped bathrooms, which sit exactly on
## the shared wet slots. If this ever prints per floor, the floors
## are re-rolling geometry and the stack guarantee is void.
func _print_slot_roll() -> void:
	if active_block.is_empty():
		return
	var floor0: Dictionary = active_block["floors"][0]
	var by_slot: Dictionary = {}
	for unit in active_block["units"]:
		if int(unit["floor"]) == 0:
			by_slot[int(unit["slot"])] = unit
	var classes: Array = []
	for s in by_slot.keys():
		classes.append(BlockLayout.slot_class_of(String(by_slot[s]["kind"])))
	print("SLOT ROLL slots=%d classes=%s (rolled once per block)" % [by_slot.size(), ", ".join(classes)])
	for s in by_slot.keys():
		var unit_id: String = String(by_slot[s]["id"])
		for room in floor0["rooms"]:
			if room["type"] == "bathroom" and String(room.get("unit", "")) == unit_id:
				print("SLOT %d class=%s wet_rect=%s" % [int(s) + 1, BlockLayout.slot_class_of(String(by_slot[s]["kind"])), str(room["rect"])])

func _show_floor(floor_index: int) -> void:
	if active_block.is_empty():
		return
	active_floor = clampi(floor_index, 0, (active_block["floors"] as Array).size() - 1)
	active_plan = active_block["floors"][active_floor]
	BlockLayout.build_floor_doors(active_plan)
	viewer.set_plan(active_plan["rooms"], active_footprint)
	viewer.set_doors_v2(active_plan["doors"])
	var kinds: Array = []
	for unit in active_block["units"]:
		if int(unit["floor"]) == active_floor:
			kinds.append("%s %s" % [unit["id"], unit["kind"]])
	flow_label.text = "Floor %d of %d — %s (F = next floor)" % [active_floor + 1,
		(active_block["floors"] as Array).size(), ", ".join(kinds)]

func _solve_block() -> void:
	var program: ApartmentProgram = _default_program()
	var result: Dictionary = BlockSolver.solve(program, active_core, current_seed)
	active_block = result["block"]
	if active_block.is_empty():
		cert_label.text = result["report"][0]
		return
	cert_label.text = "\n".join(result["report"])
	_show_floor(0)
	flow_label.text = "Step 4 — solver-accepted block. Certificate below; build it with step 5."

func _build_block() -> void:
	if active_block.is_empty():
		_solve_block()
	if active_block.is_empty():
		return
	_show_world()
	var host: Node3D = Node3D.new()
	host.name = "Block_0"
	street_node.add_child(host)
	var rng: RandomNumberGenerator = SeedBank.stream_for(current_seed, SeedBank.STREAM_BUILDINGS)
	block_roof_group = HouseBuilder.build(host, active_block, false, rng)
	block_roof_group.visible = false # dollhouse: the audit view (Ch 30)
	camera.position = Vector3(30, 20, 26)
	camera.look_at(Vector3(12, 3, 6.5), Vector3.UP)
	flow_label.text = "Step 5 — the block, extruded by Part V's builder, unmodified. Roof group hidden: dollhouse audit view."

func _show_world() -> void:
	plan_lab.visible = false
	world.visible = true


func _run_facade() -> void:
	_build_block()
	if active_block.is_empty():
		return
	# _build_block rebuilt the block under Street/Block_0, dollhouse
	# style. Add the facade + roof for the presentation view.
	var host: Node3D = street_node.get_node("Block_0")
	var balconies: Array = FacadeBuilder.build_facade(host, active_block)
	var violations: Array = ApartmentRules.check_balconies(active_block, balconies)
	for v in violations:
		print("FACADE ", v)
	var style: String = "flat" if typology == "corridor" else "gable"
	RoofBuilder.build(block_roof_group, active_footprint, style)
	RoofBuilder.set_roof_visible(block_roof_group, true)
	camera.position = Vector3(9.8, 2.5, 41.0)
	camera.look_at(Vector3(9.8, 6.0, 19.5), Vector3.UP)
	flow_label.text = "Step 6 — balconies on windows, roof on (%s), %d balconies, %d facade violations." % [style, balconies.size(), violations.size()]

func _run_furnished_floor() -> void:
	if active_block.is_empty():
		_solve_block()
	if active_block.is_empty():
		return
	_show_world()
	for child in street_node.get_children():
		child.queue_free()
	var host: Node3D = Node3D.new()
	host.name = "Block_0"
	street_node.add_child(host)
	var rng: RandomNumberGenerator = SeedBank.stream_for(current_seed, SeedBank.STREAM_BUILDINGS)
	block_roof_group = HouseBuilder.build(host, active_block, true, rng)
	block_roof_group.visible = false
	# Stand in the core hall of floor 1 (index 0), at eye level,
	# looking along it: front doors on both sides, homes beyond them.
	var hall_rect: Rect2 = active_core["hall_rect"]
	camera.position = Vector3(hall_rect.position.x + 0.6, 1.6, hall_rect.get_center().y)
	camera.look_at(Vector3(hall_rect.end.x - 0.4, 1.5, hall_rect.get_center().y), Vector3.UP)
	flow_label.text = "Step 7 — furnished block from the core hall. Every front door off this hall; every home furnished by its stamped type."

func _run_street() -> void:
	_show_world()
	for child in street_node.get_children():
		child.queue_free()
	var result: Dictionary = StreetBuilder.build_street(street_node, current_seed, 4)
	cert_label.text = "\n".join(result["report"])
	var length: float = float(result["length"])
	camera.position = Vector3(length * 0.35, 2.0, 14.0)
	camera.look_at(Vector3(length * 0.45, 5.0, -8.0), Vector3.UP)
	flow_label.text = "Step 8 — a street of certified blocks (parcels-lite; Part VIII does real parcels)."


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
	# foreign run landing mid-arrange corrupted a certificate grab
	# during a busy capture window (the DungeonStage lesson).
	var path: String = DIRECTIVE_PATH
	if FileAccess.file_exists("/tmp/p6_stage_directive.txt"):
		path = "/tmp/p6_stage_directive.txt"
	var txt: String = FileAccess.get_file_as_string(path)
	var want_step: int = step
	var want_select: String = "root"
	var want_clicks: int = 1
	for line in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
		elif line.begins_with("clicks="):
			want_clicks = int(line.trim_prefix("clicks="))
	step = want_step # setter rebuilds at the requested step
	rebuild()
	var sel: EditorSelection = EditorInterface.get_selection()
	if want_select == "facade":
		# Expand Block_0's tree in the Scene dock (selection expands
		# ancestors), hold a beat, then re-select the root so the
		# Inspector shows the stage exports (Ch 33 caption).
		var fg: Node = street_node.find_child("FacadeGroup", true, false)
		if fg != null:
			# Select the first balcony holder, not the group: the
			# dock expands every ancestor INCLUDING FacadeGroup
			# itself, so the Balcony_<room> holders are in frame
			# (Ch 33's placement proof).
			var target: Node = fg
			if fg.get_child_count() > 0:
				target = fg.get_child(0)
			sel.clear()
			sel.add_node(target)
			await get_tree().create_timer(0.6).timeout
	sel.clear()
	sel.add_node(self)
	if want_select == "facade":
		await get_tree().create_timer(0.5).timeout
		_arrange_scene_tree()
	if step >= 5:
		EditorInterface.set_main_screen_editor("3D")
		_frame_editor_camera()
	else:
		EditorInterface.set_main_screen_editor("2D")
		await get_tree().create_timer(0.5).timeout
		_pan_plan_view()
		await get_tree().create_timer(0.4).timeout
	await _expand_output_panel()
	# Re-run the printing step now the Output panel is visible, so
	# the receipt lines (slot roll / block certificate) land in the
	# open log, scrolled to the bottom (the DungeonStage pattern).
	if step == 4:
		_solve_block()
	elif step == 2 or step == 3:
		_print_slot_roll()
	if step < 5:
		EditorInterface.set_main_screen_editor("2D")
	await get_tree().create_timer(0.5).timeout
	var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("arranged step=%d select=%s\n" % [step, want_select])
		f.close()
	# Private handshake for this part's own capture wrapper: the
	# shared arranged file is racy when several workers capture at
	# once, so the wrapper waits on this file instead.
	var priv: FileAccess = FileAccess.open("/tmp/p6_stage_arranged.txt",
			FileAccess.WRITE)
	if priv != null:
		priv.store_string("apartments arranged step=%d select=%s\n"
				% [step, want_select])
		priv.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)


## Scene-dock shaping for the Ch 33 facade shot: the editor
## auto-expands the first built branch (Floor_0 and its mesh
## rows flood the dock, pushing FacadeGroup out of frame), and
## saved folding state does not govern it. Walk the dock's Tree
## directly: collapse the Floor items, unfold FacadeGroup, so
## Block_0 shows floors, facade holders and roof as siblings.
func _arrange_scene_tree() -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var tree: Tree = _find_scene_tree(base)
	if tree == null or tree.get_root() == null:
		return
	var block_item: TreeItem = _find_tree_item(tree.get_root(), "Block_0")
	if block_item == null:
		return
	# Give the Scene dock more height (its split with the
	# FileSystem dock below): Block_0's subtree — floors, fifteen
	# wall meshes, roof, facade, holders — needs ~35 rows and the
	# default split shows ~21.
	var anc: Node = tree.get_parent()
	while anc != null and not (anc is SplitContainer and anc.name == "DockVSplitLeftR"):
		anc = anc.get_parent()
	if anc != null:
		(anc as SplitContainer).split_offset += 400
	var facade_item: TreeItem = null
	var child: TreeItem = block_item.get_first_child()
	while child != null:
		var t: String = child.get_text(0)
		if t.begins_with("Floor_"):
			child.set_collapsed(true)
		elif t == "FacadeGroup":
			child.set_collapsed(false)
			facade_item = child
		child = child.get_next()
	if facade_item != null and block_item.get_child_count() > 0:
		# Top-anchor the scroll on Floor_0: with the dock enlarged
		# (above), the whole subtree — floors, wall meshes, roof,
		# facade group and its first holders — fits beneath it.
		tree.scroll_to_item(block_item.get_child(0))


func _find_scene_tree(c: Control) -> Tree:
	if c is Tree:
		var t: Tree = c as Tree
		if t.get_root() != null and t.get_root().get_text(0) == "ApartmentStage":
			return t
	for child in c.get_children():
		if child is Control:
			var found: Tree = _find_scene_tree(child as Control)
			if found != null:
				return found
	return null


func _find_tree_item(item: TreeItem, text: String) -> TreeItem:
	if item.get_text(0) == text:
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var found: TreeItem = _find_tree_item(child, text)
		if found != null:
			return found
		child = child.get_next()
	return null


## Centre the plan in the 2D editor view: the plan draws at
## 40 px/m from a fixed offset, and the editor's default view
## leaves its bottom rows behind the expanded Output panel.
## Shifting the PlanViewer node (editor-only, never saved — the
## capture wrapper kills the editor) moves the drawing up and
## left into the free canvas. (A simulated middle-drag pan was
## tried first; the canvas editor ignores pushed motion events.)
func _pan_plan_view() -> void:
	viewer.position -= Vector2(150, 110)


## Frame the editor's own 3D camera on the built subject (the scene
## Camera is the game's; ENGINE shots show the editor viewport).
func _frame_editor_camera() -> void:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	if step == 6:
		cam.position = Vector3(12, 7.0, 34)
		cam.look_at(Vector3(12, 4.0, 6.5), Vector3.UP)
	elif step == 8:
		cam.position = Vector3(46, 16.0, 42)
		cam.look_at(Vector3(46, 3.0, -8.0), Vector3.UP)
	else:
		cam.position = Vector3(30, 20, 26)
		cam.look_at(Vector3(12, 3, 6.5), Vector3.UP)


## The Ch 32/33 ENGINE captions require the Output panel's lines IN
## the frame; the default editor layout starts with it collapsed.
## Godot 4.7's bottom panel tabs are drawn and hit-tested by the
## internal EditorBottomPanel control itself — a full tree dump
## contains no "Output" Button to press (an earlier version of
## this function searched for one and silently did nothing, so
## ENGINE grabs kept landing on a collapsed panel). The faithful
## equivalent of the reader's click on the Output tab is a
## simulated click pushed through the editor window's viewport
## at the tab's position (the DungeonStage pattern). The click is
## a TOGGLE, though, and the editor restores the previous
## session's panel state unpredictably — so _expand_output_panel
## reads the editor window's own pixels and clicks until the
## log's text is measurably on screen (see _output_panel_open).
func _expand_output_panel() -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	# The click toggles, and the editor restores the previous
	# session's panel state unpredictably (the layout save races
	# the capture wrapper's kill), so do not guess: read the
	# editor window's own pixels and click until the log's text
	# is measurably on screen.
	for attempt in range(4):
		if _output_panel_open(base):
			return
		_click_output_tab(base)
		await get_tree().create_timer(0.7).timeout


func _click_output_tab(base: Control) -> void:
	var vp: Viewport = base.get_viewport()
	var pos := Vector2(320, 1056)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev)


## Is the Output log on screen? Sample the strip where the log's
## text lines sit when the panel is open (y 840..1000): open, it
## is full of light text pixels; closed, it is empty dark canvas.
func _output_panel_open(base: Control) -> bool:
	var tex: ViewportTexture = base.get_viewport().get_texture()
	if tex == null:
		return false
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 1600 or img.get_height() < 1000:
		return false
	var bright: int = 0
	var y: int = 840
	while y < 1000:
		var x: int = 300
		while x < 1600:
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.55 and c.g > 0.55 and c.b > 0.55:
				bright += 1
				if bright > 40:
					return true
			x += 7
		y += 7
	return false
