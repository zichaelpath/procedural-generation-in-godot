extends SceneTree

func _init() -> void:
	# Apartment reference: does BlockSolver succeed, and is its floor reachable?
	var aprogram: ApartmentProgram = ApartmentProgram.build(Vector2(24, 13), 4, {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15})
	var acore: Dictionary = ApartmentProgram.core_for("point", Vector2(24, 13))
	var aresult: Dictionary = BlockSolver.solve(aprogram, acore, 20261119, 50)
	print("APARTMENT solve empty=", aresult["block"].is_empty(), " attempts=", aresult["attempts"])
	if not aresult["block"].is_empty():
		var plan: Dictionary = aresult["block"]["floors"][0]
		print("APARTMENT floor0 reachable=", BlockLayout.floor_fully_reachable(plan))
		print("APARTMENT floor0 rooms=", plan["rooms"].map(func(r: Dictionary) -> String: return String(r["name"])))
		print("APARTMENT floor0 doors=", plan["doors"].map(func(d: Dictionary) -> String: return String(d["a"]) + ">" + String(d["b"])))
	# Office: which doors exist on floor 1?
	var program: OfficeProgram = OfficeProgram.default_tower()
	var core: Dictionary = OfficeProgram.core_for("point", program.footprint)
	var rng: RandomNumberGenerator = SeedBank.stream_for(20261119, SeedBank.STREAM_BUILDINGS)
	var tower: Dictionary = OfficeLayout.generate_tower(program, core, rng)
	var oplan: Dictionary = tower["floors"][1]
	OfficeLayout.build_floor_doors(oplan, core)
	print("OFFICE floor1 doors:")
	for d in oplan["doors"]:
		print("  ", d["a"], " > ", d["b"], " ", d["kind"])
	quit()
