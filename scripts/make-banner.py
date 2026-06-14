#!/usr/bin/env python3
"""Generate the README banner (docs/banner.png): graphite background, the Recall
tile, wordmark, and tagline."""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 360
BG = (0x0B, 0x11, 0x20)            # near-black slate
TL = (0x33, 0x41, 0x55)           # tile gradient (slate-700 -> slate-900)
BR = (0x0F, 0x17, 0x2A)
WHITE = (0xFF, 0xFF, 0xFF)
AMBER = (0xF5, 0x9E, 0x0B)
SUB = (0x94, 0xA3, 0xB8)          # slate-400

BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG = "/System/Library/Fonts/Supplemental/Arial.ttf"


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_tile(size):
    s = size * 2
    grad = Image.new("RGB", (s, s)); px = grad.load()
    for y in range(s):
        for x in range(s):
            px[x, y] = lerp(TL, BR, (x + y) / (2 * (s - 1)))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255)
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0)); tile.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(tile)
    w = int(s * 0.075)

    def stroke(pts):
        d.line(pts, fill=WHITE, width=w, joint="curve"); r = w // 2
        for x, y in pts:
            d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)
    u = s / 1024.0
    stroke([(300 * u, 352 * u), (548 * u, 512 * u), (300 * u, 672 * u)])
    stroke([(596 * u, 648 * u), (792 * u, 648 * u)])
    cx, cy, rad = 748 * u, 300 * u, 96 * u
    d.ellipse([cx - rad - 20 * u, cy - rad - 20 * u, cx + rad + 20 * u, cy + rad + 20 * u], fill=WHITE)
    d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=AMBER)
    return tile.resize((size, size), Image.LANCZOS)


img = Image.new("RGBA", (W, H), BG + (255,))
d = ImageDraw.Draw(img)

TS = 232
img.paste(make_tile(TS), (72, (H - TS) // 2), make_tile(TS))

word = ImageFont.truetype(BOLD, 120)
sub = ImageFont.truetype(REG, 38)
tx = 350
d.text((tx, 120), "Recall", font=word, fill=WHITE)
d.text((tx + 4, 250), "Jump back to the terminal that pinged you.", font=sub, fill=SUB)

dest = os.path.join(os.path.dirname(__file__), "..", "docs", "banner.png")
img.convert("RGB").save(os.path.abspath(dest))
print("wrote", os.path.abspath(dest))
