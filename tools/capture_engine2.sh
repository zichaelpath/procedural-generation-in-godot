#!/bin/bash
# ENGINE capture with stage arrangement — companion to capture_engine.sh.
#
# The shared addons/book_stage plugin always arranges step=2 + root
# selection. Part II shots need other steps / selections / the Ch14
# benchmark, so terrain_stage.gd reads a directive file (written here
# before launch) and, once the plugin has finished, applies the shot's
# step/selection itself and writes /tmp/book_stage_arranged.txt. This
# script polls for THAT file, settles, grabs the X11 root window, and
# kills only the editor it started.
#
# Usage: tools/capture_engine2.sh <stage-res-path> <out.png> <step> <select> [benchmark]
#   select: root | TerrainMesh | ChunkManager
set -uo pipefail
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PROJECT="${PROJECT:-$HOME/procgen-book-project}"
STAGE="${1:?stage res:// path required}"
OUT="${2:?output png path required}"
STEP="${3:?step required}"
SELECT="${4:-root}"
BENCH="${5:-0}"
mkdir -p "$(dirname "$OUT")"
rm -f /tmp/book_editor_ready.txt /tmp/book_stage_arranged.txt
rm -f "$PROJECT/.godot/editor/editor_layout.cfg"
printf "step=%s\nselect=%s\nbenchmark=%s\n" "$STEP" "$SELECT" "$BENCH" > /tmp/book_stage_directive.txt
DISPLAY=:99 "$GODOT" --editor --resolution 1920x1080 --position 0,0 --path "$PROJECT" "$STAGE" >/tmp/book_editor2.log 2>&1 &
EDITOR_PID=$!
echo "editor pid=$EDITOR_PID — waiting for BOOK_STAGE_ARRANGED (step=$STEP select=$SELECT bench=$BENCH)…"
for i in $(seq 1 150); do
  if [ -f /tmp/book_stage_arranged.txt ]; then break; fi
  if ! kill -0 "$EDITOR_PID" 2>/dev/null; then echo "editor died early"; cat /tmp/book_editor2.log; rm -f /tmp/book_stage_directive.txt; exit 1; fi
  sleep 1
done
cat /tmp/book_stage_arranged.txt 2>/dev/null || echo "(no arranged file after 150s — capturing anyway)"
sleep 4
DISPLAY=:99 python3 "$PROJECT/tools/x11_capture.py" "$OUT"
kill "$EDITOR_PID" 2>/dev/null
wait "$EDITOR_PID" 2>/dev/null
rm -f /tmp/book_stage_directive.txt
ls -l "$OUT"
