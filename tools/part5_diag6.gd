extends Node
func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_5_houses.tscn")
	var stage: Node = packed.instantiate()
	add_child(stage)
	stage.set("step", 13)
	stage.call("rebuild")
	await get_tree().process_frame
	await get_tree().process_frame
	var fr: Node = stage.get_node("World/House/FurnitureRoot/Furniture_0")
	for h in fr.get_children():
		print("ITEM ", h.name, " pos=", (h as Node3D).position, " rot_y=", snappedf((h as Node3D).rotation_degrees.y, 0.1))
	get_tree().quit()
