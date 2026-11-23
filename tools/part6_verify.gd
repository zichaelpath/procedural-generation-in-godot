extends SceneTree

func _init() -> void:
	var footprint := Rect2(0, 0, 19.5, 19.5)
	var mix := {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15}
	var program: ApartmentProgram = ApartmentProgram.build(footprint.size, 4, mix)
	var core: Dictionary = ApartmentProgram.core_for("point", footprint.size)
	print("SLOTS: ", program.units_per_floor)
	# Raw attempt diagnostics (first 5 attempts, violation histogram)
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	for attempt in range(1, 6):
		var block: Dictionary = BlockLayout.generate_block(program, core, rng)
		var reach_all := true
		for plan in block["floors"]:
			BlockLayout.build_floor_doors(plan)
			WindowPlacer.place_windows(plan)
			if not BlockLayout.floor_fully_reachable(plan):
				reach_all = false
		var verdict: Dictionary = ApartmentRules.validate_block(block)
		print("ATTEMPT ", attempt, " reachable_all=", reach_all, " violations=", verdict["violations"].size(), " warnings=", verdict["warnings"].size())
		for v in verdict["violations"]:
			print("  V: ", v)
	# Floor kinds per floor for the narrative (fresh stream, as the stage rolls)
	var rng2: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	var block2: Dictionary = BlockLayout.generate_block(program, core, rng2)
	for f in 4:
		var kinds: Array = []
		for unit in block2["units"]:
			if int(unit["floor"]) == f:
				kinds.append("%s %s" % [unit["id"], unit["kind"]])
		print("FLOOR ", f + 1, ": ", ", ".join(kinds))
	# The real solver, book configuration
	var result: Dictionary = BlockSolver.solve(program, core, 20261119)
	print("SOLVER attempts=", result["attempts"], " block_empty=", result["block"].is_empty())
	# Corridor typology solve (street block 3 uses it)
	var core_c: Dictionary = ApartmentProgram.core_for("corridor", footprint.size)
	var result_c: Dictionary = BlockSolver.solve(program, core_c, 424242)
	print("CORRIDOR SOLVER attempts=", result_c["attempts"], " block_empty=", result_c["block"].is_empty())
	if result_c["block"].is_empty():
		print(result_c["report"][0])
	quit()
