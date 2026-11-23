#!/bin/bash
# ENGINE capture — full Godot editor window (Scene dock + Inspector
# visible) grabbed from X11 on display :99. The addons/book_stage plugin
# arranges the scene (opens it, step=2, root selected) and writes
# /tmp/book_editor_ready.txt; this script polls for that file, grabs the
# window with tools/x11_capture.py (Pillow ImageGrab — no import/scrot/
# xwd exists on this box), then kills ONLY the editor it started.
#
# Usage: tools/capture_engine.sh <stage-res-path> <out.png>
# Example:
#   tools/capture_engine.sh res://stages/stage_terrain_heightfield.tscn \
#     ~/procgen-book-project/captures/ch09-heightfield-engine.png
set -uo pipefail
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PROJECT="${PROJECT:-$HOME/procgen-book-project}"
STAGE="${1:?stage res:// path required}"
OUT="${2:?output png path required}"
mkdir -p "$(dirname "$OUT")"
rm -f /tmp/book_editor_ready.txt
# Reset the project's stored editor layout so the capture always gets
# the DEFAULT dock layout (Scene left, Inspector right).
rm -f "$PROJECT/.godot/editor/editor_layout.cfg"
# Geometry MUST be forced with --resolution/--position: Xvfb has no
# window manager, so --maximized is ignored and the editor otherwise
# opens at 1152x648 — narrow enough that Godot hides the Inspector dock.
DISPLAY=:99 "$GODOT" --editor --resolution 1920x1080 --position 0,0 --path "$PROJECT" "$STAGE" >/tmp/book_editor.log 2>&1 &
EDITOR_PID=$!
echo "editor pid=$EDITOR_PID — waiting for BOOK_STAGE_READY…"
for i in $(seq 1 90); do
  if [ -f /tmp/book_editor_ready.txt ]; then break; fi
  if ! kill -0 "$EDITOR_PID" 2>/dev/null; then echo "editor died early"; cat /tmp/book_editor.log; exit 1; fi
  sleep 1
done
cat /tmp/book_editor_ready.txt 2>/dev/null || echo "(no ready file after 90s — capturing anyway)"
# Let the @tool preview + editor UI finish drawing after arrangement.
sleep 6
DISPLAY=:99 python3 "$PROJECT/tools/x11_capture.py" "$OUT"
kill "$EDITOR_PID" 2>/dev/null
wait "$EDITOR_PID" 2>/dev/null
ls -l "$OUT"
