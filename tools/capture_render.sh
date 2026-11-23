#!/bin/bash
# RENDER capture — one stage, one step, one PNG. Real GPU render under
# Xvfb (DISPLAY=:99), NOT --headless. See tools/README.md.
#
# Usage: tools/capture_render.sh <stage-res-path> <step> <out.png> [seed]
# Example:
#   tools/capture_render.sh res://stages/stage_terrain_heightfield.tscn 2 \
#     ~/procgen-book-project/captures/ch09-heightfield-render.png
set -euo pipefail
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PROJECT="${PROJECT:-$HOME/procgen-book-project}"
STAGE="${1:?stage res:// path required}"
STEP="${2:?step required}"
OUT="${3:?output png path required}"
SEED="${4:-}"
ARGS=(--stage="$STAGE" --step="$STEP" --out="$OUT")
if [ -n "$SEED" ]; then ARGS+=(--seed="$SEED"); fi
mkdir -p "$(dirname "$OUT")"
DISPLAY=:99 "$GODOT" --path "$PROJECT" res://tools/book_capture.tscn -- "${ARGS[@]}"
ls -l "$OUT"
