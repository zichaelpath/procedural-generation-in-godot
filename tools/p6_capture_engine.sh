#!/usr/bin/env bash
# Part VI private ENGINE capture wrapper (mirrors tools/capture_engine2.sh
# but with private handshake files + a no-other-editor gate, so parallel
# capture workers cannot clobber this part's arrange).
set -u
DISPLAY_ID=":99"
PROJ="$HOME/procgen-book-project"
GODOT="$HOME/.local/bin/godot"
SCENE_RES="${1:?scene res path}"
OUT="${2:?output png}"
STEP="${3:?step}"
SELECT="${4:-root}"
CLICKS="${5:-1}"
DIRECTIVE="/tmp/p6_stage_directive.txt"
ARRANGED="/tmp/p6_stage_arranged.txt"
READY="/tmp/book_editor_ready.txt"
LOG="/tmp/p6_editor.log"

# Gate: never launch while another worker's editor is up.
for i in $(seq 1 40); do
  if ! pgrep -f 'godot.*--editor' >/dev/null 2>&1; then break; fi
  echo "waiting for a free display (other editor running) $i"
  sleep 15
done
if pgrep -f 'godot.*--editor' >/dev/null 2>&1; then
  echo "DISPLAY_BUSY: another editor still running; aborting" >&2
  exit 3
fi

# Reset this scene's saved tree-folding state: accumulated folding
# (an expanded Floor_0 flooding the dock with mesh rows) otherwise
# decides what the Scene dock shows, not the arrange.
rm -f "$PROJ"/.godot/editor/stage_6_apartments.tscn-folding-*.cfg
printf 'step=%s\nselect=%s\nclicks=%s\n' "$STEP" "$SELECT" "$CLICKS" > "$DIRECTIVE"
printf 'step=%s\nselect=%s\nclicks=%s\n' "$STEP" "$SELECT" "$CLICKS" > /tmp/book_stage_directive.txt
rm -f "$READY" "$ARRANGED" /tmp/book_stage_arranged.txt
export DISPLAY="$DISPLAY_ID"
"$GODOT" --editor --resolution 1920x1080 --position 0,0 --path "$PROJ" "$SCENE_RES" > "$LOG" 2>&1 &
EPID=$!
echo "editor pid=$EPID scene=$SCENE_RES step=$STEP select=$SELECT"

ok=0
for i in $(seq 1 120); do
  if [ -f "$READY" ] && grep -q "$SCENE_RES" "$READY"; then ok=1; break; fi
  if ! kill -0 "$EPID" 2>/dev/null; then echo "editor exited early" >&2; break; fi
  sleep 1
done
echo "plugin ready=$ok"
ok=0
for i in $(seq 1 60); do
  if [ -f "$ARRANGED" ] && grep -q "apartments arranged" "$ARRANGED"; then ok=1; break; fi
  if ! kill -0 "$EPID" 2>/dev/null; then break; fi
  sleep 1
done
echo "arranged=$ok"
sleep 4
DISPLAY=:99 python3 "$PROJ/tools/x11_capture.py" "$OUT" || { kill "$EPID" 2>/dev/null; exit 4; }
kill "$EPID" 2>/dev/null
sleep 1
kill -9 "$EPID" 2>/dev/null
ls -la "$OUT"
