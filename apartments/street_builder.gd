class_name StreetBuilder
extends RefCounted
## Parcels-lite: solved blocks on a line, with setbacks and gaps.
## NOT Part VIII's parcel system — a street slab, a pavement slab,
## and arithmetic. What is real is every building: each block is an
## independent BlockSolver solve with its own derived seed, built,
## balconied, and roofed by the same passes as steps 5–6.

const STREET_Z: float = 0.0 # the street slab's centre line (world z)
const PAVEMENT_W: float = 3.0

static var mat_road: StandardMaterial3D = null
static var mat_pavement: StandardMaterial3D = null
static var mat_lawn: StandardMaterial3D = null

static func _materials() -> void:
	if mat_road != null:
		return
	mat_road = StandardMaterial3D.new()
	mat_road.albedo_color = Color(0.16, 0.16, 0.17)
	mat_pavement = StandardMaterial3D.new()
	mat_pavement.albedo_color = Color(0.55, 0.54, 0.52)
	mat_lawn = StandardMaterial3D.new()
	mat_lawn.albedo_color = Color(0.35, 0.52, 0.30)

static func _slab(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)

static func build_street(parent: Node3D, master_seed: int, block_count: int) -> Dictionary:
	_materials()
	var rng: RandomNumberGenerator = SeedBank.stream_for(master_seed, SeedBank.STREAM_BUILDINGS)
	var mixes: Array = [
		{"studio": 0.15, "one_bed": 0.25, "two_bed": 0.30, "family": 0.30},
		{"studio": 0.10, "one_bed": 0.30, "two_bed": 0.30, "family": 0.30},
		{"studio": 0.20, "one_bed": 0.20, "two_bed": 0.30, "family": 0.30},
		{"studio": 0.15, "one_bed": 0.30, "two_bed": 0.25, "family": 0.30},
	]
	var typologies: Array = ["point", "point", "corridor", "point"]
	var report: Array = []
	var cursor_x: float = 0.0
	var placed: int = 0
	for i in block_count:
		var width: float = rng.randf_range(19.0, 20.0)
		var depth: float = rng.randf_range(19.5, 20.0)
		var setback: float = rng.randf_range(3.0, 6.0)
		var floors: int = rng.randi_range(3, 6)
		var block_seed: int = rng.randi_range(1, 2000000000)
		var program: ApartmentProgram = ApartmentProgram.build(Vector2(width, depth), floors, mixes[i % mixes.size()])
		var core: Dictionary = ApartmentProgram.core_for(typologies[i % typologies.size()], program.footprint)
		var result: Dictionary = BlockSolver.solve(program, core, block_seed)
		if result["block"].is_empty():
			report.append("Street block %d: solver surrendered — skipped, not placed" % i)
			cursor_x += width + rng.randf_range(4.0, 8.0)
			continue
		var block: Dictionary = result["block"]
		var host: Node3D = Node3D.new()
		host.name = "Block_%d" % i
		host.position = Vector3(cursor_x, 0, -(setback + depth))
		parent.add_child(host)
		var roof_group: Node3D = HouseBuilder.build(host, block, false, rng)
		FacadeBuilder.build_facade(host, block)
		var style: String = "flat" if core["typology"] == "corridor" else ["flat", "gable"][rng.randi_range(0, 1)]
		RoofBuilder.build(roof_group, block["footprint"], style)
		RoofBuilder.set_roof_visible(roof_group, true)
		# The plot, parcels-lite: a lawn slab the size of the plot.
		_slab(host, Vector3(width * 0.5, -0.04, depth * 0.5), Vector3(width + 4.0, 0.05, depth + setback), mat_lawn)
		report.append("Street block %d: %d floors, %d units, %s, solved in %d attempts" % [i, floors,
			(block["units"] as Array).size(), core["typology"], int(result["attempts"])])
		placed += 1
		cursor_x += width + rng.randf_range(4.0, 8.0)
	# Street furniture, such as it is: one road slab, one pavement.
	_slab(parent, Vector3(cursor_x * 0.5, -0.05, STREET_Z + 3.5), Vector3(cursor_x + 16.0, 0.06, 7.0), mat_road)
	_slab(parent, Vector3(cursor_x * 0.5, -0.02, STREET_Z), Vector3(cursor_x + 16.0, 0.06, PAVEMENT_W), mat_pavement)
	report.append("Street complete: %d of %d blocks placed" % [placed, block_count])
	for line in report:
		print(line)
	return {"report": report, "placed": placed, "length": cursor_x}
