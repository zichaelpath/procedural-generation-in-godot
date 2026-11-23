extends Node3D

## Cross-check: run the REAL stage_8_cities scene at step 10 and let
## its own census prints speak; compare against the audit replica.

func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_8_cities.tscn")
	var stage: Node = packed.instantiate()
	stage.step = 10
	add_child(stage)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
