"""Renders the user marker as an RGBA PNG with genuinely transparent corners.

qlmanage was the wrong tool: it produces Quick Look *thumbnails*, which are
composited onto an opaque white card. The file carries an alpha channel, so
`sips -g hasAlpha` says yes, but every pixel outside the disc is opaque white —
which is the white square showing up behind the marker on the map.

The artwork is only concentric circles, so it is drawn analytically here and
encoded with the stdlib (zlib + struct). No rasteriser, no image library, and
the area outside the outer circle is left at alpha 0.
"""
import struct
import sys
import zlib

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 256
OUT = sys.argv[2] if len(sys.argv) > 2 else "marker.png"
BLUE = (0x21, 0x96, 0xF3)
WHITE = (0xFF, 0xFF, 0xFF)
HAIRLINE = (0xE3, 0xE6, 0xEA)

# Radii in pixels. Proportions follow source.png: a white disc with a faint grey
# edge and a solid centre at ~81% of the outer radius.
r_outer = SIZE / 2.0 - 1.0
r_white = r_outer - max(1.0, SIZE * 0.008)
r_inner = r_outer * (9.7 / 12.0)

cx = cy = (SIZE - 1) / 2.0
SS = 4                      # 4x4 supersampling for anti-aliased edges
inv = 1.0 / (SS * SS)

rows = []
for y in range(SIZE):
    # filter byte 0 (None) per scanline
    row = bytearray([0])
    for x in range(SIZE):
        # Accumulate premultiplied colour so the transparent edge does not
        # fringe toward black when averaged.
        pr = pg = pb = pa = 0.0
        for sy in range(SS):
            fy = y + (sy + 0.5) / SS - 0.5
            dy = fy - cy
            for sx in range(SS):
                fx = x + (sx + 0.5) / SS - 0.5
                dx = fx - cx
                d = (dx * dx + dy * dy) ** 0.5
                if d <= r_inner:
                    c = BLUE
                elif d <= r_white:
                    c = WHITE
                elif d <= r_outer:
                    c = HAIRLINE
                else:
                    continue        # outside the marker: contributes alpha 0
                pr += c[0]
                pg += c[1]
                pb += c[2]
                pa += 255.0
        a = pa * inv
        if a <= 0.0:
            row += b"\x00\x00\x00\x00"
        else:
            # un-premultiply back to straight alpha
            k = 1.0 / pa
            row += bytes((
                int(round(pr * k * 255.0)),
                int(round(pg * k * 255.0)),
                int(round(pb * k * 255.0)),
                int(round(a)),
            ))
    rows.append(bytes(row))

raw = b"".join(rows)


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))

with open(OUT, "wb") as f:
    f.write(png)
print(f"wrote {OUT} {SIZE}x{SIZE} RGBA")
