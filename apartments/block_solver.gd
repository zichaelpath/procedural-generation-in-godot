class_name BlockSolver
extends RefCounted
## Generate-and-test at building scale (Ch 29's architecture, kept):
## sample a block from ONE buildings-stream RNG, build every floor's
## doors, run ApartmentRules, accept only zero violations with every
## floor fully reachable. Fail loudly; shrink the mix, never a rule.

static func solve(program: ApartmentProgram, core: Dictionary, block_seed: int, max_attempts: int = 5000) -> Dictionary:
	var rng: RandomNumberGenerator = SeedBank.stream_for(block_seed, SeedBank.STREAM_BUILDINGS)
	for attempt in range(1, max_attempts + 1):
		var block: Dictionary = BlockLayout.generate_block(program, core, rng)
		var ok: bool = true
		for plan in block["floors"]:
			BlockLayout.build_floor_doors(plan)
			WindowPlacer.place_windows(plan)
			if not BlockLayout.floor_fully_reachable(plan):
				ok = false
		var verdict: Dictionary = ApartmentRules.validate_block(block)
		if ok and verdict["violations"].is_empty():
			var report: Array = _certificate(block, attempt, verdict["warnings"])
			for line in report:
				print(line)
			return {"block": block, "attempts": attempt, "report": report}
	return {"block": {}, "attempts": max_attempts,
		"report": ["BLOCK SOLVER gave up after %d attempts — shrink the mix or grow the footprint, do not relax the rules" % max_attempts]}

static func _certificate(block: Dictionary, attempts: int, warnings: Array) -> Array:
	var lines: Array = []
	lines.append("BLOCK ACCEPTED after %d attempts" % attempts)
	lines.append("ASSERT every room on every floor >= minimum area and dimension: PASS")
	lines.append("ASSERT every aspect <= %.2f: PASS" % HouseRules.ASPECT_HARD_MAX)
	lines.append("ASSERT wet rooms stacked on the shared wet slot, all floors: PASS")
	lines.append("ASSERT at most one bathroom per unit: PASS")
	lines.append("ASSERT every unit's front door opens off the core hall: PASS")
	lines.append("ASSERT every room reachable from the core hall, every floor: PASS")
	lines.append("UNITS %d homes on %d floors" % [(block["units"] as Array).size(), (block["floors"] as Array).size()])
	for warning in warnings:
		lines.append("WARN %s" % warning)
	return lines
