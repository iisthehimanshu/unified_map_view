#!/usr/bin/env python3
"""Generate the flat user-puck disc PNG (assets/markers/userDiscBlue.png).

A host uses this puck via UnifiedMapController.setUserMarkerStyle to show a
position that is not a live fix (a simulated or replayed walk), so it has to
read as clearly *not* the default arrow while still looking native to the map.

Regenerate with this script rather than exporting from a rasteriser: macOS
`qlmanage` composites onto an opaque white card, which still reports hasAlpha
but paints a white square behind the marker on the map.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow.

    python3 tool/make_user_disc.py

Geometry mirrors the marker it replaces: a coloured disc inside a white outline
ring, on transparency. Rendered at 4x the logical size so it stays sharp on
3x-density screens.
"""
import zlib, struct, math

SIZE = 96                 # px; ~4x the logical render size
FILL = (0x02, 0x5f, 0x9d)  # app blue, sampled from assets/markers/user.png
RING = (0xff, 0xff, 0xff)
RING_FRACTION = 13.0 / 15.0  # fill radius / outer radius, from the prior marker
SS = 4                    # supersampling factor per axis, for antialiasing
OUT = "assets/markers/userDiscBlue.png"


def coverage(cx, cy, x, y, radius):
    """Fraction of pixel (x, y) inside a circle, by supersampling."""
    hits = 0
    for sy in range(SS):
        for sx in range(SS):
            px = x + (sx + 0.5) / SS
            py = y + (sy + 0.5) / SS
            if math.hypot(px - cx, py - cy) <= radius:
                hits += 1
    return hits / (SS * SS)


def build():
    c = SIZE / 2.0
    r_outer = SIZE / 2.0
    r_fill = r_outer * RING_FRACTION
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            a_outer = coverage(c, c, x, y, r_outer)
            a_fill = coverage(c, c, x, y, r_fill)
            if a_outer <= 0:
                row += bytes((0, 0, 0, 0))
                continue
            # Composite fill over ring, then the whole thing over transparency.
            r = FILL[0] * a_fill + RING[0] * (1 - a_fill)
            g = FILL[1] * a_fill + RING[1] * (1 - a_fill)
            b = FILL[2] * a_fill + RING[2] * (1 - a_fill)
            row += bytes((round(r), round(g), round(b), round(255 * a_outer)))
        rows.append(row)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)  # filter type 0 per row

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"wrote {path}  {SIZE}x{SIZE}  fill=#{FILL[0]:02x}{FILL[1]:02x}{FILL[2]:02x}")


if __name__ == "__main__":
    write_png(OUT, build())
