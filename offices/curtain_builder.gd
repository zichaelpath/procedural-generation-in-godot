class_name CurtainBuilder
extends RefCounted
## The curtain: a facade read off the window data (Ch 33's balcony
## discipline, one material up). One glass pane per window, set
## proud of the wall; one spandrel band per floor per facade at the
## slab edge. The returned pane list must count EXACTLY the plans'
## windows — every pane cites a window; every window got its pane.

const PANE_OFFSET: float = 0.07

static var mat_glass: StandardMaterial3D = null
static var mat_spandrel: StandardMaterial3D = null

static func _materials() -> void:
	if mat_glass != null:
		return
	mat_glass = StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.45, 0.62, 0.72, 0.85)
	mat_glass.metallic = 0.35
	mat_glass.roughness = 0.18
	mat_spandrel = StandardMaterial3D.new()
	mat_spandrel.albedo_color = Color(0.36, 0.38, 0.42)

static func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)

static func build_curtain(parent: Node3D, tower: Dictionary) -> Array:
	_materials()
	var group: Node3D = Node3D.new()
	group.name = "CurtainGroup"
	parent.add_child(group)
	var panes: Array = []
	var floors: Array = tower["floors"]
	for f in floors.size():
		var plan: Dictionary = floors[f]
		var footprint: Rect2 = plan["footprint"]
		var y_base: float = f * HouseBuilder.WALL_HEIGHT
		for window in plan["windows"]:
			var center: Vector2 = window["center"]
			var wall: String = window["wall"]
			var outward: Vector2
			match wall:
				"N": outward = Vector2(0, -1)
				"S": outward = Vector2(0, 1)
				"W": outward = Vector2(-1, 0)
				_: outward = Vector2(1, 0)
			var pane_center: Vector2 = center + outward * PANE_OFFSET
			var height: float = float(window["header"]) - float(window["sill"])
			var mid_y: float = y_base + (float(window["sill"]) + float(window["header"])) * 0.5
			var along_x: bool = wall == "N" or wall == "S"
			var size: Vector3 = Vector3(float(window["width"]), height, 0.04) if along_x else Vector3(0.04, height, float(window["width"]))
			_box(group, Vector3(pane_center.x, mid_y, pane_center.y), size, mat_glass)
			panes.append({"floor": f, "room": window["room"], "wall": wall, "center": center})
		# Spandrel bands: one per facade, at this floor's slab edge.
		var band_y: float = y_base + HouseBuilder.WALL_HEIGHT - 0.28
		_box(group, Vector3(footprint.get_center().x, band_y, footprint.position.y - 0.02),
			Vector3(footprint.size.x, 0.56, 0.06), mat_spandrel)
		_box(group, Vector3(footprint.get_center().x, band_y, footprint.end.y + 0.02),
			Vector3(footprint.size.x, 0.56, 0.06), mat_spandrel)
		_box(group, Vector3(footprint.position.x - 0.02, band_y, footprint.get_center().y),
			Vector3(0.06, 0.56, footprint.size.y), mat_spandrel)
		_box(group, Vector3(footprint.end.x + 0.02, band_y, footprint.get_center().y),
			Vector3(0.06, 0.56, footprint.size.y), mat_spandrel)
	return panes
