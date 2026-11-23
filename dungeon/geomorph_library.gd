class_name GeomorphLibrary
extends RefCounted
## Hand-authored rooms as ASCII (Ch 20's format). A 'D' cell on a
## room's border is a SOCKET: a place this room may connect. The
## library is content — authorship lives here, assembly is plumbing.

static func rooms() -> Array:
	return [
		{
			"name": "crossroads", "weight": 1.0,
			"rows": [
				"#####D#####",
				"#.........#",
				"#..##.##..#",
				"D....#....D",
				"#..##.##..#",
				"#.........#",
				"#####D#####",
			],
		},
		{
			"name": "barracks", "weight": 1.2,
			"rows": [
				"#########",
				"#...#...#",
				"#...D...#",
				"#...#...#",
				"####D####",
			],
		},
		{
			"name": "vault", "weight": 0.7,
			"rows": [
				"#######",
				"#.....#",
				"#.#.#.#",
				"#.....#",
				"###D###",
			],
		},
		{
			"name": "shrine", "weight": 0.9,
			"rows": [
				"#####",
				"#...#",
				"#.D.#",
				"#...#",
				"##D##",
			],
		},
		{
			"name": "store", "weight": 1.0,
			"rows": [
				"########",
				"#......#",
				"#..##..#",
				"#..##..#",
				"####D###",
			],
		},
		{
			"name": "kennel", "weight": 1.0,
			"rows": [
				"######",
				"#....#",
				"D....#",
				"#....#",
				"######",
			],
		},
	]
