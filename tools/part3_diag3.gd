extends SceneTree
## Frame-aware measurement: waits for the stage's _ready build,
## then measures steps 6/7/8 geometry. Worker tool only.
var _stage: Node = null
var _frames: int = 0

func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_3_plants.tscn") as PackedScene
	_stage = packed.instantiate()
	root.add_child(_stage)
	process_frame.connect(_on_frame)

func _bounds(segs: Array) -> String:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for s in segs:
		mn = mn.min(s["from"]).min(s["to"])
		mx = mx.max(s["from"]).max(s["to"])
	return str(mn) + " .. " + str(mx)

func _on_frame() -> void:
	_frames += 1
	if _frames < 3:
		return
	process_frame.disconnect(_on_frame)
	_stage.set("step", 6)
	_stage.call("rebuild")
	var skinned: MeshInstance3D = _stage.get_node("Lab3D/SkinnedPlant") as MeshInstance3D
	print("D3 step6 skinned global aabb=", skinned.global_transform * skinned.get_aabb())
	var arrays: Array = skinned.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	print("D3 step6 colors=", cols.size(), " c0=", cols[0] if cols.size() > 0 else "none",
		" cmid=", cols[cols.size() / 2] if cols.size() > 0 else "none")
	var t3: Node = _stage.get_node("Lab3D/Turtle3D")
	print("D3 step6 turtle bounds=", _bounds(t3.get("segments")))
	_stage.set("step", 7)
	_stage.call("rebuild")
	for nm in ["SpeciesA", "SpeciesB", "SpeciesC"]:
		var h: MeshInstance3D = _stage.get_node("Lab3D/" + nm) as MeshInstance3D
		print("D3 step7 ", nm, " global aabb=", h.global_transform * h.get_aabb())
	_stage.set("step", 8)
	_stage.call("rebuild")
	for nm in ["TreeBall", "TreeUmbrella", "TreeCone", "TreePruned"]:
		var h: MeshInstance3D = _stage.get_node("Lab3D/" + nm) as MeshInstance3D
		print("D3 step8 ", nm, " global aabb=", h.global_transform * h.get_aabb(), " pos=", h.position)
	print("D3 done")
	quit(0)
