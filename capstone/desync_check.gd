class_name DesyncCheck
extends RefCounted

## Multiplayer determinism, reduced to the book's own machinery:
## two peers generate from the same seed + manifest, exchange
## FINGERPRINTS (a few hundred bytes of text), and compare. Equal
## fingerprints: the worlds are the same world, and only inputs
## need to travel. First differing line: the address of the desync
## — the same forensic handle as the Return Test (Ch 43), because
## it is the same test, run across a network instead of an unload.

func local_fingerprint(builder: WorldBuilder) -> String:
	var test := ReturnTest.new()
	var lines: Array[String] = test.fingerprint(builder)
	return "\n".join(lines)


func compare(builder: WorldBuilder, remote_fingerprint: String) -> String:
	var mine: String = local_fingerprint(builder)
	if mine == remote_fingerprint:
		return "IN SYNC (" + str(mine.count("\n") + 1) + " fingerprint lines)"
	var my_lines: PackedStringArray = mine.split("\n")
	var their_lines: PackedStringArray = remote_fingerprint.split("\n")
	var n: int = mini(my_lines.size(), their_lines.size())
	for i: int in range(n):
		if my_lines[i] != their_lines[i]:
			return "DESYNC at line %d — mine: '%s' · theirs: '%s'. Regenerate that address standalone (Ch 43, Exercise 2) on both peers and diff its inputs." % [i, my_lines[i], their_lines[i]]
	return "DESYNC — fingerprint length differs (" + str(my_lines.size()) + " vs " + str(their_lines.size()) + " lines): a system registered on one peer only."
