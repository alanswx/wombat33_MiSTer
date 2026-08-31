#!/usr/bin/env python3
"""Where is the highlighted row in an open Mac OS pull-down menu?

  python3 scripts/menuitem_probe.py <shot.png> <title_left_x>
  -> "ITEM band=[98,111] panel_bottom=113 gap=2"  (gap 0-4 means the LAST item)
  -> "NOITEM panel_bottom=113"                    (menu open, nothing under the pointer)
  -> "NOPANEL"

`title_left_x` is the second field from scripts/menubar_probe.py: a Mac OS menu
panel is left-aligned with its title.

Detection is by colour, not brightness. The panel is neutral grey (R=G=B, light),
the highlighted row is the appearance blue (measured: rgb ~ (84,84,179), so
B - R is large), and the desktop below the panel is teal (G,B > R). Brightness
alone cannot separate a blue highlight from the dark desktop, which is what an
earlier greyscale version of this got wrong.

Used by scripts/mac_shutdown.sh to confirm that Shut Down -- the LAST item of
the Special menu -- is the highlighted row before the button is released,
because Restart is the row directly above it.
"""
import sys

import numpy as np
from PIL import Image

rgb = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(int)
x0 = int(sys.argv[2])
# start a little left of the title: the panel is left-aligned with it, but the
# title's detected left edge can be a few px off when its glyphs are wide.
win = rgb[20:220, max(0, x0 - 2):x0 + 70]
r, g, b = win[:, :, 0], win[:, :, 1], win[:, :, 2]

grey = ((abs(r - g) < 10) & (abs(g - b) < 10) & (r > 120)).mean(axis=1)
blue = ((b - r > 50) & (b > 120)).mean(axis=1)

# Separator rules and item underlines are neither, so allow a few such rows
# inside the panel before calling it the bottom edge.
bottom, miss = None, 0
for y in range(win.shape[0]):
    if grey[y] > 0.5 or blue[y] > 0.5:
        bottom, miss = y, 0
    else:
        miss += 1
        if miss > 4:
            break

if bottom is None:
    print("NOPANEL")
    sys.exit(0)

band = [y for y in range(bottom + 1) if blue[y] > 0.5]
if band:
    print("ITEM band=[%d,%d] panel_bottom=%d gap=%d"
          % (band[0] + 20, band[-1] + 20, bottom + 20, bottom - band[-1]))
else:
    print("NOITEM panel_bottom=%d" % (bottom + 20))
