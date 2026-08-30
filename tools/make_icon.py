#!/usr/bin/env python3
"""Draw the Timberline launcher icon - a pine over a saw blade - at any size.

The Venu 2 family wants two sizes (70px for the 416x416 watches, 61px for the
360x360 Venu 2S), so the artwork is described once in a 60x60 design space and
rasterised with 4x supersampling at whatever size is asked for. Pure stdlib, so
it runs anywhere the build runs.

    python3 tools/make_icon.py resources-round-416x416/drawables/launcher_icon.png 70
"""
import math
import os
import struct
import sys
import zlib

DESIGN = 60.0   # the coordinate space the shapes below are drawn in
SS = 4          # supersampling factor

BG = (0x0C, 0x12, 0x0C, 255)
LEAF = (0x2E, 0xD5, 0x73, 255)
LEAF_DARK = (0x1B, 0x8F, 0x4B, 255)
TRUNK = (0x8C, 0x5A, 0x3C, 255)
CLEAR = (0, 0, 0, 0)


def in_disc(px, py, cx, cy, r):
    return (px - cx) ** 2 + (py - cy) ** 2 <= r * r


def in_rect(px, py, x, y, w, h):
    return x <= px <= x + w and y <= py <= y + h


def in_triangle(px, py, ax, ay, bx, by, cx, cy):
    def side(x1, y1, x2, y2):
        return (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1)

    d1, d2, d3 = side(ax, ay, bx, by), side(bx, by, cx, cy), side(cx, cy, ax, ay)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def shade(px, py):
    """Colour of the design-space point (px, py), or CLEAR outside the icon."""
    if not in_disc(px, py, 30, 30, 29.5):
        return CLEAR
    # Trunk, then three stacked canopies from the bottom up.
    if in_rect(px, py, 27, 40, 6, 11):
        return TRUNK
    if in_triangle(px, py, 30, 30, 13, 45, 47, 45):
        return LEAF_DARK
    if in_triangle(px, py, 30, 20, 16, 36, 44, 36):
        return LEAF
    if in_triangle(px, py, 30, 9, 19, 26, 41, 26):
        return LEAF
    return BG


def render(size):
    scale = DESIGN / (size * SS)
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x * SS + sx + 0.5) * scale
                    py = (y * SS + sy + 0.5) * scale
                    c = shade(px, py)
                    r, g, b, a = r + c[0], g + c[1], b + c[2], a + c[3]
            n = SS * SS
            row += bytes((r // n, g // n, b // n, a // n))
        rows.append(row)
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path, size = argv[1], int(argv[2])
    write_png(path, size, render(size))
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
