class_name CaveGenerator
extends RefCounted
## Cellular-automata caves: random fill, then birth/survival
## smoothing. Organic, emergent, and — until Listing 22.2's cleanup
## runs — NOT guaranteed to be one connected space. Produces the
## same DungeonData as every other generator in the part, with no
## rooms and no edges: a cave asserts nothing.

var fill_probability: float = 0.45
var smooth_steps: int = 5
var birth_limit: int = 5    # floor becomes wall at >= this many wall neighbours
var survive_limit: int = 4  # wall survives at >= this many wall neighbours

var _rng: RandomNumberGenerator

func generate(master_seed: int, width: int, height: int) -> DungeonData:
	_rng = SeedBank.stream_for(master_seed, SeedBank.STREAM_DUNGEON)
	var data := DungeonData.new()
	data.setup(width, height)
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if x == 0 or y == 0 or x == width - 1 or y == height - 1:
				data.set_tile(pos, DungeonData.Tile.WALL)  # the border never leaks
			elif _rng.randf() < fill_probability:
				# FIX (build): the listing filled FLOOR here, but
				# §22.1's own tuning prose says "more fill means
				# more wall" — fill_probability is the WALL density
				# of the classic B5/S4 recipe. As printed, the map
				# started 55% wall, past the rule's percolation
				# threshold: every seed fragmented into 7-16 floor
				# regions (largest 75-498 of ~2400) and cleanup
				# deleted most of the cave, contradicting §22.2's
				# "one big cavern with a few satellite pockets"
				# and the step-7 caption. Branches swapped; the
				# 0.45 dial is unchanged.
				data.set_tile(pos, DungeonData.Tile.WALL)
			else:
				data.set_tile(pos, DungeonData.Tile.FLOOR)
	for i in smooth_steps:
		_smooth(data)
	return data

func _smooth(data: DungeonData) -> void:
	# Read from a snapshot, write into the live grid: every cell's
	# fate is decided by the SAME generation of neighbours. Updating
	# in place would let early cells vote in their neighbours'
	# elections — a different, streakier algorithm.
	var snapshot: Array = []
	for y in range(data.height):
		snapshot.append((data.tiles[y] as Array).duplicate())
	for y in range(data.height):
		for x in range(data.width):
			var pos := Vector2i(x, y)
			var walls: int = _wall_neighbours(snapshot, data.width, data.height, pos)
			var current: int = int(snapshot[y][x])
			if current == DungeonData.Tile.WALL:
				if walls < survive_limit:
					data.set_tile(pos, DungeonData.Tile.FLOOR)
			else:
				if walls >= birth_limit:
					data.set_tile(pos, DungeonData.Tile.WALL)

func _wall_neighbours(snapshot: Array, width: int, height: int, pos: Vector2i) -> int:
	var n: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var q := Vector2i(pos.x + dx, pos.y + dy)
			if q.x < 0 or q.y < 0 or q.x >= width or q.y >= height:
				n += 1  # outside the snapshot is rock, as get_tile() rules
			elif int(snapshot[q.y][q.x]) == DungeonData.Tile.WALL:
				n += 1
	return n

## Fill-policy cleanup: keep the largest floor region, return every
## other region to rock. Returns the region report from BEFORE the
## fill, so the caller can print what the guarantee cost.
func cleanup(data: DungeonData) -> Array:
	var report: Array = data.region_report()
	if report.size() <= 1:
		return report
	var keep_id: int = int(report[0]["id"])
	var labels: Array = data.label_floor_regions()
	for y in range(data.height):
		for x in range(data.width):
			var id: int = int(labels[y][x])
			if id >= 0 and id != keep_id:
				data.set_tile(Vector2i(x, y), DungeonData.Tile.WALL)
	return report

## generate() + the guarantee. This is the cave entry point the
## stage (and your games) should call.
func generate_clean(master_seed: int, width: int, height: int) -> DungeonData:
	var data: DungeonData = generate(master_seed, width, height)
	cleanup(data)
	# Entrance: the first tile of the surviving region, scan order.
	# A cave has no rooms, so "entrance room" stays -1 by design;
	# start_tile is the contract the player spawn reads.
	for y in range(data.height):
		for x in range(data.width):
			if data.is_passable(Vector2i(x, y)):
				data.start_tile = Vector2i(x, y)
				return data
	return data
