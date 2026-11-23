extends Control
## Determinism test: the contract, enforced by machine.
## Hash the generated DATA (never screenshots, never node trees),
## regenerate, compare. Three checks, three clauses of the contract.

@onready var output: RichTextLabel = $Output


func _ready() -> void:
	var lines: Array[String] = []
	var failures: int = 0

	# Check 1: same seed, twice -> identical hash. The basic promise.
	var h1: int = _field_hash(20261119)
	var h2: int = _field_hash(20261119)
	failures += _report(lines, "Regeneration is identical", h1 == h2)

	# Check 2: unrelated generation work — 1,000 draws from ANOTHER
	# stream, plus 1,000 draws burned off the GLOBAL generator —
	# must not move this field by a single float. Isolation, enforced.
	var plants := SeedBank.stream_for(20261119, SeedBank.STREAM_PLANTS)
	for i in 1000:
		plants.randf()
	for i in 1000:
		randf()
	var h3: int = _field_hash(20261119)
	failures += _report(lines, "Other streams cannot disturb terrain", h3 == h1)

	# Check 3: a different seed MUST give a different field.
	# Catches the classic facepalm: the seed not wired in at all.
	var h4: int = _field_hash(20261120)
	failures += _report(lines, "A different seed gives a different world", h4 != h1)

	lines.append("")
	lines.append("ALL CHECKS PASSED — same seed, same world." if failures == 0 else "%d CHECK(S) FAILED." % failures)
	output.text = "\n".join(lines)


func _field_hash(master_seed: int) -> int:
	var field: HeightField = FieldGenerators.fractal_height_field(master_seed, 33, 2.0)
	return hash(field.heights.to_byte_array())


func _report(lines: Array[String], name: String, ok: bool) -> int:
	lines.append("%s: %s" % [name, "PASS" if ok else "FAIL"])
	return 0 if ok else 1
