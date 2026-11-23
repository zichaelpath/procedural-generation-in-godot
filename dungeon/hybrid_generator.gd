class_name HybridGenerator
extends RefCounted
## BSP bones, cave guts: generate a guaranteed BSP dungeon, erode
## chosen rooms into organic chambers, punch in a separate cave
## pocket, connect it with a drunkard tunnel — and RE-PROVE one
## region after every surgery. Surgery without re-proof is how
## disconnected dungeons are born in generators that used to be safe.

func generate(master_seed: int, width: int, height: int) -> DungeonData:
	var rng: RandomNumberGenerator = SeedBank.stream_for(master_seed, SeedBank.STREAM_DUNGEON)
	var data: DungeonData = BSPGenerator.new().generate(master_seed, width, height)
	# Surgery 1: erode the grand hall (and the last room) into guts.
	var eroded: int = 0
	for room in data.rooms:
		var tags: Array = room["tags"]
		if tags.has("grand") or int(room["id"]) == data.rooms.size() - 1:
			_erode_room(data, room["rect"])
			tags.append("cave")
			eroded += 1
	_reconnect(data, rng, "erosion")
	# Surgery 2: a cave pocket in the rock, tunnelled in.
	_punch_cave_pocket(data, rng)
	_reconnect(data, rng, "pocket")
	print("Hybrid: eroded ", eroded, " rooms; regions now ",
		data.region_report().size(), " (must be 1)")
	return data

## A few cellular passes confined to the rect grown by a margin:
## corners round off, walls bulge, the room's ADDRESS (id, centre,
## tags) is untouched — only its tiles melt.
func _erode_room(data: DungeonData, rect: Rect2i) -> void:
	var area: Rect2i = rect.grow(1).intersection(Rect2i(1, 1, data.width - 2, data.height - 2))
	for pass_no in 2:
		var snapshot: Array = []
		for y in range(data.height):
			snapshot.append((data.tiles[y] as Array).duplicate())
		for y in range(area.position.y, area.position.y + area.size.y):
			for x in range(area.position.x, area.position.x + area.size.x):
				var pos := Vector2i(x, y)
				var walls: int = 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var q := Vector2i(pos.x + dx, pos.y + dy)
						if int(snapshot[q.y][q.x]) == DungeonData.Tile.WALL:
							walls += 1
				var current: int = int(snapshot[y][x])
				if current == DungeonData.Tile.WALL and walls < 3:
					data.set_tile(pos, DungeonData.Tile.FLOOR)
				elif current != DungeonData.Tile.WALL and walls >= 5:
					# FIX (build): the listing's >= 6 can never trigger
					# on rectangular rooms — a corner floor cell has
					# exactly 5 wall neighbours — so erosion was a
					# verified no-op (0 tiles changed at the master
					# seed). >= 5 rounds the corners, as §22.4 says.
					data.set_tile(pos, DungeonData.Tile.WALL)

## Stamp a small raw cave into open rock, far from every room rect.
## If no clean site exists, skip the pocket — a skipped feature is
## a valid outcome; a pocket stamped through a room is not.
##
## FIX (build): as listed, the grow(2) site test can never pass on
## the stage's 60x40 BSP maps — a site probe over every origin and
## pocket sizes down to 10x8 with grow(0) found NO legal site at
## the master seed (rooms + margins tile the map too completely),
## so the pocket was skipped on every seed and §22.4's caption
## ("a separate cave pocket joined by a winding tunnel") was
## unreachable. The search below keeps the listing's random
## attempts first, then falls back to a deterministic scan for an
## origin whose pocket floor cells land ONLY on rock (zero
## overwrites), then to the fewest-overwrite origin. Stamping is
## monotonic (wall cells only), so the fallback can graze a room's
## rock margin but can never overwrite a room or corridor tile.
func _punch_cave_pocket(data: DungeonData, rng: RandomNumberGenerator) -> void:
	var cave := CaveGenerator.new()
	cave.fill_probability = 0.48
	cave.smooth_steps = 4
	var pocket: DungeonData = cave.generate(rng.randi(), 18, 12)
	var placed: bool = false
	for attempt in 24:
		var ox: int = rng.randi_range(2, data.width - 20)
		var oy: int = rng.randi_range(2, data.height - 14)
		var site := Rect2i(ox, oy, 18, 12)
		var clear: bool = true
		for room in data.rooms:
			if site.intersects((room["rect"] as Rect2i).grow(2)):
				clear = false
				break
		if not clear:
			continue
		_stamp_pocket(data, pocket, ox, oy)
		placed = true
		break
	if not placed:
		var origin: Vector2i = _scan_pocket_site(data, pocket)
		if origin.x >= 0:
			_stamp_pocket(data, pocket, origin.x, origin.y)
			placed = true
	print("Hybrid pocket placed: ", placed)

## Writes the pocket's open cells at (ox, oy), WALL cells only —
## excavation stays monotonic even when the site grazes a room.
func _stamp_pocket(data: DungeonData, pocket: DungeonData, ox: int, oy: int) -> void:
	for y in range(12):
		for x in range(18):
			if pocket.get_tile(Vector2i(x, y)) != DungeonData.Tile.WALL:
				var target := Vector2i(ox + x, oy + y)
				if data.get_tile(target) == DungeonData.Tile.WALL:
					data.set_tile(target, DungeonData.Tile.FLOOR)

## Deterministic fallback site search: the first origin (scan
## order) where every pocket floor cell lands on rock; if none,
## the origin with the fewest non-rock landings. (-1, -1) only if
## the map has no rock left at all.
func _scan_pocket_site(data: DungeonData, pocket: DungeonData) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_hits: int = 1 << 30
	for oy in range(1, data.height - 12):
		for ox in range(1, data.width - 18):
			var hits: int = 0
			for y in range(12):
				for x in range(18):
					if pocket.get_tile(Vector2i(x, y)) != DungeonData.Tile.WALL:
						if data.get_tile(Vector2i(ox + x, oy + y)) != DungeonData.Tile.WALL:
							hits += 1
			if hits == 0:
				return Vector2i(ox, oy)
			if hits < best_hits:
				best_hits = hits
				best = Vector2i(ox, oy)
	return best

## The re-proof: label regions; tunnel the largest region to every
## smaller one until one region remains. Prints nothing — the
## caller prints the final report, so the receipt has one author.
func _reconnect(data: DungeonData, rng: RandomNumberGenerator, _why: String) -> void:
	var report: Array = data.region_report()
	while report.size() > 1:
		var labels: Array = data.label_floor_regions()
		var main_id: int = int(report[0]["id"])
		var main_tile := Vector2i(-1, -1)
		var other_tile := Vector2i(-1, -1)
		for y in range(data.height):
			for x in range(data.width):
				var id: int = int(labels[y][x])
				if id == main_id and main_tile == Vector2i(-1, -1):
					main_tile = Vector2i(x, y)
				elif id == int(report[1]["id"]) and other_tile == Vector2i(-1, -1):
					other_tile = Vector2i(x, y)
		WalkTunneller.connect_points(data, rng, other_tile, main_tile, 30)
		report = data.region_report()
