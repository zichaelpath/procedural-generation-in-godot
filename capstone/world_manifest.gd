class_name WorldManifest
extends RefCounted

## The world seed tree, made explicit — and serialisable.
## One record per registered thing:
##   {"address": String, "kind": String, "parent": String,
##    "seed_a": int, "seed_b": int, "note": String}
## Records describe what each subsystem ACTUALLY uses (a ChunkData
## stored pair read back, a borough's Ch 41 grid-seed derivation, a
## parcel's Ch 40 derivation) — plus, for things this part mints
## (the world root, dungeon entrances), a true stored pair rolled
## from the parent stream, Ch 4's SeedNode pattern at world scale.
## The manifest is the map AND the save skeleton: master seed +
## records regenerate the world; Ch 44 weighs what else a save needs.

const FORMAT_VERSION: int = 1

var master_seed: int = 0
var records: Array[Dictionary] = []
var root_seed_a: int = 0
var root_seed_b: int = 0


func _init(p_master_seed: int) -> void:
	master_seed = p_master_seed
	var root_rng: RandomNumberGenerator = SeedBank.stream_for(
		master_seed, SeedBank.STREAM_WORLD)
	root_seed_a = root_rng.randi()
	root_seed_b = root_rng.randi()
	records.append({
		"address": "world", "kind": "root", "parent": "",
		"seed_a": root_seed_a, "seed_b": root_seed_b,
		"note": "minted pair, stream: world",
	})


## Mint a stored pair for a NEW child of the given stream — the
## SeedNode.create() move: two draws, snapshotted, independent from
## this moment on. The child regenerates from the pair alone.
func mint_pair(stream_name: String, address: String, kind: String, parent: String) -> Dictionary:
	var rng: RandomNumberGenerator = SeedBank.stream_for(master_seed, stream_name)
	# Advance deterministically past pairs already minted from this
	# stream in this manifest, so two children never share a pair.
	var already: int = 0
	for record: Dictionary in records:
		if str(record.get("parent", "")) == parent and str(record.get("kind", "")) == kind:
			already += 1
	for i: int in range(already * 2):
		rng.randi()
	var pair := {"seed_a": rng.randi(), "seed_b": rng.randi()}
	var record := {
		"address": address, "kind": kind, "parent": parent,
		"seed_a": int(pair["seed_a"]), "seed_b": int(pair["seed_b"]),
		"note": "minted pair, stream: " + stream_name,
	}
	records.append(record)
	return record


## Record a seed fact this manifest did not mint — a subsystem's own
## stored pair or derivation, read back honestly (see §43.2).
func record_fact(address: String, kind: String, parent: String, seed_a: int, seed_b: int, note: String) -> void:
	records.append({
		"address": address, "kind": kind, "parent": parent,
		"seed_a": seed_a, "seed_b": seed_b, "note": note,
	})


func record_for(address: String) -> Dictionary:
	for record: Dictionary in records:
		if str(record["address"]) == address:
			return record
	return {}


## A stream rebuilt from a record's stored pair alone — the pair is
## sufficient; no parent, no registry order, no world required.
static func stream_from_pair(seed_a: int, seed_b: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_a) + ":" + str(seed_b) + ":" + purpose)
	return rng


## Serialise: master seed + version + records. This file, plus the
## generator code's version, IS the runtime world's save skeleton.
func save_to(path: String) -> bool:
	var data := {
		"format_version": FORMAT_VERSION,
		"master_seed": master_seed,
		"records": records,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("WorldManifest: cannot write " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func load_from(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		push_warning("WorldManifest: format version mismatch in " + path)
		return false
	master_seed = int(data.get("master_seed", 0))
	records.clear()
	var loaded: Array = data.get("records", [])
	for record: Variant in loaded:
		if typeof(record) == TYPE_DICTIONARY:
			records.append(record)
	var root: Dictionary = record_for("world")
	if not root.is_empty():
		root_seed_a = int(root["seed_a"])
		root_seed_b = int(root["seed_b"])
	return true
