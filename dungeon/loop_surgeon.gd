class_name LoopSurgeon
extends RefCounted
## The two-step loop method. Step one: backbone_report() verifies
## the spanning backbone (connected, zero loops) — surgery never
## starts from an assumption. Step two: add_one_loop_priced() buys
## exactly one loop and returns its price tag. Surgery rule, from
## Ch 21 and never waived: graph and tiles change together, in the
## same function, or the mission layer and the player will disagree
## about what is connected.

## Step one, as data: the guarantee, printable. A false "connected"
## or a nonzero "loops" means there is no backbone yet.
static func backbone_report(data: DungeonData) -> Dictionary:
	var reached: int = data.bfs_room_distances(data.entrance_room).size()
	return {
		"rooms": data.rooms.size(),
		"edges": data.edges.size(),
		"loops": loop_count(data),
		"reached": reached,
		"connected": reached == data.rooms.size(),
	}

## Loops = edges beyond a tree (edges - rooms + 1).
static func loop_count(data: DungeonData) -> int:
	return data.edges.size() - (data.rooms.size() - 1)

## The story length right now: entrance to farthest room, in
## rooms. (Ch 24 refines this to entrance->boss once roles exist;
## the surgeon measures with the graph it has.)
static func story_length(data: DungeonData) -> int:
	var dist: Dictionary = data.bfs_room_distances(data.entrance_room)
	var far: int = 0
	for id in dist.keys():
		far = maxi(far, int(dist[id]))
	return far + 1  # distances count edges; the path counts rooms

## Adds up to loop_count loops. Candidates must sit graph-distance
## 3-4 apart (2 = trivial triangle, 6+ = second spine) and
## physically close, so corridors stay short. Returns loops added.
static func add_loops(data: DungeonData, rng: RandomNumberGenerator, count: int, min_graph_distance: int = 3, max_graph_distance: int = 4, max_cell_distance: float = 26.0) -> int:
	var added: int = 0
	var attempts: int = 0
	var max_attempts: int = count * 12
	while added < count and attempts < max_attempts:
		attempts += 1
		var a: int = int(data.rooms[rng.randi_range(0, data.rooms.size() - 1)]["id"])
		var distances: Dictionary = data.bfs_room_distances(a)
		var neighbours: Array = data.adjacency().get(a, [])
		var candidates: Array = []
		for room in data.rooms:
			var b: int = int(room["id"])
			if b == a or neighbours.has(b) or not distances.has(b):
				continue
			var graph_dist: int = int(distances[b])
			if graph_dist < min_graph_distance or graph_dist > max_graph_distance:
				continue
			var centre_a: Vector2i = data.room_by_id(a)["center"]
			var centre_b: Vector2i = room["center"]
			if Vector2(centre_a).distance_to(Vector2(centre_b)) > max_cell_distance:
				continue
			candidates.append(b)
		if candidates.is_empty():
			continue
		var target: int = int(candidates[rng.randi_range(0, candidates.size() - 1)])
		var from_cell: Vector2i = data.room_by_id(a)["center"]
		var to_cell: Vector2i = data.room_by_id(target)["center"]
		# Tiles first, edge second, same breath. The digging is
		# Ch 21's L-carver on a borrowed BSPGenerator instance,
		# seeded the way generate() seeds it.
		var digger := BSPGenerator.new()
		digger.corridor_width = 1
		digger.build_tree(rng.randi(), data.width, data.height)
		var corner: Vector2i = digger._carve_corridor(data, from_cell, to_cell)
		data.edges.append({"a": a, "b": target, "door_tile": corner, "locked_key": ""})
		added += 1
	return added

## Step two, one purchase at a time: add exactly one loop and
## return its receipt — story length before and after, and the
## running loop total. Buying in bulk and pricing afterwards is
## not the method.
static func add_one_loop_priced(data: DungeonData, rng: RandomNumberGenerator) -> Dictionary:
	var before: int = story_length(data)
	var added: int = add_loops(data, rng, 1)
	var after: int = story_length(data)
	return {
		"added": added,
		"path_before": before,
		"path_after": after,
		"loops": loop_count(data),
	}
