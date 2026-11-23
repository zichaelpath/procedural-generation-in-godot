extends SceneTree

func _init() -> void:
	var footprint := Rect2(0, 0, 19.5, 19.5)
	var mix := {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15}
	var program: ApartmentProgram = ApartmentProgram.build(footprint.size, 4, mix)
	var core: Dictionary = ApartmentProgram.core_for("point", footprint.size)
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	var block: Dictionary = BlockLayout.generate_block(program, core, rng)
	var plan: Dictionary = block["floors"][0]
	BlockLayout.build_floor_doors(plan)
	print("DOORS: ", plan["doors"].size())
	for d in plan["doors"]:
		print("  ", d["a"], " <-> ", d["b"], " kind=", d["kind"])
	# BFS by hand to list unvisited
	var visited: Array = ["core_hall"]
	var frontier: Array = ["core_hall"]
	while not frontier.is_empty():
		var current: String = String(frontier.pop_back())
		for door in plan["doors"]:
			var other: String = ""
			if door["a"] == current:
				other = door["b"]
			elif door["b"] == current:
				other = door["a"]
			if other != "" and not visited.has(other):
				visited.append(other)
				frontier.append(other)
	for room in plan["rooms"]:
		if not visited.has(room["name"]):
			print("UNREACHABLE: ", room["name"], " type=", room["type"], " rect=", room["rect"])
	quit()
