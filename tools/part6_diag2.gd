extends SceneTree

func _init() -> void:
	var mixes := {
		"mix0": {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15},
		"mix1": {"studio": 0.15, "one_bed": 0.30, "two_bed": 0.35, "family": 0.20},
		"mix2": {"studio": 0.10, "one_bed": 0.25, "two_bed": 0.30, "family": 0.35},
	}
	for fp in [Vector2(24, 13), Vector2(28, 15), Vector2(30, 16), Vector2(36, 18)]:
		for mix_name in mixes.keys():
			var program: ApartmentProgram = ApartmentProgram.build(fp, 4, mixes[mix_name])
			var core: Dictionary = ApartmentProgram.core_for("point", fp)
			var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
			var best := 99999
			var best_reach := false
			for attempt in range(1, 201):
				var block: Dictionary = BlockLayout.generate_block(program, core, rng)
				var reach := true
				for plan in block["floors"]:
					BlockLayout.build_floor_doors(plan)
					WindowPlacer.place_windows(plan)
					if not BlockLayout.floor_fully_reachable(plan):
						reach = false
				var verdict: Dictionary = ApartmentRules.validate_block(block)
				if verdict["violations"].size() < best:
					best = verdict["violations"].size()
					best_reach = reach
			print("FP ", fp, " ", mix_name, " slots=", program.units_per_floor.size(), " best_violations_in_200=", best, " reach_at_best=", best_reach)
	quit()
