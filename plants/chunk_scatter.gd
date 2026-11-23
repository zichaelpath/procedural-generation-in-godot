class_name ChunkScatter
extends RefCounted

## Per-chunk scatter: a pure function of ChunkData. Fills the
## ChunkData.scatter array Chapter 13 left empty, rolling from the
## chunk's STORED seed pair (stream_from_stored) — never from a new
## create() roll, because create()'s roll order is append-only.
## Placement respects the chunk's own grids (heights / normals /
## biomes) and, via poisson_disc_chunked, its neighbours' points.

const MIN_DIST: float = 5.0        # metres between trees in a chunk
const MAX_SLOPE: float = 0.20      # 1 - cos(angle): ~37 degrees
const HOLDER_NAME: String = "ScatterHolder"

## Fill data.scatter with {position (world), kind, scale, yaw}
## dictionaries. neighbour_points are the already-finished scatter
## positions of adjacent chunks, in THIS chunk's local frame.
static func fill_chunk(data: ChunkData, cfg: WorldConfig, neighbour_points: Array[Vector2]) -> void:
	data.scatter.clear()
	var rng: RandomNumberGenerator = data.stream_from_stored("scatter")
	var region := Vector2(cfg.chunk_size_m, cfg.chunk_size_m)
	var local: Array[Vector2] = Scatter.poisson_disc_chunked(region, MIN_DIST, rng, neighbour_points)
	var origin: Vector2 = Vector2(float(data.coord.x), float(data.coord.y)) * cfg.chunk_size_m
	for p in local:
		# Ask the chunk's OWN grids: biome decides whether a plant may
		# stand here at all, and how likely it is to survive thinning.
		var gx: int = clampi(int(p.x / cfg.cell_size_m()), 0, cfg.chunk_cells)
		var gz: int = clampi(int(p.y / cfg.cell_size_m()), 0, cfg.chunk_cells)
		var idx: int = gz * (cfg.chunk_cells + 1) + gx
		var biome: int = int(data.biomes[idx])
		var density: float = float(TerrainHeight.BIOME_DENSITY.get(biome, 0.1))
		if density <= 0.0:
			continue  # ocean / rock / snow: the biome vetoes plants
		var slope: float = 1.0 - data.normals[idx].y
		if slope > MAX_SLOPE:
			continue
		if rng.randf() > clampf(density * 1.2, 0.0, 1.0):
			continue  # thinning: kept density follows the biome table
		data.scatter.append({
			"position": Vector3(origin.x + p.x, _height_on_chunk(data, cfg, p.x, p.y), origin.y + p.y),
			"kind": "tree",
			"scale": rng.randf_range(0.8, 1.3),
			"yaw": rng.randf_range(0.0, TAU),
		})

## Bilinear height over the chunk's own height grid — the same
## interpolation height_at() does over the island, at chunk scale.
static func _height_on_chunk(data: ChunkData, cfg: WorldConfig, lx: float, lz: float) -> float:
	var side: int = cfg.chunk_cells + 1
	var fx: float = clampf(lx / cfg.cell_size_m(), 0.0, float(cfg.chunk_cells) - 0.001)
	var fz: float = clampf(lz / cfg.cell_size_m(), 0.0, float(cfg.chunk_cells) - 0.001)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var h00: float = data.heights[iz * side + ix]
	var h10: float = data.heights[iz * side + ix + 1]
	var h01: float = data.heights[(iz + 1) * side + ix]
	var h11: float = data.heights[(iz + 1) * side + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

## Build the render holder for a filled chunk: two MultiMeshes
## (trunks + canopies) instanced from data.scatter, in chunk-local
## space, as a child the chunk node can carry — and pool — with it.
## Rebuilding frees the previous holder first: pool hygiene.
static func build_holder(data: ChunkData, cfg: WorldConfig) -> Node3D:
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	if data.scatter.is_empty():
		return holder
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.15
	trunk_mesh.height = 1.5
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk_mesh.material = trunk_mat
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.3
	canopy_mesh.height = 2.4
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.23, 0.42, 0.18)
	canopy_mesh.material = canopy_mat
	_add_instanced(holder, trunk_mesh, data, cfg, 0.75)
	_add_instanced(holder, canopy_mesh, data, cfg, 2.6)
	return holder

static func _add_instanced(holder: Node3D, mesh: Mesh, data: ChunkData, cfg: WorldConfig, y_offset: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = data.scatter.size()
	var origin: Vector2 = Vector2(float(data.coord.x), float(data.coord.y)) * cfg.chunk_size_m
	for i in data.scatter.size():
		var item: Dictionary = data.scatter[i]
		var world_pos: Vector3 = item["position"]
		# The holder is a child of the chunk NODE (which sits at the
		# chunk origin), so instances are stored chunk-LOCAL.
		var local_pos := Vector3(world_pos.x - origin.x, world_pos.y, world_pos.z - origin.y)
		var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"]))
		mm.set_instance_transform(i, Transform3D(basis, local_pos + Vector3(0.0, y_offset * float(item["scale"]), 0.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	holder.add_child(mmi)
