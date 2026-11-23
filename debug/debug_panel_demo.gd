extends Control
## Demo: one HeightField, three instruments, plus stats and a
## one-key screenshot for comparing runs.

var _field: HeightField

@onready var gray_rect: TextureRect = $HBoxContainer/VBoxGray/GrayRect
@onready var height_rect: TextureRect = $HBoxContainer/VBoxHeight/HeightRect
@onready var moisture_rect: TextureRect = $HBoxContainer/VBoxMoisture/MoistureRect
@onready var stats_label: Label = $StatsLabel


func _ready() -> void:
	_field = FieldGenerators.fractal_height_field(20261119)
	gray_rect.texture = FieldView.texture_from_values(_field.heights, _field.size, FieldView.Ramp.GRAYSCALE)
	height_rect.texture = FieldView.texture_from_values(_field.heights, _field.size, FieldView.Ramp.HEIGHT)
	# Same field through the moisture ramp: the point is that the
	# VIEW changes the question, even before the data differs.
	moisture_rect.texture = FieldView.texture_from_values(_field.heights, _field.size, FieldView.Ramp.MOISTURE)
	var s: Dictionary = FieldView.stats_of(_field.heights)
	stats_label.text = "min %.2f · max %.2f · average %.2f · press S for a screenshot" % [s["min"], s["max"], s["average"]]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_S:
		var viewport_image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://field_compare.png"
		viewport_image.save_png(path)
		print("Saved comparison screenshot to ", ProjectSettings.globalize_path(path))
