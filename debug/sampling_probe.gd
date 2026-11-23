extends Node
## The probe: a SEPARATE scene that knows nothing about the
## lab except the shared convention (SeedBank + FieldSampler).
## Its printed value must match the lab's label exactly.

const PROBE_POINT := Vector2(37.5, -12.25)


func _ready() -> void:
	var noise := FieldSampler.demo_noise()
	var value: float = FieldSampler.sample_height(noise, PROBE_POINT.x, PROBE_POINT.y)
	print("Probe value at world (%.2f, %.2f) = %.6f" % [PROBE_POINT.x, PROBE_POINT.y, value])
