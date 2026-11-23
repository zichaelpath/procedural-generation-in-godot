class_name LSystem
extends RefCounted

## The book's string rewriter. Pure data: no nodes, no drawing.
## Rules map a single-character String to its replacement String.
## Symbols with no rule copy themselves into the next generation.

static func expand(axiom: String, rules: Dictionary, iterations: int) -> String:
	var current: String = axiom
	for gen in iterations:
		var next: String = ""
		# Parallel rewriting: we READ only from `current` (last
		# generation) and BUILD `next`. Never read from the string
		# being built — that one discipline is the whole algorithm.
		for i in current.length():
			var symbol: String = current.substr(i, 1)
			if rules.has(symbol):
				next += str(rules[symbol])
			else:
				next += symbol
		current = next
	return current

## Stochastic expansion: rules map a symbol to an Array of
## [weight, replacement] pairs. The RNG is PASSED IN (the "plants"
## stream) so results replay exactly from the master seed.
static func expand_stochastic(axiom: String, weighted_rules: Dictionary, iterations: int, rng: RandomNumberGenerator) -> String:
	var current: String = axiom
	for gen in iterations:
		var next: String = ""
		for i in current.length():
			var symbol: String = current.substr(i, 1)
			if weighted_rules.has(symbol):
				next += _weighted_pick(weighted_rules[symbol], rng)
			else:
				next += symbol
		current = next
	return current

static func _weighted_pick(options: Array, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for opt in options:
		total += float(opt[0])
	var roll: float = rng.randf_range(0.0, total)
	for opt in options:
		roll -= float(opt[0])
		if roll <= 0.0:
			return str(opt[1])
	return str(options[options.size() - 1][1])

## Context-sensitivity demo: a signal "S" climbs a stem of dormant
## "a" segments, flipping each one it passes to activated "A".
## One step = the signal swaps one place toward the tip, and the
## cell it leaves behind stays activated — a growing trail.
static func step_signal(state: String) -> String:
	var s_idx: int = state.find("S")
	if s_idx == -1 or s_idx >= state.length() - 1:
		return state  # no signal, or signal already at the tip
	var rebuilt: String = ""
	for i in state.length():
		if i == s_idx:
			rebuilt += "A"  # the cell the signal leaves behind wakes
		elif i == s_idx + 1:
			rebuilt += "S"
		else:
			rebuilt += state.substr(i, 1)
	return rebuilt
