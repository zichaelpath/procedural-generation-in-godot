extends SceneTree

func _init() -> void:
	_go.call_deferred()

func _go() -> void:
	var ps: PackedScene = load("res://stages/stage_6_apartments.tscn")
	var stage: Node = ps.instantiate()
	root.add_child(stage)
	stage.set("step", 6)
	stage.call("rebuild")
	for i in range(10):
		await process_frame
	var street: Node = stage.get_node("World/Street")
	_dump(street, 0)
	quit()

func _dump(n: Node, depth: int) -> void:
	var pad := ""
	for i in range(depth):
		pad += "  "
	print(pad, n.name, " [", n.get_class(), "] children=", n.get_child_count())
	if depth < 3:
		for c in n.get_children():
			_dump(c, depth + 1)
