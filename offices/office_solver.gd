class_name OfficeSolver
extends RefCounted
## Generate-and-test at tower scale (Ch 29's architecture, kept):
## sample a tower from ONE buildings-stream RNG, run every floor's
## passes in fixed order (stamp -> doors -> desks -> windows), run
## OfficeRules, accept only zero violations with every floor fully
## reachable from its core hall. Fail loudly; shrink the brief,
## never a rule.

static func solve(program: OfficeProgram, core: Dictionary, tower_seed: int, max_attempts: int = 5000) -> Dictionary:
	var rng: RandomNumberGenerator = SeedBank.stream_for(tower_seed, SeedBank.STREAM_BUILDINGS)
	for attempt in range(1, max_attempts + 1):
		var tower: Dictionary = OfficeLayout.generate_tower(program, core, rng)
		var ok: bool = true
		for plan in tower["floors"]:
			OfficeLayout.build_floor_doors(plan, core)
			DeskField.generate(plan, rng, OfficeLayout.desk_density_for(String(plan["meta"]["plate_kind"])))
			WindowPlacer.place_windows(plan)
			if not BlockLayout.floor_fully_reachable(plan):
				ok = false
		var verdict: Dictionary = OfficeRules.validate_tower(tower)
		if ok and verdict["violations"].is_empty():
			var report: Array = _certificate(tower, attempt, verdict["warnings"])
			for line in report:
				print(line)
			return {"tower": tower, "attempts": attempt, "report": report}
	return {"tower": {}, "attempts": max_attempts,
		"report": ["TOWER SOLVER gave up after %d attempts — shrink the headcount or grow the plate, do not relax the rules" % max_attempts]}

static func _certificate(tower: Dictionary, attempts: int, warnings: Array) -> Array:
	var lines: Array = []
	lines.append("TOWER ACCEPTED after %d attempts" % attempts)
	lines.append("ASSERT every room >= its office minimum, every floor: PASS")
	lines.append("ASSERT every meeting / focus / office room on the facade: PASS")
	lines.append("ASSERT WC / server / storage stacked on the core, all floors: PASS")
	lines.append("ASSERT every room reachable from the core hall, every floor: PASS")
	for plan in tower["floors"]:
		var assigned: int = int(plan["meta"].get("headcount", 0))
		if assigned > 0:
			lines.append("HEADCOUNT floor %d (%s): %d desks for %d assigned seats: PASS" % [
				int(plan["meta"]["floor_index"]) + 1, String(plan["meta"]["plate_kind"]),
				DeskField.count_for_floor(plan), assigned])
	lines.append("TENANCIES %d floors, %d people seated in total" % [
		(tower["floors"] as Array).size(), int(tower["meta"]["headcount_total"])])
	for warning in warnings:
		lines.append("WARN %s" % warning)
	return lines
