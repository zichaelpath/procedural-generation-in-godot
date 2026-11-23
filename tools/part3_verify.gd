extends SceneTree
## Part III logic verification — worker tool, NOT a book listing.
## Exercises the chapter systems headlessly and prints receipts +
## timings so captures can be checked against numbers.
##   godot --headless --path ~/procgen-book-project -s res://tools/part3_verify.gd
func _init() -> void:
	print("P3VERIFY start")
	var config := WorldConfig.new()
	config.master_seed = 20261119
	config.sea_level = 5.0
	var t0: int = Time.get_ticks_msec()
	var data := TerrainHeight.new()
	data.generate(config)
	print("terrain generate ms=", Time.get_ticks_msec() - t0, " sea=", data.sea_level, " cells=", data.cells)
	# Ch16 ladder
	var rules: Dictionary = {"F": "FF+[-F+F]-[+F-F]"}
	var lens: Array[int] = []
	for gen in range(0, 6):
		lens.append(LSystem.expand("F", rules, gen).length())
	print("ladder lengths=", lens, " (expect 1, 19, ...)")
	# Ch15 step 0 counts
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_SCATTER)
	var region := Vector2(60.0, 40.0)
	print("random=", Scatter.random_points(region, 300, rng).size(),
		" jittered=", Scatter.jittered_grid(region, 3.4, rng).size(),
		" poisson=", Scatter.poisson_disc(region, 3.4, rng).size())
	# Ch15 step 1 chunk pair
	var manager := ChunkManager.new()
	manager.setup(data, config)
	var ld: ChunkData = manager.get_or_generate_data(Vector2i(0, 0))
	ChunkScatter.fill_chunk(ld, config, [])
	var nb: Array[Vector2] = []
	for item in ld.scatter:
		var wp: Vector3 = item["position"]
		nb.append(Vector2(wp.x - config.chunk_size_m, wp.z))
	var rd: ChunkData = manager.get_or_generate_data(Vector2i(1, 0))
	ChunkScatter.fill_chunk(rd, config, nb)
	var worst: float = INF
	for a in ld.scatter:
		for b in rd.scatter:
			var pa: Vector3 = a["position"]
			var pb: Vector3 = b["position"]
			worst = minf(worst, Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)))
	print("chunk pair left=", ld.scatter.size(), " right=", rd.scatter.size(), " closest=", worst, " (must be >= 5.0)")
	# Ch15 step 2 ecology
	var rng2: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_SCATTER)
	var manifest: Array[Dictionary] = Scatter.ecology_scatter(data, Rect2(-60, -60, 120, 120), 2600, rng2)
	var counts: Dictionary = {}
	for item in manifest:
		counts[item["kind"]] = int(counts.get(item["kind"], 0)) + 1
	print("ecology manifest=", manifest.size(), " counts=", counts)
	# Ch17 turtle + builder + cache
	var t3 := Turtle3D.new()
	t3.grow(LSystem.expand("F", {"F": "FF+[\\-F+F]-[+F-F]"}, 4))
	print("turtle3d segments=", t3.segments.size())
	var oak: Dictionary = TreeBuilder.SPECIES["Oak"]
	var m1: ArrayMesh = TreeBuilder.build_mesh(t3.segments, 8, oak)
	var m2: ArrayMesh = TreeBuilder.build_mesh(t3.segments, 8, oak)
	print("skinned verts=", m1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	# Ch17 recursive trio sizes
	var rng3: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TREES)
	for nm in ["Oak", "Pine", "Willow"]:
		var sp: Dictionary = TreeBuilder.SPECIES[nm]
		var sk: Array[Dictionary] = TreeBuilder.recursive_skeleton(Vector3.ZERO, Vector3.UP, float(sp["start_length"]), int(sp["depth"]), sp, rng3)
		print("species ", nm, " segments=", sk.size())
	# Ch18 colonization timing (the expensive one)
	var rng4: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TREES)
	var tc: int = Time.get_ticks_msec()
	var sc := SpaceColonization.new()
	var segs: Array[Dictionary] = sc.grow(SpaceColonization.cloud_ball(Vector3(-6, 2.6, 0), 1.5, 260, rng4), Vector3(-6, 0, 0), rng4)
	print("colonization ball: segments=", segs.size(), " ms=", Time.get_ticks_msec() - tc)
	# Ch16 stochastic replay
	var wr: Dictionary = {"F": [[0.7, "FF+[-F+F]-[+F-F]"], [0.3, "F[+F][-F]F"]]}
	var r1: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	var l1: Array[int] = []
	for n in 3:
		l1.append(LSystem.expand_stochastic("F", wr, 4, r1).length())
	var r2: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	var l2: Array[int] = []
	for n in 3:
		l2.append(LSystem.expand_stochastic("F", wr, 4, r2).length())
	print("stochastic replay identical=", l1 == l2, " ", l1)
	print("P3VERIFY done")
	quit(0)
