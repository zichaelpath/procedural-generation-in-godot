extends Node3D
## One button rebuilds the SAME scatter every time, the other never
## does. The only difference is where the randomness comes from:
## a fixed seed versus the system clock.

const BLOCK_COUNT: int = 48
const FIELD_HALF: float = 15.0

@onready var scatter_root: Node3D = $Scatter
@onready var seeded_button: Button = $UI/SeededButton
@onready var random_button: Button = $UI/RandomButton

var _block_mesh: BoxMesh


func _ready() -> void:
	_block_mesh = BoxMesh.new()
	_block_mesh.size = Vector3.ONE
	seeded_button.pressed.connect(_on_seeded_pressed)
	random_button.pressed.connect(_on_random_pressed)
	_on_seeded_pressed()


func _on_seeded_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	_build_scatter(rng)


func _on_random_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_build_scatter(rng)


func _build_scatter(rng: RandomNumberGenerator) -> void:
	for child in scatter_root.get_children():
		scatter_root.remove_child(child)
		child.free()
	for i in BLOCK_COUNT:
		var block := MeshInstance3D.new()
		block.mesh = _block_mesh
		var height: float = rng.randf_range(0.5, 6.0)
		block.position = Vector3(
			rng.randf_range(-FIELD_HALF, FIELD_HALF),
			height * 0.5,
			rng.randf_range(-FIELD_HALF, FIELD_HALF))
		block.scale = Vector3(1.0, height, 1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(rng.randf(), 0.55, 0.85)
		block.material_override = mat
		scatter_root.add_child(block)
