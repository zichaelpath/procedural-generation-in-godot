extends Control
## Noise gallery: the SAME coordinate field rendered by three noise
## algorithms. Noise = a smooth, deterministic function of position.
## The algorithm decides the grain; the field is shared.

const PREVIEW_SIZE: int = 256
const PREVIEW_FREQUENCY: float = 0.02
const PREVIEW_SEED: int = 1234

@onready var value_rect: TextureRect = $HBoxContainer/VBoxValue/ValueRect
@onready var perlin_rect: TextureRect = $HBoxContainer/VBoxPerlin/PerlinRect
@onready var simplex_rect: TextureRect = $HBoxContainer/VBoxSimplex/SimplexRect


func _ready() -> void:
	value_rect.texture = _render_preview(FastNoiseLite.TYPE_VALUE)
	perlin_rect.texture = _render_preview(FastNoiseLite.TYPE_PERLIN)
	simplex_rect.texture = _render_preview(FastNoiseLite.TYPE_SIMPLEX)


func _render_preview(noise_type: FastNoiseLite.NoiseType) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = noise_type
	noise.seed = PREVIEW_SEED
	noise.frequency = PREVIEW_FREQUENCY

	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			# Noise returns roughly -1..1; remap to 0..1 for display.
			var n: float = noise.get_noise_2d(float(x), float(y))
			var grey: float = clampf(n * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(grey, grey, grey))
	return ImageTexture.create_from_image(image)
