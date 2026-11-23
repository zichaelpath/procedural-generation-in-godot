extends Control
## Dice lab: one named stream, exercised properly.
## Ranges, bell curves, state snapshots, reproducible shuffles.

@onready var output: RichTextLabel = $VBoxContainer/Output


func _ready() -> void:
	run_lab()


func _on_run_button_pressed() -> void:
	run_lab()


func run_lab() -> void:
	var lines: Array[String] = []
	var rng := SeedBank.stream_for(20261119, SeedBank.STREAM_DUNGEON)

	# --- Ranges: randi_range is INCLUSIVE at both ends. ---
	var rolls: Array[int] = []
	for i in 10:
		rolls.append(rng.randi_range(1, 6))
	lines.append("Ten d6 rolls: %s" % str(rolls))

	# --- randfn: a bell curve around a mean. Average of 1,000 samples
	# should land close to 50, unlike uniform's hard edges. ---
	var total: float = 0.0
	for i in 1000:
		total += rng.randfn(50.0, 10.0)
	lines.append("randfn(50, 10) average over 1,000 draws: %.2f" % (total / 1000.0))

	# --- State snapshot: save the position, draw, restore, redraw.
	# The second batch MUST equal the first batch after the restore. ---
	for i in 5:
		rng.randi()
	var saved_state: int = rng.state
	var batch_a: Array[int] = []
	for i in 5:
		batch_a.append(rng.randi_range(0, 999))
	rng.state = saved_state
	var batch_b: Array[int] = []
	for i in 5:
		batch_b.append(rng.randi_range(0, 999))
	lines.append("Batch before restore: %s" % str(batch_a))
	lines.append("Batch after restore:  %s" % str(batch_b))
	lines.append("State snapshot works: %s" % str(batch_a == batch_b))

	# --- Reproducible shuffle: same stream position, same order. ---
	var deck: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
	# NOTE (scene fix, Ch.2 Listing 2.4): RandomNumberGenerator has no
	# shuffle() in Godot 4.7.2 — Fisher-Yates driven by this same stream
	# keeps the shuffle reproducible, as the chapter intends.
	for si in range(deck.size() - 1, 0, -1):
		var sj: int = rng.randi_range(0, si)
		var tmp: String = deck[si]
		deck[si] = deck[sj]
		deck[sj] = tmp
	lines.append("Shuffled deck: %s" % str(deck))

	# --- The reusable pattern: a loot roll drawn from a passed-in
	# stream. Whoever owns the stream owns the reproducibility. ---
	var loot_stream := SeedBank.stream_for(20261119, SeedBank.STREAM_DUNGEON)
	lines.append("Loot rolls: %s" % str(loot_roll(loot_stream, 20)))

	output.text = "\n".join(lines)


## Returns `count` loot-tier rolls (0 = junk … 3 = epic) from the
## given stream. Deterministic for a fresh stream, every time.
func loot_roll(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var result: Array[int] = []
	for i in count:
		var roll: int = rng.randi_range(0, 99)
		if roll < 60:
			result.append(0)
		elif roll < 85:
			result.append(1)
		elif roll < 97:
			result.append(2)
		else:
			result.append(3)
	return result
