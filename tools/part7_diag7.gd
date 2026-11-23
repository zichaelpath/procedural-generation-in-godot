extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_7_offices.tscn")
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	stage.set("step", 8)
	await process_frame
	print("DIAG length=", stage.get("last_street_length"))
	var host: Node = stage.get_node("World/Tower/Tower_0")
	print("DIAG tower_host_pos=", (host as Node3D).position)
	var cam: Camera3D = stage.get_node("World/CameraRig/Camera")
	print("DIAG game_cam_pos=", cam.position)
	quit()
