extends Node3D
## Fractal explorer: FBM = the same noise sampled at doubling
## frequencies, summed with shrinking amplitude.
## Lacunarity = how fast frequency grows per octave.
## Gain = how fast amplitude shrinks per octave.

const PREVIEW_SIZE: int = 128
const MESH_POINTS: int = 49
const MESH_WORLD_SIZE: float = 100.0
const HEIGHT_SCALE: float = 14.0

var _octaves: int = 4
var _lacunarity: float = 2.0
var _gain: float = 0.5

@onready var preview: TextureRect = $CanvasLayer/OctavePreview
@onready var terrain_mesh: MeshInstance3D = $TerrainMesh


func _ready() -> void:
	$CanvasLayer/LacunaritySlider.value_changed.connect(_on_lacunarity_changed)
	$CanvasLayer/GainSlider.value_changed.connect(_on_gain_changed)
	$CanvasLayer/Oct1.pressed.connect(_set_octaves.bind(1))
	$CanvasLayer/Oct2.pressed.connect(_set_octaves.bind(2))
	$CanvasLayer/Oct4.pressed.connect(_set_octaves.bind(4))
	$CanvasLayer/Oct8.pressed.connect(_set_octaves.bind(8))
	_rebuild()


func _set_octaves(count: int) -> void:
	_octaves = count
	_rebuild()


func _on_lacunarity_changed(value: float) -> void:
	_lacunarity = value
	_rebuild()


func _on_gain_changed(value: float) -> void:
	_gain = value
	_rebuild()


func _make_noise() -> FastNoiseLite:
	var noise := SeedBank.noise_for(20261119, SeedBank.STREAM_TERRAIN, 0.015, _octaves)
	noise.fractal_lacunarity = _lacunarity
	noise.fractal_gain = _gain
	return noise


func _rebuild() -> void:
	var noise := _make_noise()
	_render_preview(noise)
	_build_mesh(noise)


func _render_preview(noise: FastNoiseLite) -> void:
	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			var wx: float = (float(x) / float(PREVIEW_SIZE - 1) - 0.5) * MESH_WORLD_SIZE
			var wz: float = (float(y) / float(PREVIEW_SIZE - 1) - 0.5) * MESH_WORLD_SIZE
			var v: float = clampf(noise.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	preview.texture = ImageTexture.create_from_image(image)


func _build_mesh(noise: FastNoiseLite) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step: float = MESH_WORLD_SIZE / float(MESH_POINTS - 1)
	for z in MESH_POINTS - 1:
		for x in MESH_POINTS - 1:
			var x0: float = -MESH_WORLD_SIZE * 0.5 + float(x) * step
			var z0: float = -MESH_WORLD_SIZE * 0.5 + float(z) * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			var h00: float = noise.get_noise_2d(x0, z0) * HEIGHT_SCALE
			var h10: float = noise.get_noise_2d(x1, z0) * HEIGHT_SCALE
			var h01: float = noise.get_noise_2d(x0, z1) * HEIGHT_SCALE
			var h11: float = noise.get_noise_2d(x1, z1) * HEIGHT_SCALE
			# Two triangles per cell, wound to face UP (counter-clockwise
			# seen from above in Godot's right-handed space, -Z forward).
			st.add_vertex(Vector3(x0, h00, z0))
			st.add_vertex(Vector3(x0, h01, z1))
			st.add_vertex(Vector3(x1, h10, z0))
			st.add_vertex(Vector3(x1, h10, z0))
			st.add_vertex(Vector3(x0, h01, z1))
			st.add_vertex(Vector3(x1, h11, z1))
	st.generate_normals()
	terrain_mesh.mesh = st.commit()
