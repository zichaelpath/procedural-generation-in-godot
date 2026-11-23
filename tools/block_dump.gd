extends Node3D

## Dump step-10 borough blocks (no placement) and inspect overlaps.

const SEED: int = 20261119

func _ready() -> void:
	var config := WorldConfig.new()
	config.master_seed = SEED
	config.sea_level = 5.0
	config.terrain_world_size = 960.0
	config.terrain_cells = 160
	config.terrain_height_scale = 42.0
	var terrain := TerrainHeight.new()
	terrain.erode_droplets = 0
	terrain.thermal_iterations = 0
	terrain.generate(config)
	var network := RoadNetwork.new(terrain)
	var city := BoroughCity.new(network, terrain, SEED)
	city.generate()
	city.apply_seams()
	city.add_diagonal_avenue()
	print("blocks after generate+seams: ", city.borough_blocks.size())
	var per: Dictionary = {}
	var area_sum: float = 0.0
	for b in city.borough_blocks:
		per[b["borough"]] = int(per.get(b["borough"], 0)) + 1
		area_sum += float(b["area"])
	print("per borough: ", per, " area sum=", area_sum)
	# Same-borough pairwise overlaps, top 5.
	var blocks: Array[Dictionary] = city.borough_blocks
	var hits: Array = []
	for i in range(blocks.size()):
		for j in range(i + 1, blocks.size()):
			if String(blocks[i]["borough"]) != String(blocks[j]["borough"]):
				continue
			var area: float = 0.0
			for piece in Geometry2D.intersect_polygons(blocks[i]["polygon"], blocks[j]["polygon"]):
				area += BlockParcels._polygon_area(piece)
			if area > 0.05:
				hits.append([area, i, j])
	hits.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	print("same-borough overlap pairs: ", hits.size())
	for k in range(mini(3, hits.size())):
		var h: Array = hits[k]
		print("pair area=", h[0], " i=", h[1], " j=", h[2])
		print("  poly i: ", blocks[int(h[1])]["polygon"])
		print("  poly j: ", blocks[int(h[2])]["polygon"])
	get_tree().quit()
