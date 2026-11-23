extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_5_houses.tscn")
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	stage.set("step", 15)
	stage.call("rebuild")
	var house: Node = stage.get_node("World/House")
	_print_tree(house, 0)
	quit()
func _print_tree(n: Node, depth: int) -> void:
	var pad: String = ""
	for i in depth: pad += "  "
	var pos: String = ""
	if n is Node3D: pos = str((n as Node3D).position)
	print(pad, n.name, " ", n.get_class(), " ", pos)
	for c in n.get_children():
		if depth < 3: _print_tree(c, depth + 1)
