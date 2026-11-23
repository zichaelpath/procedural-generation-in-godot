class_name OfficeRules
extends RefCounted
## The tower judge. Its minimums are its OWN (Ch 34: HouseRules'
## table has no office types, and unlisted types are skipped
## silently — an ungraded plan is worse than a failing one). Its
## proportion cap is 3.5, not Ch 29's 1.8: a wide, shallow meeting
## room against glass is correct, not skinny. The one family reused
## whole is Ch 30's window-split clearance — pure geometry, true
## in any building. Violations carry their numbers, always.

const MINIMUMS: Dictionary = {
	"open_plan": {"min_area": 20.0}, "breakout": {"min_area": 20.0},
	"lobby": {"min_area": 20.0}, "meeting": {"min_area": 8.0},
	"focus": {"min_area": 6.0}, "office": {"min_area": 9.0},
	"kitchenette": {"min_area": 6.0}, "server": {"min_area": 6.0},
	"storage": {"min_area": 3.0}, "wc": {"min_area": 3.5},
	"hall": {"min_area": 3.0},
}
const ASPECT_OFFICE_MAX: float = 3.5
const SERVICE_TYPES: Array = ["wc", "server", "storage"]

static func validate_tower(tower: Dictionary) -> Dictionary:
	var violations: Array = []
	var warnings: Array = []
	for plan in tower["floors"]:
		violations.append_array(check_office_minimums(plan))
		violations.append_array(check_office_proportions(plan))
		violations.append_array(HouseRules.check_window_split_clearance(plan))
		violations.append_array(_check_facade(plan))
		violations.append_array(_check_headcount(plan))
	violations.append_array(_check_service_stack(tower))
	return {"violations": violations, "warnings": warnings}

static func check_office_minimums(plan: Dictionary) -> Array:
	var violations: Array = []
	for room in plan["rooms"]:
		var rule: Dictionary = MINIMUMS.get(room["type"], {})
		if rule.is_empty():
			continue
		var area: float = (room["rect"] as Rect2).get_area()
		if area < float(rule["min_area"]) - 0.001:
			violations.append("MINIMUM %s area %.1f m² < minimum %.1f m²" % [room["name"], area, float(rule["min_area"])])
	return violations

static func check_office_proportions(plan: Dictionary) -> Array:
	var violations: Array = []
	for room in plan["rooms"]:
		var aspect: float = HouseRules.aspect_of(room["rect"])
		if aspect > ASPECT_OFFICE_MAX + 0.001:
			violations.append("PROPORTION %s aspect %.2f exceeds office cap %.2f" % [room["name"], aspect, ASPECT_OFFICE_MAX])
	return violations

static func _check_facade(plan: Dictionary) -> Array:
	var violations: Array = []
	var footprint: Rect2 = plan["footprint"]
	for room in plan["rooms"]:
		if room["type"] != "meeting" and room["type"] != "focus" and room["type"] != "office":
			continue
		var rect: Rect2 = room["rect"]
		var on_exterior: bool = absf(rect.position.y - footprint.position.y) < 0.02 or absf(rect.end.y - footprint.end.y) < 0.02 \
			or absf(rect.position.x - footprint.position.x) < 0.02 or absf(rect.end.x - footprint.end.x) < 0.02
		if not on_exterior:
			violations.append("FACADE %s (%s) touches no exterior wall — enclosed rooms live on the glass" % [room["name"], room["type"]])
	return violations

static func _check_headcount(plan: Dictionary) -> Array:
	var violations: Array = []
	var assigned: int = int(plan["meta"].get("headcount", 0))
	if assigned <= 0:
		return violations
	var desks: int = DeskField.count_for_floor(plan)
	var owed: int = int(ceil(float(assigned) * OfficeProgram.DESK_RATIO))
	if desks < owed:
		violations.append("HEADCOUNT floor %d seats %d but the field holds %d desks (%d owed at ratio %.2f)" % [
			int(plan["meta"]["floor_index"]) + 1, assigned, desks, owed, OfficeProgram.DESK_RATIO])
	return violations

static func _check_service_stack(tower: Dictionary) -> Array:
	var violations: Array = []
	var floors: Array = tower["floors"]
	if floors.size() < 2:
		return violations
	var reference: Dictionary = {}
	for room in floors[0]["rooms"]:
		if SERVICE_TYPES.has(room["type"]):
			reference[room["name"]] = room["rect"]
	for f in range(1, floors.size()):
		# Ch 36 §36.1, in the open: the setback floor is a separate
		# roll with its own core, so the stack assertion covers the
		# main stack (floors 0..top-1) against floor 0; the setback
		# floor's single-floor stack is vacuous. (Listing 35.6 as
		# printed compares every floor, which would convict every
		# setback tower by construction; §36.1's prose governs.)
		if bool(floors[f]["meta"].get("setback", false)):
			continue
		for room in floors[f]["rooms"]:
			if SERVICE_TYPES.has(room["type"]) and reference.has(room["name"]):
				if not (reference[room["name"]] as Rect2).is_equal_approx(room["rect"]):
					violations.append("SERVICE_STACK %s moved on floor %d — services stack on the core, exactly" % [room["name"], f + 1])
	return violations
