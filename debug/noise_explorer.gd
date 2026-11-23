extends Control
## Noise explorer: live Inspector knobs over FastNoiseLite.
## 1D = a cross-section of the field, 2D = the heightmap, 3D = a
## slice drifting through time. One instance per field — the 1D line
## and 3D slice share the configured one.

const PREVIEW_SIZE: int = 256
const LINE_HEIGHT: int = 64

@export var noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_PERLIN
@export var noise_seed: int = 7
@export var frequency: float = 0.02
@export var cellular_seed: int = 99

var _noise: FastNoiseLite
var _slice_time: float = 0.0
var _slice_timer: float = 0.0

@onready var value_rect: TextureRect = $HBoxContainer/VBoxValue/ValueRect
@onready var perlin_rect: TextureRect = $HBoxContainer/VBoxPerlin/PerlinRect
@onready var simplex_rect: TextureRect = $HBoxContainer/VBoxSimplex/SimplexRect
@onready var line_rect: TextureRect = $HBoxContainer2/LineRect
@onready var slice_rect: TextureRect = $HBoxContainer2/SliceRect
@onready var cellular_rect: TextureRect = $HBoxContainer2/CellularRect


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = noise_type
	_noise.seed = noise_seed
	_noise.frequency = frequency
	# One shared instance renders the 2D previews; only the TYPE differs.
	value_rect.texture = _render_type(FastNoiseLite.TYPE_VALUE)
	perlin_rect.texture = _render_type(FastNoiseLite.TYPE_PERLIN)
	simplex_rect.texture = _render_type(FastNoiseLite.TYPE_SIMPLEX)
	line_rect.texture = _render_line()
	slice_rect.texture = _render_slice(0.0)
	cellular_rect.texture = _render_cellular()


func _process(delta: float) -> void:
	_slice_timer += delta
	if _slice_timer < 0.25:
		return
	_slice_timer = 0.0
	_slice_time += 0.25
	slice_rect.texture = _render_slice(_slice_time)


func _render_type(noise_type: FastNoiseLite.NoiseType) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = noise_type
	n.seed = noise_seed
	n.frequency = frequency
	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			var v: float = clampf(n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(image)


func _render_line() -> ImageTexture:
	var image := Image.create_empty(PREVIEW_SIZE, LINE_HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	for x in PREVIEW_SIZE:
		var v: float = _noise.get_noise_2d(float(x), 0.0) * 0.5 + 0.5
		var row: int = clampi(int((1.0 - v) * float(LINE_HEIGHT - 1)), 0, LINE_HEIGHT - 1)
		image.set_pixel(x, row, Color.WHITE)
		if row + 1 < LINE_HEIGHT:
			image.set_pixel(x, row + 1, Color(0.7, 0.7, 0.7))
	return ImageTexture.create_from_image(image)


func _render_slice(t: float) -> ImageTexture:
	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			var v: float = clampf(_noise.get_noise_3d(float(x), float(y), t) * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(image)


func _render_cellular() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.seed = cellular_seed
	n.frequency = frequency
	# Cellular returns a distance value (0..1-ish); show it directly.
	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			var v: float = clampf(n.get_noise_2d(float(x), float(y)), 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(image)
