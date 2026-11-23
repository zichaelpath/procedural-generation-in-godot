@tool
class_name Turtle3D
extends Node3D

## The 3D turtle. State = position + Basis FRAME (growth / up / left
## arrows) + bracket depth. Rotations are always around the frame's
## OWN axes, which is what stops the plant twisting into knots.
##
## Commands: F forward · + - yaw · & ^ pitch · \ / roll · | turn 180
##           [ ] push/pop full state.
## The walk is recorded as segment DATA (dictionaries with
## from/to/depth/dist); rendering pours the segments into one
## MultiMesh of stretched boxes.

@export var angle_degrees: float = 22.0
@export var segment_length: float = 0.35
@export var box_thickness: float = 0.045

var segments: Array[Dictionary] = []

var _multimesh_instance: MultiMeshInstance3D = null

func grow(source_string: String) -> void:
	segments.clear()
	var pos: Vector3 = Vector3.ZERO
	# Frame starts growing straight up: growth dir = -Z of the basis,
	# so rotate identity so that -Z points at +Y.
	# PROJECT FIX (Listing 17.1 sign error, chapter untouched): the
	# listing prints -PI / 2.0, which maps -Z to -Y — the tree grows
	# underground (measured bounds y 0 .. -15.7). +PI / 2.0 is what
	# the listing's own comment above describes.
	var frame: Basis = Basis(Vector3.RIGHT, PI / 2.0)
	var depth: int = 0
	var dist: float = 0.0
	var stack: Array[Dictionary] = []
	var angle: float = deg_to_rad(angle_degrees)
	for i in source_string.length():
		var symbol: String = source_string.substr(i, 1)
		match symbol:
			"F":
				var dir: Vector3 = -frame.z.normalized()
				var next_pos: Vector3 = pos + dir * segment_length
				segments.append({
					"from": pos, "to": next_pos,
					"depth": depth, "dist": dist,
				})
				pos = next_pos
				dist += segment_length
			"+":
				frame = Basis(frame.y, angle) * frame
			"-":
				frame = Basis(frame.y, -angle) * frame
			"&":
				frame = Basis(frame.x, angle) * frame
			"^":
				frame = Basis(frame.x, -angle) * frame
			"\\":
				frame = Basis(frame.z, angle) * frame
			"/":
				frame = Basis(frame.z, -angle) * frame
			"|":
				frame = Basis(frame.y, PI) * frame
			"[":
				stack.push_back({"position": pos, "frame": frame, "depth": depth, "dist": dist})
				depth += 1
			"]":
				if stack.is_empty():
					continue
				var state: Dictionary = stack.pop_back()
				pos = state["position"]
				frame = state["frame"]
				depth = int(state["depth"])
				dist = float(state["dist"])
			_:
				pass
	_render_boxes()

func _render_boxes() -> void:
	if _multimesh_instance == null:
		_multimesh_instance = MultiMeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.28, 0.16)
		box.material = mat
		_multimesh_instance.multimesh = MultiMesh.new()
		_multimesh_instance.multimesh.mesh = box
		_multimesh_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		add_child(_multimesh_instance)
	var mm: MultiMesh = _multimesh_instance.multimesh
	mm.instance_count = segments.size()
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		var dir: Vector3 = b - a
		var len: float = dir.length()
		var up_hint: Vector3 = Vector3.UP
		if abs(dir.normalized().dot(Vector3.UP)) > 0.99:
			up_hint = Vector3.RIGHT  # guard: looking_at degenerates straight up/down
		var basis: Basis = Basis.looking_at(dir.normalized(), up_hint)
		basis = basis.scaled(Vector3(box_thickness, box_thickness, len))
		mm.set_instance_transform(i, Transform3D(basis, (a + b) * 0.5))
