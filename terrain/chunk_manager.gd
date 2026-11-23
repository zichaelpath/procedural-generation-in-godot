@tool
class_name ChunkManager
extends Node3D

## Streaming chunk manager. Four mechanisms, four jobs:
##  - load radius < unload radius (hysteresis: border chunks never thrash)
##  - a distance-sorted build queue (nearest + in-front first)
##  - a per-frame build budget (cost spread over frames, no hitches)
##  - a node pool + a data cache that outlives its nodes (Section 13.3)
## Chunk/world coordinate conversion lives HERE and nowhere else.
##
## Assembled: Listing 13.5 (fixed grid + cache + debug tint — the form
## the step-8 captures use) grown into Listing 13.6 (the streamer),
## plus Chapter 14's LOD selection / dead band (Listing 14.3) and
## origin rebasing (Listing 14.4).
##
## Integration correction to Listing 14.4's walkthrough: the focus
## chunk is computed from player_world_position() (ABSOLUTE chunk
## coordinates), not from the raw scene position — otherwise the
## wanted set would jump back to the origin after every rebase.
## _last_focus therefore lives in absolute chunk space and is NOT
## shifted by _maybe_rebase().

@export var terrain_material: Material
@export var debug_tint_chunks: bool = false
@export var player: Node3D

## Stage display switch (Chapter 14 captures): tint by LOD stride
## instead of by coordinate hash. Not a chapter export — the book's
## ring shot needs ring-readable tints; see the discrepancy report.
var tint_by_lod: bool = false

var cfg: WorldConfig
var terrain: TerrainHeight
var chunks: Dictionary = {}      # Vector2i -> TerrainChunk (visible nodes)
var data_cache: Dictionary = {}  # Vector2i -> ChunkData (outlives nodes)

var load_radius_chunks: int = 8
var unload_radius_chunks: int = 10
var data_evict_radius_chunks: int = 16
var builds_per_frame: int = 2

var _queue: Array[Vector2i] = []
var _pool: Array[TerrainChunk] = []
var _last_focus: Vector2i = Vector2i(999999, 999999)
var _built_step: Dictionary = {}        # Vector2i -> int (LOD stride as built)
var _lod_mismatch: Dictionary = {}      # Vector2i -> consecutive focus changes at a new ring

## Origin rebasing: chunk coordinates are IDENTITY and never change;
## origin_offset records how far the scene frame has been shifted, in
## whole chunks, so scene positions stay near zero (float precision)
## while absolute positions stay exact (integers + this offset).
var origin_offset: Vector2i = Vector2i.ZERO
var rebase_threshold_m: float = 1024.0

func setup(p_terrain: TerrainHeight, p_cfg: WorldConfig) -> void:
	terrain = p_terrain
	cfg = p_cfg

## THE conversions. Call these; never multiply by hand elsewhere.
func chunk_to_world_origin(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x), float(coord.y)) * cfg.chunk_size_m

func world_to_chunk(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(floori(world_x / cfg.chunk_size_m),
			floori(world_z / cfg.chunk_size_m))

func get_or_generate_data(coord: Vector2i) -> ChunkData:
	if data_cache.has(coord):
		return data_cache[coord]
	var data: ChunkData = ChunkData.generate(coord, terrain, cfg)
	data_cache[coord] = data
	return data

# --- Listing 13.5: the fixed grid (step-8 capture form) ---

func build_fixed_grid() -> void:
	for cz in range(-cfg.view_radius_chunks, cfg.view_radius_chunks + 1):
		for cx in range(-cfg.view_radius_chunks, cfg.view_radius_chunks + 1):
			var coord := Vector2i(cx, cz)
			var chunk := TerrainChunk.new()
			add_child(chunk)
			chunk.build_from_data(get_or_generate_data(coord), cfg,
					_material_for(coord, 1), 1)
			chunk.position = chunk_node_position(coord)
			chunks[coord] = chunk
			_built_step[coord] = 1

func rebuild_all_from_data() -> void:
	# The data/node proof: throw away every NODE, keep every DATA,
	# rebuild — the world must come back identical.
	for coord in chunks.keys():
		chunks[coord].queue_free()
	chunks.clear()
	_built_step.clear()
	build_fixed_grid()

# --- Chapter 14, Listing 14.3: LOD rings ---

## Ring of a chunk = its Chebyshev distance from the focus; the ring
## picks the build stride. Square rings on a square grid: one integer.
func lod_for_chunk(coord: Vector2i, focus: Vector2i) -> int:
	var ring: int = maxi(absi(coord.x - focus.x), absi(coord.y - focus.y))
	if ring <= 1:
		return 1   # 33x33 vertices
	if ring == 2:
		return 2   # 17x17
	return 4       # 9x9

# --- Chapter 14, Listing 14.4: origin rebasing ---

## Where a chunk's NODE sits in the scene: its absolute origin minus
## the accumulated shift. The chunk's coordinate is untouched.
func chunk_node_position(coord: Vector2i) -> Vector3:
	var rel: Vector2i = coord - origin_offset
	return Vector3(float(rel.x) * cfg.chunk_size_m, 0.0, float(rel.y) * cfg.chunk_size_m)

## The player's absolute world position: scene position + shift.
## Game code asks THIS, never player.position directly.
func player_world_position() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return Vector2(player.position.x, player.position.z) \
			+ Vector2(origin_offset) * cfg.chunk_size_m

func _maybe_rebase() -> void:
	if player == null:
		return
	if absf(player.position.x) < rebase_threshold_m \
			and absf(player.position.z) < rebase_threshold_m:
		return
	# Shift by WHOLE chunks, so every chunk node lands exactly on its
	# grid and no mesh is rebuilt — a rebase is pure translation.
	var shift: Vector2i = world_to_chunk(player.position.x, player.position.z)
	if shift == Vector2i.ZERO:
		return
	var shift_world := Vector3(float(shift.x) * cfg.chunk_size_m, 0.0,
			float(shift.y) * cfg.chunk_size_m)
	player.position -= shift_world
	for coord in chunks.keys():
		chunks[coord].position = chunk_node_position(coord)
	origin_offset += shift
	# NOTE: _last_focus is tracked in ABSOLUTE chunk coordinates (the
	# focus is derived from player_world_position()), so it needs no
	# adjustment here — chunk identities never move.

# --- Listing 13.6: the streamer ---

func _process(_delta: float) -> void:
	if player == null or terrain == null:
		return
	_maybe_rebase()
	var wp: Vector2 = player_world_position()
	var focus: Vector2i = world_to_chunk(wp.x, wp.y)
	if focus != _last_focus:
		_last_focus = focus
		_refresh_wanted(focus)
		_apply_lod_changes(focus)
	_unload_beyond(focus)
	_build_from_queue()

func _refresh_wanted(focus: Vector2i) -> void:
	_queue.clear()
	var missing: Array[Vector2i] = []
	for cz in range(focus.y - load_radius_chunks, focus.y + load_radius_chunks + 1):
		for cx in range(focus.x - load_radius_chunks, focus.x + load_radius_chunks + 1):
			var coord := Vector2i(cx, cz)
			if not chunks.has(coord):
				missing.append(coord)
	# Nearest first; ties broken toward the direction of travel, so the
	# ground you are flying INTO exists before the ground behind you.
	var travel: Vector2 = Vector2.ZERO
	if player.has_method("travel_direction"):
		travel = player.travel_direction()
	var focus_world := Vector2(player.position.x, player.position.z)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ca: Vector2 = chunk_to_world_origin(a) + Vector2.ONE * cfg.chunk_size_m * 0.5
		var cb: Vector2 = chunk_to_world_origin(b) + Vector2.ONE * cfg.chunk_size_m * 0.5
		var da: float = ca.distance_squared_to(focus_world) - ca.dot(travel) * cfg.chunk_size_m
		var db: float = cb.distance_squared_to(focus_world) - cb.dot(travel) * cfg.chunk_size_m
		return da < db)
	_queue = missing

func _apply_lod_changes(focus: Vector2i) -> void:
	# Dead band (Chapter 14): a chunk rebuilds at a new LOD only when
	# its ring has differed for two consecutive focus changes — except
	# ring 0, where near detail is never late.
	for coord in chunks.keys():
		var want: int = lod_for_chunk(coord, focus)
		var built: int = int(_built_step.get(coord, 1))
		if want == built:
			_lod_mismatch.erase(coord)
			continue
		var n: int = int(_lod_mismatch.get(coord, 0)) + 1
		_lod_mismatch[coord] = n
		if want == 1 or n >= 2:
			var chunk: TerrainChunk = chunks[coord]
			chunk.build_from_data(get_or_generate_data(coord), cfg,
					_material_for(coord, want), want)
			chunk.position = chunk_node_position(coord)
			_built_step[coord] = want
			_lod_mismatch.erase(coord)

func _build_from_queue() -> void:
	var built: int = 0
	while built < builds_per_frame and not _queue.is_empty():
		var coord: Vector2i = _queue.pop_front()
		if chunks.has(coord):
			continue
		var chunk: TerrainChunk = _take_from_pool()
		add_child(chunk)
		var step: int = lod_for_chunk(coord, _last_focus)
		var data: ChunkData = get_or_generate_data(coord)
		chunk.build_from_data(data, cfg, _material_for(coord, step), step)
		chunk.position = chunk_node_position(coord)
		# Part III hook (Chapter 15, Listing 15.5): collision + scatter
		# ride the same build. Scatter is filled ONCE per data (it is
		# data, not nodes); the holder is rebuilt per node, like the
		# mesh itself. (Project integration: the LOD `step` argument
		# and the chunk_node_position/_built_step bookkeeping above are
		# Chapter 14's, kept from the pre-hook version of this function.)
		if data.scatter.is_empty():
			ChunkScatter.fill_chunk(data, cfg, _neighbour_scatter_points(coord))
		chunk.build_collision(data, cfg)
		var old_holder: Node = chunk.get_node_or_null(ChunkScatter.HOLDER_NAME)
		if old_holder != null:
			chunk.remove_child(old_holder)
			old_holder.free()
		chunk.add_child(ChunkScatter.build_holder(data, cfg))
		chunks[coord] = chunk
		_built_step[coord] = step
		built += 1

## The finished scatter points of the (up to) 8 neighbours, shifted
## into coord's local frame — the pre-load of Section 15.3. Neighbour
## DATA comes from the cache (generated on demand, nodes or not);
## a neighbour with no scatter yet contributes nothing, and the
## later-generated chunk of every border pair still guards the pair.
## (Chapter 15, Listing 15.5.)
func _neighbour_scatter_points(coord: Vector2i) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var ncoord := Vector2i(coord.x + dx, coord.y + dz)
			if not data_cache.has(ncoord):
				continue
			var ndata: ChunkData = data_cache[ncoord]
			for item in ndata.scatter:
				var wp: Vector3 = item["position"]
				pts.append(Vector2(
					wp.x - float(coord.x) * cfg.chunk_size_m,
					wp.z - float(coord.y) * cfg.chunk_size_m))
	return pts

func _unload_beyond(focus: Vector2i) -> void:
	var gone: Array = []
	for coord in chunks.keys():
		var d: int = maxi(absi(coord.x - focus.x), absi(coord.y - focus.y))
		if d > unload_radius_chunks:
			gone.append(coord)
	for coord in gone:
		var chunk: TerrainChunk = chunks[coord]
		chunks.erase(coord)
		_built_step.erase(coord)
		_lod_mismatch.erase(coord)
		remove_child(chunk)
		_pool.append(chunk)  # node returns to the pool; its DATA stays cached
	# Data eviction is stingier than node unloading: only far beyond the
	# unload radius do we let regeneration replace memory.
	var evict: Array = []
	for coord in data_cache.keys():
		var d: int = maxi(absi(coord.x - focus.x), absi(coord.y - focus.y))
		if d > data_evict_radius_chunks:
			evict.append(coord)
	for coord in evict:
		data_cache.erase(coord)

func _take_from_pool() -> TerrainChunk:
	if _pool.is_empty():
		return TerrainChunk.new()
	return _pool.pop_back()

func _material_for(coord: Vector2i, step: int = 1) -> Material:
	if tint_by_lod:
		if terrain_material == null:
			return null
		var ml: Material = terrain_material.duplicate()
		var hue_l: float = 0.36 if step <= 1 else (0.13 if step == 2 else 0.0)
		if ml is ShaderMaterial:
			ml.set_shader_parameter("tint", Color.from_hsv(hue_l, 0.45, 1.0))
		elif ml is StandardMaterial3D:
			ml.albedo_color = Color.from_hsv(hue_l, 0.35, 1.0)
		return ml
	if not debug_tint_chunks or terrain_material == null:
		return terrain_material
	# Debug view: one tinted copy of the material per chunk, coloured by
	# a hash of the coordinates so boundaries are visible at a glance.
	var m: Material = terrain_material.duplicate()
	var hue: float = float(absi(hash("chunk:%d,%d" % [coord.x, coord.y])) % 360) / 360.0
	if m is ShaderMaterial:
		m.set_shader_parameter("tint", Color.from_hsv(hue, 0.35, 1.0))
	elif m is StandardMaterial3D:
		m.albedo_color = Color.from_hsv(hue, 0.35, 1.0)
	return m
