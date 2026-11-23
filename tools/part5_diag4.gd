extends Node
func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_5_houses.tscn")
	var stage: Node = packed.instantiate()
	add_child(stage)
	stage.set("step", 13)
	stage.call("rebuild")
	await get_tree().process_frame
	await get_tree().process_frame
	var cam: Camera3D = stage.get_node("World/CameraRig/Camera")
	print("CAM global=", cam.global_position, " fwd=", -cam.global_transform.basis.z)
	var target: Vector3 = cam.global_position
	_scan(stage.get_node("World/House"), target)
	get_tree().quit()
func _scan(n: Node, target: Vector3) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if aabb.has_point(target) or aabb.grow(1.5).has_point(target):
			print("NEAR ", mi.get_path(), " aabb=", aabb)
	for c in n.get_children():
		_scan(c, target)
