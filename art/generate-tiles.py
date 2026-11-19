"""Generate seamless RGB color maps from periodic patterns. No dependencies."""
import math
from pathlib import Path
import struct
import zlib

SIZE = 128
ROOT = Path(__file__).parent / "textures"
ROOT.mkdir(exist_ok=True)
TAU = math.tau


def intensity(kind, x, y):
    u, v = x / SIZE, y / SIZE
    warp = math.sin(TAU * v) + 0.31 * math.cos(TAU * (u + v))
    grain = ((x * 193 ^ y * 97 ^ x * y * 17) % 19 - 9) / 3
    if kind == "loom":
        over = ((x // 4 + y // 4) % 2) == 0
        weave = math.cos(TAU * (x if over else y) / 4)
        border = (x + y) % 64 in (0, 1) or (x - y) % 64 in (0, 1)
        return 199 + 11 * weave + 16 * border + grain
    if kind == "timber":
        growth = math.sin(TAU * (12*u + .32*warp))
        board = min(x % 32, 32 - x % 32)
        return 211 + 9*growth - 30*(board < 1) + grain
    if kind == "meadow":
        return 209 + 8*math.cos(TAU*(2*u-v)) + 7*math.sin(TAU*(7*u+3*v)) + grain*2
    if kind == "brass":
        return 221 + 3*math.sin(TAU*32*v) + 9*((x+y) % 64 < 2) + grain
    # Interlocking strata with thin, irregular mineral veins.
    strata = math.sin(TAU * (4*v + .38*math.sin(TAU*u)))
    return 207 + 8*strata + 15*(abs(strata) < .09) + grain


def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name+data))


for material in ("loom", "timber", "meadow", "brass", "shale"):
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            gray = round(intensity(material, x, y))
            rows.extend((gray, gray, gray))
    hdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    (ROOT / (material + ".png")).write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    )
