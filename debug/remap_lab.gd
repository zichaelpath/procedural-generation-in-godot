extends Control
## Remap lab: ONE field, many readings. The generator never
## changes — only the function reshaping its values does.
## Flat spots in the curve become flat spots in the world.

const PREVIEW_SIZE: int = 256

var _field: PackedFloat32Array = PackedFloat32Array()
var _curve: Curve

@onready var before_rect: TextureRect = $HBoxContainer/BeforeRect
@onready var after_rect: TextureRect = $HBoxContainer/AfterRect
@onready var mode_picker: OptionButton = $ModePicker
@onready var sea_slider: HSlider = $SeaSlider


func _ready() -> void:
	_curve = load("res://debug/remap_curve.tres") as Curve
	var noise := FieldSampler.demo_noise()
	_field.resize(PREVIEW_SIZE * PREVIEW_SIZE)
	for y in PREVIEW_SIZE:
		for x in PREVIEW_SIZE:
			var wx: float = (float(x) / float(PREVIEW_SIZE - 1)) * 200.0 - 100.0
			var wz: float = (float(y) / float(PREVIEW_SIZE - 1)) * 200.0 - 100.0
			_field[y * PREVIEW_SIZE + x] = clampf(noise.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	mode_picker.item_selected.connect(_on_controls_changed)
	sea_slider.value_changed.connect(_on_controls_changed)
	_render()


func _on_controls_changed(_ignored: float = 0.0) -> void:
	_render()


func apply_remap(v: float) -> float:
	match mode_picker.selected:
		0:  # Linear: the baseline. Output = input.
			return v
		1:  # Smoothstep: thin the middle, fatten the extremes.
			return smoothstep(0.0, 1.0, v)
		2:  # Power: sink everything except the peaks.
			return pow(v, 2.2)
		3:  # The designer-edited Curve resource.
			return _curve.sample(v)
	return v


func _render() -> void:
	var sea: float = sea_slider.value
	before_rect.texture = _render_image(false, sea)
	after_rect.texture = _render_image(true, sea)


func _render_image(remapped: bool, sea: float) -> ImageTexture:
	var image := Image.create_empty(PREVIEW_SIZE, PREVIEW_SIZE, false, Image.FORMAT_RGB8)
	for i in _field.size():
		var v: float = _field[i]
		if remapped:
			v = apply_remap(v)
		var col: Color
		if v < sea:
			col = Color(0.1, 0.3, 0.6) * (0.5 + v)  # water, deeper = darker
		else:
			col = Color(v, v, v)  # land as grayscale height
		image.set_pixel(i % PREVIEW_SIZE, i / PREVIEW_SIZE, col)
	return ImageTexture.create_from_image(image)
