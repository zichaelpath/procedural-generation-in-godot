extends SceneTree
## Part VII diagnostic 6: print the built Tower/Street subtree
## structure at step 8 (names + child counts, 3 levels deep).

func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_7_offices.tscn")
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	# Let _ready/rebuild run a frame before forcing the step.
	await process_frame
	await process_frame
	stage.set("step", 8)
	await process_frame
	var world: Node = stage.get_node("World")
	for child in world.get_children():
		_dump(child, 0)
	quit()


func _dump(n: Node, depth: int) -> void:
	var pad: String = ""
	for i in depth:
		pad += "  "
	print(pad, n.name, " children=", n.get_child_count())
	if depth >= 2:
		return
	for c in n.get_children():
		_dump(c, depth + 1)
