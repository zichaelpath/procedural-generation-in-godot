extends Node
func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_5_houses.tscn")
	var stage: Node = packed.instantiate()
	add_child(stage)
	stage.set("step", 13)
	stage.call("rebuild")
	await get_tree().process_frame
	var plan: Dictionary = stage.get("active_plan")
	print("ROOMS:")
	for r in plan["rooms"]:
		print("  ", r["name"], " type=", r["type"], " rect=", r["rect"])
	print("DOORS:")
	for d in plan["doors"]:
		print("  ", plan["rooms"][int(d["a"])]["name"], " <-> ", plan["rooms"][int(d["b"])]["name"], " center=", d["center"], " w=", d["width"], " kind=", d["kind"])
	print("ENTRANCE: ", plan.get("entrance", {}))
	get_tree().quit()
