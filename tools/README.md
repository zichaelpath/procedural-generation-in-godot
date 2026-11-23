# Capture harness — exact commands (PLAN.md §5, §7)

Two kinds of book screenshots. Both run on the AI PC under Xvfb
`DISPLAY=:99` with real GPU rendering — **never `--headless`**.

Prerequisite check before any capture session (frozen-frame rule):
Xvfb must be alive on :99 — `pgrep -x Xvfb`. If captures ever return
identical bytes for different content, Xvfb died; restart it detached:

```
(setsid nohup ~/xvfb-pkg/usr/bin/Xvfb :99 -screen 0 1920x1080x24 > /tmp/xvfb.log 2>&1 < /dev/null &)
```

## RENDER — the running stage's camera view

Harness: `res://tools/book_capture.tscn` + `tools/book_capture.gd`
(loads the stage, sets step/seed, waits 45 frames, saves the viewport).

```
DISPLAY=:99 ~/.local/bin/godot --path ~/procgen-book-project \
  res://tools/book_capture.tscn -- \
  --stage=res://stages/stage_terrain_heightfield.tscn \
  --step=2 --out=$HOME/procgen-book-project/captures/ch09-heightfield-render.png
```

Wrapper (same thing): `tools/capture_render.sh <stage> <step> <out.png> [seed]`

## ENGINE — the full editor window (Scene dock + Inspector visible)

The `addons/book_stage/` EditorPlugin opens/arranges the stage in the
editor (step = 2, stage root selected so the Inspector shows the stage
script's exports) and writes `/tmp/book_editor_ready.txt`. The wrapper
polls for that file, waits 6 s for the UI to settle, grabs the whole
1920×1080 X11 root window, then kills only the editor it started.

There is **no** `import`/`scrot`/`xwd` on this box and nothing may be
installed system-wide, so the grab uses Pillow's `ImageGrab`
(`tools/x11_capture.py`), which talks X11 directly — verified working
on :99 on 2026-11-19.

```
tools/capture_engine.sh res://stages/stage_terrain_heightfield.tscn \
  ~/procgen-book-project/captures/ch09-heightfield-engine.png
```

Manual equivalent:

```
rm -f /tmp/book_editor_ready.txt
rm -f ~/procgen-book-project/.godot/editor/editor_layout.cfg
DISPLAY=:99 ~/.local/bin/godot --editor --resolution 1920x1080 --position 0,0 \
  --path ~/procgen-book-project res://stages/stage_terrain_heightfield.tscn &
# wait until /tmp/book_editor_ready.txt exists, then sleep 6
DISPLAY=:99 python3 ~/procgen-book-project/tools/x11_capture.py /path/to/out.png
# kill the editor PID you started
```

Two Xvfb gotchas baked into the wrapper (learned 2026-11-19):
- `--maximized` is IGNORED (no window manager on :99); without
  `--resolution 1920x1080 --position 0,0` the editor opens at 1152×648,
  and at that width Godot hides the Inspector dock — the shot looks
  fine at a glance and is useless. Always force the geometry.
- Generated children deliberately have NO `owner` in the editor, so
  they do not appear as sub-nodes of `Generated` in the Scene dock
  (they are visible in the 3D viewport). This is intentional: owned
  generated nodes would be baked into the .tscn if anyone saved the
  scene from the editor. The ENGINE shot's subject is the stage root,
  its authored tree, and its Inspector exports.

## Verification (standing rule, no exceptions)

Open every PNG and look at it before it is used. A render must show the
actual generated subject (not black/blank); an engine shot must show the
editor UI with the stage scene open. Also diff two different steps'
renders — identical bytes means a frozen frame, not a success.
