extends SceneTree

func _init() -> void:
	var program: OfficeProgram = OfficeProgram.default_tower()
	var core: Dictionary = OfficeProgram.core_for("point", program.footprint)
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	for attempt in range(1, 6):
		var tower: Dictionary = OfficeLayout.generate_tower(program, core, rng)
		var reach_all := true
		var unreach: Array = []
		for plan in tower["floors"]:
			OfficeLayout.build_floor_doors(plan, core)
			DeskField.generate(plan, rng, OfficeLayout.desk_density_for(String(plan["meta"]["plate_kind"])))
			WindowPlacer.place_windows(plan)
			if not BlockLayout.floor_fully_reachable(plan):
				reach_all = false
				# find unreachable rooms by BFS over doors from core_hall
				var visited: Array = ["core_hall"]
				var frontier: Array = ["core_hall"]
				while not frontier.is_empty():
					var cur: String = String(frontier.pop_back())
					for door in plan["doors"]:
						var other: String = ""
						if door["a"] == cur:
							other = door["b"]
						elif door["b"] == cur:
							other = door["a"]
						if other != "" and other != "EXTERIOR" and not visited.has(other):
							visited.append(other)
							frontier.append(other)
				for room in plan["rooms"]:
					if not visited.has(room["name"]):
						unreach.append("f%d:%s" % [int(plan["meta"]["floor_index"]), room["name"]])
		var verdict: Dictionary = OfficeRules.validate_tower(tower)
		print("ATTEMPT ", attempt, " reachable_all=", reach_all, " violations=", verdict["violations"].size())
		for u in unreach:
			print("  UNREACH: ", u)
		for v in verdict["violations"]:
			print("  V: ", v)
		for plan in tower["floors"]:
			print("  floor ", int(plan["meta"]["floor_index"]) + 1, " ", String(plan["meta"]["plate_kind"]), " desks=", DeskField.count_for_floor(plan), " seats=", int(plan["meta"].get("headcount", 0)))
	quit()
