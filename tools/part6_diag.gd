extends SceneTree

func _init() -> void:
	var footprint := Rect2(0, 0, 24, 13)
	var mix := {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15}
	var program: ApartmentProgram = ApartmentProgram.build(footprint.size, 4, mix)
	var core: Dictionary = ApartmentProgram.core_for("point", footprint.size)
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
		for w in verdict["warnings"]:
			print("  W: ", w)
	quit()
