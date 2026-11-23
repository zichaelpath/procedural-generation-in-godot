@tool
class_name TerrainChunk
extends MeshInstance3D

## A BUILDER, nothing more: ChunkData in, node out. Building the same
## data twice gives the same node twice (idempotent), so nodes can be
## freed and rebuilt freely — the data is the world; this is its
## photograph.
## (Chapter 13, Listing 13.4; the `step` parameter is Chapter 14's LOD
## stride, passed through by the manager — the builder stays a pure
## function of (data, step).)

var chunk_coord: Vector2i = Vector2i.ZERO

func build_from_data(data: ChunkData, cfg: WorldConfig, material: Material, step: int = 1) -> void:
	chunk_coord = data.coord
	data.lod_step = step
	mesh = TerrainMesh.build_chunk_mesh(data.heights_for_lod(step), (cfg.chunk_cells / step) + 1,
			cfg.cell_size_m() * float(step), data.normals_for_lod(step), 3.0 * float(step))
	material_override = material
	var origin: Vector2 = Vector2(float(data.coord.x), float(data.coord.y)) * cfg.chunk_size_m
	position = Vector3(origin.x, 0.0, origin.y)
	name = "Chunk_%d_%d" % [data.coord.x, data.coord.y]

## Per-chunk collision (Part III pays Chapter 14's named debt): a
## HeightMapShape3D from the SAME grid the mesh was built from, as a
## child of this chunk node — so the manager's pool pools the body
## with the mesh, and what you see is exactly what you stand on.
## (Chapter 15, Listing 15.5.)
func build_collision(data: ChunkData, cfg: WorldConfig) -> StaticBody3D:
	var old: Node = get_node_or_null("CollisionBody")
	if old != null:
		remove_child(old)
		old.free()
	var shape := HeightMapShape3D.new()
	shape.map_width = cfg.chunk_cells + 1
	shape.map_depth = cfg.chunk_cells + 1
	shape.map_data = data.heights.duplicate()
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.name = "CollisionBody"
	body.add_child(col)
	add_child(body)
	# HeightMapShape3D is centred on its node; the chunk's mesh origin
	# is the grid's corner, so shift the body to the grid's centre.
	body.position = Vector3(cfg.chunk_size_m * 0.5, 0.0, cfg.chunk_size_m * 0.5)
	return body
