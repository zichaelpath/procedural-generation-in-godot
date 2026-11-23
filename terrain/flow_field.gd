class_name FlowField
extends RefCounted

## Flow analysis over a height grid: D8 downstream directions and
## flow accumulation. Pure data in, pure data out — the mesh, the
## biomes and the waterline never appear in here.

var width: int = 0                       # points per row (cells + 1)
var downstream: PackedInt32Array = PackedInt32Array()   # index, or -1
var accumulation: PackedFloat32Array = PackedFloat32Array()
var labels: PackedInt32Array = PackedInt32Array()
var _outlet_total: int = 0

func cell_index(ix: int, iz: int) -> int:
	return iz * width + ix

# The D8 step: the lowest of the 8 neighbours, or -1 when no neighbour
# is lower (sea cell, map edge draining outward, or a pit).
func lowest_neighbour(source: PackedFloat32Array, ix: int, iz: int) -> int:
	var best: int = -1
	var best_h: float = source[cell_index(ix, iz)]
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var nx: int = ix + dx
			var nz: int = iz + dz
			if nx < 0 or nz < 0 or nx >= width or nz >= width:
				continue
			var j: int = cell_index(nx, nz)
			if source[j] < best_h:
				best_h = source[j]
				best = j
	return best

func compute(source: PackedFloat32Array, grid_width: int, sea_level: float) -> void:
	width = grid_width
	var count: int = width * width
	downstream.resize(count)
	accumulation.resize(count)
	for i in range(count):
		accumulation[i] = 1.0  # every cell starts with its own rain
	for iz in range(width):
		for ix in range(width):
			var i: int = cell_index(ix, iz)
			if source[i] < sea_level:
				downstream[i] = -1  # already in the sea: journey over
			else:
				downstream[i] = lowest_neighbour(source, ix, iz)
	# Highest first, so a cell is always processed BEFORE the neighbour
	# it pours into. Sorting indices by height is the whole trick.
	var order: Array[int] = []
	order.resize(count)
	for i in range(count):
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool: return source[a] > source[b])
	for i in order:
		var d: int = downstream[i]
		if d >= 0:
			accumulation[d] += accumulation[i]

# A river is a threshold, not a discovery process.
func is_river(i: int, threshold: float) -> bool:
	return accumulation[i] >= threshold

# Priority-flood depression filling. Returns a NEW array: the source
# with every pit raised to its spill height. Route flow on the filled
# surface; render and build on the true one.
func filled_heights(source: PackedFloat32Array) -> PackedFloat32Array:
	var count: int = width * width
	var filled: PackedFloat32Array = source.duplicate()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(count)
	var heap: Array[int] = []
	# Seed the queue with every edge cell at its true height.
	for ix in range(width):
		_push(heap, filled, cell_index(ix, 0))
		_push(heap, filled, cell_index(ix, width - 1))
		visited[cell_index(ix, 0)] = 1
		visited[cell_index(ix, width - 1)] = 1
	for iz in range(width):
		_push(heap, filled, cell_index(0, iz))
		_push(heap, filled, cell_index(width - 1, iz))
		visited[cell_index(0, iz)] = 1
		visited[cell_index(width - 1, iz)] = 1
	while not heap.is_empty():
		var c: int = _pop(heap, filled)
		var cx: int = c % width
		var cz: int = c / width
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nx: int = cx + dx
				var nz: int = cz + dz
				if nx < 0 or nz < 0 or nx >= width or nz >= width:
					continue
				var j: int = cell_index(nx, nz)
				if visited[j] == 1:
					continue
				visited[j] = 1
				# Never lower than the water level that reached it.
				filled[j] = maxf(source[j], filled[c])
				_push(heap, filled, j)
	return filled

# --- Binary heap over cell indices, ordered by filled height. ---
func _push(heap: Array[int], keys: PackedFloat32Array, value: int) -> void:
	heap.append(value)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if keys[heap[i]] >= keys[heap[parent]]:
			break
		var tmp: int = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent

func _pop(heap: Array[int], keys: PackedFloat32Array) -> int:
	var top: int = heap[0]
	var last: int = heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		while true:
			var left: int = i * 2 + 1
			var right: int = left + 1
			var smallest: int = i
			if left < heap.size() and keys[heap[left]] < keys[heap[smallest]]:
				smallest = left
			if right < heap.size() and keys[heap[right]] < keys[heap[smallest]]:
				smallest = right
			if smallest == i:
				break
			var tmp: int = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top

# Labels every cell with the id of the outlet its water reaches.
# Ocean cells are -1. Call AFTER compute().
func watershed_labels() -> PackedInt32Array:
	var count: int = width * width
	labels.resize(count)
	labels.fill(-2)  # -2 = unlabelled; -1 = ocean / no outlet land cell
	var next_label: int = 0
	for i in range(count):
		if labels[i] != -2:
			continue
		# Walk downstream from i, remembering the path.
		var path: Array[int] = []
		var c: int = i
		while c >= 0 and labels[c] == -2:
			path.append(c)
			c = downstream[c]
		var label: int
		if c >= 0:
			label = labels[c]  # ran into an already-labelled cell
		else:
			label = next_label  # reached a terminal cell: new outlet
			next_label += 1
		for p in path:
			labels[p] = label
	_outlet_total = next_label
	return labels

func outlet_count() -> int:
	return _outlet_total
