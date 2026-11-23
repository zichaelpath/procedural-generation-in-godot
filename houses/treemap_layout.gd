class_name TreemapLayout
extends RefCounted
## Squarified treemap layout (Bruls et al. via Marson & Musse 2010,
## flat version). Data in, data out: specs are Dictionaries
## (name/type/zone/target/min); layout() returns them with "rect"
## filled, sorted largest-first. Shared edges are exact by
## construction: each recursion's leftover rectangle starts at the
## same float the frozen strip ended at.

static func layout(rooms: Array, rect: Rect2) -> Array:
	var total_weight: float = 0.0
	for r in rooms:
		total_weight += float(r["target"])
	var scale: float = rect.get_area() / total_weight
	var items: Array = []
	for r in rooms:
		items.append({"room": r, "area": float(r["target"]) * scale})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) > float(b["area"]))
	_place(items, rect)
	var out: Array = []
	for it in items:
		out.append(it["room"])
	return out

static func _place(items: Array, rect: Rect2) -> void:
	if items.is_empty():
		return
	if items.size() == 1:
		items[0]["room"]["rect"] = rect
		return
	var side: float = minf(rect.size.x, rect.size.y)
	var row: Array = [items[0]]
	var i: int = 1
	while i < items.size():
		var candidate: Array = row.duplicate()
		candidate.append(items[i])
		if _worst(candidate, side) <= _worst(row, side):
			row = candidate
			i += 1
		else:
			break
	var row_area: float = 0.0
	for it in row:
		row_area += float(it["area"])
	var rest: Array = items.slice(row.size())
	if rect.size.x >= rect.size.y:
		# Row becomes a vertical strip on the left; rooms stack inside it.
		var strip_w: float = row_area / rect.size.y
		var y: float = rect.position.y
		for it in row:
			var h: float = float(it["area"]) / strip_w
			it["room"]["rect"] = Rect2(rect.position.x, y, strip_w, h)
			y += h
		_place(rest, Rect2(rect.position.x + strip_w, rect.position.y, rect.size.x - strip_w, rect.size.y))
	else:
		# Row becomes a horizontal strip on top; rooms sit side by side.
		var strip_h: float = row_area / rect.size.x
		var x: float = rect.position.x
		for it in row:
			var w: float = float(it["area"]) / strip_h
			it["room"]["rect"] = Rect2(x, rect.position.y, w, strip_h)
			x += w
		_place(rest, Rect2(rect.position.x, rect.position.y + strip_h, rect.size.x, rect.size.y - strip_h))

static func _worst(row: Array, side: float) -> float:
	# Worst aspect ratio among the row's rectangles, if the row were
	# laid along an edge of length `side`. Lower is squarer. This is
	# THE objective function — §27.2 computes it by hand, repeatedly.
	var s: float = 0.0
	var r_max: float = 0.0
	var r_min: float = INF
	for it in row:
		var a: float = float(it["area"])
		s += a
		r_max = maxf(r_max, a)
		r_min = minf(r_min, a)
	if s <= 0.0 or r_min <= 0.0:
		return INF
	return maxf((side * side * r_max) / (s * s), (s * s) / (side * side * r_min))

# Two-level split (Marson & Musse 2010): zone groups get their own
# super-rectangles, each treemapped independently. Grouping is the
# only new geometry — layout() does all the packing.

static func group_of(room: Dictionary) -> String:
	# Service rooms have awkward citizenship: kitchen is social-adjacent,
	# bathroom and WC are private-adjacent, the hall rides with the
	# social band (it serves the entrance). One function, one place
	# to disagree.
	if String(room["zone"]) == "private" or String(room["type"]) == "bathroom" or String(room["type"]) == "wc":
		return "private"
	return "social"

static func layout_two_level(rooms: Array, rect: Rect2) -> Array:
	var social_rooms: Array = []
	var private_rooms: Array = []
	var w_social: float = 0.0
	var w_private: float = 0.0
	for r in rooms:
		if group_of(r) == "private":
			private_rooms.append(r)
			w_private += float(r["target"])
		else:
			social_rooms.append(r)
			w_social += float(r["target"])
	var total: float = w_social + w_private
	var frac: float = w_private / total if total > 0.0 else 0.5
	var out: Array = []
	if rect.size.x >= rect.size.y:
		# Private band across the top (north), social below, entrance at south.
		var ph: float = rect.size.y * frac
		out.append_array(layout(private_rooms, Rect2(rect.position, Vector2(rect.size.x, ph))))
		out.append_array(layout(social_rooms, Rect2(rect.position + Vector2(0, ph), Vector2(rect.size.x, rect.size.y - ph))))
	else:
		var pw: float = rect.size.x * frac
		out.append_array(layout(private_rooms, Rect2(rect.position, Vector2(pw, rect.size.y))))
		out.append_array(layout(social_rooms, Rect2(rect.position + Vector2(pw, 0), Vector2(rect.size.x - pw, rect.size.y))))
	return out
