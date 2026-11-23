class_name SpaceColonization
extends RefCounted

## Space colonization (Runions et al. 2007): branches grow TOWARD
## unclaimed space. Attraction points float in a canopy volume;
## nodes grow toward the points that claim them; points die when a
## node gets close. The shape of the point cloud IS the species —
## the algorithm just competes for it.
##
## Output: the same segment dictionaries TreeBuilder already skins.

var step_length: float = 0.22
var influence_radius: float = 1.6
var kill_distance: float = 0.35
var max_iterations: int = 400

## --- Canopy clouds: where the goals float. All randomness from
## the stream the caller passes in. ---

static func cloud_ball(center: Vector3, radius: float, count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for n in count:
		# Rejection-sample a uniform ball (simple, and count is small).
		while true:
			var p := Vector3(
				rng.randf_range(-radius, radius),
				rng.randf_range(-radius, radius),
				rng.randf_range(-radius, radius))
			if p.length() <= radius:
				pts.append(center + p)
				break
	return pts

static func cloud_umbrella(center: Vector3, radius: float, count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for n in count:
		var ang: float = rng.randf_range(0.0, TAU)
		var r: float = radius * sqrt(rng.randf())  # sqrt = uniform over the disc
		var p := Vector3(cos(ang) * r, rng.randf_range(-0.25, 0.45), sin(ang) * r)
		pts.append(center + p)
	return pts

static func cloud_cone(center: Vector3, height: float, base_radius: float, count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for n in count:
		var t: float = rng.randf()  # 0 at base, 1 at tip
		var local_radius: float = base_radius * (1.0 - t)
		var ang: float = rng.randf_range(0.0, TAU)
		var r: float = local_radius * sqrt(rng.randf())
		pts.append(center + Vector3(cos(ang) * r, t * height, sin(ang) * r))
	return pts

func _nearest_point_dist(from: Vector3, points: Array[Vector3]) -> float:
	var best: float = INF
	for p in points:
		best = minf(best, from.distance_to(p))
	return best

## --- The growth loop: sense -> grow -> kill, until the cloud is
## claimed or the budget runs out. Both guards are load-bearing. ---

func grow(points_in: Array[Vector3], trunk_base: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var points: Array[Vector3] = points_in.duplicate()
	var nodes: Array[Vector3] = [trunk_base]
	var parents: Array[int] = [-1]
	var generations: Array[int] = [0]
	# Phase 1: grow the trunk until it can feel the cloud.
	var guard: int = 0
	while _nearest_point_dist(nodes[nodes.size() - 1], points) > influence_radius and guard < 200:
		var prev: Vector3 = nodes[nodes.size() - 1]
		nodes.append(prev + Vector3.UP * step_length)
		parents.append(nodes.size() - 2)
		generations.append(generations[generations.size() - 1] + 1)
		guard += 1
	# Phase 2: sense -> grow -> kill, until the cloud is claimed or capped.
	var iteration: int = 0
	var last_point_count: int = points.size() + 1
	while not points.is_empty() and iteration < max_iterations:
		iteration += 1
		# Each point claims its nearest node within influence.
		var claims: Dictionary = {}  # node index -> Array of directions
		for p in points:
			var best: int = -1
			var best_d: float = influence_radius
			for ni in nodes.size():
				var d: float = nodes[ni].distance_to(p)
				if d < best_d:
					best_d = d
					best = ni
			if best != -1:
				if not claims.has(best):
					claims[best] = []
				claims[best].append((p - nodes[best]).normalized())
		if claims.is_empty():
			break  # nothing can feel anything: remaining points are stranded
		# Grow one new node per claimed node, toward the average claim.
		var new_nodes: Array[Vector3] = []
		var new_parents: Array[int] = []
		var new_gens: Array[int] = []
		for ni in claims.keys():
			var avg := Vector3.ZERO
			for dir in claims[ni]:
				avg += dir
			avg = (avg / float(claims[ni].size())).normalized()
			# A whisper of upward bias keeps crowns from sagging
			# into the ground.
			avg = (avg + Vector3.UP * 0.08).normalized()
			new_nodes.append(nodes[ni] + avg * step_length)
			new_parents.append(int(ni))
			new_gens.append(generations[ni] + 1)
		for i in new_nodes.size():
			nodes.append(new_nodes[i])
			parents.append(new_parents[i])
			generations.append(new_gens[i])
		# Kill points that any node has reached.
		var survivors: Array[Vector3] = []
		for p in points:
			var killed: bool = false
			for ni in nodes.size():
				if nodes[ni].distance_to(p) < kill_distance:
					killed = true
					break
			if not killed:
				survivors.append(p)
		points = survivors
		if points.size() == last_point_count and iteration > 30:
			break  # stalled: the survivors are unreachable stragglers
		last_point_count = points.size()
	print("Colonization: ", nodes.size(), " nodes, ", iteration, " iterations, ",
		points.size(), " points unclaimed")
	# Convert nodes+parents into TreeBuilder segments.
	var segments: Array[Dictionary] = []
	for ni in range(1, nodes.size()):
		var from: Vector3 = nodes[parents[ni]]
		var to: Vector3 = nodes[ni]
		segments.append({
			"from": from, "to": to,
			"depth": generations[ni] / 6,  # generation scaled into "branch depth"
			"dist": float(generations[ni]) * step_length,
		})
	return segments
