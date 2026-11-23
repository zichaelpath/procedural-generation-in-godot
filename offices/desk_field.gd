class_name DeskField
extends RefCounted
## The desk field: Part III's jittered grid + Ch 30's hazards-first
## rejection, at office scale. Candidates are born on a bench grid
## (1.5 m along, 2.6 m across rows), jittered a few centimetres,
## and REJECTED against pre-loaded blockers: structural columns
## and door-clearance discs. Nothing is nudged; nothing is forced.
## The survivors are data (plan["desks"]) — the headcount rule in
## OfficeRules grades the count, Ch 36 builds the desks from it.

const PITCH: Vector2 = Vector2(1.5, 2.6) # along-bench, across rows
const FIELD_MARGIN: float = 0.55
const COLUMN_CLEAR: float = 0.9
const DOOR_CLEAR: float = 0.85
const COLUMN_BAY_X: float = 7.5
const COLUMN_BAY_Y: float = 7.33

static func columns_for(footprint: Rect2) -> Array:
	var columns: Array = []
	var gx: int = 1
	while gx * COLUMN_BAY_X < footprint.size.x - 1.0:
		var gy: int = 1
		while gy * COLUMN_BAY_Y < footprint.size.y - 1.0:
			columns.append(footprint.position + Vector2(gx * COLUMN_BAY_X, gy * COLUMN_BAY_Y))
			gy += 1
		gx += 1
	return columns

static func generate(plan: Dictionary, rng: RandomNumberGenerator, density: float) -> Array:
	var desks: Array = []
	var columns: Array = columns_for(plan["footprint"])
	var door_centres: Array = []
	for door in plan["doors"]:
		door_centres.append(door["center"])
	for room in plan["rooms"]:
		if room["type"] != "open_plan":
			continue
		var rect: Rect2 = room["rect"]
		var jitter: Vector2 = Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		var row: int = 0
		var y: float = rect.position.y + FIELD_MARGIN + PITCH.y * 0.5 + jitter.y
		while y <= rect.end.y - FIELD_MARGIN - 0.4:
			var x: float = rect.position.x + FIELD_MARGIN + PITCH.x * 0.5 + jitter.x
			while x <= rect.end.x - FIELD_MARGIN - 0.4:
				var candidate: Vector2 = Vector2(x, y)
				if density >= 1.0 or rng.randf() < density:
					if not _blocked(candidate, columns, door_centres):
						desks.append({"room": room["name"], "pos": candidate,
							"rot_deg": 0.0 if row % 2 == 0 else 180.0, "workgroup": room["name"]})
				x += PITCH.x
			y += PITCH.y
			row += 1
	plan["desks"] = desks
	return desks

static func _blocked(candidate: Vector2, columns: Array, door_centres: Array) -> bool:
	for column in columns:
		if candidate.distance_to(column) < COLUMN_CLEAR:
			return true
	for centre in door_centres:
		if candidate.distance_to(centre) < DOOR_CLEAR:
			return true
	return false

static func count_for_floor(plan: Dictionary) -> int:
	return (plan["desks"] as Array).size()

# Build one floor's desks as simple bench furniture: a top slab and
# a monitor block per desk, under a holder per desk (Ch 30's holder
# discipline: position and facing live on the holder, geometry
# inside it). Returns the number built — the stage prints it next
# to the plan's counted desks, and the two numbers must agree.
static var mat_desk: StandardMaterial3D = null
static var mat_screen: StandardMaterial3D = null

static func build_desk_nodes(parent: Node3D, plan: Dictionary, y_base: float) -> int:
	if mat_desk == null:
		mat_desk = StandardMaterial3D.new()
		mat_desk.albedo_color = Color(0.80, 0.78, 0.74)
		mat_screen = StandardMaterial3D.new()
		mat_screen.albedo_color = Color(0.12, 0.14, 0.18)
	var built: int = 0
	for desk in plan["desks"]:
		var holder: Node3D = Node3D.new()
		holder.name = "Desk"
		var pos: Vector2 = desk["pos"]
		holder.position = Vector3(pos.x, y_base, pos.y)
		holder.rotation.y = deg_to_rad(float(desk["rot_deg"]))
		parent.add_child(holder)
		var top: MeshInstance3D = MeshInstance3D.new()
		var top_mesh: BoxMesh = BoxMesh.new()
		top_mesh.size = Vector3(1.4, 0.05, 0.7)
		top.mesh = top_mesh
		top.position = Vector3(0, 0.73, 0)
		top.material_override = mat_desk
		holder.add_child(top)
		var screen: MeshInstance3D = MeshInstance3D.new()
		var screen_mesh: BoxMesh = BoxMesh.new()
		screen_mesh.size = Vector3(0.55, 0.36, 0.04)
		screen.mesh = screen_mesh
		screen.position = Vector3(0, 0.98, -0.22)
		screen.material_override = mat_screen
		holder.add_child(screen)
		built += 1
	return built
