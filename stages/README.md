# The stage pattern — follow this exactly for every new stage

Every chapter subject gets ONE stage scene. A stage builds its subject in
numbered steps so the book can screenshot the build-up, not just the result.

## Files for a new stage

| Piece | Where | Notes |
|---|---|---|
| Scene | `res://stages/stage_<part>_<slug>.tscn` | e.g. `stage_terrain_heightfield.tscn` |
| Stage script | `res://<domain>/<slug>_stage.gd` | In the DOMAIN folder, not in `stages/`. Extends `StageBase`. `@tool` if the chapter teaches editor-time generation, otherwise runtime-only. |
| Framework | `res://stages/stage_base.gd` | `class_name StageBase`. Never fork it per stage. |

## Fixed scene layout (copy the terrain heightfield stage as the template)

```
<StageRoot>            Node3D, stage script attached, exports set in Inspector
├── DirectionalLight3D rotation_degrees = (-50, -30, 0), shadow_enabled = true
├── WorldEnvironment   Environment: Background Sky (ProceduralSkyMaterial),
│                      Ambient Light Source = Sky, Tonemap Mode = ACES
├── CameraRig          Node3D
│   └── PresetCamera   Camera3D, current = true — position/rotation come from
│                      StageBase.CAMERA_PRESET_*; do not hand-frame per shot
├── Generated          Node3D — build_step() puts ALL generated nodes here,
│                      and only here, so rebuild() can clear safely
└── DebugUI            CanvasLayer
    └── PanelContainer (offset 12,12) → VBoxContainer:
        SeedLabel ("Master seed"), SeedField (LineEdit),
        StepLabel ("Step"), StepSpin (SpinBox, min 0, max = last step),
        RegenButton ("Regenerate"), InfoLabel
```

## Rules

1. **Exports are the interface.** `step: int` and `master_seed: int` come from
   `StageBase`. Set their starting values in the Inspector (they are what an
   ENGINE screenshot must show). Changing either in the Inspector rebuilds
   live in the editor because stages are `@tool`.
2. **Override only `build_step(p_step)`.** Read the seed from `config`
   (a `WorldConfig` synced from the `master_seed` export). Get ALL randomness
   via `config.stream(name)` / `config.noise(name, freq, octaves)` — i.e.
   SeedBank named streams. Never global `randf()`/`randi()`.
3. **Data first.** Compute the data (heights, grid, graph…), then turn data
   into nodes/meshes under `Generated`. Generators return data; builders
   make nodes — say which is which in the script's header comment.
4. **Steps are cumulative and honest.** Step N shows everything step N−1
   showed plus the new idea of step N (raw → falloff → water, etc.). A step
   must be screenshot-worthy on its own: the book captures every step.
5. **One camera.** All renders use `PresetCamera`. If a subject truly needs
   a second framing, add a named preset constant beside the first in the
   stage script and document it here — never drag the camera per capture.
6. **Deterministic.** Same seed + same step ⇒ identical scene, in editor
   and at runtime. If it isn't, that's a bug in the stage, not a quirk.
7. **Generated nodes get no `owner`.** In the editor they therefore show
   in the viewport but not as sub-nodes of `Generated` in the Scene dock.
   Deliberate: owned generated nodes would be baked into the .tscn on
   save. Never set `owner` on generated content.

## Capturing a stage (see tools/README.md for the full commands)

- RENDER: `tools/book_capture.tscn` runs the stage offscreen-of-the-editor
  (real GPU render under Xvfb) and saves the viewport PNG.
- ENGINE: open the stage in the editor (the `addons/book_stage/` plugin
  selects the root so the Inspector shows the exports), then grab the full
  editor window with `tools/x11_capture.py`.
