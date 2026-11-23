class_name LobbyBuilder
extends RefCounted
## The lobby's furniture-scale truth, from plan data: columns at
## the atrium voids' corners, a canopy over the entrance (centred
## on the core's entrance_x — the entrance's data, spent again), a
## reception desk facing it, railings on the galleries. A lobby has
## four columns, not forty candidates: rules, not scatter.

static var mat_stone: StandardMaterial3D = null
static var mat_dark: StandardMaterial3D = null

static func _materials() -> void:
	if mat_stone != null:
		return
	mat_stone = StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.78, 0.76, 0.72)
	mat_dark = StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.30, 0.28, 0.26)

static func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)

static func build_lobby(parent: Node3D, tower: Dictionary) -> void:
	_materials()
	var group: Node3D = Node3D.new()
	group.name = "LobbyGroup"
	parent.add_child(group)
	var ground: Dictionary = tower["floors"][0]
	var footprint: Rect2 = ground["footprint"]
	var entrance_x: float = float(tower["core"]["entrance_x"])
	# Canopy: a slab outside the south wall, centred on the entrance.
	_box(group, Vector3(entrance_x, HouseBuilder.WALL_HEIGHT - 0.35, footprint.end.y + 1.1),
		Vector3(5.0, 0.18, 2.2), mat_dark)
	# Reception: one desk, centred in the south lobby field, facing
	# the entrance it serves. Its position is read off the lobby
	# room's rectangle, not placed by eye.
	for room in ground["rooms"]:
		if room["type"] == "lobby" and room["name"].ends_with("lobby_south"):
			var rect: Rect2 = room["rect"]
			var c: Vector2 = rect.get_center()
			_box(group, Vector3(c.x, 0.55, c.y + 0.6), Vector3(3.2, 1.1, 0.7), mat_dark)
			_box(group, Vector3(c.x, 0.06, c.y + 0.6), Vector3(3.6, 0.12, 1.0), mat_stone)
	# Columns + gallery railings, from floor 1's atrium voids.
	if (tower["floors"] as Array).size() > 1:
		var upper: Dictionary = tower["floors"][1]
		var voids: Array = upper["meta"].get("atrium_voids", [])
		var top_y: float = HouseBuilder.WALL_HEIGHT * 2.0
		for void_rect in voids:
			var rect: Rect2 = void_rect
			for corner in [rect.position, Vector2(rect.end.x, rect.position.y),
					Vector2(rect.position.x, rect.end.y), rect.end]:
				_box(group, Vector3(corner.x, top_y * 0.5, corner.y),
					Vector3(0.45, top_y, 0.45), mat_stone)
			# Railing along the void's long edges at gallery height.
			var rail_y: float = HouseBuilder.WALL_HEIGHT + 0.55
			_box(group, Vector3(rect.get_center().x, rail_y, rect.position.y + 0.03),
				Vector3(rect.size.x, 0.05, 0.05), mat_dark)
			_box(group, Vector3(rect.get_center().x, rail_y, rect.end.y - 0.03),
				Vector3(rect.size.x, 0.05, 0.05), mat_dark)
