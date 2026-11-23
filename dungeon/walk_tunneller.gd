class_name WalkTunneller
extends RefCounted
## A random-walk carver with direction persistence and a budget of
## NEW tiles. Two modes: carve() wanders freely (mine shafts, cave
## flavour); connect_points() wanders WITH a destination and finishes
## straight, so the connection is guaranteed, not hoped for.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Wander from `start`, carving CORRIDOR into wall (never relabelling
## existing open tiles — monotonic carving, Ch 21's rule), until
## `budget` new tiles have been opened. Returns tiles opened.
static func carve(data: DungeonData, rng: RandomNumberGenerator, start: Vector2i, budget: int, persistence: float = 0.7) -> int:
	var pos: Vector2i = start
	var dir: Vector2i = DIRS[rng.randi_range(0, 3)]
	var opened: int = 0
	var steps_left: int = budget * 40  # hard step cap: a walker can loiter
	while opened < budget and steps_left > 0:
		steps_left -= 1
		if data.get_tile(pos) == DungeonData.Tile.WALL:
			data.set_tile(pos, DungeonData.Tile.CORRIDOR)
			opened += 1
		if rng.randf() >= persistence:
			dir = _fresh_direction(rng, dir)
		var next: Vector2i = pos + dir
		next.x = clampi(next.x, 1, data.width - 2)
		next.y = clampi(next.y, 1, data.height - 2)
		pos = next
	return opened

## (Named connect_points in code: Listing 22.3's `connect` cannot
## compile — it overrides Object.connect(). See the build report.)
## Wander from `from` toward `to`, then finish straight. The wander
## gives the tunnel its character; the straight finish is the
## contract: when this returns, `to` is reachable from `from`.
static func connect_points(data: DungeonData, rng: RandomNumberGenerator, from: Vector2i, to: Vector2i, wander_budget: int = 60) -> void:
	var pos: Vector2i = from
	var opened: int = 0
	var guard: int = wander_budget * 40 + 400
	while pos != to and guard > 0:
		guard -= 1
		if data.get_tile(pos) == DungeonData.Tile.WALL:
			data.set_tile(pos, DungeonData.Tile.CORRIDOR)
			opened += 1
		if opened >= wander_budget:
			break  # wandered enough — the straight finish takes over
		# Drift: half the steps aim at the target, half wander.
		var dir: Vector2i
		if rng.randf() < 0.5:
			var delta: Vector2i = to - pos
			if abs(delta.x) >= abs(delta.y):
				dir = Vector2i(signi(delta.x), 0)
			else:
				dir = Vector2i(0, signi(delta.y))
		else:
			dir = DIRS[rng.randi_range(0, 3)]
		var next: Vector2i = pos + dir
		next.x = clampi(next.x, 1, data.width - 2)
		next.y = clampi(next.y, 1, data.height - 2)
		pos = next
	_carve_straight(data, pos, to)

static func _carve_straight(data: DungeonData, a: Vector2i, b: Vector2i) -> void:
	var pos: Vector2i = a
	while pos.x != b.x:
		if data.get_tile(pos) == DungeonData.Tile.WALL:
			data.set_tile(pos, DungeonData.Tile.CORRIDOR)
		pos.x += signi(b.x - pos.x)
	while pos.y != b.y:
		if data.get_tile(pos) == DungeonData.Tile.WALL:
			data.set_tile(pos, DungeonData.Tile.CORRIDOR)
		pos.y += signi(b.y - pos.y)
	if data.get_tile(b) == DungeonData.Tile.WALL:
		data.set_tile(b, DungeonData.Tile.CORRIDOR)

static func _fresh_direction(rng: RandomNumberGenerator, current: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in DIRS:
		if d != current and d != -current:
			options.append(d)  # turns, never U-turns: tunnels don't fold
	return options[rng.randi_range(0, options.size() - 1)]
