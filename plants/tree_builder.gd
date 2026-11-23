@tool
class_name TreeBuilder
extends RefCounted

## The body shop: skins ANY segment skeleton (turtle, recursion, or
## space colonization — dictionaries with from/to/depth/dist) as
## tapered cylinders merged into ONE ArrayMesh. Vertex colours bake
## a bark->twig gradient. Three brains, one body shop: when you
## write a new plant brain, you never write rendering again.

static var base_radius: float = 0.09
static var taper_per_meter: float = 0.86   # radius multiplier per metre of dist
static var depth_step: float = 0.78        # extra shrink per bracket depth
static var min_radius: float = 0.008

## --- Species table ---
## ONE row per species, EVERY field consumed by the ONE builder:
## bark/twig -> build_mesh colours; base_radius/taper/depth_step ->
## radius_at; children/length_factor/spread_degrees/droop/
## start_length/depth -> recursive_skeleton; leaf_density/
## leaf_coherence -> build_leaves (passed in by the caller);
## deadness -> recursive_skeleton's per-child roll. The statics at
## the top of this file are now only the DEFAULTS for a caller that
## passes no row — space colonization (Chapter 18) is that caller.
static var SPECIES: Dictionary = {
	"Oak": {
		"bark": Color(0.32, 0.22, 0.13), "twig": Color(0.45, 0.42, 0.25),
		"base_radius": 0.09, "taper": 0.86, "depth_step": 0.78,
		"children": 2, "length_factor": 0.72, "spread_degrees": 28.0, "droop": 0.12,
		"start_length": 1.2, "depth": 5,
		"leaf_density": 1.0, "leaf_coherence": 0.35, "deadness": 0.05,
	},
	"Pine": {
		"bark": Color(0.38, 0.30, 0.24), "twig": Color(0.42, 0.38, 0.28),
		"base_radius": 0.07, "taper": 0.90, "depth_step": 0.82,
		"children": 3, "length_factor": 0.68, "spread_degrees": 38.0, "droop": 0.04,
		"start_length": 1.5, "depth": 5,
		"leaf_density": 0.85, "leaf_coherence": 0.8, "deadness": 0.18,
	},
	"Willow": {
		"bark": Color(0.40, 0.33, 0.22), "twig": Color(0.50, 0.48, 0.30),
		"base_radius": 0.11, "taper": 0.82, "depth_step": 0.74,
		"children": 2, "length_factor": 0.82, "spread_degrees": 24.0, "droop": 0.38,
		"start_length": 1.1, "depth": 5,
		"leaf_density": 1.25, "leaf_coherence": 0.2, "deadness": 0.02,
	},
}

static func radius_at(dist: float, depth: int, species: Dictionary = {}) -> float:
	var base_r: float = float(species.get("base_radius", base_radius))
	var taper: float = float(species.get("taper", taper_per_meter))
	var step: float = float(species.get("depth_step", depth_step))
	var r: float = base_r * pow(taper, dist) * pow(step, float(depth))
	return maxf(r, min_radius)

## --- Branch geometry cache ---
## A branch's GEOMETRY is its length, its two radii and its radial
## count — not where it sits or which way it points. Build each
## unique shape once in local space (base at the origin, tip up
## +Y), cache it, and transform copies into place. Keys are
## bucketed (length to 0.02 m, radii to 0.005 m): a twig may land
## millimetres off the exact radius — invisible — in exchange for
## being built only once.
static var _branch_cache: Dictionary = {}
static var _cache_reuses: int = 0

static func _branch_triangles(radial_segments: int, length: float, r0: float, r1: float) -> PackedVector3Array:
	var key: String = "%d|%0.2f|%0.3f|%0.3f" % [
		radial_segments, snappedf(length, 0.02), snappedf(r0, 0.005), snappedf(r1, 0.005)]
	if _branch_cache.has(key):
		_cache_reuses += 1
		return _branch_cache[key]
	# Build this shape once, from the BUCKETED values, so every
	# segment that shares the key shares these exact triangles.
	var qlen: float = snappedf(length, 0.02)
	var qr0: float = snappedf(r0, 0.005)
	var qr1: float = snappedf(r1, 0.005)
	var tris := PackedVector3Array()
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for k in radial_segments:
		var ang: float = TAU * float(k) / float(radial_segments)
		ring0.append(Vector3(cos(ang) * qr0, 0.0, sin(ang) * qr0))
		ring1.append(Vector3(cos(ang) * qr1, qlen, sin(ang) * qr1))
	for k in radial_segments:
		var k2: int = (k + 1) % radial_segments
		# Quad = two triangles: (r0k, r1k, r1k2) and (r0k, r1k2, r0k2)
		tris.append(ring0[k]); tris.append(ring1[k]); tris.append(ring1[k2])
		tris.append(ring0[k]); tris.append(ring1[k2]); tris.append(ring0[k2])
	_branch_cache[key] = tris
	return tris

static func build_mesh(segments: Array[Dictionary], radial_segments: int = 8, species: Dictionary = {}) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = species.get("bark", Color(0.32, 0.22, 0.13))
	var twig: Color = species.get("twig", Color(0.45, 0.42, 0.25))
	var reuses_before: int = _cache_reuses
	for seg in segments:
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		var depth: int = int(seg["depth"])
		var dist: float = float(seg["dist"])
		var seg_len: float = a.distance_to(b)
		var r0: float = radius_at(dist, depth, species)
		var r1: float = radius_at(dist + seg_len, depth, species)
		var shade: float = clampf(dist / 3.0, 0.0, 1.0)
		var col: Color = bark.lerp(twig, shade)
		if bool(seg.get("dead", false)):
			col = Color(0.52, 0.50, 0.46)  # dead wood: grey, no gradient
		var dir: Vector3 = (b - a).normalized()
		var helper: Vector3 = Vector3.UP
		if abs(dir.dot(Vector3.UP)) > 0.99:
			helper = Vector3.RIGHT
		var axis1: Vector3 = dir.cross(helper).normalized()
		var axis2: Vector3 = dir.cross(axis1).normalized()
		var tris: PackedVector3Array = _branch_triangles(radial_segments, seg_len, r0, r1)
		st.set_color(col)
		for v in tris:
			st.add_vertex(a + axis1 * v.x + dir * v.y + axis2 * v.z)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	print("TreeBuilder: ", segments.size(), " segments -> ",
		mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " vertices",
		" | branch cache: ", _branch_cache.size(), " unique, ",
		_cache_reuses - reuses_before, " reused this build")
	return mesh

## Recursive tree: a branch function that calls itself with less
## length and less depth budget. It reads its dials from ONE species
## row (see SPECIES above) and produces the SAME segment
## dictionaries as the turtle, so the same skinning and leaves
## consume it untouched. Callers with a plain parameters dictionary
## still work: every field is read with .get and a default.
static func recursive_skeleton(
	start: Vector3, direction: Vector3, length: float, depth: int,
	params: Dictionary, rng: RandomNumberGenerator,
	dist: float = 0.0, out: Array[Dictionary] = [], dead: bool = false
) -> Array[Dictionary]:
	var end: Vector3 = start + direction * length
	out.append({"from": start, "to": end, "depth": depth, "dist": dist, "dead": dead})
	if dead or depth <= 0 or length < 0.12:
		return out  # termination: dead, OR depth floor, OR length floor
	var children: int = int(params.get("children", 2))
	var length_factor: float = float(params.get("length_factor", 0.72))
	var spread_deg: float = float(params.get("spread_degrees", 28.0))
	var droop: float = float(params.get("droop", 0.12))
	var deadness: float = float(params.get("deadness", 0.0))
	# A stable frame around the branch direction, for spreading children.
	var helper: Vector3 = Vector3.UP
	if abs(direction.dot(Vector3.UP)) > 0.99:
		helper = Vector3.RIGHT
	var side: Vector3 = direction.cross(helper).normalized()
	var around: Vector3 = direction.cross(side).normalized()
	for c in children:
		var around_angle: float = TAU * float(c) / float(children) + rng.randf_range(-0.4, 0.4)
		var spread: float = deg_to_rad(spread_deg) * rng.randf_range(0.75, 1.25)
		var child_dir: Vector3 = (direction
			+ (side * cos(around_angle) + around * sin(around_angle)) * tan(spread)
			+ Vector3.DOWN * droop).normalized()
		var child_len: float = length * length_factor * rng.randf_range(0.85, 1.15)
		# Deadness is rolled PER CHILD from the species row: a dead
		# child grows once, short, marked dead — build_mesh greys it
		# and build_leaves skips it — and never recurses.
		var is_dead: bool = rng.randf() < deadness
		var grow_len: float = child_len * 0.45 if is_dead else child_len
		recursive_skeleton(end, child_dir, grow_len, depth - 1, params, rng, dist + length, out, is_dead)
	return out

## Leaf placement, species-aware: dead segments never carry leaves,
## and COHERENCE — the species row's agreement dial — narrows the
## yaw, tilt and scale ranges as it rises toward 1.0, so one tree's
## leaves behave as one canopy instead of a crowd. At coherence
## 0.0 the ranges are exactly Listing 17.3's.
static func build_leaves(segments: Array[Dictionary], leaf_mesh: Mesh, density: float, min_depth: int, rng: RandomNumberGenerator, coherence: float = 0.0) -> MultiMesh:
	var is_start: Dictionary = {}
	for seg in segments:
		is_start[seg["from"]] = true
	var sites: Array[Dictionary] = []
	for seg in segments:
		if bool(seg.get("dead", false)):
			continue  # dead wood carries no leaves, at any density
		var terminal: bool = not is_start.has(seg["to"])
		if terminal or int(seg["depth"]) >= min_depth:
			var chance: float = 0.45 if terminal else 0.12
			if rng.randf() < chance * density:
				sites.append(seg)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = leaf_mesh
	mm.instance_count = sites.size()
	var yaw_range: float = lerpf(PI, 0.35, coherence)
	var tilt_range: float = lerpf(0.6, 0.15, coherence)
	var scale_var: float = lerpf(0.25, 0.05, coherence)
	for i in sites.size():
		var seg: Dictionary = sites[i]
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		var dir: Vector3 = (b - a).normalized()
		var tip: Vector3 = b + dir * 0.06
		var up_hint: Vector3 = Vector3.UP
		if abs(dir.dot(Vector3.UP)) > 0.99:
			up_hint = Vector3.RIGHT
		var basis: Basis = Basis.looking_at(dir, up_hint)
		basis = basis.rotated(basis.y, rng.randf_range(-yaw_range, yaw_range))
		basis = basis.rotated(basis.x, rng.randf_range(-tilt_range, tilt_range))
		var scale: float = rng.randf_range(1.0 - scale_var * 0.8, 1.0 + scale_var)
		basis = basis.scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, Transform3D(basis, tip))
	return mm
