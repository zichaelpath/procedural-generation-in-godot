class_name FieldView
extends RefCounted
## The book's standard instrument: any float grid -> an image.
## Colours show SHAPE (data is normalised to its own min/max);
## the stats line shows SCALE. Read both, every time — each lies
## in its own way.

enum Ramp { GRAYSCALE, HEIGHT, MOISTURE }


static func texture_from_values(values: PackedFloat32Array, size: int, ramp: Ramp) -> ImageTexture:
	var stats: Dictionary = stats_of(values)
	var lo: float = stats["min"]
	var hi: float = stats["max"]
	var span: float = maxf(hi - lo, 0.000001)
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for i in values.size():
		var t: float = (values[i] - lo) / span
		image.set_pixel(i % size, i / size, _ramp_color(ramp, t))
	return ImageTexture.create_from_image(image)


static func stats_of(values: PackedFloat32Array) -> Dictionary:
	var lo: float = INF
	var hi: float = -INF
	var total: float = 0.0
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		total += v
	return {"min": lo, "max": hi, "average": total / float(maxi(values.size(), 1))}


static func _ramp_color(ramp: Ramp, t: float) -> Color:
	match ramp:
		Ramp.GRAYSCALE:
			return Color(t, t, t)
		Ramp.HEIGHT:
			# Map-style: deep water -> sand -> grass -> rock -> snow.
			if t < 0.35:
				return Color(0.1, 0.3, 0.65)
			elif t < 0.45:
				return Color(0.76, 0.7, 0.5)
			elif t < 0.7:
				return Color(0.3, 0.55, 0.25)
			elif t < 0.88:
				return Color(0.45, 0.42, 0.4)
			else:
				return Color(0.95, 0.95, 0.97)
		Ramp.MOISTURE:
			# Parched brown -> tan -> green -> saturated blue.
			if t < 0.3:
				return Color(0.6, 0.45, 0.25)
			elif t < 0.55:
				return Color(0.75, 0.65, 0.4)
			elif t < 0.8:
				return Color(0.3, 0.55, 0.3)
			else:
				return Color(0.15, 0.4, 0.8)
	return Color.MAGENTA
