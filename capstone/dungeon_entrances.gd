class_name DungeonEntrances
extends RefCounted

## The pipeline's last stage. An entrance is a land-use decision:
## chosen BY RULE from the finished parcels (fronting + green first,
## nearest the centre), given a MINTED stored pair from the dungeon
## stream, and proven completable before its prop is built. The
## interior is NOT built here — it is the pair's process() half,
## cashed on entry (Ch 4's two-phase pattern, at world scale).
##
## Integration adaptations vs Listing 43.5 as printed (call sites
## only — no generator forked; see Part IX build report):
##  * Part IV's built BSPGenerator.generate() takes
##    (master_seed: int, width: int, height: int) and seeds itself
##    from SeedBank's dungeon stream — so the pair-alone stream of
##    the listing is cashed as the pair-derived seed integer
##    hash("a:b:dungeon"), the exact seed stream_from_pair() would
##    give an RNG. Same property: the pair alone regenerates it.
##  * MissionPlanner.is_completable() as built returns a Dictionary
##    {"completable": bool, "order": Array}; the listing's bool is
##    read out of that dictionary.

const MAX_ENTRANCES: int = 3
const DUNGEON_SIZE := Vector2i(48, 48)

var proofs: Array[String] = []


func place_entrances(parcels: Array[Dictionary], terrain: TerrainHeight, manifest: WorldManifest, host: Node3D, config: WorldConfig) -> Array[Dictionary]:
	proofs.clear()
	var candidates: Array[Dictionary] = []
	for parcel: Dictionary in parcels:
		if bool(parcel.get("fronting", false)) and str(parcel.get("use", "")) == "green":
			candidates.append(parcel)
	var substituted: bool = false
	if candidates.is_empty():
		substituted = true
		for parcel: Dictionary in parcels:
			if bool(parcel.get("fronting", false)):
				candidates.append(parcel)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _centre_of(a).length() < _centre_of(b).length())
	var placed: Array[Dictionary] = []
	var count: int = mini(MAX_ENTRANCES, candidates.size())
	for i: int in range(count):
		var parcel: Dictionary = candidates[i]
		var centre: Vector2 = _centre_of(parcel)
		var address: String = "dungeon/entrance_%d" % i
		var record: Dictionary = manifest.mint_pair(
			SeedBank.STREAM_DUNGEON, address, "dungeon", "world")
		# Pair-alone regeneration: the seed integer below is the one
		# WorldManifest.stream_from_pair(a, b, "dungeon") assigns its
		# RNG — fed here to Part IV's seed-taking entry point.
		var pair_seed: int = hash(str(int(record["seed_a"])) + ":" + str(int(record["seed_b"])) + ":dungeon")
		var data: DungeonData = BSPGenerator.new().generate(pair_seed, DUNGEON_SIZE.x, DUNGEON_SIZE.y)
		var planner := MissionPlanner.new()
		planner.annotate(data)
		var ok: bool = bool(planner.is_completable(data).get("completable", false))
		proofs.append(address + ": " + ("COMPLETABLE" if ok else "NOT COMPLETABLE"))
		if not ok:
			push_error("DungeonEntrances: " + address + " failed its proof — refusing to place its prop")
			continue
		_build_prop(host, parcel, centre, terrain, i)
		placed.append({
			"address": address, "parcel_block": int(parcel.get("block", 0)),
			"centre": centre, "seed_a": int(record["seed_a"]),
			"seed_b": int(record["seed_b"]),
			"dungeon_hash": hash(data.to_ascii()),
			"substituted_parcel": substituted,
		})
		print("[entrance] ", address, " on parcel parcel/",
			int(parcel.get("block", 0)), "_", parcels.find(parcel),
			" (block ", int(parcel.get("block", 0)), ") pair (",
			int(record["seed_a"]), ", ", int(record["seed_b"]),
			") — COMPLETABLE")
	return placed


func _centre_of(parcel: Dictionary) -> Vector2:
	var frame: Dictionary = parcel["frame"]
	var local: Vector2 = (parcel["local_rect"] as Rect2).get_center()
	return BlockParcels._to_world(frame, local)


## The surface prop: boxes with intent — a stairwell housing, a door
## frame, steps descending below grade. Its contract is position,
## facing, and footprint; beauty is a dressing pass (Ch 45), later.
func _build_prop(host: Node3D, parcel: Dictionary, centre: Vector2, terrain: TerrainHeight, index: int) -> void:
	var prop := Node3D.new()
	prop.name = "Entrance_%d" % index
	prop.position = Vector3(centre.x, terrain.height_at(centre.x, centre.y), centre.y)
	var frame: Dictionary = parcel["frame"]
	prop.rotation.y = -atan2(frame["axis"].y, frame["axis"].x)
	host.add_child(prop)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.28)
	_add_box(prop, Vector3(0.0, 1.1, 0.0), Vector3(3.2, 2.2, 2.6), mat)
	_add_box(prop, Vector3(0.0, 0.55, 1.45), Vector3(1.4, 1.1, 0.3), mat)
	for s: int in range(4):
		_add_box(prop, Vector3(0.0, 0.36 - float(s) * 0.18, 1.9 + float(s) * 0.45),
			Vector3(1.4, 0.12, 0.5), mat)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = pos
	box.material_override = mat
	parent.add_child(box)
