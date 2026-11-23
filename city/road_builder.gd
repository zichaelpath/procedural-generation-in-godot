class_name RoadBuilder
extends Node3D

## Turns a RoadNetwork's DRAW segments into geometry: one flat ribbon
## per segment, one pad per junction. Reads data, decides nothing.
## Ribbons sample height_at() at both ends and at the midpoint, so a
## street crossing a swell sits ON the terrain instead of through it.
##
## Project integration notes:
## - build_network() takes an optional road filter (a list of logic
##   road indices). Chapter 41's stage draws one builder per borough
##   so the ENGINE shot's Scene dock shows the boroughs as nodes;
##   the segments drawn are the same globally-derived set, filtered
##   by the road each segment was clipped from. Unfiltered (the
##   default) this is Listing 37.2 exactly.
## - Junction degrees are accumulated in ONE pass as 4-bit direction
##   masks (the same masks RoadNetwork.connection_mask() computes
##   per node), instead of one full segment scan per node. Identical
##   degrees; Chapter 42's network has thousands of both.

const STREET_WIDTH: float = 7.0
const AVENUE_WIDTH: float = 11.0

var _asphalt: StandardMaterial3D
var _pad_material: StandardMaterial3D


func _init() -> void:
	_asphalt = StandardMaterial3D.new()
	_asphalt.albedo_color = Color(0.16, 0.16, 0.17)
	_asphalt.roughness = 0.95
	_pad_material = StandardMaterial3D.new()
	_pad_material.albedo_color = Color(0.22, 0.22, 0.23)
	_pad_material.roughness = 0.95


## The height of the RENDERED terrain at (x, z). TerrainMesh draws
## two planar triangles per height-grid cell while height_at()
## interpolates bilinearly; over one cell the two surfaces disagree
## by up to a quarter of the cell's corner spread — on this relief,
## more than any sane ribbon lift. Anything that must sit ON the
## picture drapes against this surface, not the bilinear one.
static func facet_height(terrain: TerrainHeight, x: float,
		z: float) -> float:
	if terrain.noise_backed:
		# A function-backed field has no grid to read (Ch 43's
		# capstone terrain): the query IS the surface truth —
		# the chunk meshes are built from it.
		return terrain.height_at(x, z)
	var size: float = terrain.world_size
	var cells: int = terrain.cells
	var gx: float = clampf((x + size * 0.5) / size * float(cells),
		0.0, float(cells) - 0.001)
	var gz: float = clampf((z + size * 0.5) / size * float(cells),
		0.0, float(cells) - 0.001)
	var ix: int = int(gx)
	var iz: int = int(gz)
	var fx: float = gx - float(ix)
	var fz: float = gz - float(iz)
	var h00: float = terrain.grid_height(ix, iz)
	var h10: float = terrain.grid_height(ix + 1, iz)
	var h01: float = terrain.grid_height(ix, iz + 1)
	var h11: float = terrain.grid_height(ix + 1, iz + 1)
	if fx + fz <= 1.0:
		return h00 * (1.0 - fx - fz) + h10 * fx + h01 * fz
	return h11 * (fx + fz - 1.0) + h10 * (1.0 - fz) + h01 * (1.0 - fx)


func build_network(network: RoadNetwork, terrain: TerrainHeight,
		road_filter: Array = []) -> void:
	for child in get_children():
		child.queue_free()
	var use_filter: bool = not road_filter.is_empty()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for seg in network.segments:
		if use_filter and not road_filter.has(int(seg["road"])):
			continue
		var road: Dictionary = network.logic_roads[int(seg["road"])]
		var width: float = AVENUE_WIDTH if road["kind"] == "avenue" \
			else STREET_WIDTH
		_ribbon_into(st, network.nodes[int(seg["a"])],
			network.nodes[int(seg["b"])], width, terrain)
	var mesh: ArrayMesh = st.commit()
	var ribbons := MeshInstance3D.new()
	ribbons.mesh = mesh
	ribbons.material_override = _asphalt
	ribbons.name = "DrawSegments"
	add_child(ribbons)
	# One pad per junction of degree >= 3: the square that lets four
	# ribbons stop at its edge instead of overlapping at its centre.
	var masks: Dictionary = _direction_masks(network, road_filter)
	var pad_st := SurfaceTool.new()
	pad_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for node_i in masks.keys():
		var degree: int = 0
		var m: int = int(masks[node_i])
		for bit in range(4):
			if m & (1 << bit) != 0:
				degree += 1
		if degree >= 3:
			_pad_into(pad_st, network.nodes[int(node_i)],
				STREET_WIDTH * 1.02, terrain)
	var pads := MeshInstance3D.new()
	pads.mesh = pad_st.commit()
	pads.material_override = _pad_material
	pads.name = "JunctionPads"
	add_child(pads)


# Per-node 4-bit direction masks over the (optionally filtered)
# segment set — the same classification as RoadNetwork's
# connection_mask(), accumulated in a single pass.
func _direction_masks(network: RoadNetwork,
		road_filter: Array) -> Dictionary:
	var use_filter: bool = not road_filter.is_empty()
	var masks: Dictionary = {}
	for seg in network.segments:
		if use_filter and not road_filter.has(int(seg["road"])):
			continue
		var a: int = int(seg["a"])
		var b: int = int(seg["b"])
		_mark(masks, network, a, b)
		_mark(masks, network, b, a)
	return masks


func _mark(masks: Dictionary, network: RoadNetwork, from_i: int,
		to_i: int) -> void:
	var d: Vector3 = network.nodes[to_i] - network.nodes[from_i]
	var angle: float = atan2(d.x, -d.z)
	var dir: int = int(round(angle / (PI * 0.5))) % 4
	if dir < 0:
		dir += 4
	masks[from_i] = int(masks.get(from_i, 0)) | (1 << dir)


func _ribbon_into(st: SurfaceTool, a: Vector3, b: Vector3,
		width: float, terrain: TerrainHeight) -> void:
	# Listing 37.2 splits the segment at its midpoint so the ribbon
	# bends over a swell. Three refinements the island's relief
	# forces, all the same idea at finer grain: split every ~3 m
	# (the mesh's own resolution); drape EVERY CORNER on the facet
	# surface (a strip held at centreline heights is buried by its
	# own uphill edge on any cross-slope); and run a centre spine
	# row, because a crowned cross-profile otherwise pokes through
	# the middle of the street as pale flecks.
	var dist: float = Vector2(b.x - a.x, b.z - a.z).length()
	var steps: int = clampi(int(ceil(dist / 3.0)), 1, 24)
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side: Vector3 = dir.cross(Vector3.UP) * (width * 0.5)
	var lift: float = 0.10
	var prev_l := Vector3.ZERO
	var prev_c := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in range(steps + 1):
		var p: Vector3 = a.lerp(b, float(i) / float(steps))
		var l: Vector3 = p - side
		var r: Vector3 = p + side
		var c: Vector3 = p
		l.y = facet_height(terrain, l.x, l.z) + lift
		r.y = facet_height(terrain, r.x, r.z) + lift
		c.y = facet_height(terrain, c.x, c.z) + lift
		if i > 0:
			st.set_normal(Vector3.UP)
			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(prev_c)
			st.add_vertex(prev_c)
			st.add_vertex(l)
			st.add_vertex(c)
			st.add_vertex(prev_c)
			st.add_vertex(c)
			st.add_vertex(prev_r)
			st.add_vertex(prev_r)
			st.add_vertex(c)
			st.add_vertex(r)
		prev_l = l
		prev_c = c
		prev_r = r


func _quad_into(st: SurfaceTool, a: Vector3, b: Vector3,
		width: float) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.01:
		return
	var side: Vector3 = flat.normalized().cross(Vector3.UP) \
		* (width * 0.5)
	var lift: float = 0.10 # sit just above the terrain, never z-fight
	var a0: Vector3 = a - side + Vector3(0.0, lift, 0.0)
	var a1: Vector3 = a + side + Vector3(0.0, lift, 0.0)
	var b0: Vector3 = b - side + Vector3(0.0, lift, 0.0)
	var b1: Vector3 = b + side + Vector3(0.0, lift, 0.0)
	st.set_normal(Vector3.UP)
	st.add_vertex(a0)
	st.add_vertex(b0)
	st.add_vertex(a1)
	st.add_vertex(a1)
	st.add_vertex(b0)
	st.add_vertex(b1)


func _pad_into(st: SurfaceTool, centre: Vector3, size: float,
		terrain: TerrainHeight) -> void:
	# A fan over eight perimeter points (corners + edge midpoints),
	# each at facet height: a flat quad at the centre's height lets
	# facet corners poke through on any slope at all.
	var h: float = size * 0.5
	var lift: float = 0.11
	var ring: Array[Vector3] = []
	var offs: Array[Vector2] = [Vector2(-h, -h), Vector2(0, -h),
		Vector2(h, -h), Vector2(h, 0), Vector2(h, h), Vector2(0, h),
		Vector2(-h, h), Vector2(-h, 0)]
	for off in offs:
		var px: float = centre.x + off.x
		var pz: float = centre.z + off.y
		ring.append(Vector3(px, facet_height(terrain, px, pz) + lift,
			pz))
	var c := Vector3(centre.x, facet_height(terrain, centre.x,
		centre.z) + lift, centre.z)
	st.set_normal(Vector3.UP)
	for i in range(ring.size()):
		st.add_vertex(c)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % ring.size()])


## Highway geometry from a finalised route (Listing 38.2's output):
## ribbon spans sampled densely at GRADE heights (not raw terrain),
## bridge spans as flat decks on piers. Appended as children of this
## builder, alongside the street meshes — one network, two builds.
func build_highway(parent: Node3D, points: PackedVector3Array,
		finalised: Dictionary, terrain: TerrainHeight) -> void:
	var grade: PackedFloat32Array = finalised["grade"]
	var spans: Array = finalised["spans"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for span in spans:
		var from_i: int = int(span["from"])
		var to_i: int = int(span["to"])
		if span["kind"] == "bridge":
			_deck_into(st, points[from_i], points[to_i],
				float(span["deck_y"]), terrain)
		else:
			for i in range(from_i, to_i):
				_dense_ribbon(st, points[i], points[i + 1],
					grade[i], grade[i + 1], terrain)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _asphalt
	mesh_instance.name = "Highway"
	parent.add_child(mesh_instance)


# A ribbon in ~3 m slices at the route's grade heights, with a skirt
# dropped to the terrain on each side: the visible cut-and-fill that
# tells the player this road was BUILT on the land, not draped on it.
func _dense_ribbon(st: SurfaceTool, a: Vector3, b: Vector3,
		ga: float, gb: float, terrain: TerrainHeight) -> void:
	var steps: int = maxi(1, int(a.distance_to(b) / 3.0))
	var prev_a: Vector3 = a
	var prev_ga: float = ga
	for s in range(1, steps + 1):
		var t: float = float(s) / float(steps)
		var p: Vector3 = a.lerp(b, t)
		var g: float = lerpf(ga, gb, t)
		# Grade is computed from bilinear samples; the rendered
		# facets can stand proud of it mid-span. The deck rides the
		# higher of the two — a guard, not a regrade.
		g = maxf(g, facet_height(terrain, p.x, p.z) + 0.10)
		_quad_at_grade(st, prev_a, p, prev_ga, g, 9.0, terrain)
		_skirt(st, prev_a, p, prev_ga, g, terrain, -1.0)
		_skirt(st, prev_a, p, prev_ga, g, terrain, 1.0)
		prev_a = p
		prev_ga = g


func _quad_at_grade(st: SurfaceTool, a: Vector3, b: Vector3,
		ga: float, gb: float, width: float,
		terrain: TerrainHeight = null) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.01:
		return
	var side: Vector3 = flat.normalized().cross(Vector3.UP) \
		* (width * 0.5)
	var a0: Vector3 = Vector3(a.x, ga, a.z) - side + Vector3(0, 0.06, 0)
	var a1: Vector3 = Vector3(a.x, ga, a.z) + side + Vector3(0, 0.06, 0)
	var b0: Vector3 = Vector3(b.x, gb, b.z) - side + Vector3(0, 0.06, 0)
	var b1: Vector3 = Vector3(b.x, gb, b.z) + side + Vector3(0, 0.06, 0)
	if terrain != null:
		# Corner clamp: on a side-hill the uphill corner of a
		# grade-held deck can dip under the rendered facet even
		# when the centreline clears it.
		a0.y = maxf(a0.y, facet_height(terrain, a0.x, a0.z) + 0.10)
		a1.y = maxf(a1.y, facet_height(terrain, a1.x, a1.z) + 0.10)
		b0.y = maxf(b0.y, facet_height(terrain, b0.x, b0.z) + 0.10)
		b1.y = maxf(b1.y, facet_height(terrain, b1.x, b1.z) + 0.10)
	st.set_normal(Vector3.UP)
	st.add_vertex(a0)
	st.add_vertex(b0)
	st.add_vertex(a1)
	st.add_vertex(a1)
	st.add_vertex(b0)
	st.add_vertex(b1)


func _skirt(st: SurfaceTool, a: Vector3, b: Vector3, ga: float,
		gb: float, terrain: TerrainHeight, side_sign: float) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.01:
		return
	var side: Vector3 = flat.normalized().cross(Vector3.UP) \
		* (4.5 * side_sign)
	var top_a := Vector3(a.x + side.x, ga + 0.05, a.z + side.z)
	var top_b := Vector3(b.x + side.x, gb + 0.05, b.z + side.z)
	var bot_a := Vector3(top_a.x, terrain.height_at(top_a.x, top_a.z)
		- 0.2, top_a.z)
	var bot_b := Vector3(top_b.x, terrain.height_at(top_b.x, top_b.z)
		- 0.2, top_b.z)
	st.set_normal(side.normalized())
	st.add_vertex(top_a)
	st.add_vertex(bot_a)
	st.add_vertex(top_b)
	st.add_vertex(top_b)
	st.add_vertex(bot_a)
	st.add_vertex(bot_b)


func _deck_into(st: SurfaceTool, a: Vector3, b: Vector3,
		deck_y: float, terrain: TerrainHeight) -> void:
	# Deck: one level quad the whole span; piers: boxes from the deck
	# down past the waterline every ~18 m. Crude, honest, readable.
	_quad_at_grade(st, a, b, deck_y, deck_y, 9.0, terrain)
	var length: float = a.distance_to(b)
	var piers: int = maxi(1, int(length / 18.0))
	for i in range(piers):
		var t: float = (float(i) + 0.5) / float(piers)
		var c: Vector3 = a.lerp(b, t)
		_pier_into(st, c, deck_y)


func _pier_into(st: SurfaceTool, centre: Vector3, deck_y: float) -> void:
	var h: float = 1.4 # half-width of the pier shaft
	var base_y: float = centre.y - 14.0 # below any book waterline
	var corners: Array[Vector3] = [
		Vector3(centre.x - h, base_y, centre.z - h),
		Vector3(centre.x + h, base_y, centre.z - h),
		Vector3(centre.x + h, base_y, centre.z + h),
		Vector3(centre.x - h, base_y, centre.z + h)]
	for side_i in range(4):
		var c0: Vector3 = corners[side_i]
		var c1: Vector3 = corners[(side_i + 1) % 4]
		var t0 := Vector3(c0.x, deck_y, c0.z)
		var t1 := Vector3(c1.x, deck_y, c1.z)
		st.set_normal((c1 - c0).normalized())
		st.add_vertex(c0)
		st.add_vertex(t0)
		st.add_vertex(c1)
		st.add_vertex(c1)
		st.add_vertex(t0)
		st.add_vertex(t1)
