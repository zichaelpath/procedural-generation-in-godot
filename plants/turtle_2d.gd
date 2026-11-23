@tool
class_name Turtle2D
extends Node2D

## The turtle, refactored: GENERATION is separated from DRAWING.
## regenerate() walks the string once (applying jitter from a
## passed-in RNG) and caches line segments as data. _draw() only
## renders the cache — no dice are ever rolled at draw time.

@export var source_string: String = "":
	set(value):
		source_string = value
		regenerate()
@export var angle_degrees: float = 25.0:
	set(value):
		angle_degrees = value
		regenerate()
@export var segment_length: float = 6.0:
	set(value):
		segment_length = value
		regenerate()
## Jitter bands: length_jitter is a fraction (0.15 = +/-15%),
## angle_jitter_degrees is an absolute wobble in degrees.
@export var length_jitter: float = 0.0
@export var angle_jitter_degrees: float = 0.0
@export var line_color: Color = Color(0.45, 0.75, 0.35)
@export var line_width: float = 2.0

var jitter_rng: RandomNumberGenerator = null  # set by the caller before regenerate()
var _segments: Array[Vector2] = []  # flat pairs: [from0, to0, from1, to1, ...]

func regenerate() -> void:
	_segments.clear()
	var pos: Vector2 = Vector2.ZERO
	var heading: Vector2 = Vector2.UP
	var base_angle: float = deg_to_rad(angle_degrees)
	var stack: Array[Dictionary] = []
	for i in source_string.length():
		var symbol: String = source_string.substr(i, 1)
		match symbol:
			"F":
				var len_factor: float = 1.0
				if jitter_rng != null and length_jitter > 0.0:
					len_factor = 1.0 + jitter_rng.randf_range(-length_jitter, length_jitter)
				var next_pos: Vector2 = pos + heading * segment_length * len_factor
				_segments.append(pos)
				_segments.append(next_pos)
				pos = next_pos
			"+", "-":
				var wobble: float = 0.0
				if jitter_rng != null and angle_jitter_degrees > 0.0:
					wobble = deg_to_rad(jitter_rng.randf_range(-angle_jitter_degrees, angle_jitter_degrees))
				var turn: float = base_angle + wobble
				heading = heading.rotated(turn if symbol == "+" else -turn)
			"[":
				stack.push_back({"position": pos, "heading": heading})
			"]":
				if stack.is_empty():
					continue
				var state: Dictionary = stack.pop_back()
				pos = state["position"]
				heading = state["heading"]
			_:
				pass
	queue_redraw()

func _draw() -> void:
	var i: int = 0
	while i + 1 < _segments.size():
		draw_line(_segments[i], _segments[i + 1], line_color, line_width)
		i += 2
