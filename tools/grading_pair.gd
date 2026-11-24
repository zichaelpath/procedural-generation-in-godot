extends Node

## Grading before/after pair (Fix Round 2 captures — Ch 42's grading
## section). Instances the real stage_8_cities at step 10 and poses its
## camera at step 10's worst pre-fix slope crossing: street road 31,
## segment nodes 83->84, clearance-audit sample point (260.7, 300.2),
## where the BEFORE audit measured max poke 8.663 m.
##
## ONE fixed pose serves both shots. In auto mode the pose is computed
## in-scene from the segment's actual node positions and printed as
## GRADING_POSE; the before shot is then taken with that exact pose
## passed back in via --pos=/--look=, so the two frames are pixel-
## comparable even though the terrain under the camera differs.
##
## Usage: DISPLAY=:99 godot --path . res://tools/grading_pair.tscn -- \
##   --out=/abs/path.png [--pos=x,y,z --look=x,y,z]
## Exit code is non-zero if the stage or the save fails.

const SAMPLE := Vector2(260.7, 300.2) # clearance audit's worst sample (XZ)
const NODE_A := 83
const NODE_B := 84

var _out: String = ""
var _pos_arg: String = ""
var _look_arg: String = ""
var _frames: int = 0
var _done: bool = false
var _stage: Node = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--pos="):
			_pos_arg = arg.trim_prefix("--pos=")
		elif arg.begins_with("--look="):
			_look_arg = arg.trim_prefix("--look=")
	if _out == "":
		push_error("grading_pair: --out= required")
		get_tree().quit(2)
		return
	var packed: PackedScene = load("res://stages/stage_8_cities.tscn") as PackedScene
	_stage = packed.instantiate()
	add_child(_stage)
	_stage.set("step", 10)
	if _stage.has_method("rebuild"):
		_stage.call("rebuild")
	_pose_camera()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _parse_vec(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _pose_camera() -> void:
	var cam: Camera3D = _stage.find_child("Camera", true, false) as Camera3D
	if cam == null:
		push_error("grading_pair: no camera found")
		return
	cam.current = true
	var pos: Vector3
	var look: Vector3
	if _pos_arg != "" and _look_arg != "":
		pos = _parse_vec(_pos_arg)
		look = _parse_vec(_look_arg)
		print("GRADING_POSE source=arg pos=", pos, " look=", look)
	else:
		var network: RoadNetwork = _stage.get("network")
		var terrain: TerrainHeight = _stage.get("terrain")
		var a3: Vector3 = network.nodes[NODE_A]
		var b3: Vector3 = network.nodes[NODE_B]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var along: Vector2 = (b - a).normalized()
		var perp := Vector2(-along.y, along.x)
		var road_h: float = terrain.height_at(SAMPLE.x, SAMPLE.y)
		# Low oblique: 23.3 m from the sample point (20 m back along the
		# segment, 12 m to the side), 5 m above the road surface at the
		# sample, looking at a point 6 m past the sample along the road,
		# 1 m above the surface — the terrain crossing the asphalt
		# mid-segment reads clearly from here.
		var cam_xz: Vector2 = SAMPLE - along * 20.0 + perp * 12.0
		pos = Vector3(cam_xz.x, road_h + 5.0, cam_xz.y)
		var look_xz: Vector2 = SAMPLE + along * 6.0
		look = Vector3(look_xz.x, road_h + 1.0, look_xz.y)
		print("GRADING_POSE source=auto nodeA=", a3, " nodeB=", b3,
			" sample=", SAMPLE, " road_h=", snappedf(road_h, 0.001),
			" pos=", pos, " look=", look)
	cam.far = 9000.0
	cam.near = 0.5
	cam.global_position = pos
	if pos.distance_squared_to(look) > 0.001:
		cam.look_at(look, Vector3.UP)


func _on_frame_post_draw() -> void:
	if _done:
		return
	_frames += 1
	if _frames < 45:
		return
	_done = true
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("grading_pair: viewport image empty")
		get_tree().quit(3)
		return
	var err: Error = img.save_png(_out)
	print("GRADING_CAPTURED ", _out, " size=", img.get_size(), " err=", err)
	get_tree().quit(0 if err == OK else 3)
