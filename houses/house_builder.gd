class_name HouseBuilder
extends RefCounted
## Extrudes a certified plan into a real little building.
## One idea: NEVER cut a hole — assemble around one. A wall with a
## door is a run of boxes: solid span, header box above the opening
## (plus a sill box below, for a window), next solid span. No CSG,
## no booleans, nothing to explode on a degenerate plan.
## Plan (x, y) maps to world (x, up, z = y). Data in, nodes out.

const WALL_HEIGHT: float = 2.6
const WALL_T: float = 0.12
const DOOR_HEADER: float = 2.1
const OPENING_HEADER: float = 2.3

static var mat_exterior: Material = null
static var mat_interior: Material = null
static var mat_wood: Material = null
static var mat_tile: Material = null
static var mat_hall: Material = null

static func _materials() -> void:
	if mat_exterior != null:
		return
	mat_exterior = _flat(Color(0.82, 0.78, 0.70))
	mat_interior = _flat(Color(0.92, 0.90, 0.86))
	mat_wood = _flat(Color(0.62, 0.45, 0.30))
	mat_tile = _flat(Color(0.65, 0.75, 0.78))
	mat_hall = _flat(Color(0.78, 0.72, 0.62))

static func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	return material

static func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)
	return instance

# Build a whole house dictionary {footprint, floors, stair_rect, meta}.
# Returns the (empty, for now) RoofGroup — §30.4 fills it.
static func build(parent: Node3D, house: Dictionary, with_furniture: bool, rng: RandomNumberGenerator) -> Node3D:
	_materials()
	for child in parent.get_children():
		child.queue_free()
	var floors: Array = house["floors"]
	for i in floors.size():
		var floor_root: Node3D = Node3D.new()
		floor_root.name = "Floor_%d" % i
		parent.add_child(floor_root)
		build_floor(floor_root, floors[i], i * WALL_HEIGHT, i > 0, house.get("stair_rect", Rect2()))
	if house.get("stair_rect", Rect2()).size.x > 0.0 and floors.size() > 1:
		_build_steps(parent, house["stair_rect"])
	if with_furniture:
		var furniture_root: Node3D = Node3D.new()
		furniture_root.name = "FurnitureRoot"
		parent.add_child(furniture_root)
		for i in floors.size():
			var floor_furniture: Node3D = Node3D.new()
			floor_furniture.name = "Furniture_%d" % i
			furniture_root.add_child(floor_furniture)
			FurnitureRules.place(floor_furniture, floors[i], i * WALL_HEIGHT, rng)
	var roof_group: Node3D = Node3D.new()
	roof_group.name = "RoofGroup"
	roof_group.position.y = floors.size() * WALL_HEIGHT
	parent.add_child(roof_group)
	return roof_group

static func _build_steps(parent: Node3D, stair_rect: Rect2) -> void:
	# A straight flight along the east wall: fifteen steps rising
	# south to north, landing at the hall band on the upper floor.
	var step_count: int = 15
	var rise: float = WALL_HEIGHT / step_count
	var tread: float = 0.28
	for i in step_count:
		var z: float = stair_rect.end.y - (i + 0.5) * tread
		_box(parent, Vector3(stair_rect.get_center().x, (i + 1) * rise - rise * 0.5, z),
			Vector3(stair_rect.size.x - 0.06, rise, tread), mat_hall)

static func build_floor(parent: Node3D, plan: Dictionary, y_base: float, is_upper: bool, stair_rect: Rect2) -> void:
	_materials()
	# Floors: one slab per room, material by type — a floor you can
	# read is a plan you can still audit in 3D.
	for room in plan["rooms"]:
		if is_upper and room["type"] == "stairs":
			continue # the stairwell: the upper floor's hole is this room
		var rect: Rect2 = room["rect"]
		var floor_material: Material = mat_wood
		if room["type"] == "bathroom" or room["type"] == "wc" or room["type"] == "kitchen" or room["type"] == "kitchen_dining":
			floor_material = mat_tile
		elif room["zone"] == "circulation":
			floor_material = mat_hall
		_box(parent, Vector3(rect.get_center().x, y_base - 0.03, rect.get_center().y),
			Vector3(rect.size.x, 0.06, rect.size.y), floor_material)
	# Walls: every unique segment, openings assembled around.
	for segment in _wall_segments(plan):
		_build_wall(parent, segment, plan, y_base)

# Every unique wall segment in the plan: each room contributes four
# edges; a shared edge is emitted once, owned by neither room.
static func _wall_segments(plan: Dictionary) -> Array:
	var seen: Dictionary = {}
	var segments: Array = []
	for room in plan["rooms"]:
		var rect: Rect2 = room["rect"]
		var edges: Array = [
			[rect.position, Vector2(rect.end.x, rect.position.y)],
			[Vector2(rect.end.x, rect.position.y), rect.end],
			[rect.end, Vector2(rect.position.x, rect.end.y)],
			[Vector2(rect.position.x, rect.end.y), rect.position],
		]
		for edge in edges:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var key: String = "%.2f,%.2f-%.2f,%.2f" % [minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y)]
			if a.x != b.x and a.y != b.y:
				continue
			if seen.has(key):
				continue
			seen[key] = true
			segments.append({"from": a, "to": b, "exterior": _is_exterior(a, b, plan["footprint"])})
	return segments

static func _is_exterior(a: Vector2, b: Vector2, footprint: Rect2) -> bool:
	if absf(a.y - b.y) < 0.01 and (absf(a.y - footprint.position.y) < 0.02 or absf(a.y - footprint.end.y) < 0.02):
		return true
	if absf(a.x - b.x) < 0.01 and (absf(a.x - footprint.position.x) < 0.02 or absf(a.x - footprint.end.x) < 0.02):
		return true
	return false

# Openings belonging to one wall segment, sorted along it: doors and
# the entrance from plan["doors"], windows from plan["windows"].
static func _openings_on(segment: Dictionary, plan: Dictionary) -> Array:
	var a: Vector2 = segment["from"]
	var b: Vector2 = segment["to"]
	var along_x: bool = absf(b.x - a.x) > absf(b.y - a.y)
	# FIX (Ch 30): _wall_segments() emits south edges right-to-left and
	# west edges bottom-to-top, so (center - a) along one axis is
	# NEGATIVE for openings on those walls — Listing 30.3's raw
	# (center.x - a.x) offset put their sill/header boxes outside the
	# house and left the walls solid. The offset is the distance
	# along the segment, measured with the segment's own direction.
	var direction: Vector2 = (b - a).normalized()
	var openings: Array = []
	for door in plan["doors"]:
		var center: Vector2 = door["center"]
		if _on_segment(center, a, b):
			openings.append({"offset": (center - a).dot(direction),
				"width": float(door["width"]),
				"header": OPENING_HEADER if door["kind"] == "opening" else DOOR_HEADER,
				"sill": 0.0})
	for window in plan["windows"]:
		var center: Vector2 = window["center"]
		if _on_segment(center, a, b):
			openings.append({"offset": (center - a).dot(direction),
				"width": float(window["width"]),
				"header": float(window["header"]),
				"sill": float(window["sill"])})
	openings.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["offset"]) < float(q["offset"]))
	return openings

static func _on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	if absf(b.x - a.x) > absf(b.y - a.y):
		return absf(p.y - a.y) < 0.03 and p.x >= minf(a.x, b.x) - 0.01 and p.x <= maxf(a.x, b.x) + 0.01
	return absf(p.x - a.x) < 0.03 and p.y >= minf(a.y, b.y) - 0.01 and p.y <= maxf(a.y, b.y) + 0.01

static func _build_wall(parent: Node3D, segment: Dictionary, plan: Dictionary, y_base: float) -> void:
	var a: Vector2 = segment["from"]
	var b: Vector2 = segment["to"]
	var along_x: bool = absf(b.x - a.x) > absf(b.y - a.y)
	var length: float = (b - a).length()
	var material: Material = mat_exterior if segment["exterior"] else mat_interior
	var wall_root: Node3D = Node3D.new()
	parent.add_child(wall_root)
	var cursor: float = 0.0
	for opening in _openings_on(segment, plan):
		var start: float = float(opening["offset"]) - float(opening["width"]) * 0.5
		var end: float = float(opening["offset"]) + float(opening["width"]) * 0.5
		if start > cursor:
			_span(wall_root, a, b, along_x, cursor, start, 0.0, WALL_HEIGHT, y_base, material)
		if float(opening["sill"]) > 0.01:
			_span(wall_root, a, b, along_x, start, end, 0.0, float(opening["sill"]), y_base, material)
		_span(wall_root, a, b, along_x, start, end, float(opening["header"]), WALL_HEIGHT, y_base, material)
		cursor = maxf(cursor, end)
	if cursor < length:
		_span(wall_root, a, b, along_x, cursor, length, 0.0, WALL_HEIGHT, y_base, material)

# One box of wall between distances d0..d1 along the segment and
# heights h0..h1 above the floor base.
static func _span(parent: Node3D, a: Vector2, b: Vector2, along_x: bool, d0: float, d1: float, h0: float, h1: float, y_base: float, material: Material) -> void:
	if d1 - d0 < 0.01 or h1 - h0 < 0.01:
		return
	var direction: Vector2 = (b - a).normalized()
	var mid: Vector2 = a + direction * ((d0 + d1) * 0.5)
	var size: Vector3 = Vector3(d1 - d0, h1 - h0, WALL_T) if along_x else Vector3(WALL_T, h1 - h0, d1 - d0)
	_box(parent, Vector3(mid.x, y_base + (h0 + h1) * 0.5, mid.y), size, material)
