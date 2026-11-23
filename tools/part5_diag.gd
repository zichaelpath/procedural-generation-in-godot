extends SceneTree
func _init() -> void:
	for p in ["res://houses/plan_viewer.gd","res://houses/house_program.gd","res://houses/treemap_layout.gd","res://houses/connection_table.gd","res://houses/door_graph.gd","res://houses/house_rules.gd","res://houses/band_layout.gd","res://houses/house_solver.gd","res://houses/window_placer.gd","res://houses/house_builder.gd","res://houses/furniture_rules.gd","res://houses/roof_builder.gd","res://houses/house_stage.gd"]:
		var s: Resource = load(p)
		print("LOAD ", p, " -> ", s != null)
	quit()
