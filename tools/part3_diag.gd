extends SceneTree
func _init() -> void:
	var config := WorldConfig.new()
	config.master_seed = 20261119
	config.sea_level = 5.0
	var data := TerrainHeight.new()
	data.generate(config)
	var smax: float = 0.0
	var over30: int = 0
	var over16dry: int = 0
	var tree_ok: int = 0
	var total: int = 0
	var hmax: float = -1e9
	for iz in range(0, 129, 2):
		for ix in range(0, 129, 2):
			var wp: Vector2 = data.grid_to_world(ix, iz)
			if absf(wp.x) > 60.0 or absf(wp.y) > 60.0:
				continue
			total += 1
			var s: float = data.slope_at(wp.x, wp.y)
			var m: float = Scatter.moisture_at_world(data, wp.x, wp.y)
			var h: float = data.height_at(wp.x, wp.y)
			smax = maxf(smax, s)
			hmax = maxf(hmax, h)
			if s > 0.30:
				over30 += 1
			if s > 0.16 and m <= 0.22:
				over16dry += 1
			if m > 0.45 and s < 0.08 and h >= data.sea_level + 0.3 and h < data.sea_level + 22.0:
				tree_ok += 1
	print("DIAG region samples=", total, " slope_max=", smax, " h_max=", hmax,
		" slope>0.30 cells=", over30, " slope>0.16&dry cells=", over16dry, " tree-ok cells=", tree_ok)
	# Island-wide slope max
	var gmax: float = 0.0
	var gover: int = 0
	for iz in range(0, 129):
		for ix in range(0, 129):
			var wp2: Vector2 = data.grid_to_world(ix, iz)
			var s2: float = data.slope_at(wp2.x, wp2.y)
			gmax = maxf(gmax, s2)
			if s2 > 0.30:
				gover += 1
	print("DIAG island slope_max=", gmax, " cells slope>0.30=", gover)
	quit(0)
