class_name WfcGenerator
extends RefCounted
## A small, honest Wave Function Collapse solver. A cell starts
## able to be EVERY tile; collapsing picks one; propagation removes
## neighbour options whose sockets break the contract. Two tiles
## may sit side by side when the touching socket labels match.

const DIRS: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)] # N E S W
const OPPOSITE: Array = [2, 3, 0, 1]

var tile_defs: Array = []
var width: int = 0
var height: int = 0
var rng: RandomNumberGenerator
var cells: Array = []      # per cell: Array of still-possible tile indices
var collapsed: Array = []  # per cell: final tile index, or -1 while undecided
var contradiction: bool = false

func _init(defs: Array, w: int, h: int, stream: RandomNumberGenerator) -> void:
	tile_defs = defs
	width = w
	height = h
	rng = stream
	reset()

func reset() -> void:
	cells.clear()
	collapsed.clear()
	contradiction = false
	var all: Array = []
	for i in range(tile_defs.size()):
		all.append(i)
	for y in range(height):
		for x in range(width):
			# DUPLICATE per cell. Sharing one list across cells would
			# let one propagation edit two cells — a haunting, not a bug
			# you can find by reading the code once.
			cells.append(all.duplicate())
			collapsed.append(-1)

func _idx(x: int, y: int) -> int:
	return y * width + x

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func is_finished() -> bool:
	if contradiction:
		return true
	for c in collapsed:
		if int(c) == -1:
			return false
	return true

# The cell with the fewest remaining options is the most dangerous
# one left on the board, so it decides first. Ties break through
# the stream: same seed, same tie-breaks, same dungeon.
func lowest_entropy_cell() -> int:
	var best_size: int = 999999
	var ties: Array = []
	for i in range(cells.size()):
		if int(collapsed[i]) != -1:
			continue
		var option_count: int = (cells[i] as Array).size()
		if option_count < best_size:
			best_size = option_count
			ties = [i]
		elif option_count == best_size:
			ties.append(i)
	if ties.is_empty():
		return -1
	return int(ties[rng.randi_range(0, ties.size() - 1)])

func collapse_step() -> bool:
	if contradiction:
		return false
	var cell: int = lowest_entropy_cell()
	if cell == -1:
		return false
	var options: Array = cells[cell]
	if options.is_empty():
		contradiction = true
		return false
	var pick: int = _weighted_pick(options)
	cells[cell] = [pick]
	collapsed[cell] = pick
	_propagate(cell)
	return not contradiction

func _weighted_pick(options: Array) -> int:
	var total: float = 0.0
	for o in options:
		total += float(tile_defs[int(o)].get("weight", 1.0))
	var roll: float = rng.randf() * total
	for o in options:
		roll -= float(tile_defs[int(o)].get("weight", 1.0))
		if roll <= 0.0:
			return int(o)
	return int(options[options.size() - 1])

func _propagate(from_cell: int) -> void:
	var stack: Array = [from_cell]
	while not stack.is_empty():
		var current: int = int(stack[stack.size() - 1])
		stack.remove_at(stack.size() - 1)
		var cx: int = current % width
		var cy: int = current / width
		for d in range(4):
			var dir: Vector2i = DIRS[d]
			var nx: int = cx + dir.x
			var ny: int = cy + dir.y
			if not _in_bounds(nx, ny):
				continue
			var ncell: int = _idx(nx, ny)
			if int(collapsed[ncell]) != -1:
				continue
			var before: int = (cells[ncell] as Array).size()
			var kept: Array = []
			for option in cells[ncell]:
				if _can_sit(current, int(option), d):
					kept.append(option)
			cells[ncell] = kept
			if kept.is_empty():
				contradiction = true
				return
			if kept.size() != before:
				stack.append(ncell)

# A candidate survives in the neighbour if at least one tile still
# possible in the current cell presents a matching socket label.
# This is arc consistency in plain clothes, and it does ninety
# percent of the work in this chapter.
func _can_sit(from_cell: int, candidate: int, dir: int) -> bool:
	var need: String = str(tile_defs[candidate]["sockets"][OPPOSITE[dir]])
	for option in cells[from_cell]:
		if str(tile_defs[int(option)]["sockets"][dir]) == need:
			return true
	return false

func run_to_completion(max_steps: int = 100000) -> bool:
	var steps: int = 0
	while not is_finished() and steps < max_steps:
		collapse_step()
		steps += 1
	return not contradiction

## The dungeon tile set, written ONCE per shape. Sockets are
## "wall" / "floor" per side [N, E, S, W]; kind decides how the
## finished cell translates into DungeonData.
static func dungeon_base_tiles() -> Array:
	var w: String = "wall"
	var f: String = "floor"
	return [
		{"name": "solid", "kind": "wall", "sockets": [w, w, w, w], "weight": 1.0},
		{"name": "open", "kind": "floor", "sockets": [f, f, f, f], "weight": 4.0},
		{"name": "edge", "kind": "wall", "sockets": [w, f, f, f], "weight": 1.2},
		{"name": "corner", "kind": "wall", "sockets": [w, w, f, f], "weight": 0.8},
		{"name": "door_edge", "kind": "door", "sockets": [w, f, f, f], "weight": 0.5},
		{"name": "pillar", "kind": "pillar", "sockets": [f, f, f, f], "weight": 0.35},
	]

## Expands base tiles into all distinct rotations. Rotating 90
## degrees clockwise: new [N,E,S,W] = old [W,N,E,S]. Duplicates
## are dropped — a symmetric tile kept four times would silently
## quadruple its weight.
static func expanded_tiles() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for base in dungeon_base_tiles():
		var sockets: Array = (base["sockets"] as Array).duplicate()
		for rot in 4:
			var key: String = str(base["name"]) + "|" + str(sockets)
			if not seen.has(key):
				seen[key] = true
				var tile: Dictionary = base.duplicate()
				tile["sockets"] = sockets.duplicate()
				tile["rotation"] = rot
				out.append(tile)
			sockets = [sockets[3], sockets[0], sockets[1], sockets[2]]
	return out

## Runs the solver into a DungeonData, restarting on contradiction
## from the SAME continuing stream. The retry count is recorded in
## meta: it is the tile set's temperament, measured.
static func generate_dungeon(master_seed: int, size: int = 24, max_retries: int = 40) -> DungeonData:
	var stream: RandomNumberGenerator = SeedBank.stream_for(master_seed, SeedBank.STREAM_DUNGEON)
	var defs: Array = expanded_tiles()
	var data := DungeonData.new()
	data.setup(size, size)
	var retries: int = 0
	while retries <= max_retries:
		var solver := WfcGenerator.new(defs, size, size, stream)
		if solver.run_to_completion():
			var pillars: Array = []
			for y in range(size):
				for x in range(size):
					var tile: Dictionary = defs[int(solver.collapsed[solver._idx(x, y)])]
					match str(tile["kind"]):
						"wall":
							data.set_tile(Vector2i(x, y), DungeonData.Tile.WALL)
						"floor":
							data.set_tile(Vector2i(x, y), DungeonData.Tile.FLOOR)
						"door":
							data.set_tile(Vector2i(x, y), DungeonData.Tile.DOOR)
						"pillar":
							data.set_tile(Vector2i(x, y), DungeonData.Tile.FLOOR)
							pillars.append(Vector2i(x, y))
			data.meta["pillars"] = pillars
			data.meta["wfc_retries"] = retries
			# Start tile: first floor cell in scan order.
			for y in range(size):
				for x in range(size):
					if data.is_passable(Vector2i(x, y)):
						data.start_tile = Vector2i(x, y)
						return data
			return data
		retries += 1
	# Every attempt contradicted: return solid rock and SAY SO in
	# the data. A silent partial dungeon would be worse.
	data.meta["wfc_retries"] = retries
	data.meta["wfc_failed"] = true
	return data
