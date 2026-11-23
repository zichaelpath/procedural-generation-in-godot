extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_7_offices.tscn")
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	stage.set("step", 8)
	await process_frame
	var street: Node = stage.get_node("World/Street")
	for c in street.get_children():
		print("DIAG street child ", c.name, " pos=", (c as Node3D).position)
	quit()
