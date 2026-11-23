@tool
extends EditorScript

## Baked shipping form: freeze one verified world as a scene.
## THE FIDDLY PART: a PackedScene saves only nodes whose owner is
## the scene root — skip _own_recursive and you bake a beautiful,
## empty file, with no error anywhere. Everyone forgets this once.
## The second discipline: reopen the artefact and COUNT. A bake you
## have not reopened is a rumour (§44.5).

const BAKE_SEED: int = 20261119
const OUT_DIR: String = "res://baked"


func _run() -> void:
	var edited: Node = EditorInterface.get_edited_scene_root()
	if edited == null or edited.name != "WorldStage":
		push_error("Bake: open stage_9_world.tscn and generate step 6 first")
		return
	var world_root: Node3D = edited.get_node("WorldBuilder/WorldRoot") as Node3D
	if world_root == null:
		push_error("Bake: WorldRoot not found — was step 6 generated?")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var bake_root := Node3D.new()
	bake_root.name = "BakedWorld_%d" % BAKE_SEED
	edited.remove_child(world_root)
	bake_root.add_child(world_root)
	_own_recursive(bake_root, bake_root)
	var packed := PackedScene.new()
	var err: Error = packed.pack(bake_root)
	if err != OK:
		push_error("Bake: pack failed: %s" % err)
		return
	var path: String = "%s/world_%d.tscn" % [OUT_DIR, BAKE_SEED]
	err = ResourceSaver.save(packed, path)
	print("[bake] saved ", path, " err=", err)
	_verify_bake(path)


func _own_recursive(node: Node, new_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = new_owner
		_own_recursive(child, new_owner)


## Verify the artefact, not the process: load the saved scene fresh
## and count what matters — buildings present, entrances present.
func _verify_bake(path: String) -> void:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("Bake verify: cannot load " + path)
		return
	var instance: Node = scene.instantiate()
	var buildings_host: Node = instance.find_child("Buildings", true, false)
	var entrances_host: Node = instance.find_child("Entrances", true, false)
	var buildings: int = buildings_host.get_child_count() if buildings_host != null else 0
	var entrances: int = entrances_host.get_child_count() if entrances_host != null else 0
	print("[bake] verify: Buildings children=", buildings, " Entrances children=", entrances)
	if buildings == 0 or entrances == 0:
		push_error("Bake verify: SILENT ABSENCE — a host baked empty; check owner stamping")
	instance.free()
