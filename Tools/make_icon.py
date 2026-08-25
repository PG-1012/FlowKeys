#!/usr/bin/env python3
"""Generate FlowKeys.icns.

The mark is three stacked cards fanning back, with the front one highlighted:
the clipboard history, and the one you are about to paste.
"""
import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/FlowKeys.icns"
S = 1024
SS = 4  # supersample factor for clean edges

BG_TOP = (88, 101, 242)
BG_BOTTOM = (58, 66, 190)
CARD_BACK = (255, 255, 255, 70)
CARD_MID = (255, 255, 255, 130)
CARD_FRONT = (255, 255, 255, 255)
ACCENT = (88, 101, 242, 255)


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def render(size):
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))

    # macOS-style squircle background with a vertical gradient.
    grad = Image.new("RGBA", (n, n))
    gd = ImageDraw.Draw(grad)
    for y in range(n):
        t = y / max(1, n - 1)
        gd.line(
            [(0, y), (n, y)],
            fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,),
        )
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, n - 1, n - 1], radius=int(n * 0.2237), fill=255
    )
    img.paste(grad, (0, 0), mask)

    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Three cards, each offset up-and-right, front one solid.
    cw, ch = int(n * 0.46), int(n * 0.30)
    radius = int(n * 0.045)
    step = int(n * 0.075)
    # Centre the whole fan, not just the front card: the stack extends
    # 2*step up and right, so bias the origin down and left by half that.
    cx = int((n - cw - 2 * step) / 2)
    cy = int((n - ch + 2 * step) / 2)

    for i, fill in enumerate((CARD_BACK, CARD_MID)):
        off = (2 - i) * step
        rounded(d, [cx + off, cy - off, cx + off + cw, cy - off + ch], radius, fill)

    rounded(d, [cx, cy, cx + cw, cy + ch], radius, CARD_FRONT)

    # Three text lines on the front card, the middle one accented and short —
    # the selected entry.
    lw = int(cw * 0.62)
    lh = max(2, int(n * 0.022))
    lx = cx + int(cw * 0.14)
    for i in range(3):
        ly = cy + int(ch * 0.28) + i * int(ch * 0.21)
        width = int(lw * (0.55 if i == 1 else 1.0))
        colour = ACCENT if i == 1 else (60, 66, 110, 190)
        rounded(d, [lx, ly, lx + width, ly + lh], lh // 2, colour)

    img = Image.alpha_composite(img, layer)
    return img.resize((size, size), Image.LANCZOS)


def main():
    iconset = "FlowKeys.iconset"
    os.makedirs(iconset, exist_ok=True)
    specs = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in specs:
        px = base * scale
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        render(px).save(os.path.join(iconset, name))

    os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
    subprocess.run(["rm", "-rf", iconset], check=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
