class_name PlantGallery
extends RefCounted

## A library of classic rule sets, stored as DATA. Each entry =
## genome (axiom + rules) + the physics it expects (angle, segment
## length, iterations). A rule set is not just its strings: the same
## strings at a different angle are a different species.

const SPECIES: Array[Dictionary] = [
	{
		"name": "Bush",
		"axiom": "F",
		"rules": {"F": "FF+[-F+F]-[+F-F]"},
		"angle": 25.0, "length": 3.5, "iterations": 5,
	},
	{
		"name": "Weed",
		"axiom": "F",
		"rules": {"F": "F[+F]F[-F]F"},
		"angle": 20.0, "length": 7.0, "iterations": 4,
	},
	{
		"name": "Fern",
		"axiom": "X",
		"rules": {"X": "F+[[X]-X]-F[-FX]+X", "F": "FF"},
		"angle": 22.0, "length": 4.0, "iterations": 5,
	},
	{
		"name": "Algae (Lindenmayer's original)",
		"axiom": "A",
		"rules": {"A": "AB", "B": "A"},
		"angle": 0.0, "length": 3.0, "iterations": 10,
	},
	{
		"name": "Tree silhouette",
		"axiom": "F",
		"rules": {"F": "FF[-F+F+F][+F-F-F]"},
		"angle": 22.0, "length": 5.0, "iterations": 4,
	},
]
