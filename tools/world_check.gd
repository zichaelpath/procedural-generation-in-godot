extends Node3D

## Part IX smoke: instance the REAL stage_9_world at step 6, let it
## build, then run its Return Test and let the verdict print.

func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_9_world.tscn")
	var stage: Node = packed.instantiate()
	add_child(stage)
	await get_tree().create_timer(2.0).timeout
	print("WORLD_CHECK: build complete, running Return Test ...")
	stage.run_return_test()
	print("WORLD_CHECK: done")
	get_tree().quit()
