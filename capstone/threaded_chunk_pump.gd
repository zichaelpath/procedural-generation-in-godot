class_name ThreadedChunkPump
extends Node

## Moves ChunkData.process() off the main thread. Safety argument,
## in one paragraph (Ch 13's split, cashed): ChunkData generation
## is a PURE function of (coord, terrain, config); it builds no
## nodes and frees none. Worker threads therefore write ONLY the
## manager's data_cache (plain data, one writer per coordinate);
## node building stays on the main thread in the manager's own
## queue, which finds warm data and skips the expensive half.
## Terrain edits are pipeline-stage business (Ch 43) — the edit
## list is frozen while this pump runs, by contract, not by lock.

@export var prewarm_radius: int = 9

var _manager: ChunkManager
var _terrain: TerrainHeight
var _config: WorldConfig
var _queued: Dictionary = {} # Vector2i -> bool


func setup(manager: ChunkManager, terrain: TerrainHeight, config: WorldConfig) -> void:
	_manager = manager
	_terrain = terrain
	_config = config


## Queue data generation for every chunk in the prewarm square that
## the cache does not already hold. Cheap to call every frame; the
## _queued map is the de-duplication, and it lives on the main
## thread — workers never see it.
func prewarm_around(centre_chunk: Vector2i) -> void:
	for cz: int in range(centre_chunk.y - prewarm_radius, centre_chunk.y + prewarm_radius + 1):
		for cx: int in range(centre_chunk.x - prewarm_radius, centre_chunk.x + prewarm_radius + 1):
			var coord := Vector2i(cx, cz)
			if _manager.data_cache.has(coord) or _queued.has(coord):
				continue
			_queued[coord] = true
			WorkerThreadPool.add_task(Callable(self, "_generate_one").bind(coord))


func _generate_one(coord: Vector2i) -> void:
	# WORKER THREAD. Pure data in, pure data out. No nodes, no
	# queue_free, no scene tree — the whole safety proof is that
	# this function cannot name a Node if it tries.
	var data: ChunkData = ChunkData.generate(coord, _terrain, _config)
	# Dictionary writes from workers: one writer per key, and the
	# main thread only ever READS completed entries. A half-written
	# entry is impossible — the value is a finished RefCounted.
	_manager.data_cache[coord] = data
