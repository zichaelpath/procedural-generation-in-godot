class_name RoofBuilder
extends RefCounted
## Roofs from footprints, grounds from data. The plan does not
## determine the roof — footprint and taste do — so the style is
## rolled from the DRESSING stream, leaving the HOUSES stream with
## exactly one consumer (the solver; Ch 29's determinism rule).

const OVERHANG: float = 0.35

static var mat_roof: StandardMaterial3D = null
static var mat_lawn: StandardMaterial3D = null
static var mat_path: StandardMaterial3D = null

static func _materials() -> void:
	if mat_roof != null:
		return
	mat_roof = StandardMaterial3D.new()
	mat_roof.albedo_color = Color(0.45, 0.30, 0.26)
	mat_roof.cull_mode = BaseMaterial3D.CULL_DISABLED # generated prisms: a winding slip costs a normal, not a roof
	mat_lawn = StandardMaterial3D.new()
	mat_lawn.albedo_color = Color(0.35, 0.55, 0.30)
	mat_path = StandardMaterial3D.new()
	mat_path.albedo_color = Color(0.75, 0.73, 0.68)

static func build(group: Node3D, footprint: Rect2, style: String) -> void:
	_materials()
	for child in group.get_children():
		child.queue_free()
	var w: float = footprint.size.x + OVERHANG * 2.0
	var d: float = footprint.size.y + OVERHANG * 2.0
	group.position = Vector3(footprint.get_center().x, group.position.y, footprint.get_center().y)
	match style:
		"flat":
			_slab(group, w, d)
		"gable":
			_prism(group, w, d, false)
		"hip":
			_prism(group, w, d, true)

static func set_roof_visible(group: Node3D, visible: bool) -> void:
	if group != null:
		group.visible = visible

static func _slab(group: Node3D, w: float, d: float) -> void:
	_box(group, Vector3(0, 0.09, 0), Vector3(w, 0.18, d))
	# Parapet: four thin boxes around the rim.
	_box(group, Vector3(0, 0.3, -d * 0.5 + 0.06), Vector3(w, 0.42, 0.12))
	_box(group, Vector3(0, 0.3, d * 0.5 - 0.06), Vector3(w, 0.42, 0.12))
	_box(group, Vector3(-w * 0.5 + 0.06, 0.3, 0), Vector3(0.12, 0.42, d))
	_box(group, Vector3(w * 0.5 - 0.06, 0.3, 0), Vector3(0.12, 0.42, d))

static func _prism(group: Node3D, w: float, d: float, hip: bool) -> void:
	# Canonical frame: ridge along the long axis. Build with the long
	# axis as X (swapping w/d if needed) and rotate the group if swapped.
	var swapped: bool = d > w
	var lw: float = maxf(w, d)
	var ld: float = minf(w, d)
	var h: float = ld * 0.38
	var inset: float = ld * 0.5 if hip else 0.0
	var a: Vector3 = Vector3(-lw * 0.5, 0, -ld * 0.5)
	var b: Vector3 = Vector3(lw * 0.5, 0, -ld * 0.5)
	var c: Vector3 = Vector3(lw * 0.5, 0, ld * 0.5)
	var e: Vector3 = Vector3(-lw * 0.5, 0, ld * 0.5)
	var r1: Vector3 = Vector3(-lw * 0.5 + inset, h, 0)
	var r2: Vector3 = Vector3(lw * 0.5 - inset, h, 0)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, e, c, r2, r1) # south slope
	_quad(st, b, a, r1, r2) # north slope
	_tri(st, c, b, r2) # east cap (a triangle for hip AND gable: the gable end)
	_tri(st, a, e, r1) # west cap
	var mesh: ArrayMesh = st.commit()
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat_roof
	if swapped:
		instance.rotation.y = PI * 0.5
	group.add_child(instance)

static func _quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	_tri(st, p1, p2, p3)
	_tri(st, p1, p3, p4)

static func _tri(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var normal: Vector3 = (p2 - p1).cross(p3 - p1).normalized()
	st.set_normal(normal)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)

static func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = mat_path if size.y < 0.1 else mat_roof
	parent.add_child(instance)

# Grounds: lawn, and a path that walks from the street edge to the
# ENTRANCE DOOR'S OWN DATA. If the path ever lands anywhere but the
# front door, the bug is upstream, in data you can print.
static func add_grounds(parent: Node3D, plan: Dictionary) -> void:
	_materials()
	var footprint: Rect2 = plan["footprint"]
	var lawn: MeshInstance3D = MeshInstance3D.new()
	var lawn_mesh: BoxMesh = BoxMesh.new()
	lawn_mesh.size = Vector3(footprint.size.x + 6.0, 0.05, footprint.size.y + 6.0)
	lawn.mesh = lawn_mesh
	lawn.position = Vector3(footprint.get_center().x, -0.06, footprint.get_center().y)
	lawn.material_override = mat_lawn
	parent.add_child(lawn)
	var entrance_center: Vector2 = Vector2(footprint.get_center().x, footprint.end.y)
	for door in plan["doors"]:
		if door["kind"] == "entrance":
			entrance_center = door["center"]
	var path: MeshInstance3D = MeshInstance3D.new()
	var path_mesh: BoxMesh = BoxMesh.new()
	path_mesh.size = Vector3(1.2, 0.04, 3.4)
	path.mesh = path_mesh
	path.position = Vector3(entrance_center.x, -0.02, footprint.end.y + 1.7)
	path.material_override = mat_path
	parent.add_child(path)
	var step: MeshInstance3D = MeshInstance3D.new()
	var step_mesh: BoxMesh = BoxMesh.new()
	step_mesh.size = Vector3(1.4, 0.12, 0.5)
	step.mesh = step_mesh
	step.position = Vector3(entrance_center.x, 0.02, footprint.end.y + 0.25)
	step.material_override = mat_path
	parent.add_child(step)
