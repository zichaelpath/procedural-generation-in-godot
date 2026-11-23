@tool
extends Node3D
## The heightfield demo as an EDITOR instrument.
## @tool runs this in the editor; changing master_seed in the
## Inspector rebuilds the preview live. Preview for taste in the
## editor — verify for truth in a run (and in the hash test).
##
## The builder half is unchanged from §4.2: generators make
## data, builders make meshes, the contract holds even in @tool.

@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		rebuild()

@export_tool_button("Regenerate Preview")
var _regenerate_button: Callable = rebuild

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		_mesh_instance.material_override = mat
		add_child(_mesh_instance)
		# In the editor, don't let the preview node get saved as an
		# owned child of the scene every time it regenerates.
		if Engine.is_editor_hint():
			_mesh_instance.owner = null
	_mesh_instance.mesh = build_debug_mesh(field_for_current_seed())


func field_for_current_seed() -> HeightField:
	return FieldGenerators.fractal_height_field(master_seed)


func build_debug_mesh(field: HeightField) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: int = field.size
	var half: float = field.world_extent() * 0.5
	for z in size - 1:
		for x in size - 1:
			var x0: float = float(x) * field.cell_size - half
			var z0: float = float(z) * field.cell_size - half
			var x1: float = x0 + field.cell_size
			var z1: float = z0 + field.cell_size
			var h00: float = field.get_point(x, z)
			var h10: float = field.get_point(x + 1, z)
			var h01: float = field.get_point(x, z + 1)
			var h11: float = field.get_point(x + 1, z + 1)
			_add_tri(st, Vector3(x0, h00, z0), Vector3(x0, h01, z1), Vector3(x1, h10, z0))
			_add_tri(st, Vector3(x1, h10, z0), Vector3(x0, h01, z1), Vector3(x1, h11, z1))
	st.generate_normals()
	return st.commit()


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_color(_ramp_color(v.y))
		st.add_vertex(v)


func _ramp_color(h: float) -> Color:
	if h < 1.0:
		return Color(0.76, 0.7, 0.5)
	elif h < 8.0:
		return Color(0.3, 0.55, 0.25)
	else:
		return Color(0.45, 0.42, 0.4)
