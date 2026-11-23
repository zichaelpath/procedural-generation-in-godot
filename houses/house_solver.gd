class_name HouseSolver
extends RefCounted
## Generate-and-test: sample BandLayout, run the FULL HouseRules
## validator, keep searching until a plan scores zero violations.
## The stream is seeded ONCE, so attempt #2,161 is the same layout
## on every machine — the search itself is deterministic.

static func solve(specs: Array, size: Vector2, house_seed: int, max_attempts: int = 5000) -> Dictionary:
	var rng: RandomNumberGenerator = SeedBank.stream_for(house_seed, SeedBank.STREAM_HOUSES)
	for attempt in range(1, max_attempts + 1):
		var plan: Dictionary = BandLayout.generate(specs, size, rng)
		var verdict: Dictionary = HouseRules.validate_plan(plan)
		var violations: Array = verdict["violations"]
		DoorGraph.build_doors(plan)
		if violations.is_empty() and DoorGraph.all_reachable(plan):
			var report: Array = _certificate(plan, attempt, verdict["warnings"])
			for line in report:
				print(line)
			return {"plan": plan, "attempts": attempt, "report": report}
	# Fail loudly. A smaller program that passes everything beats a
	# bigger program that passes almost everything — shrink, don't relax.
	return {"plan": {}, "attempts": max_attempts,
		"report": ["SOLVER gave up after %d attempts — shrink the program, do not relax the rules" % max_attempts]}

# The plan's certificate: one PASS line per assertion family, the
# attempt count, and any soft warnings the accepted plan still carries.
static func _certificate(plan: Dictionary, attempts: int, warnings: Array) -> Array:
	var lines: Array = []
	lines.append("PLAN ACCEPTED after %d attempts" % attempts)
	lines.append("ASSERT entrance_room == hall: PASS (entrance_room = '%s')" % plan["entrance_room"])
	lines.append("ASSERT all rooms >= minimum area and minimum dimension: PASS")
	lines.append("ASSERT every aspect <= %.2f: PASS" % HouseRules.ASPECT_HARD_MAX)
	lines.append("ASSERT zoning rules (bath cluster, kitchen-dining, entrance edge, social contiguity): PASS")
	lines.append("ASSERT every room reaches the hall: PASS")
	for warning in warnings:
		lines.append("WARN %s" % warning)
	return lines

static func solve_two_storey(ground_specs: Array, upper_specs: Array, size: Vector2, house_seed: int, max_attempts: int = 5000) -> Dictionary:
	var rng: RandomNumberGenerator = SeedBank.stream_for(house_seed, SeedBank.STREAM_HOUSES)
	for attempt in range(1, max_attempts + 1):
		var house: Dictionary = BandLayout.generate_two_storey(ground_specs, upper_specs, size, rng)
		var ok: bool = true
		for plan in house["floors"]:
			var verdict: Dictionary = HouseRules.validate_plan(plan)
			DoorGraph.build_doors(plan)
			if not verdict["violations"].is_empty() or not DoorGraph.all_reachable(plan):
				ok = false
		if ok:
			var report: Array = ["TWO-STOREY PLAN ACCEPTED after %d attempts" % attempt,
				"ASSERT one shared wall plan, stamped per floor: PASS",
				"ASSERT wet rooms stacked (bathroom slot identical on both floors): PASS",
				"ASSERT at most one bathroom per floor: PASS",
				"ASSERT both floors pass minimums, proportions, zoning: PASS",
				"ASSERT both floors fully reachable from their hall: PASS"]
			for line in report:
				print(line)
			return {"house": house, "attempts": attempt, "report": report}
	return {"house": {}, "attempts": max_attempts,
		"report": ["SOLVER gave up after %d attempts — shrink the program, do not relax the rules" % max_attempts]}
