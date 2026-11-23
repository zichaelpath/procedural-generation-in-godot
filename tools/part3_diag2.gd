extends SceneTree
func _init() -> void:
	print("leaf import exists: ", FileAccess.file_exists("res://plants/leaf.png.import"))
	var tex: Resource = load("res://plants/leaf.png")
	print("leaf load: ", tex, " class=", tex.get_class() if tex != null else "null")
	var packed: PackedScene = load("res://stages/stage_3_plants.tscn") as PackedScene
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	stage.set("step", 6)
	stage.call("rebuild")
	var skinned: MeshInstance3D = stage.get_node("Lab3D/SkinnedPlant") as MeshInstance3D
	print("step6 skinned aabb=", skinned.get_aabb())
	var arrays: Array = skinned.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	print("step6 color array size=", cols.size(), " first=", cols[0] if cols.size() > 0 else "none")
	var t3: Node = stage.get_node("Lab3D/Turtle3D")
	var segs: Array = t3.get("segments")
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for s in segs:
		var a: Vector3 = s["from"]
		var b: Vector3 = s["to"]
		mn = mn.min(a).min(b)
		mx = mx.max(a).max(b)
	print("step6 segment bounds min=", mn, " max=", mx, " count=", segs.size())
	stage.set("step", 7)
	stage.call("rebuild")
	for nm in ["SpeciesA", "SpeciesB", "SpeciesC"]:
		var h: MeshInstance3D = stage.get_node("Lab3D/" + nm) as MeshInstance3D
		print("step7 ", nm, " aabb=", h.get_aabb(), " pos=", h.position)
	stage.set("step", 8)
	stage.call("rebuild")
	for nm in ["TreeBall", "TreeUmbrella", "TreeCone", "TreePruned"]:
		var h: MeshInstance3D = stage.get_node("Lab3D/" + nm) as MeshInstance3D
		print("step8 ", nm, " aabb=", h.get_aabb(), " pos=", h.position)
	quit(0)
