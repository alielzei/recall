#!/usr/bin/env python3
"""Generate the Recall extension icon (extension/icon.png).

Renders at 4x then downscales for crisp anti-aliased edges. No external assets.
Concept: rounded-square indigo->violet tile, white terminal prompt ">_",
amber notification dot (terminal + notification = Recall).
"""
import os
from PIL import Image, ImageDraw

S = 1024                      # working resolution
OUT = 256                     # final icon size
R = 220                       # corner radius
TL = (0x33, 0x41, 0x55)       # slate-700
BR = (0x0F, 0x17, 0x2A)       # slate-900
WHITE = (0xFF, 0xFF, 0xFF)
AMBER = (0xF5, 0x9E, 0x0B)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


# --- diagonal gradient ------------------------------------------------------
grad = Image.new("RGB", (S, S))
px = grad.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * (S - 1))
        px[x, y] = lerp(TL, BR, t)

# --- rounded-square mask ----------------------------------------------------
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=R, fill=255)

icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(icon)


def stroke(pts, width, fill):
    """Polyline with round caps + joins."""
    d.line(pts, fill=fill, width=width, joint="curve")
    r = width // 2
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


# --- terminal prompt ">_" ---------------------------------------------------
W = 76
# chevron ">"
stroke([(300, 352), (548, 512), (300, 672)], W, WHITE)
# underscore "_"
stroke([(596, 648), (792, 648)], W, WHITE)

# --- notification dot -------------------------------------------------------
cx, cy, rad = 748, 300, 96
d.ellipse([cx - rad - 20, cy - rad - 20, cx + rad + 20, cy + rad + 20], fill=WHITE)
d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=AMBER)

# --- downscale & save -------------------------------------------------------
out = icon.resize((OUT, OUT), Image.LANCZOS)
dest = os.path.join(os.path.dirname(__file__), "..", "extension", "icon.png")
out.save(os.path.abspath(dest))
print("wrote", os.path.abspath(dest))
