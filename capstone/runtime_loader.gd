extends Node

## Runtime shipping form: the game ships GENERATORS, not the world.
## Reads the seed, generates, verifies with the Return Test's
## fingerprint machinery, and — the commercial pattern — rejects a
## failed seed and deals another. The player never sees a bad world.

const MAX_SEED_TRIES: int = 8

@onready var builder: WorldBuilder = $WorldBuilder

var config: WorldConfig


func _ready() -> void:
	config = WorldConfig.new()
	var tier: Dictionary = WorldQuality.apply("high", config)
	print("[runtime] tier high, garnish: ", tier)
	var seed_value: int = _read_seed()
	for attempt: int in range(MAX_SEED_TRIES):
		config.master_seed = seed_value
		var t0: int = Time.get_ticks_msec()
		builder.generate_all(6, config)
		var ok: bool = _verify(builder)
		print("[runtime] seed ", seed_value, " generated in ",
			Time.get_ticks_msec() - t0, " ms — verify ", "OK" if ok else "FAILED")
		if ok:
			builder.manifest.save_to("user://world_manifest.json")
			return
		seed_value += 1
	push_error("RuntimeLoader: no clean seed in %d tries" % MAX_SEED_TRIES)


## Runtime verification is the Return Test's cheap half plus the
## pipeline's own proofs: entrances all completable, at least one
## building placed, edits registered. (The full unload-regenerate
## comparison is the editor-side sweep of §44.6, not a load-time tax.)
func _verify(b: WorldBuilder) -> bool:
	if b.entrances.is_empty():
		return false
	for proof: String in b.dungeon_proofs:
		if proof.ends_with("NOT COMPLETABLE"):
			return false
	var placed_total: int = 0
	for key: Variant in b.placement_ledger.keys():
		placed_total += int(b.placement_ledger[key].get("placed", 0))
	return placed_total > 0 and b.terrain.city_edit_count() > 0


func _read_seed() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.trim_prefix("--seed="))
	var cfg := ConfigFile.new()
	if cfg.load("user://seed.cfg") == OK:
		return int(cfg.get_value("world", "seed", 20261119))
	return 20261119
