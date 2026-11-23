class_name FacadeBuilder
extends RefCounted
## The exterior, read off the plan. A balcony exists where a living
## room or bedroom has an exterior window: centred on that window,
## sized from it, built from boxes (Ch 30's rule: assemble, never
## cut). Ground floors get terraces. Nothing here edits a plan —
## the returned balcony list is data for ApartmentRules to grade.

const BALCONY_DEPTH: float = 1.2
const BALCONY_TYPES: Array = ["living", "bedroom"]
const MIN_WIDTH: float = 1.5
const MAX_WIDTH: float = 3.0

static var mat_slab: StandardMaterial3D = null
static var mat_rail: StandardMaterial3D = null

static func _materials() -> void:
	if mat_slab != null:
		return
	mat_slab = StandardMaterial3D.new()
	mat_slab.albedo_color = Color(0.72, 0.70, 0.66)
	mat_rail = StandardMaterial3D.new()
	mat_rail.albedo_color = Color(0.25, 0.25, 0.28)

static func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)

# Build every balcony/terrace for a block. Returns the balcony list:
# {room, floor, wall, center (plan Vector2), width, terrace}.
static func build_facade(parent: Node3D, block: Dictionary) -> Array:
	_materials()
	var group: Node3D = Node3D.new()
	group.name = "FacadeGroup"
	parent.add_child(group)
	var balconies: Array = []
	var floors: Array = block["floors"]
	var entrance_x: float = float(block["core"]["entrance_x"])
	for f in floors.size():
		var plan: Dictionary = floors[f]
		var y_base: float = f * HouseBuilder.WALL_HEIGHT
		for room in plan["rooms"]:
			if not BALCONY_TYPES.has(room["type"]):
				continue
			var window: Dictionary = _largest_window(plan, room)
			if window.is_empty():
				continue # no exterior window: no balcony (corridor-block inner rooms, honestly skipped)
			var center: Vector2 = window["center"]
			var wall: String = window["wall"]
			if f == 1 and wall == "S" and absf(center.x - entrance_x) < 1.6:
				continue # rule 4: never over the core entrance
			var width: float = clampf(float(window["width"]) + 0.6, MIN_WIDTH, MAX_WIDTH)
			var terrace: bool = f == 0
			_build_one(group, room, wall, center, width, y_base, terrace)
			balconies.append({"room": room["name"], "floor": f, "wall": wall,
				"center": center, "width": width, "terrace": terrace})
	return balconies

static func _largest_window(plan: Dictionary, room: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for window in plan["windows"]:
		if window["room"] == room["name"]:
			if best.is_empty() or float(window["width"]) > float(best["width"]):
				best = window
	return best

static func _build_one(group: Node3D, room: Dictionary, wall: String, center: Vector2, width: float, y_base: float, terrace: bool) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Balcony_" + String(room["name"])
	group.add_child(holder)
	# Outward direction and slab centre, from the wall the window is on.
	var outward: Vector2
	match wall:
		"N": outward = Vector2(0, -1)
		"S": outward = Vector2(0, 1)
		"W": outward = Vector2(-1, 0)
		_: outward = Vector2(1, 0)
	var slab_center: Vector2 = center + outward * (BALCONY_DEPTH * 0.5)
	var along_x: bool = wall == "N" or wall == "S"
	var slab_size: Vector3 = Vector3(width, 0.12, BALCONY_DEPTH) if along_x else Vector3(BALCONY_DEPTH, 0.12, width)
	var slab_y: float = 0.06 if terrace else y_base + 0.02
	_box(holder, Vector3(slab_center.x, slab_y, slab_center.y), slab_size, mat_slab)
	if terrace:
		return # at grade: a slab is the whole statement
	# Railing: front rail (two bars) + two side rails, all boxes.
	var edge: Vector2 = center + outward * BALCONY_DEPTH
	var rail_y: float = y_base + 0.55
	var front_size: Vector3 = Vector3(width, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, width)
	_box(holder, Vector3(edge.x, rail_y, edge.y), front_size, mat_rail)
	_box(holder, Vector3(edge.x, y_base + 1.05, edge.y), front_size, mat_rail)
	var side_len: Vector3 = Vector3(0.05, 0.05, BALCONY_DEPTH) if along_x else Vector3(BALCONY_DEPTH, 0.05, 0.05)
	var off_a: Vector2 = Vector2(width * 0.5, 0) if along_x else Vector2(0, width * 0.5)
	_box(holder, Vector3(slab_center.x + off_a.x, rail_y, slab_center.y + off_a.y), side_len, mat_rail)
	_box(holder, Vector3(slab_center.x - off_a.x, rail_y, slab_center.y - off_a.y), side_len, mat_rail)
