extends SceneTree
var _stage: Node = null
var _frames: int = 0

func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_3_plants.tscn") as PackedScene
	_stage = packed.instantiate()
	root.add_child(_stage)
	process_frame.connect(_on_frame)

func _report(tag: String, mi: MeshInstance3D) -> void:
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var white: int = 0
	for c in cols:
		if c.r > 0.7 and c.g > 0.7:
			white += 1
	print("D4 ", tag, " verts=", cols.size(), " whiteish=", white,
		" c0=", cols[0] if cols.size() > 0 else "none",
		" n0=", nrms[0] if nrms.size() > 0 else "none")

func _on_frame() -> void:
	_frames += 1
	if _frames < 3:
		return
	process_frame.disconnect(_on_frame)
	_stage.set("step", 7)
	_stage.call("rebuild")
	_report("SpeciesA", _stage.get_node("Lab3D/SpeciesA"))
	_report("SpeciesB", _stage.get_node("Lab3D/SpeciesB"))
	_stage.set("step", 8)
	_stage.call("rebuild")
	_report("TreeBall", _stage.get_node("Lab3D/TreeBall"))
	print("D4 done")
	quit(0)
