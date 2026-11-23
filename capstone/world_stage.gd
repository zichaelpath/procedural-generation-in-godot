@tool
extends Node3D

## stage_9_world: the capstone stage. Step selector + seed field +
## Return Test button, in the pattern of every stage since Ch 5.
## Steps are fixed in Ch 43 §43.5's table and used by Chs 44–45.
##
## Harness adaptations (Listing 43.7's body kept; see Part IX build
## report): the file is @tool like every stage since Ch 5 so the
## editor itself can generate for ENGINE captures; step/master_seed
## carry StageBase-style setters; rebuild() is the harness entry the
## book_stage plugin and tools/book_capture.gd call; camera presets
## answer book_capture's --camera names (preset / low / entrance /
## tier / final); and the /tmp/book_stage_directive.txt arrangement
## follows terrain_stage.gd's established pattern, extended with
## profiler= and returntest= keys for Ch 43/44's Output shots.

@export var step: int = 6:
	set(value):
		step = value
		if is_inside_tree() and is_node_ready():
			_sync_config()
			rebuild()
@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if is_inside_tree() and is_node_ready():
			_sync_config()
			rebuild()
@export var view_radius_chunks: int = 7
## Ch 44's quality tier (Listing 44.3): consulted before generation;
## it moves the ring radius on the config and hands the garnish
## scales to the builder. The skeleton never negotiates (§44.4).
@export var quality_tier: String = "high"

var config: WorldConfig
var _tier: Dictionary = {}

var _built_step: int = -1
var _built_seed: int = -1
var _stats_frame: int = -1

@onready var builder: WorldBuilder = $WorldBuilder


func _ready() -> void:
	_sync_config()
	# With a capture directive present, the plugin + arrangement own
	# the generation sequence; generating here too would only repeat
	# the same world twice more before the shot.
	if Engine.is_editor_hint() and FileAccess.file_exists(DIRECTIVE_PATH):
		_arrange_from_directive()
		return
	rebuild()


func _sync_config() -> void:
	if config == null:
		config = WorldConfig.new()
	config.master_seed = master_seed
	config.view_radius_chunks = view_radius_chunks
	# The tier owns the ring (§44.4: apply() moves exactly this
	# field) — re-apply on every sync, because the harness's export
	# setters call _sync_config again after the first application
	# and would silently restore the stage's stored radius.
	_tier = WorldQuality.apply(quality_tier, config)


## Harness entry (plugin + book_capture): regenerate only when the
## requested (step, seed) actually changed — the harness sets the
## exports AND calls rebuild(), and one of the two must be a no-op.
func rebuild() -> void:
	if builder == null:
		return
	if _built_step == step and _built_seed == master_seed:
		return
	_generate()


func regenerate() -> void:
	_generate()


func _generate() -> void:
	_sync_config()
	builder.scatter_density_scale = float(_tier.get("scatter_density_scale", 1.0))
	print("[stage] quality tier: ", quality_tier, " (ring ", config.view_radius_chunks, ", scatter x", builder.scatter_density_scale, ")")
	builder.generate_all(step, config)
	_built_step = step
	_built_seed = master_seed
	$UI/TitleLabel.text = "Stage 9 — One Seed, Whole World (step %d)" % step
	$UI/FlowLabel.text = "seed %d · steps 0 tree · 1 terrain+water · 2 chunks+plants · 3 roads+edits · 4 parcels · 5 buildings · 6 entrances" % master_seed
	var pump: Node = get_node_or_null("ThreadedChunkPump")
	if pump != null and not Engine.is_editor_hint() and builder.terrain != null:
		pump.setup(builder.chunk_manager, builder.terrain, config)
	_stats_frame = 0


## Ch 44's frame numbers, sampled once the built world has actually
## rendered for a few dozen frames under whichever camera the
## harness chose — the profiler's table and the tier frames must
## describe the same moment (§44.1's walkthrough).
func _process(_delta: float) -> void:
	if _stats_frame < 0:
		return
	_stats_frame += 1
	if _stats_frame == 40:
		_stats_frame = -1
		print("[frame] tier ", quality_tier, " · draw calls in frame: ",
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			" · live nodes: ", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			" · video memory MB: ", snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1))


func run_return_test() -> void:
	var test := ReturnTest.new()
	test.run(builder, step, config)
	_built_step = step
	_built_seed = master_seed


func run_profiler() -> void:
	var profiler := WorldProfiler.new()
	profiler.print_budget(builder)


# --- Camera presets (book_capture --camera names) -----------------

## "preset" = the high orbit over the whole island; "low" = street
## level on the steepest terraced road segment the world actually
## built; "entrance" = eye level at entrance_0's prop; "tier" = the
## stage's marked TierCamera (Ch 44's fixed tier-comparison frame);
## "final" = the TierCamera pulled back along its road (Ch 45).
func apply_camera_preset_by_name(preset_name: String) -> void:
	var rig: Node3D = get_node_or_null("PlayerRig") as Node3D
	var rig_cam: Camera3D = get_node_or_null("PlayerRig/Camera3D") as Camera3D
	var tier_cam: Camera3D = get_node_or_null("TierCamera") as Camera3D
	if rig == null or rig_cam == null:
		return
	if preset_name == "tier" and tier_cam != null:
		rig_cam.current = false
		tier_cam.current = true
		return
	rig_cam.current = true
	if tier_cam != null:
		tier_cam.current = false
	match preset_name:
		"ground":
			# Ch 43's street-level frame: on the one placed tower's
			# street, looking down its terraced bench toward the
			# borough centre — the tower stands on its flattened
			# parcel at frame left, parcels either side.
			rig.position = Vector3(-26.0, 18.6, 100.0)
			rig.look_at(Vector3(-31.0, 14.8, 55.0), Vector3.UP)
		"low":
			if not _frame_steepest_road(rig):
				rig.position = Vector3(0.0, 26.0, 150.0)
				rig.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
		"entrance":
			if not _frame_entrance(rig):
				rig.position = Vector3(14.0, 24.0, 54.0)
				rig.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
		"final":
			if tier_cam != null:
				var t: Transform3D = tier_cam.global_transform
				var fwd: Vector3 = -t.basis.z.normalized()
				rig.position = t.origin - fwd * 70.0 + Vector3.UP * 16.0
				rig.look_at(t.origin + fwd * 60.0, Vector3.UP)
			else:
				rig.position = Vector3(0.0, 120.0, 330.0)
				rig.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
		_: # "preset" — high orbit, whole ring in frame
			rig.position = Vector3(0.0, 560.0, 680.0)
			rig.rotation_degrees = Vector3(-38.0, 0.0, 0.0)


func _frame_steepest_road(rig: Node3D) -> bool:
	if builder == null or builder.network == null:
		return false
	var net: RoadNetwork = builder.network
	var best: float = 2.0
	var best_a := Vector3.ZERO
	var best_b := Vector3.ZERO
	for segment: Dictionary in net.segments:
		var ends: Array[Vector2] = builder._segment_ends(segment)
		var a3 := Vector3(ends[0].x, builder.terrain.height_at(ends[0].x, ends[0].y), ends[0].y)
		var b3 := Vector3(ends[1].x, builder.terrain.height_at(ends[1].x, ends[1].y), ends[1].y)
		var dh: float = absf(a3.y - b3.y)
		if dh > best and a3.distance_to(b3) > 25.0:
			best = dh
			best_a = a3
			best_b = b3
	if best <= 2.0:
		return false
	var dir3: Vector3 = (best_b - best_a).normalized()
	rig.position = best_a - dir3 * 12.0 + Vector3.UP * 2.4 + Vector3(-dir3.z, 0.0, dir3.x) * 5.0
	rig.look_at(best_b + Vector3.UP * 1.2, Vector3.UP)
	print("[camera] low preset: terraced segment ", best_a, " -> ", best_b, " (drop ", snappedf(best, 0.1), " m)")
	return true


func _frame_entrance(rig: Node3D) -> bool:
	if builder == null or builder.entrances.is_empty():
		return false
	var centre: Vector2 = builder.entrances[0]["centre"]
	var h: float = builder.terrain.height_at(centre.x, centre.y)
	# Stand on the prop's FRONT: the housing's door and descending
	# steps face its local +Z (DungeonEntrances._build_prop), and the
	# prop is rotated to its parcel's frontage — a fixed world offset
	# can end up behind it, where the prop reads as a plain box.
	var prop: Node3D = builder.find_child("Entrance_0", true, false) as Node3D
	if prop != null:
		var front: Vector3 = prop.global_transform.basis.z
		front.y = 0.0
		front = front.normalized()
		var base: Vector3 = prop.global_position
		rig.position = base + front * 10.0 + Vector3.UP * 1.7
		rig.look_at(base + Vector3.UP * 0.9, Vector3.UP)
	else:
		rig.position = Vector3(centre.x + 8.0, h + 1.7, centre.y + 9.0)
		rig.look_at(Vector3(centre.x, h + 1.0, centre.y), Vector3.UP)
	print("[camera] entrance preset: entrance_0 at ", centre, " h=", snappedf(h, 0.1))
	return true


# --- Editor arrangement for ENGINE captures -----------------------
# tools/capture_engine2.sh writes a directive file before launching
# the editor; after the shared book_stage plugin has done its own
# arrangement (step=2, root selected), this applies the shot's real
# step / flags and writes the arranged file the wrapper polls for.
# Extra keys vs terrain_stage: profiler=1, returntest=1.

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"


func _arrange_from_directive() -> void:
	await get_tree().create_timer(6.0).timeout
	var txt: String = FileAccess.get_file_as_string(DIRECTIVE_PATH)
	var want_step: int = step
	var want_select: String = ""
	var want_profiler: bool = false
	var want_returntest: bool = false
	for line: String in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
		elif line.begins_with("profiler="):
			want_profiler = line.trim_prefix("profiler=") == "1"
		elif line.begins_with("returntest="):
			want_returntest = line.trim_prefix("returntest=") == "1"
	step = want_step # setter rebuilds at the requested step
	rebuild() # no-op if the setter already built it
	if want_returntest:
		run_return_test()
	if want_profiler:
		run_profiler()
	EditorInterface.set_main_screen_editor("3D")
	_frame_editor_camera()
	_expand_scene_tree()
	_open_output_panel()
	var node: Node = self
	if want_select != "" and want_select != "root":
		var found: Node = find_child(want_select, true, false)
		if found != null:
			node = found
	_select_in_editor(node)
	await get_tree().create_timer(1.0).timeout
	_select_in_editor(node)
	var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("arranged step=%d select=%s profiler=%d returntest=%d\n" % [step, want_select, int(want_profiler), int(want_returntest)])
		f.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)


func _select_in_editor(node: Node) -> void:
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


func _open_output_panel() -> void:
	# Press the editor's "Output" bottom-panel button (there is no
	# public API for the built-in panels; the button is findable).
	# Godot 4.7's bottom-panel tabs are custom-drawn (no Button or
	# TabBar node carries them), so this scan finds nothing on this
	# version and the capture wrapper opens the panel with a real
	# double-click on the tab instead. The scan stays for older/newer
	# editors where the tab IS a Button.
	var stack: Array[Node] = [EditorInterface.get_base_control()]
	var target: BaseButton = null
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			var b := n as Button
			if b.text == "Output" or b.tooltip_text == "Output":
				target = b
		for ch: Node in n.get_children():
			stack.append(ch)
	if target != null:
		if target.toggle_mode:
			target.set_pressed(true)
		else:
			target.emit_signal("pressed")


func _frame_editor_camera() -> void:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var t := Transform3D.IDENTITY.translated(Vector3(0.0, 300.0, 430.0))
	t = t.looking_at(Vector3(0.0, 10.0, 0.0), Vector3.UP)
	cam.global_transform = t


func _expand_scene_tree() -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var trees: Array[Tree] = []
	_collect_trees(base, trees)
	for t: Tree in trees:
		var root_item: TreeItem = t.get_root()
		if root_item != null and root_item.get_text(0) == name:
			_expand_item(root_item)


func _collect_trees(node: Node, out: Array[Tree]) -> void:
	if node is Tree:
		out.append(node as Tree)
	for child: Node in node.get_children():
		_collect_trees(child, out)


func _expand_item(item: TreeItem) -> void:
	item.set_collapsed(false)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_expand_item(child)
		child = child.get_next()
