#!/usr/bin/env python3
"""Where is the mouse pointer, in screen pixels?

  python3 probe_cursor.py <background.png> <withcursor.png>
  -> "CURSOR x=246 y=142"   or   "NOCURSOR"

mrext only sends RELATIVE motion and Mac OS accelerates it, so there is no
absolute position to read back and the event-to-pixel scale is not stable
(scripts/mac_shutdown.sh has the war story). The way to get an absolute
position is to look at the screen.

Finding a black arrow by shape is fragile on a screen full of black text, so
this does it by DIFFERENCE instead: park the pointer somewhere harmless, grab
a background frame, move it, grab again. On a static screen the only thing
that changed is the pointer. The tip is the topmost pixel of the changed
region, and the leftmost pixel of that top row -- which is exactly the arrow's
hotspot.

Robustness: ignores single stray pixels (the guest's clock ticks, and the
menu-bar seconds change under us), by requiring the changed region to have at
least MIN_PIXELS members and by taking the largest connected-ish cluster via a
coarse row/column histogram rather than true connected components.
"""
import sys

import numpy as np
from PIL import Image

MIN_PIXELS = 12
TOL = 40           # per-channel difference that counts as "changed"


def main():
    if len(sys.argv) < 3:
        print("usage: probe_cursor.py bg.png cur.png", file=sys.stderr)
        return 2
    bg = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int16)
    cur = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.int16)
    if bg.shape != cur.shape:
        print("NOCURSOR")
        return 0

    diff = np.abs(cur - bg).max(axis=2) > TOL

    # Two regions change for reasons that are not the pointer, and blanking the
    # whole menu bar to dodge them would blind this to any menu-bar target:
    #   * the guest's clock, top right, ticks on its own
    #   * the top-left corner, where the pointer was PARKED for the background
    #     frame -- its disappearance is a change too, and it is the same size
    #     as the pointer we are hunting, so the cluster pick would coin-flip
    use = diff.copy()
    use[:20, 540:] = False
    use[:20, :20] = False

    if use.sum() < MIN_PIXELS:
        print("NOCURSOR")
        return 0

    ys, xs = np.nonzero(use)
    # Cluster: keep only pixels within 24 px of the densest 16x16 cell, which
    # throws away unrelated repaints elsewhere on screen.
    h, w = use.shape
    cell = 16
    hist = {}
    for y, x in zip(ys, xs):
        k = (y // cell, x // cell)
        hist[k] = hist.get(k, 0) + 1
    (cy, cx), _ = max(hist.items(), key=lambda kv: kv[1])
    cy = cy * cell + cell // 2
    cx = cx * cell + cell // 2
    keep = (np.abs(ys - cy) <= 24) & (np.abs(xs - cx) <= 24)
    ys, xs = ys[keep], xs[keep]
    if len(ys) < MIN_PIXELS:
        print("NOCURSOR")
        return 0

    top = ys.min()
    left = xs[ys == top].min()
    print(f"CURSOR x={left} y={top}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
