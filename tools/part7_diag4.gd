extends SceneTree
## Part VII diagnostic 4: reproduce the EDITOR's step sequence
## headlessly — plugin forces step 2 first, then the shot's step 5 —
## and compare against a direct step 5, to find what state the
## step-2 pass leaves behind that makes the tower solver fail.

func _init() -> void:
	var packed: PackedScene = load("res://stages/stage_7_offices.tscn")
	# Sequence A: direct step 5 (the render-capture flow).
	var a: Node = packed.instantiate()
	root.add_child(a)
	a.set("step", 5)
	print("DIAG A direct step5 cert_first_line=", _cert_first(a))
	a.queue_free()
	# Sequence B: step 2 first (the editor/plugin flow), then step 5.
	var b: Node = packed.instantiate()
	root.add_child(b)
	b.set("step", 2)
	b.call("rebuild")
	b.set("step", 5)
	print("DIAG B step2-then-5 cert_first_line=", _cert_first(b))
	# Solve a third time in the same instance (the arrange re-print).
	b.call("_solve_tower")
	print("DIAG B2 re-solve cert_first_line=", _cert_first(b))
	b.queue_free()
	quit()


func _cert_first(stage: Node) -> String:
	var label: Label = stage.get_node("UI/CertLabel")
	if label == null:
		return "<no label>"
	var t: String = label.text
	if t.is_empty():
		return "<empty>"
	return t.split("\n")[0]
