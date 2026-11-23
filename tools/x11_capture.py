#!/usr/bin/env python3
"""X11 full-screen capture for ENGINE shots.

No import/scrot/xwd exists on the AI PC and nothing may be installed
system-wide, so this uses Pillow's ImageGrab, which talks X11 directly
(it needs DISPLAY set, e.g. DISPLAY=:99). Verified on the AI PC
2026-11-19: grabs the full 1920x1080 Xvfb root window.

Usage: DISPLAY=:99 python3 tools/x11_capture.py /absolute/path/out.png
"""
import sys

from PIL import ImageGrab


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: x11_capture.py <out.png>", file=sys.stderr)
        return 2
    img = ImageGrab.grab()
    img.save(sys.argv[1])
    print(f"X11_CAPTURED {sys.argv[1]} size={img.size} mode={img.mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
