@tool
extends EditorPlugin
## Book Stage editor plugin — ENGINE-shot arranger (PLAN.md §5, §7).
##
## When the editor opens a stage scene, this plugin (deferred, after the
## editor settles):
##   1. makes sure a stage scene is the edited scene (opens the terrain
##      heightfield stage if nothing with a `step` export is open),
##   2. sets the stage root's `step` to 2 (the finished step of the stage),
##   3. selects the stage root, so the Scene dock shows the tree and the
##      Inspector shows the stage script + its exports (step, master_seed),
##   4. writes /tmp/book_editor_ready.txt — tools/capture_engine.sh polls
##      for that file, then grabs the full editor window via X11.
##
## It never saves scenes and never quits the editor; the shell script
## owns the editor process lifetime.

const DEFAULT_STAGE := "res://stages/stage_terrain_heightfield.tscn"
const READY_FILE := "/tmp/book_editor_ready.txt"


func _enter_tree() -> void:
	# Deferred so the editor interface exists before we touch it.
	_arrange.call_deferred()


func _arrange() -> void:
	# Give the editor a moment to finish opening the initial scene.
	await get_tree().create_timer(2.0).timeout
	var iface: EditorInterface = get_editor_interface()
	var root: Node = iface.get_edited_scene_root()
	if root == null or root.get("step") == null:
		iface.open_scene_from_path(DEFAULT_STAGE)
		await get_tree().create_timer(2.0).timeout
		root = iface.get_edited_scene_root()
	if root == null:
		push_warning("book_stage: no edited scene root to arrange")
		return
	if root.get("step") != null:
		root.set("step", 2)
	if root.get("master_seed") != null:
		root.set("master_seed", 20261119)
	if root.has_method("rebuild"):
		root.call("rebuild")
	var selection: EditorSelection = iface.get_selection()
	selection.clear()
	selection.add_node(root)
	# Make sure the main 3D screen (not e.g. Script) is in front.
	iface.set_main_screen_editor("3D")
	var f: FileAccess = FileAccess.open(READY_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string("ready scene=%s step=%s\n" % [root.scene_file_path, str(root.get("step"))])
		f.close()
	print("BOOK_STAGE_READY scene=", root.scene_file_path)
