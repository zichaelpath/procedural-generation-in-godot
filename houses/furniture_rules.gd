class_name FurnitureRules
extends RefCounted
## Furnishing by rejection. A checklist (data) proposes; a blocked
## test disposes; what does not fit in 10 tries is SKIPPED with a
## warning — never forced, never overlapped. Absence is invisible;
## intersection is forever. (Pattern after Frank Gennari's 3DWorld
## furnishing tests — is_obj_placement_blocked — reimplemented here.)

const KIT_ROOT: String = "res://assets/kenney_furniture/"
const MODEL_SCALE: float = 1.6 # the kit models at ~0.6x real size, corner origins — see _spawn()
const MAX_TRIES: int = 10

# Our collision truth per item: (width along facing, depth front-back), metres.
const SIZES: Dictionary = {
	"sofa": Vector2(2.0, 0.95), "coffeeTable": Vector2(1.1, 0.55),
	"tvStand": Vector2(1.6, 0.45), "bookcase": Vector2(0.9, 0.35),
	"loungeChair": Vector2(0.75, 0.8), "bedSingle": Vector2(1.0, 2.1),
	"bedDouble": Vector2(1.6, 2.1), "sideTable": Vector2(0.45, 0.4),
	"wardrobe": Vector2(1.4, 0.6), "desk": Vector2(1.2, 0.6),
	"bath": Vector2(1.7, 0.75), "toilet": Vector2(0.45, 0.65),
	"sink": Vector2(0.55, 0.5), "kitchenCounter": Vector2(2.4, 0.65),
	"table": Vector2(1.5, 0.95), "chair": Vector2(0.45, 0.45),
}

# The checklists. Order matters: anchors first, relatives after.
# at_wall: N/S/W/E; along: 0..1 fraction along that wall;
# relative_to: an earlier item's name in the same room, offset in
# metres in the ANCHOR's frame (x = right, y = forward).
const LAYOUTS: Dictionary = {
	"living": [
		{"item": "sofa", "at_wall": "S", "along": 0.5},
		{"item": "coffeeTable", "relative_to": "sofa", "offset": Vector2(0.0, -1.15)},
		{"item": "tvStand", "at_wall": "N", "along": 0.5},
		{"item": "bookcase", "at_wall": "W", "along": 0.25},
		{"item": "loungeChair", "relative_to": "sofa", "offset": Vector2(-1.7, -0.9), "rot_add": 35.0},
	],
	"kitchen_dining": [
		{"item": "kitchenCounter", "at_wall": "W", "along": 0.45},
		{"item": "table", "at_wall": "S", "along": 0.55},
		{"item": "chair", "relative_to": "table", "offset": Vector2(-0.45, -0.75)},
		{"item": "chair", "relative_to": "table", "offset": Vector2(0.45, -0.75)},
		{"item": "chair", "relative_to": "table", "offset": Vector2(-0.45, 0.75), "rot_add": 180.0},
		{"item": "chair", "relative_to": "table", "offset": Vector2(0.45, 0.75), "rot_add": 180.0},
	],
	"dining": [
		{"item": "table", "at_wall": "S", "along": 0.5},
		{"item": "chair", "relative_to": "table", "offset": Vector2(-0.45, -0.75)},
		{"item": "chair", "relative_to": "table", "offset": Vector2(0.45, -0.75)},
		{"item": "chair", "relative_to": "table", "offset": Vector2(-0.45, 0.75), "rot_add": 180.0},
		{"item": "chair", "relative_to": "table", "offset": Vector2(0.45, 0.75), "rot_add": 180.0},
	],
	"kitchen": [
		{"item": "kitchenCounter", "at_wall": "W", "along": 0.5},
	],
	"bedroom": [
		{"item": "bedSingle", "at_wall": "N", "along": 0.3},
		{"item": "sideTable", "relative_to": "bedSingle", "offset": Vector2(0.85, 0.3)},
		{"item": "wardrobe", "at_wall": "S", "along": 0.8},
		{"item": "desk", "at_wall": "W", "along": 0.65},
	],
	"master": [
		{"item": "bedDouble", "at_wall": "N", "along": 0.5},
		{"item": "sideTable", "relative_to": "bedDouble", "offset": Vector2(1.1, 0.3)},
		{"item": "sideTable", "relative_to": "bedDouble", "offset": Vector2(-1.1, 0.3)},
		{"item": "wardrobe", "at_wall": "E", "along": 0.4},
	],
	"bathroom": [
		{"item": "bath", "at_wall": "W", "along": 0.5},
		{"item": "sink", "at_wall": "S", "along": 0.3},
		{"item": "toilet", "at_wall": "S", "along": 0.78},
	],
	"wc": [
		{"item": "toilet", "at_wall": "N", "along": 0.5},
		{"item": "sink", "at_wall": "W", "along": 0.5},
	],
}

static func place(parent: Node3D, plan: Dictionary, y_base: float, rng: RandomNumberGenerator) -> int:
	var placed_count: int = 0
	# Fixed hazards first: a clear disc on both sides of every door.
	var door_zones: Array = []
	for door in plan["doors"]:
		if door["kind"] == "entrance":
			continue
		door_zones.append({"center": door["center"], "radius": 0.55})
	for room in plan["rooms"]:
		var entries: Array = LAYOUTS.get(room["type"], [])
		if entries.is_empty():
			continue
		var rect: Rect2 = room["rect"]
		var placed: Array = [] # {name, rect (plan space), rot_deg}
		for entry in entries:
			var item: String = entry["item"]
			var size: Vector2 = SIZES[item]
			var done: bool = false
			for attempt in MAX_TRIES:
				var candidate: Dictionary = _propose(entry, rect, placed, attempt)
				if candidate.is_empty():
					break
				var footprint: Rect2 = _footprint_of(candidate["pos"], size, candidate["rot_deg"])
				if not is_obj_placement_blocked(footprint, rect, placed, door_zones):
					_spawn(parent, item, candidate["pos"], candidate["rot_deg"], y_base)
					placed.append({"name": item, "rect": footprint, "rot_deg": candidate["rot_deg"], "pos": candidate["pos"]})
					placed_count += 1
					done = true
					break
			if not done:
				print("FURNITURE WARNING %s: no legal spot for %s in %s after %d tries — skipped, not forced" % [room["name"], item, room["name"], MAX_TRIES])
	return placed_count

# The blocked test. Three checks, all cheap, all in plan space:
# inside the room, clear of placed items, clear of door swings.
static func is_obj_placement_blocked(footprint: Rect2, room_rect: Rect2, placed: Array, door_zones: Array) -> bool:
	# FIX (Ch 30): Listing 30.5 tests against room_rect.grow(-0.05),
	# but _propose() places at_wall items FLUSH with the wall — a
	# flush footprint always exceeds the shrunk room by exactly the
	# shrink, so no wall item could ever be placed. A 2 cm tolerance
	# keeps the inside-the-room check honest without banning flush.
	if not room_rect.grow(0.02).encloses(footprint):
		return true
	for other in placed:
		if footprint.intersects(other["rect"].grow(0.05)):
			return true
	for zone in door_zones:
		var center: Vector2 = zone["center"]
		var nearest: Vector2 = Vector2(
			clampf(center.x, footprint.position.x, footprint.end.x),
			clampf(center.y, footprint.position.y, footprint.end.y))
		if nearest.distance_to(center) < float(zone["radius"]):
			return true
	return false

static func _propose(entry: Dictionary, rect: Rect2, placed: Array, attempt: int) -> Dictionary:
	var size: Vector2 = SIZES[entry["item"]]
	var shift: float = 0.0
	if attempt > 0:
		shift = 0.3 * ceilf(attempt * 0.5) * (1.0 if attempt % 2 == 1 else -1.0)
	if entry.has("relative_to"):
		var anchor: Dictionary = {}
		for p in placed:
			if p["name"] == entry["relative_to"]:
				anchor = p
		if anchor.is_empty():
			return {}
		var anchor_rot: float = float(anchor["rot_deg"])
		var offset: Vector2 = entry["offset"]
		var rotated: Vector2 = offset.rotated(deg_to_rad(-anchor_rot))
		var pos: Vector2 = anchor["pos"] + rotated + Vector2(shift, 0.0)
		return {"pos": pos, "rot_deg": anchor_rot + float(entry.get("rot_add", 0.0))}
	var wall: String = entry["at_wall"]
	var along: float = float(entry["along"])
	var rot_deg: float = 0.0
	var pos: Vector2
	match wall:
		"S":
			rot_deg = 0.0 # against the south wall, facing north into the room
			pos = Vector2(rect.position.x + along * rect.size.x + shift, rect.end.y - size.y * 0.5)
		"N":
			rot_deg = 180.0
			pos = Vector2(rect.position.x + along * rect.size.x + shift, rect.position.y + size.y * 0.5)
		"W":
			rot_deg = -90.0
			pos = Vector2(rect.position.x + size.y * 0.5, rect.position.y + along * rect.size.y + shift)
		"E":
			rot_deg = 90.0
			pos = Vector2(rect.end.x - size.y * 0.5, rect.position.y + along * rect.size.y + shift)
	return {"pos": pos, "rot_deg": rot_deg}

static func _footprint_of(pos: Vector2, size: Vector2, rot_deg: float) -> Rect2:
	var quarter_turn: bool = int(round(absf(rot_deg) / 90.0)) % 2 == 1
	var extent: Vector2 = Vector2(size.y, size.x) if quarter_turn else size
	return Rect2(pos - extent * 0.5, extent)

static func _spawn(parent: Node3D, item: String, pos: Vector2, rot_deg: float, y_base: float) -> void:
	var path: String = KIT_ROOT + item + ".glb"
	if not ResourceLoader.exists(path):
		print("FURNITURE WARNING missing model: ", path)
		return
	var holder: Node3D = Node3D.new()
	holder.name = "Furniture_" + item
	holder.position = Vector3(pos.x, y_base, pos.y)
	holder.rotation.y = deg_to_rad(rot_deg)
	parent.add_child(holder)
	var scene: PackedScene = load(path)
	var instance: Node3D = scene.instantiate()
	instance.scale = Vector3.ONE * MODEL_SCALE
	holder.add_child(instance)
	# Recentre on the merged AABB: the model's centre lands on the
	# holder's origin, its base on the floor — whatever the kit's
	# origin conventions, the PLACEMENT stays true.
	var aabb: AABB = _merged_aabb(instance, Transform3D.IDENTITY)
	var center: Vector3 = aabb.get_center()
	instance.position = Vector3(-center.x * MODEL_SCALE, -aabb.position.y * MODEL_SCALE, -center.z * MODEL_SCALE)

static func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		result = xform * mesh_instance.get_aabb()
		first = false
	for child in node.get_children():
		var child_aabb: AABB = _merged_aabb(child, xform * (child as Node3D).transform)
		if child_aabb.size != Vector3.ZERO:
			if first:
				result = child_aabb
				first = false
			else:
				result = result.merge(child_aabb)
	return result
