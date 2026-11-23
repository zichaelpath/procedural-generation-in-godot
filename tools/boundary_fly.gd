extends Node

## Boundary fly-through (validation frames for the Part VIII
## overlap fix — NOT book captures). Instances the real
## stage_8_cities, builds a step, poses its camera on the
## downtown/old_town territorial boundary, saves the viewport.
##
## Usage: DISPLAY=:99 godot --path . res://tools/boundary_fly.tscn -- \
##   --step=10 --mode=a --out=/abs/path.png
## Modes (step 10): a = aerial oblique over the boundary zone,
##   b = street level on the downtown<->old_town connector looking
##   along it, c = street level facing a clipped street end at the
##   boundary gap. Mode d (step 11) = aerial over the Montreal
##   downtown/old_town bisector.

var _step: int = 10
var _mode: String = "a"
var _out: String = ""
var _frames: int = 0
var _done: bool = false
var _stage: Node = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--step="):
			_step = int(arg.trim_prefix("--step="))
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _out == "":
		push_error("boundary_fly: --out= required")
		get_tree().quit(2)
		return
	var packed: PackedScene = load("res://stages/stage_8_cities.tscn") as PackedScene
	_stage = packed.instantiate()
	add_child(_stage)
	_stage.set("step", _step)
	if _stage.has_method("rebuild"):
		_stage.call("rebuild")
	_pose_camera()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _centres() -> Array:
	if _step == 11:
		var assembler := MontrealAssembler.new()
		var table: Array = assembler.borough_table()
		return [table[0]["centre"], table[1]["centre"]]
	return [BoroughCity.BOROUGHS[0]["centre"],
		BoroughCity.BOROUGHS[1]["centre"]]


func _pose_camera() -> void:
	var cam: Camera3D = _stage.find_child("Camera", true, false) as Camera3D
	if cam == null:
		push_error("boundary_fly: no camera found")
		return
	cam.current = true
	var terrain: TerrainHeight = _stage.get("terrain")
	var network: RoadNetwork = _stage.get("network")
	var centres: Array = _centres()
	var cd: Vector2 = centres[0]
	var co: Vector2 = centres[1]
	var mid: Vector2 = (cd + co) * 0.5
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	match _mode:
		"a":
			var h: float = terrain.height_at(mid.x, mid.y)
			pos = Vector3(mid.x - 130.0, h + 150.0, mid.y - 200.0)
			look = Vector3(mid.x, h, mid.y)
		"d":
			var h11: float = terrain.height_at(mid.x, mid.y)
			pos = Vector3(mid.x - 800.0, h11 + 950.0, mid.y - 1150.0)
			look = Vector3(mid.x, h11, mid.y)
			print("FLY d: bisector midpoint world = ", mid)
		"b":
			var pts := PackedVector3Array()
			for road in network.logic_roads:
				if String(road["kind"]) != "avenue":
					continue
				var rp: PackedVector3Array = road["points"]
				if rp.size() < 4:
					continue
				var f := Vector2(rp[0].x, rp[0].z)
				var l := Vector2(rp[rp.size() - 1].x, rp[rp.size() - 1].z)
				if (f.distance_to(cd) < 40.0 and l.distance_to(co) < 40.0) \
						or (f.distance_to(co) < 40.0 and l.distance_to(cd) < 40.0):
					pts = rp
					break
			if pts.is_empty():
				push_error("boundary_fly: connector not found")
				pos = Vector3(mid.x, terrain.height_at(mid.x, mid.y) + 60.0, mid.y - 80.0)
				look = Vector3(mid.x, terrain.height_at(mid.x, mid.y), mid.y)
			else:
				var k: int = int(float(pts.size()) * 0.35)
				var p: Vector3 = pts[k]
				var q: Vector3 = pts[mini(k + 6, pts.size() - 1)]
				pos = Vector3(p.x, terrain.height_at(p.x, p.z) + 2.2, p.z)
				look = Vector3(q.x, terrain.height_at(q.x, q.z) + 1.5, q.z)
				print("FLY b: connector cam at ", Vector2(p.x, p.z), " looking to ", Vector2(q.x, q.z), " (route points=", pts.size(), ")")
		"c":
			var dir: Vector2 = (co - cd).normalized()
			var plane_pt: Vector2 = mid - dir * (BoroughCity.BOUNDARY_GAP * 0.5)
			var best_end := Vector2.ZERO
			var best_prev := Vector2.ZERO
			var best_abs: float = 2.5
			var found: bool = false
			for road in network.logic_roads:
				if String(road["kind"]) != "street":
					continue
				var rp: PackedVector3Array = road["points"]
				if rp.size() < 2:
					continue
				for end_i in [0, rp.size() - 1]:
					var e := Vector2(rp[end_i].x, rp[end_i].z)
					var dplane: float = (e - plane_pt).dot(dir)
					if absf(dplane) >= best_abs:
						continue
					var prev_i: int = 1 if end_i == 0 else rp.size() - 2
					var pv := Vector2(rp[prev_i].x, rp[prev_i].z)
					if pv.distance_to(e) < 12.0:
						continue
					best_abs = absf(dplane)
					best_end = e
					best_prev = pv
					found = true
			if not found:
				push_error("boundary_fly: no clipped street end found")
				pos = Vector3(mid.x, terrain.height_at(mid.x, mid.y) + 40.0, mid.y - 60.0)
				look = Vector3(mid.x, terrain.height_at(mid.x, mid.y), mid.y)
			else:
				var along: Vector2 = (best_end - best_prev).normalized()
				var cam2: Vector2 = best_end - along * 7.0
				pos = Vector3(cam2.x, terrain.height_at(cam2.x, cam2.y) + 2.0, cam2.y)
				var look2: Vector2 = best_end + along * 4.0
				look = Vector3(look2.x, terrain.height_at(look2.x, look2.y) + 1.5, look2.y)
				print("FLY c: street end at ", best_end, " cam at ", cam2, " looking across gap to ", look2)
	print("FLY pose mode=", _mode, " step=", _step, " pos=", pos, " look=", look)
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
		push_error("boundary_fly: viewport image empty")
		get_tree().quit(3)
		return
	var err: Error = img.save_png(_out)
	print("FLY_CAPTURED ", _out, " size=", img.get_size(), " err=", err)
	get_tree().quit(0 if err == OK else 3)
