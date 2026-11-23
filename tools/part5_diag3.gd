extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_5_houses.tscn")
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	stage.set("step", 15)
	var house: Node = stage.get_node("World/House")
	print("HOUSE CHILDREN: ", house.get_child_count())
	for c in house.get_children():
		print("  child ", c.name, " pos=", (c as Node3D).position if c is Node3D else "")
	var fr: Node = house.get_node_or_null("FurnitureRoot")
	if fr != null:
		for f in fr.get_children():
			print("  ", f.name, " holders=", f.get_child_count())
			for h in f.get_children():
				print("    ", h.name, " pos=", (h as Node3D).position)
	var cam: Camera3D = stage.get_node("World/CameraRig/Camera")
	print("CAM pos=", cam.position, " rot=", cam.rotation_degrees)
	quit()
