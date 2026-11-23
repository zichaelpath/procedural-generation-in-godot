extends Control
## Sampling visualiser: one field, three samplings.
## Coarse grid (16 m), fine grid (4 m), and a diagonal line — all
## asking the noise about WORLD positions, drawn over the field.

const VIEW_SIZE: float = 512.0
const WORLD_EXTENT: float = 100.0  # world runs -100..100 on both axes
const PROBE_POINT := Vector2(37.5, -12.25)

var _texture: ImageTexture
var _noise: FastNoiseLite

@onready var probe_label: Label = $ProbeLabel


func _ready() -> void:
	_noise = FieldSampler.demo_noise()
	_texture = _render_field()
	var probe_value: float = FieldSampler.sample_height(_noise, PROBE_POINT.x, PROBE_POINT.y)
	probe_label.text = "Value at world (%.2f, %.2f) = %.6f" % [PROBE_POINT.x, PROBE_POINT.y, probe_value]
	queue_redraw()


func _world_to_view(x: float, z: float) -> Vector2:
	var u: float = (x + WORLD_EXTENT) / (2.0 * WORLD_EXTENT)
	var v: float = (z + WORLD_EXTENT) / (2.0 * WORLD_EXTENT)
	return Vector2(u * VIEW_SIZE, v * VIEW_SIZE)


func _render_field() -> ImageTexture:
	var size: int = int(VIEW_SIZE)
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for py in size:
		for px in size:
			var wx: float = (float(px) / float(size - 1)) * 2.0 * WORLD_EXTENT - WORLD_EXTENT
			var wz: float = (float(py) / float(size - 1)) * 2.0 * WORLD_EXTENT - WORLD_EXTENT
			var v: float = clampf(FieldSampler.sample_height(_noise, wx, wz) * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(px, py, Color(v, v, v))
	return ImageTexture.create_from_image(image)


func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2(16, 16), Vector2(VIEW_SIZE, VIEW_SIZE)), false)
	var origin := Vector2(16, 16)
	# Coarse grid: every 16 m, red.
	var step: float = 16.0
	var gx: float = -WORLD_EXTENT
	while gx <= WORLD_EXTENT:
		var gz: float = -WORLD_EXTENT
		while gz <= WORLD_EXTENT:
			draw_circle(origin + _world_to_view(gx, gz), 3.0, Color.RED)
			gz += step
		gx += step
	# Fine grid: every 4 m, small green.
	step = 4.0
	gx = -WORLD_EXTENT
	while gx <= WORLD_EXTENT:
		var gz: float = -WORLD_EXTENT
		while gz <= WORLD_EXTENT:
			draw_circle(origin + _world_to_view(gx, gz), 1.2, Color(0.2, 1.0, 0.3))
			gz += step
		gx += step
	# Diagonal: samples along the line from (-100,-100) to (100,100).
	for i in 65:
		var t: float = float(i) / 64.0
		var p: Vector2 = Vector2(lerpf(-WORLD_EXTENT, WORLD_EXTENT, t), lerpf(-WORLD_EXTENT, WORLD_EXTENT, t))
		draw_circle(origin + _world_to_view(p.x, p.y), 2.5, Color.YELLOW)
	# The probe point, in white, on top of everything.
	draw_circle(origin + _world_to_view(PROBE_POINT.x, PROBE_POINT.y), 5.0, Color.WHITE)
