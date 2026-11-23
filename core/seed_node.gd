class_name SeedNode
extends RefCounted
## A miniature of the seed-tree pattern (an idea from Frank Gennari's
## 3DWorld, reimplemented here from its description): every generated
## object STORES its own two seed integers, rolled from its parent.
## With those two integers it can regenerate itself — and everything
## under it — identically, in any order, at any time. Unloading is
## free: drop the node; the seeds are the save file.
##
## Two-phase generation: create() rolls the cheap parameters and
## stops; process() does the expensive expansion, later, on demand.

var address: String = ""
var seed_a: int = 0
var seed_b: int = 0
var children: Array[SeedNode] = []
var processed: bool = false


## create(): the CHEAP half. Roll this node's seed pair from the
## parent stream, derive child addresses, and stop. No children are
## expanded; a created-but-unprocessed node costs a few bytes.
static func create(parent_rng: RandomNumberGenerator, node_address: String) -> SeedNode:
	var node := SeedNode.new()
	node.address = node_address
	node.seed_a = parent_rng.randi()
	node.seed_b = parent_rng.randi()
	return node


## This node's OWN stream, rebuilt from its stored seeds alone.
## The parent does not need to exist for this to work — that is the
## whole point of storing the pair.
func own_stream() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_a) + ":" + str(seed_b))
	return rng


## process(): the EXPENSIVE half. Expand this node's children,
## giving each child its stored seed pair from THIS node's stream.
## child_count stands in for real expansion work (grids, rooms,
## floorplans) that later parts attach here.
func process(child_count: int) -> void:
	if processed:
		return
	var rng := own_stream()
	children.clear()
	for i in child_count:
		children.append(SeedNode.create(rng, address + "/" + str(i)))
	processed = true


## Drop the expansion, keep the seeds. After unload(), this node is
## back to its created state — and process() will rebuild the SAME
## children, because they are rolled from the stored pair.
func unload() -> void:
	children.clear()
	processed = false
