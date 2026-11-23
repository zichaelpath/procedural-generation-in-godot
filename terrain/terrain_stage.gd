@tool
extends Node3D

## Part II stage: builds Part I's TerrainHeight data and shows it as a
## mesh. The `step` export is the part's screenshot contract:
##   0 = raw noise heights (no falloff), grey smooth mesh
##   1 = the Part I island (falloff in the data), grey smooth mesh
##   2 = island + ramp colours + water plane
##   3 = + domain warp (Ch10)          4 = ridged variant (Ch10)
##   5 = + hydraulic erosion (Ch11)    6 = + thermal erosion (Ch11)
##   7 = splat material (Ch12)         8 = chunked grid (Ch13)
##   9 = LOD rings + streaming + origin rebasing (Ch14)
## Later chapters APPEND steps; steps never change meaning.
##
## (Chapter 9, Listing 9.5, extended by the listings of Ch10-Ch14.)
## Integration notes:
## - @tool + rebuild()/apply_camera_preset_by_name() are the project
##   capture harness's interface (tools/book_capture.gd); the chapter's
##   plain runtime script cannot be screenshotted by the book's tools.
## - The stage gates Ch11's erosion per step through the data's own
##   erode_droplets / thermal_iterations (0 = no work), because
##   generate() runs the passes unconditionally from Ch11 on and the
##   step contract requires steps 0-4 to stay un-eroded.
## - Steps 0-2 run with warp_strength = 0: Ch10's generate_heights()
##   warps unconditionally, which would silently change steps 0-2 and
##   break the contract that they are "unchanged from Ch9". Step 3 is
##   where the warp arrives, exactly as Ch10's stage note describes.
## - config.sea_level is set to the chapter value 5.0 (Listing 5.1) on
##   the stage's own config instance; the project WorldConfig default
##   (0.0) belongs to the proof-stage family and is left untouched.
## - Camera presets beyond the book's standard one ("preset") are
##   named stage presets for shots whose captions demand them:
##   "low" (shoreline), "closeup" (slope/cliff base), "high" (chunk
##   grid orbit), "rings" (LOD orbit), "rebase" (player POV post-flight).

@export var step: int = 2:
	set(value):
		step = value
		if _built:
			_build()

@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if _built:
			_build()

@export var run_benchmark: bool = false

var data: TerrainHeight
var config: WorldConfig

var _built: bool = false
var _chunk_terrain: TerrainHeight

@onready var terrain_mesh: TerrainMesh = $TerrainMesh
@onready var water: MeshInstance3D = $Water
@onready var sun: DirectionalLight3D = $Sun
@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var player_rig: Node3D = $PlayerRig
@onready var stage_camera: Camera3D = $CameraRig/Camera3D
@onready var player_camera: Camera3D = $PlayerRig/Camera3D
@onready var hud_label: Label = $DebugUI/HUDLabel

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"


func _ready() -> void:
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_built = true
	_build()
	apply_camera_preset_by_name("preset")
	if Engine.is_editor_hint() and FileAccess.file_exists(DIRECTIVE_PATH):
		_arrange_from_directive()


## The capture harness (tools/book_capture.gd) calls rebuild() after
## setting step/seed; the editor plugin calls it too.
func rebuild() -> void:
	_build()


func _build() -> void:
	if not _built or terrain_mesh == null:
		return
	config = WorldConfig.new()
	config.master_seed = master_seed
	config.sea_level = 5.0  # Listing 5.1's chapter value; see header note
	if step <= 7:
		_build_island()
	else:
		_build_chunks()
	if run_benchmark and step == 9:
		_run_benchmark()
	if _seabed != null:
		_seabed.visible = water.visible
	_update_hud()


func _build_island() -> void:
	data = TerrainHeight.new()
	data.falloff_mode = 0 if step == 0 else 1
	data.warp_strength = 35.0 if step >= 3 else 0.0
	data.variant = 1 if step == 4 else 0
	data.erode_droplets = 30000 if step >= 5 else 0
	data.thermal_iterations = 40 if step >= 6 else 0
	data.erosion_preview = false
	data.thermal_preview = false
	data.generate(config)
	if step >= 5:
		# Erosion parameters are seed jewellery: log them per generation
		# (Chapter 11, §11.3 — the step-6 engine shot shows this line).
		print("EROSION params: droplets=%d talus=%.2f iterations=%d preview=false"
				% [data.erode_droplets, data.thermal_talus, data.thermal_iterations])
	terrain_mesh.visible = true
	chunk_manager.visible = false
	player_rig.visible = false
	terrain_mesh.grey_mode = step <= 1
	terrain_mesh.use_biome_colors = step == 7
	terrain_mesh.use_splat = step == 7
	terrain_mesh.flat_shaded = false
	terrain_mesh.rebuild(data)
	_build_water(1200.0, data.sea_level)
	water.visible = step >= 2


func _build_chunks() -> void:
	terrain_mesh.visible = false
	player_rig.visible = true
	chunk_manager.visible = true
	_chunk_terrain = TerrainHeight.new()
	_chunk_terrain.use_noise_field(config)
	chunk_manager.setup(_chunk_terrain, config)
	# The manager streams whenever it has a terrain and a player —
	# including at step 8, where Ch13 wants ONLY the fixed grid.
	# Gate its _process (the streamer) to step 9.
	chunk_manager.set_process(step == 9)
	# The manager's `player` export is also assigned in the scene
	# (Inspector, per Listing 13.6); wire it here too — in the capture
	# build the exported NodePath had not resolved when _build ran.
	chunk_manager.player = player_rig
	chunk_manager.tint_by_lod = step == 9
	chunk_manager.debug_tint_chunks = step == 8
	# Fresh manager state for this build (nodes are children; the rest
	# is the manager's own bookkeeping dictionaries).
	for child in chunk_manager.get_children():
		chunk_manager.remove_child(child)
		child.free()
	chunk_manager.chunks.clear()
	chunk_manager.data_cache.clear()
	chunk_manager._built_step.clear()
	chunk_manager._pool.clear()
	chunk_manager._queue.clear()
	chunk_manager.origin_offset = Vector2i.ZERO
	chunk_manager._last_focus = Vector2i(999999, 999999)
	if step == 9 and not Engine.is_editor_hint():
		# Capture-scale streaming area (7x7 chunks): the listing radii
		# (8/10/16) describe a shipping game; the stage's LOD rings must
		# be visible inside one screenshot. Radii are manager vars, so
		# this is configuration, not a code change.
		chunk_manager.load_radius_chunks = 3
		chunk_manager.unload_radius_chunks = 4
		chunk_manager.data_evict_radius_chunks = 6
		player_rig.position = Vector3(0.0, 30.0, 40.0)
	if step == 8 or Engine.is_editor_hint():
		chunk_manager.build_fixed_grid()
		if Engine.is_editor_hint():
			# Owned children appear in the Scene dock (the step-8 engine
			# shot's subject). Runtime builds keep owner unset, per the
			# project rule that generated nodes are never baked on save;
			# the capture flow never saves the scene.
			var edited_root: Node = get_tree().edited_scene_root
			if edited_root != null:
				for child in chunk_manager.get_children():
					child.owner = edited_root
	_build_water(6000.0, _chunk_terrain.sea_level)
	# Step 8's shot is the tint quilt itself: hide the sea so the
	# below-sea-level chunks still read as patches of one landmass.
	# Step 9 keeps the water (the rebase portrait is a player view).
	water.visible = step == 9


var _seabed: MeshInstance3D

func _build_water(size_m: float, sea_y: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15  # low roughness: the sun glints on the water
	water.material_override = mat
	water.position.y = sea_y
	# A deep floor under the whole sea (the proof stage's fix): without
	# it the translucent water shows the sky's ground colour beyond the
	# terrain patch and the patch edge reads as a square outline.
	if _seabed == null:
		_seabed = MeshInstance3D.new()
		_seabed.name = "Seabed"
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.04, 0.16, 0.28)
		smat.roughness = 1.0
		_seabed.material_override = smat
		add_child(_seabed)
	var splane := PlaneMesh.new()
	splane.size = Vector2(size_m, size_m)
	_seabed.mesh = splane
	_seabed.position.y = sea_y - 8.5


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# A slowly rotating sun: moving light is a lie detector for normals.
	sun.rotation_degrees.y -= delta * 2.0
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	if Engine.is_editor_hint():
		hud_label.visible = false
		return
	hud_label.visible = step == 9
	if step == 9 and chunk_manager != null and chunk_manager.terrain != null:
		var wp: Vector2 = chunk_manager.player_world_position()
		hud_label.text = ("origin_offset %s · player world (%.0f, %.0f) · scene (%.0f, %.0f) · chunks %d"
			% [str(chunk_manager.origin_offset), wp.x, wp.y,
				player_rig.position.x, player_rig.position.z,
				chunk_manager.chunks.size()])
	elif step == 8 and chunk_manager != null:
		hud_label.text = ("chunks %d · data cached %d"
			% [chunk_manager.chunks.size(), chunk_manager.data_cache.size()])


# --- Chapter 14, Listing 14.1: the square-law benchmark ---

func _run_benchmark() -> void:
	print("--- Terrain build benchmark (single mesh, Chapter 9 builder) ---")
	print("cells | vertices | build ms | approx tris")
	for cells in [128, 256, 512]:
		var field: HeightField = FieldGenerators.fractal_height_field(
				20261119, cells + 1, 400.0 / float(cells))
		var bench_terrain := TerrainHeight.new()
		bench_terrain.cells = cells
		bench_terrain.load_grid(field.heights, cells + 1, 400.0, 30.0)
		var t0: int = Time.get_ticks_msec()
		var probe := TerrainMesh.new()
		probe.rebuild(bench_terrain)
		var ms: int = Time.get_ticks_msec() - t0
		var verts: int = (cells + 1) * (cells + 1)
		print("%d | %d | %d ms | %d" % [cells, verts, ms, cells * cells * 2])
		probe.free()
	print("--- end benchmark ---")


# --- Camera presets (called by tools/book_capture.gd) ---

func apply_camera_preset_by_name(preset_name: String) -> void:
	if stage_camera == null:
		return
	match preset_name:
		"low":
			_use_stage_camera(_shoreline_camera_pos(), Vector3(-6.0, 0.0, 0.0))
		"closeup":
			_use_closeup_camera()
		"high":
			_use_stage_camera(Vector3(0.0, 350.0, 160.0), Vector3(-68.0, 0.0, 0.0))
		"rings":
			_use_stage_camera(Vector3(0.0, 165.0, 260.0), Vector3(-37.0, 0.0, 0.0))
		"rebase":
			_use_player_camera_rebase()
		_:
			_use_stage_camera(Vector3(0.0, 175.0, 305.0), Vector3(-34.0, 0.0, 0.0))


func _use_stage_camera(pos: Vector3, rot_deg: Vector3) -> void:
	stage_camera.position = pos
	stage_camera.rotation_degrees = rot_deg
	if not Engine.is_editor_hint():
		stage_camera.current = true
		player_camera.current = false


func _shoreline_camera_pos() -> Vector3:
	# Find the OUTERMOST land on the +Z centre column, stand off its
	# shore over the water, low: the waterline crosses the frame
	# (Ch12 shoreline shot).
	if data != null and not data.heights.is_empty():
		var centre: int = data.cells / 2
		var last_land: int = -1
		for iz in range(centre, data.cells + 1):
			if data.grid_height(centre, iz) >= data.sea_level + 0.4:
				last_land = iz
		if last_land >= 0:
			var shore: Vector2 = data.grid_to_world(centre, last_land)
			return Vector3(0.0, data.sea_level + 4.5, shore.y + 30.0)
	return Vector3(0.0, 10.0, 168.0)


func _use_closeup_camera() -> void:
	# Ground level at a steep face: scan the data for the STEEPEST
	# slope in the mid heights, stand the camera at its base
	# (Ch11 thermal aprons / Ch12 splat close-up).
	if data != null and not data.heights.is_empty():
		var best_slope: float = 0.01  # slope_at is 1-cos: real faces score 0.02-0.10
		var best := Vector3.ZERO
		var found: bool = false
		for iz in range(8, data.cells - 8):
			for ix in range(8, data.cells - 8):
				var h: float = data.grid_height(ix, iz)
				if h < 8.0 or h > 26.0:
					continue
				var wp: Vector2 = data.grid_to_world(ix, iz)
				# Interior only: the falloff rim is the steepest ground
				# on the island, but a rim shot is a shoreline, not a
				# cliff base. Require land all around (12 m radius).
				var interior: bool = true
				for off in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12)]:
					if data.height_at(wp.x + off.x, wp.y + off.y) < data.sea_level + 2.5:
						interior = false
						break
				if not interior:
					continue
				var s: float = data.slope_at(wp.x, wp.y)
				if s > best_slope:
					best_slope = s
					best = Vector3(wp.x, h, wp.y)
					found = true
		if found:
			var target := best + Vector3(0.0, 1.2, 0.0)
			stage_camera.position = target + Vector3(12.0, 3.5, 16.0)
			stage_camera.look_at(target, Vector3.UP)
			if not Engine.is_editor_hint():
				stage_camera.current = true
				player_camera.current = false
			return
	_use_stage_camera(Vector3(0.0, 175.0, 305.0), Vector3(-34.0, 0.0, 0.0))


func _use_player_camera_rebase() -> void:
	# The long flight, pre-flown for the capture: teleport past the
	# 1024 m threshold; the manager rebases on its first frames and the
	# HUD readout (DebugUI) shows the absorbed origin_offset (Ch14).
	player_rig.position = Vector3(1500.0, 62.0, 120.0)
	player_rig.rotation = Vector3(-0.32, 0.5, 0.0)
	if not Engine.is_editor_hint():
		player_camera.current = true
		stage_camera.current = false


# --- Editor arrangement for ENGINE captures ---
# tools/capture_engine2.sh writes a directive file before launching
# the editor; after the shared book_stage plugin has done its own
# arrangement (step=2, root selected), this applies the shot's real
# step / selection / benchmark flag and writes the arranged file the
# wrapper polls for. No directive file = no arrangement (normal use).

func _arrange_from_directive() -> void:
	await get_tree().create_timer(6.0).timeout
	var txt: String = FileAccess.get_file_as_string(DIRECTIVE_PATH)
	var want_step: int = step
	var want_select: String = ""
	var want_bench: bool = false
	for line in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
		elif line.begins_with("benchmark="):
			want_bench = line.trim_prefix("benchmark=") == "1"
	if want_bench:
		run_benchmark = true
	step = want_step  # setter rebuilds at the requested step
	var node: Node = self
	if want_select != "" and want_select != "root":
		var found: Node = find_child(want_select, true, false)
		if found != null:
			node = found
	EditorInterface.set_main_screen_editor("3D")
	_frame_editor_camera()
	_expand_scene_tree()
	if step >= 5 or want_bench:
		# Ch11's shot shows the EROSION line and Ch14's the benchmark
		# table — both live in the Output bottom panel.
		_open_output_panel()
	# Selection goes LAST and twice: expanding the tree / switching
	# screens can drop it back to the root (the step-8 shot lost its
	# ChunkManager selection to exactly that).
	_select_in_editor(node)
	await get_tree().create_timer(1.0).timeout
	_select_in_editor(node)
	if want_bench:
		# The benchmark blocks the editor's main thread for seconds;
		# give the 3D viewport time to present again (it otherwise
		# still shows the boot splash at capture) and re-frame.
		await get_tree().create_timer(5.0).timeout
		_frame_editor_camera()
	var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("arranged step=%d select=%s\n" % [step, want_select])
		f.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)


func _select_in_editor(node: Node) -> void:
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


func _open_output_panel() -> void:
	# Press the editor's "Output" bottom-panel button (there is no
	# public API for the built-in panels; the button is findable).
	# The bottom-panel buttons are toggles: set_pressed shows the
	# panel; a bare "pressed" emit does not latch it. The button
	# inventory is written to /tmp/dbg_buttons.txt as a diagnostic:
	# under multi-worker editor contention this code path has been
	# observed not to run at all (shared editor instance, scene
	# already open), which the file's absence reveals.
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	var seen: Array = []
	var target: BaseButton = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			seen.append((n as BaseButton).text)
			if (n as BaseButton).text == "Output":
				target = n as BaseButton
		for ch in n.get_children():
			stack.append(ch)
	var f: FileAccess = FileAccess.open("/tmp/dbg_buttons.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("buttons=%d target=%s\n%s" % [seen.size(), str(target != null), "\n".join(seen)])
		f.close()
	if target != null:
		if target.toggle_mode:
			target.set_pressed(true)
		else:
			target.emit_signal("pressed")


func _frame_editor_camera() -> void:
	# The editor's 3D camera opens at the origin, inside the island;
	# the engine shots need the stage framed like the render preset.
	# The spatial editor's camera is a real Camera3D in its viewport.
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var t := Transform3D.IDENTITY.translated(Vector3(0.0, 175.0, 305.0))
	t = t.looking_at(Vector3.ZERO, Vector3.UP)
	cam.global_transform = t


func _expand_scene_tree() -> void:
	# Best effort: expand the Scene dock tree so grouped children (the
	# ChunkManager's 25 chunks) are visible in the shot.
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
