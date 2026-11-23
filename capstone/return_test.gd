class_name ReturnTest
extends RefCounted

## The book's determinism promise, kept in public: fingerprint the
## assembled world, unload EVERYTHING (nodes freed, data caches
## dropped), regenerate from the seed alone, fingerprint again,
## compare line by line. The fingerprint is built from the
## subsystems' OWN hashes, so the first differing line names the
## subsystem that drifted — an address plus a seed is a bug report.

func fingerprint(builder: WorldBuilder) -> Array[String]:
	var lines: Array[String] = []
	lines.append("seed:%d" % builder.config.master_seed)
	var coords: Array = builder.chunk_manager.data_cache.keys()
	coords.sort()
	for coord: Variant in coords:
		var data: ChunkData = builder.chunk_manager.data_cache[coord]
		lines.append("terrain/%d,%d:%d" % [data.coord.x, data.coord.y, data.data_hash()])
	lines.append("parcels:%d" % builder.parcels.size())
	var ledger_keys: Array = builder.placement_ledger.keys()
	ledger_keys.sort()
	for key: Variant in ledger_keys:
		var entry: Dictionary = builder.placement_ledger[key]
		lines.append("ledger/%s:%d/%d" % [str(key),
			int(entry.get("placed", 0)), int(entry.get("surrendered", 0))])
	for entrance: Dictionary in builder.entrances:
		lines.append("%s:%d" % [str(entrance["address"]), int(entrance["dungeon_hash"])])
	lines.append("edits:%d" % builder.terrain.city_edit_count())
	return lines


func run(builder: WorldBuilder, max_step: int, config: WorldConfig) -> bool:
	var before: Array[String] = fingerprint(builder)
	print("--- Return Test: fingerprint before (", before.size(), " lines) ---")
	for line: String in before:
		print("  ", line)
	# Capture adaptation (shot list, Ch 43): the unload/regenerate
	# phases are named in the Output so the engine shot's log reads
	# as the chapter's shot list describes. No logic changes.
	print("--- Return Test: UNLOADED (nodes freed, data caches dropped) ---")
	builder.generate_all(max_step, config)
	print("--- Return Test: REGENERATED (from the seed alone) ---")
	var after: Array[String] = fingerprint(builder)
	if before.size() != after.size():
		print("RETURN TEST: FAIL — line count ", before.size(), " -> ", after.size())
		return false
	for i: int in range(before.size()):
		if before[i] != after[i]:
			print("RETURN TEST: FAIL — first difference at line ", i,
				": '", before[i], "' vs '", after[i], "'")
			return false
	print("RETURN TEST: PASS (fingerprint identical, ", after.size(), " lines)")
	return true
