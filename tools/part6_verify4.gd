extends SceneTree

func _init() -> void:
	var host: Node3D = Node3D.new()
	host.name = "StreetTest"
	get_root().add_child(host)
	var result: Dictionary = StreetBuilder.build_street(host, 20261119, 4)
	print("STREET placed=", result["placed"], " of 4, length=", result["length"])
	# Facade pass on the book's solved block
	var footprint := Rect2(0, 0, 19.5, 19.5)
	var mix := {"studio": 0.25, "one_bed": 0.35, "two_bed": 0.25, "family": 0.15}
	var program: ApartmentProgram = ApartmentProgram.build(footprint.size, 4, mix)
	var core: Dictionary = ApartmentProgram.core_for("point", footprint.size)
	var solved: Dictionary = BlockSolver.solve(program, core, 20261119)
	var block: Dictionary = solved["block"]
	var fhost: Node3D = Node3D.new()
	get_root().add_child(fhost)
	var balconies: Array = FacadeBuilder.build_facade(fhost, block)
	var violations: Array = ApartmentRules.check_balconies(block, balconies)
	print("FACADE balconies=", balconies.size(), " violations=", violations.size())
	for v in violations:
		print("  FV: ", v)
	var by_floor: Dictionary = {}
	for b in balconies:
		by_floor[int(b["floor"])] = int(by_floor.get(int(b["floor"]), 0)) + 1
	print("BALCONIES BY FLOOR: ", by_floor)
	quit()
