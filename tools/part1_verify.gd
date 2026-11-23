extends SceneTree
## Part I numeric verification — worker tool, NOT a book listing.
## Runs the chapter worked examples and prints pipeline statistics so
## captures can be checked against numbers, not just eyeballed.
##   godot --headless --path ~/procgen-book-project -s res://tools/part1_verify.gd

func _init() -> void:
	print("VERIFY start")
	var config := WorldConfig.new()
	config.master_seed = 20261119
	config.sea_level = 5.0
	var data := TerrainHeight.new()
	data.generate(config)
	var counts := {}
	for b in data.biomes:
		counts[b] = int(counts.get(b, 0)) + 1
	print("VERIFY island biomes=", counts)
	# Disagreement over land cells (Chapter 6 expects ~4-9% of land).
	var names := {0: "Ocean", 1: "Beach", 2: "Desert", 3: "Grassland", 4: "Forest",
			5: "Rainforest", 6: "Taiga", 7: "Tundra", 8: "Rock", 9: "Snow"}
	var land: int = 0
	var disagree: int = 0
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			var id: int = data.biome_at(ix, iz)
			if id == BiomeClassifier.OCEAN:
				continue
			land += 1
			if names[id] != data.rule_labels[data.index(ix, iz)]:
				disagree += 1
	print("VERIFY disagreement land=", land, " disagree=", disagree,
			" pct=", 100.0 * float(disagree) / float(maxi(land, 1)))
	print("VERIFY rolls (0,0)=", data.cell_roll(0, 0), " (1,0)=", data.cell_roll(1, 0),
			" (40,90)=", data.cell_roll(40, 90))
	print("VERIFY worked1 whittaker=", BiomeClassifier.classify(14.0, 0.74, 0.81, 5.0, 30.0),
			" (expect 5=Rainforest)")
	print("VERIFY worked1 rule roll0.42=", BiomeClassifier.classify_rule_table(14.0, 0.74, 0.81, 5.0, 30.0, 0.42),
			" (expect Rainforest)")
	print("VERIFY worked2 whittaker=", BiomeClassifier.classify(9.0, 0.44, 0.27, 5.0, 30.0),
			" (expect 6=Taiga)")
	print("VERIFY worked2 rule roll0.5=", BiomeClassifier.classify_rule_table(9.0, 0.44, 0.27, 5.0, 30.0, 0.5),
			" (expect Tundra)")
	# Chapter 7's 3x3 worked example: bottom-right accumulation must be 9.
	var ff := FlowField.new()
	var src := PackedFloat32Array([9, 8, 7, 6, 5, 4, 3, 2, 1])
	ff.compute(src, 3, 0.0)
	print("VERIFY flow3x3 bottomright=", ff.accumulation[8], " (expect 9)")
	# Flow over the island, on the filled surface.
	var flow := FlowField.new()
	flow.width = data.row_width()
	var filled: PackedFloat32Array = flow.filled_heights(data.heights)
	var maxdiff: float = 0.0
	for i in range(filled.size()):
		maxdiff = maxf(maxdiff, filled[i] - data.heights[i])
	flow.compute(filled, data.row_width(), data.sea_level)
	flow.watershed_labels()
	var maxacc: float = 0.0
	for a in flow.accumulation:
		maxacc = maxf(maxacc, a)
	print("VERIFY flow max_acc=", maxacc, " outlets=", flow.outlet_count(),
			" fill_maxdiff=", maxdiff)
	data.carve_rivers(flow, 60.0, 2.0)
	var hmax: float = 0.0
	for h in data.heights:
		hmax = maxf(hmax, h)
	print("VERIFY carve done, island max height now=", hmax)
	# Spectral sidebar smoke test.
	var data2 := TerrainHeight.new()
	data2.generate(config)
	SpectralField.bake_into(data2, config)
	print("VERIFY spectral ok, centre height=", data2.grid_height(64, 64),
			" centre biome=", data2.biome_at(64, 64))
	# Montreal (Chapter 8), if the reader data files exist.
	if FileAccess.file_exists("res://terrain/data/montreal_heightmap.png"):
		var res: Dictionary = HeightmapImport.import_grid(
				"res://terrain/data/montreal_heightmap.png", 233.0, 2.0)
		print("VERIFY montreal import empty=", res.is_empty(), " points=", res.get("points", -1))
		if not res.is_empty():
			var md := TerrainHeight.new()
			md.generate(config)
			md.sea_level = 16.0
			md.load_grid(res["heights"], int(res["points"]), 24000.0, 466.0)
			var lookout: Vector2 = GeoReference.latlon_to_world(
					45.5048, -73.5878, 45.4000, -73.7500, 24000.0)
			print("VERIFY lookout world=", lookout, " (chapter expects ~(679, 334))")
			var cs: float = md.cell_size()
			var lix: int = roundi((lookout.x + 12000.0) / cs)
			var liz: int = roundi((lookout.y + 12000.0) / cs)
			var lmax: float = 0.0
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					lmax = maxf(lmax, md.grid_height(lix + dx, liz + dz))
			var gmax: float = 0.0
			for h in md.heights:
				gmax = maxf(gmax, h)
			print("VERIFY lookout cell=(", lix, ",", liz, ") h=", md.grid_height(lix, liz),
					" local9x9max=", lmax, " globalmax=", gmax,
					" lookout_biome=", md.biome_at(lix, liz), " (8=Rock expected at summit)")
			var mcounts := {}
			for b in md.biomes:
				mcounts[b] = int(mcounts.get(b, 0)) + 1
			print("VERIFY montreal biomes=", mcounts)
	if FileAccess.file_exists("res://terrain/data/montreal_roads.json"):
		var roads: Array = OsmImport.load_roads(
				"res://terrain/data/montreal_roads.json", 45.4000, -73.7500, 24000.0)
		print("VERIFY roads count=", roads.size())
		if roads.size() > 0:
			var pts: PackedVector2Array = roads[0].get("points")
			print("VERIFY road0 highway=", roads[0].get("highway"), " pts=", pts.size(),
					" first=", pts[0] if pts.size() > 0 else Vector2.ZERO)
	print("VERIFY done")
	quit(0)
