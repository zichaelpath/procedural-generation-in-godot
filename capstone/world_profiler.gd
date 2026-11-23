class_name WorldProfiler
extends RefCounted

## Assembles Chapter 43's stage reports into one budget table, and
## adds the renderer's own counters. It MEASURES; it does not guess.
## Numbers it cannot measure honestly (per-machine milliseconds) are
## printed from the builder's own stage_times — the pipeline is the
## instrument; this class is only the clipboard.

func print_budget(builder: WorldBuilder) -> void:
	print("=== World budget — seed ", builder.config.master_seed, " ===")
	var total_ms: int = 0
	var stage_names: Array = builder.stage_times.keys()
	stage_names.sort()
	for stage: String in stage_names:
		var ms: int = int(builder.stage_times[stage])
		total_ms += ms
		print("  stage ", stage, ": ", ms, " ms")
	print("  TOTAL generation: ", total_ms, " ms (budget: 8000 ms)")
	print("  terrain edits: ", builder.terrain.city_edit_count())
	print("  parcels: ", builder.parcels.size(),
		" · entrances: ", builder.entrances.size(),
		" · proofs: ", builder.dungeon_proofs)
	_print_chunk_census(builder)
	print("  live nodes (Performance): ",
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("  draw calls in frame (Performance): ",
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	print("  video memory (Performance, MB): ",
		snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1))


func _print_chunk_census(builder: WorldBuilder) -> void:
	var manager: ChunkManager = builder.chunk_manager
	var by_stride: Dictionary = {}
	var vertices: int = 0
	for coord: Variant in manager.chunks.keys():
		var stride: int = 1
		# Chapter 14's ring rule, read back through the manager's own
		# LOD function — the census audits the system, not a copy of it.
		var data: ChunkData = manager.data_cache.get(coord, null)
		if data != null:
			stride = maxi(1, data.lod_step)
		by_stride[stride] = int(by_stride.get(stride, 0)) + 1
		var side: int = builder.config.chunk_cells / stride + 1
		vertices += side * side
	print("  chunks live: ", manager.chunks.size(),
		" · by LOD stride: ", by_stride,
		" · terrain vertices (computed): ", vertices)
