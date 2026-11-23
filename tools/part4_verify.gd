extends SceneTree
## Part IV smoke test: build every stage step at the master seed and
## assert the chapters' theorems (edges == rooms-1, one region,
## priced loops, solver verdict, finale validation).
## Runs inside _process: nodes added from _init are not inside the
## tree yet, so their _ready (and the stage's first build) would not
## have fired.

var _ran: bool = false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var packed: PackedScene = load("res://stages/stage_4_dungeons.tscn") as PackedScene
	if packed == null:
		print("PART4_FAIL cannot load stage scene")
		return true
	var failures: Array = []
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	stage.set("master_seed", 20261119)
	for s in range(20):
		stage.set("step", s)
		stage.call("rebuild")
		var d = stage.get("data")
		var note: String = "data=null"
		if d != null:
			note = "rooms=%d edges=%d passable=%d regions=%d" % [
				d.rooms.size(), d.edges.size(), d.floor_count(), d.region_report().size()]
		print("PART4 step ", s, " OK ", note)
		if s == 4 and d != null and d.edges.size() != d.rooms.size() - 1:
			failures.append("step4 edges != rooms-1")
		if s == 7 and d != null and d.region_report().size() != 1:
			failures.append("step7 regions != 1")
		if s == 9 and d != null and d.region_report().size() != 1:
			failures.append("step9 regions != 1")
		if s == 12 and d != null:
			var v: Dictionary = MissionPlanner.new().is_completable(d)
			if not bool(v["completable"]):
				failures.append("step12 not completable")
		if s == 13 and d != null and LoopSurgeon.loop_count(d) != 2:
			failures.append("step13 loops != 2 (got %d)" % LoopSurgeon.loop_count(d))
		if s == 16 and d != null and d.floor_count() == 0:
			failures.append("step16 WFC empty/failed")
		if s == 19 and d != null:
			var rep: Dictionary = DungeonValidator.validate(d)
			if not bool(rep["pass"]):
				failures.append("step19 validation failed: %s" % str(rep["results"]))
	if failures.is_empty():
		print("PART4_ALL_OK")
	else:
		print("PART4_FAILURES ", failures)
	return true
