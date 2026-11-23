extends Node
## Capture harness — RENDER shots (PLAN.md §5, §7).
##
## Runs a stage scene OUTSIDE the editor (a real GPU render under Xvfb,
## never --headless), sets its step, waits for generation + a settle
## window of frames, saves the viewport to a PNG, and quits.
##
## Usage (from the project root, on the AI PC):
##   DISPLAY=:99 ~/.local/bin/godot --path ~/procgen-book-project \
##     res://tools/book_capture.tscn -- \
##     --stage=res://stages/stage_terrain_heightfield.tscn \
##     --step=2 --out=/absolute/path/ch09-heightfield-render.png
##
## Optional args: --seed=<int> (default: the stage's own master_seed),
## --camera=<preset|low> (default preset; see StageBase camera presets),
## --frames=<int> (settle frames before capture, default 45).
## Exit code is non-zero if the stage or the save fails.

var _stage_path: String = ""
var _step: int = -1
var _seed: int = -1
var _out: String = ""
var _camera: String = "preset"
var _frames_wait: int = 45
var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			_stage_path = arg.trim_prefix("--stage=")
		elif arg.begins_with("--step="):
			_step = int(arg.trim_prefix("--step="))
		elif arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_frames_wait = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--camera="):
			_camera = arg.trim_prefix("--camera=")
	if _stage_path == "" or _out == "":
		push_error("book_capture: --stage= and --out= are required")
		get_tree().quit(2)
		return
	var packed: PackedScene = load(_stage_path) as PackedScene
	if packed == null:
		push_error("book_capture: cannot load stage " + _stage_path)
		get_tree().quit(2)
		return
	var stage: Node = packed.instantiate()
	add_child(stage)
	if _seed >= 0 and stage.get("master_seed") != null:
		stage.set("master_seed", _seed)
	if _step >= 0 and stage.get("step") != null:
		stage.set("step", _step)
	if stage.has_method("rebuild"):
		stage.call("rebuild")
	if stage.has_method("apply_camera_preset_by_name"):
		stage.call("apply_camera_preset_by_name", _camera)
	print("BOOK_CAPTURE armed stage=", _stage_path, " step=", _step, " out=", _out)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _on_frame_post_draw() -> void:
	if _done:
		return
	_frames += 1
	if _frames < _frames_wait:
		return
	_done = true
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("book_capture: viewport image is empty")
		get_tree().quit(3)
		return
	var err: Error = img.save_png(_out)
	print("BOOK_CAPTURED ", _out, " size=", img.get_size(), " err=", err)
	get_tree().quit(0 if err == OK else 3)
