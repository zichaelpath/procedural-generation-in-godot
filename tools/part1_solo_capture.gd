extends Node
## Part I solo-preview RENDER capture — worker tool, NOT a book listing.
##
## Instantiates the real environments stage (so the stage's own _ready()
## pipeline produces the data), takes one named preview's texture, shows
## it full-screen in a square window, saves the viewport, and quits.
## This produces the book's "preview full screen" RENDER shots
## (e.g. ch07-rivers-render = FlowPreview alone) without altering the
## chapter stage files.
##
## Usage:
##   DISPLAY=:99 ~/.local/bin/godot --path ~/procgen-book-project \
##     res://tools/part1_solo_capture.tscn -- \
##     --preview=FlowPreview --out=/abs/path.png [--montreal=1]

var _preview: String = ""
var _montreal: bool = false
var _out: String = ""
var _frames_wait: int = 30
var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			_preview = arg.trim_prefix("--preview=")
		elif arg.begins_with("--montreal="):
			_montreal = arg.trim_prefix("--montreal=") == "1"
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_frames_wait = int(arg.trim_prefix("--frames="))
	if _preview == "" or _out == "":
		push_error("part1_solo_capture: --preview= and --out= are required")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1080, 1080)
	var packed: PackedScene = load("res://stages/stage_1_environments.tscn") as PackedScene
	if packed == null:
		push_error("part1_solo_capture: cannot load the environments stage")
		get_tree().quit(2)
		return
	var stage: Node = packed.instantiate()
	if _montreal:
		stage.set("use_montreal", true)
	add_child(stage)
	var rect: TextureRect = stage.get_node("UI/Previews/" + _preview) as TextureRect
	if rect == null or rect.texture == null:
		push_error("part1_solo_capture: preview has no texture: " + _preview)
		get_tree().quit(3)
		return
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var full := TextureRect.new()
	full.texture = rect.texture
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	full.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(full)
	var ui: CanvasLayer = stage.get_node("UI") as CanvasLayer
	ui.visible = false
	if _montreal:
		var d: TerrainHeight = stage.get("data") as TerrainHeight
		if d != null:
			var lookout := Vector2(679.0, 334.0)
			var cs: float = d.cell_size()
			var lix: int = roundi((lookout.x + d.world_size * 0.5) / cs)
			var liz: int = roundi((lookout.y + d.world_size * 0.5) / cs)
			var lmax: float = 0.0
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					lmax = maxf(lmax, d.grid_height(lix + dx, liz + dz))
			var gmax: float = 0.0
			for h in d.heights:
				gmax = maxf(gmax, h)
			print("SOLO_VERIFY lookout cell=(", lix, ",", liz, ") h=",
					d.grid_height(lix, liz), " local9x9max=", lmax,
					" globalmax=", gmax, " lookout_biome=", d.biome_at(lix, liz))
	print("SOLO_CAPTURE armed preview=", _preview, " montreal=", _montreal, " out=", _out)
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
		push_error("part1_solo_capture: viewport image is empty")
		get_tree().quit(3)
		return
	var err: Error = img.save_png(_out)
	print("SOLO_CAPTURED ", _out, " size=", img.get_size(), " err=", err)
	get_tree().quit(0 if err == OK else 3)
