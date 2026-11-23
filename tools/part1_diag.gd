extends SceneTree
## Part I UI geometry diagnostic — worker tool, NOT a book listing.

func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_1_environments.tscn") as PackedScene
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var p: Control = stage.get_node("UI/Previews") as Control
	print("DIAG viewport=", root.get_visible_rect())
	print("DIAG Previews type=", p.get_class(), " rect=", p.get_global_rect(),
			" anchor_r=", p.anchor_right, " anchor_b=", p.anchor_bottom,
			" min_size=", p.get_combined_minimum_size())
	for c in p.get_children():
		var r := c as TextureRect
		print("DIAG ", r.name, " rect=", r.get_global_rect(),
				" custom_min=", r.custom_minimum_size,
				" expand=", r.expand_mode, " stretch=", r.stretch_mode,
				" tex_size=", r.texture.get_size() if r.texture != null else Vector2.ZERO)
	quit(0)
