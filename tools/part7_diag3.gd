extends SceneTree

func _unvisited(plan: Dictionary) -> Array:
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
	var out: Array = []
	for room in plan["rooms"]:
		if not visited.has(room["name"]):
			out.append(room["name"])
	return out

func _init() -> void:
	var aprogram: ApartmentProgram = ApartmentProgram.build(Vector2(24, 13), 4, {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15})
	var acore: Dictionary = ApartmentProgram.core_for("point", Vector2(24, 13))
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	var block: Dictionary = BlockLayout.generate_block(aprogram, acore, rng)
	var plan: Dictionary = block["floors"][0]
	BlockLayout.build_floor_doors(plan)
	print("APARTMENT floor0 reachable=", BlockLayout.floor_fully_reachable(plan))
	print("APARTMENT floor0 unvisited=", _unvisited(plan))
	print("APARTMENT floor0 doors:")
	for d in plan["doors"]:
		print("  ", d["a"], " > ", d["b"], " ", d["kind"])
	quit()
