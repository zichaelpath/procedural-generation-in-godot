class_name BiomeClassifier
extends RefCounted

## Whittaker-style classification: temperature x moisture -> a biome ID,
## with height vetoes (ocean / beach / rock / snow) checked first.
## Thresholds are named constants — edit the DATA to change the climate.
## (Chapter 5, Listing 5.3; rule-table alternative added in Chapter 6,
## Listing 6.1.)

const OCEAN := 0
const BEACH := 1
const DESERT := 2
const GRASSLAND := 3
const FOREST := 4
const RAINFOREST := 5
const TAIGA := 6
const TUNDRA := 7
const ROCK := 8
const SNOW := 9

# Temperature bands (0..1): below COLD is polar, above HOT is tropical.
const TEMP_COLD := 0.30
const TEMP_HOT := 0.68
# Moisture bands (0..1): below DRY is arid, above WET is lush.
const MOIST_DRY := 0.35
const MOIST_WET := 0.68

static func classify(height: float, moisture: float, temperature: float,
		sea_level: float, height_scale: float) -> int:
	# Vetoes first — altitude and water outrank the climate table.
	if height < sea_level:
		return OCEAN
	if height < sea_level + 1.2:
		return BEACH
	var rel: float = height / height_scale
	if rel > 0.86:
		return SNOW
	if rel > 0.68:
		return ROCK
	# The Whittaker table proper: temperature rows, moisture columns.
	if temperature < TEMP_COLD:
		return TAIGA if moisture > MOIST_DRY else TUNDRA
	if temperature > TEMP_HOT:
		if moisture < MOIST_DRY:
			return DESERT
		return RAINFOREST if moisture > MOIST_WET else GRASSLAND
	# Temperate middle.
	if moisture < MOIST_DRY:
		return GRASSLAND
	return FOREST if moisture > MOIST_WET else GRASSLAND

# --- The alternative shape: a rule table, not a two-axis table. ---
# ONE driver (temperature) selects a branch; the branch jitters the
# moisture by a rolled amount; the label is DERIVED from branch +
# jittered moisture. `roll` is supplied by the caller (0..1) so this
# function stays pure and testable.
static func classify_rule_table(height: float, moisture: float,
		temperature: float, sea_level: float, height_scale: float,
		roll: float) -> String:
	# The same vetoes as Whittaker — altitude and water outrank climate.
	if height < sea_level:
		return "Ocean"
	if height < sea_level + 1.2:
		return "Beach"
	var rel: float = height / height_scale
	if rel > 0.86:
		return "Snow"
	if rel > 0.68:
		return "Rock"
	# Step 1: the driver selects the branch.
	var branch: String = "temperate"
	if temperature < 0.25:
		branch = "frozen"
	elif temperature < TEMP_COLD:
		branch = "cold"
	elif temperature > 0.85:
		branch = "very_hot"
	elif temperature > TEMP_HOT:
		branch = "hot"
	# Step 2: roll inside the branch — moisture jittered by +/-0.08.
	var m: float = clampf(moisture + (roll - 0.5) * 0.16, 0.0, 1.0)
	# Step 3: derive the label from branch + rolled moisture.
	match branch:
		"frozen":
			return "Taiga" if m > MOIST_DRY else "Tundra"
		"cold":
			return "Taiga" if m > 0.50 else "Tundra"
		"very_hot":
			if m < 0.45:
				return "Desert"
			return "Rainforest" if m > MOIST_WET else "Grassland"
		"hot":
			if m < MOIST_DRY:
				return "Desert"
			return "Rainforest" if m > MOIST_WET else "Grassland"
		_:  # temperate
			if m < MOIST_DRY:
				return "Grassland"
			return "Forest" if m > MOIST_WET else "Grassland"
