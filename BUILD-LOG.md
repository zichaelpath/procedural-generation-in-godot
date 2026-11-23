# BUILD-LOG — Part IX capstone measurements

World: `res://stages/stage_9_world.tscn`, step 6, master seed **20261119**.
Capture machine: the AI PC (i3-10100, 2× RTX 3080 10 GB), Godot 4.7.2,
Xvfb display :99. Measured 2026-11-20. Every number below was read from
the Profiler's / stage's own Output on this machine — none typed from
memory (Ch 44's measurement rule).

## The three measured numbers (Ch 44's blanks)

| Quantity | Measured |
|---|---|
| Total generation, step 6 (WorldProfiler, Listing 44.1) | **163,481 ms** (budget printed by the chapter: 8,000 ms) |
| Draw calls in frame, tier HIGH, at the TierCamera | **22,151** |
| Draw calls in frame, tier LOW, same TierCamera | **21,975** |

Tier draw calls are the stage's `[frame]` sampler (40 frames after a
full generate, harness camera = the stage's TierCamera), from the
tier render runs that produced `ch44-world-tier-high-render.png` /
`ch44-world-tier-low-render.png`. The chapter's printed budget lines
(frame draw calls ≤ 2,500 high / ≤ 900 low) are **not** met by this
build: at street level the count is dominated by the 67 placed
buildings' unmerged interior geometry, which neither tier negotiates —
the tiers move scatter, ring and memory (below), not building nodes.

## World budget table (WorldProfiler, verbatim, editor run)

```
=== World budget — seed 20261119 ===
  stage buildings: 2489 ms
  stage chunks_plants: 2637 ms
  stage entrances: 12 ms
  stage parcels_zoning: 86536 ms
  stage roads: 71807 ms
  stage terrain_water: 0 ms
  TOTAL generation: 163481 ms (budget: 8000 ms)
  terrain edits: 303
  parcels: 148 · entrances: 3 · proofs: ["dungeon/entrance_0: COMPLETABLE", "dungeon/entrance_1: COMPLETABLE", "dungeon/entrance_2: COMPLETABLE"]
  chunks live: 225 · by LOD stride: { 1: 225 } · terrain vertices (computed): 245025
  live nodes (Performance): 67103
  draw calls in frame (Performance): 595
  video memory (Performance, MB): 319.7
```

Notes on the table:
- `terrain_water: 0 ms` is the profiler's own print (the stage's
  terrain+water step rounds to 0 ms in the editor run; game runs of
  the same step print 13–15 ms).
- The "draw calls in frame (Performance)" line is sampled inside the
  editor, whose frame is the editor UI itself — it is not the game
  camera's count. The game-camera counts are the tier numbers above.
- Run-to-run variance: three profiler runs read TOTAL 163,691 /
  165,210 / 163,481 ms (roads 71.8–71.9 s and parcels+zoning ~86.5 s
  dominate and are stable; the delivered `ch44-profiler-engine.png`
  frame is from the 165,210 ms run — its visible tail reads
  "stage roads: 71875 ms · TOTAL generation: 165210 ms").
- LOD census: all 225 chunks at stride 1 — `build_fixed_grid()`
  builds the fixed ring at full detail, so the stride spread the
  census can report is uniform until the streaming path (Ch 14/44.2)
  drives it.

## Tier comparison (same TierCamera, game runs)

| | ring (chunks) | scatter | draw calls | live nodes | video memory |
|---|---|---|---|---|---|
| HIGH | 7 (225) | ×1.0 | 22,151 | 44,514 | 218.6 MB |
| LOW | 4 (81) | ×0.35 | 21,975 | 43,920 | 178.1 MB |

## Return Test (Listing 43.6, editor run)

```
RETURN TEST: PASS (fingerprint identical, 234 lines)
```

Verified in three independent editor runs. Fingerprint contents:
225 `terrain/x,z` chunk hashes, `parcels:148`, ledger lines
(apartment 23/7, house 44/7, office 0/1 placed/surrendered),
3 entrance dungeon hashes, `edits:303`.
