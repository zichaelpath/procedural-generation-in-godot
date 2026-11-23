extends SceneTree
## Part VII diagnostic 5 (pure data): does a step-2-style roll
## (generate_tower + doors + windows) mutate the shared program /
## core objects so that a later OfficeSolver.solve() with the SAME
## objects fails, while a solve on fresh objects succeeds?

func _init() -> void:
	var program: OfficeProgram = OfficeProgram.default_tower()
	var core: Dictionary = OfficeProgram.core_for("point", program.footprint)
	var core_before: String = str(core)
	var r1: Dictionary = OfficeSolver.solve(program, core, 20261119)
	print("DIAG r1 fresh solve attempts=", r1["attempts"], " tower_empty=", (r1["tower"] as Dictionary).is_empty())
	# Step-2-style roll with the same objects (no desks at step 2).
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	var tower: Dictionary = OfficeLayout.generate_tower(program, core, rng)
	for plan in tower["floors"]:
		OfficeLayout.build_floor_doors(plan, core)
		WindowPlacer.place_windows(plan)
	print("DIAG core mutated by roll: ", str(core) != core_before)
	if str(core) != core_before:
		print("DIAG core before=", core_before)
		print("DIAG core after =", str(core))
	var r2: Dictionary = OfficeSolver.solve(program, core, 20261119)
	print("DIAG r2 post-roll solve attempts=", r2["attempts"], " tower_empty=", (r2["tower"] as Dictionary).is_empty())
	quit()
