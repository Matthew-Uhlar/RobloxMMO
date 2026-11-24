"""Headless preview of the §48 creature rigs (Pillow + numpy, no Studio).

Assembles each rig exactly as creatures.client.lua poses it at rest: the core
mesh, every limb segment (T(at) * R(rot) * mirror * scale(k)), the tier
overlays (crown, pauldrons, horns, rune ring) and the Neon glow accents (drawn
unlit), then renders a contact sheet with the icon renderer's camera and
crease-angle smoothing. Flat Lambert only: no materials, bloom or shadows.

    python3 tools/render-creatures.py OUT.png boar:A0683D:critter golem:D4A84B:boss ...

Each KIND[:HEX[:TIER]] renders one cell (HEX defaults to the core's own tint,
TIER to the rig's natural tier: critter). Tiers: critter brute elite boss world.
Options: --cell N, --columns N, --angle front|side|three (default three).
"""
import importlib.util
import sys as _sys
_sys.dont_write_bytecode = True  # keep art/__pycache__ untouched
import json
import math
import os
import subprocess
import sys

import numpy
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
spec = importlib.util.spec_from_file_location("icons", os.path.join(ART, "render-icons.py"))
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)

RIG_DUMP = r"""
const C = new Proxy({TINT:11,TINT_DARK:15,TINT_LIGHT:16}, {get:(t,k)=>t[k]??1});
const kit = require(process.argv[1])({creature:()=>{}, C, PI:Math.PI, hash:()=>.5, jitterOf:()=>()=>1});
process.stdout.write(JSON.stringify(kit.rigs));
"""
TIER_OVERLAYS = {
    "critter": [], "brute": ["pauldron"], "elite": ["pauldron", "horns"],
    "boss": ["pauldron", "crown", "ring"], "world": ["pauldron", "worldcrown", "ring"],
}


def rigs():
    out = subprocess.check_output(["node", "-e", RIG_DUMP, os.path.join(ART, "creature-shapes.cjs")])
    return json.loads(out)


def euler_yxz(rx, ry, rz):
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    rxm = numpy.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rym = numpy.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rzm = numpy.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rym @ rxm @ rzm


MIRROR = {None: numpy.eye(3), "roll": numpy.diag([-1, -1, 1]), "yaw": numpy.diag([-1, 1, -1])}


def part(name, at=(0, 0, 0), rot=(0, 0, 0), mirror=None, k=1.0, tint=None):
    vertices, faces, meta = icons.read_obj(name)
    kv = numpy.array(k if isinstance(k, list) else [k, k, k], dtype=float)
    m = euler_yxz(*rot) @ MIRROR[mirror]
    pts = (numpy.array(vertices) * kv) @ m.T + numpy.array(at)
    if tint is None and meta["tint"]:
        tint = tuple(int(meta["tint"][i:i + 2], 16) / 255 for i in (0, 2, 4))
    return {"vertices": [tuple(p) for p in pts], "faces": faces, "smooth": meta["smooth"], "tint": tint}


def sphere(centre, radius, colour):
    t = (1 + 5 ** 0.5) / 2
    base = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    tris = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    verts = [tuple(centre[i] + c / math.sqrt(1 + t * t) * radius for i, c in enumerate(v)) for v in base]
    return {"vertices": verts, "faces": [(list(f), "Glow") for f in tris], "smooth": 0, "tint": None, "glow": colour}


def assemble(kind, rig, tint, tier):
    parts = [part(rig["core"], tint=tint)]
    tint = parts[0]["tint"]  # limbs take the creature's colour, as in the game
    for seg in rig["segs"]:
        parts.append(part(seg["shape"], seg["at"], seg.get("rot", (0, 0, 0)), seg.get("mirror"), seg.get("k", 1), tint))
    anchors = rig.get("anchors", {})
    size = max(rig["hitbox"])
    for overlay in TIER_OVERLAYS[tier]:
        if overlay == "pauldron" and "shoulder" in anchors:
            sx, sy, sz = anchors["shoulder"]
            s = 0.5 + size * 0.12
            parts.append(part("OverlayPauldron", (sx, sy, sz), (0, 0, 0), None, s, (0.69, 0.72, 0.77)))
            parts.append(part("OverlayPauldron", (-sx, sy, sz), (0, 0, 0), "yaw", s, (0.69, 0.72, 0.77)))
        elif overlay in ("crown", "worldcrown") and "crown" in anchors:
            parts.append(part("OverlayCrown" if overlay == "crown" else "OverlayWorldCrown", anchors["crown"], (0, 0, 0), None, 0.5 + size * 0.1))
        elif overlay == "horns" and "crown" in anchors:
            parts.append(part("OverlayHorns", anchors["crown"], (0, 0, 0), None, 0.6 + size * 0.1))
        elif overlay == "ring":
            r = anchors.get("ring", size / 2)
            parts.append(part("OverlayRuneRing", (0, -rig["hip"] + 0.02, 0), (0, 0, 0), None, [r, 1, r]))
    for g in rig.get("glow", []):
        c = g["color"]
        parts.append(sphere(g["at"], g["r"], tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))))
    return parts


def render(parts, size, angle):
    palette = icons.read_palette()
    allv = [v for p in parts for v in p["vertices"]]
    low = [min(v[i] for v in allv) for i in range(3)]
    high = [max(v[i] for v in allv) for i in range(3)]
    centre = tuple((low[i] + high[i]) / 2 for i in range(3))
    radius = max(high[i] - low[i] for i in range(3))
    direction = {"three": (0.75, 0.42, -1), "front": (0.05, 0.2, -1), "side": (1, 0.25, -0.05)}[angle]
    forward_dir = icons.unit(direction)
    eye = tuple(centre[i] + forward_dir[i] * radius * 2.05 for i in range(3))
    forward = icons.unit(icons.sub(centre, eye))
    right = icons.unit(icons.cross(forward, (0, 1, 0)))
    up = icons.cross(right, forward)
    focal = 1 / math.tan(math.radians(34) / 2)
    light = icons.unit((1, 1.4, -1.2))
    scale = size * icons.SUPER
    pixels = numpy.empty((scale, scale, 3), dtype=numpy.uint8)
    pixels[:] = icons.PANEL
    zbuffer = numpy.full((scale, scale), numpy.inf)
    for p in parts:
        shades = icons.tint_shades(p["tint"]) if p["tint"] else {}
        normals = icons.corner_normals(p["vertices"], p["faces"], p["smooth"])
        for (ids, material), corners in zip(p["faces"], normals):
            points = [p["vertices"][i] for i in ids]
            normal = icons.unit(icons.cross(icons.sub(points[1], points[0]), icons.sub(points[2], points[0])))
            middle = tuple(sum(q[i] for q in points) / 3 for i in range(3))
            flip = icons.dot(normal, icons.sub(eye, middle)) < 0
            colour = []
            for corner in corners:
                if p.get("glow"):
                    colour.append(tuple(min(255.0, ch * 255 * 1.15 + 30) for ch in p["glow"]))
                    continue
                base = shades.get(material) or palette[material]
                if flip:
                    corner = (-corner[0], -corner[1], -corner[2])
                shade = 0.5 + 0.6 * max(0.0, icons.dot(corner, light))
                colour.append(tuple(min(255.0, ch * 255 * shade) for ch in base))
            projected = []
            for point in points:
                relative = icons.sub(point, eye)
                depth = icons.dot(relative, forward)
                projected.append((scale / 2 + icons.dot(relative, right) / depth * focal * scale / 2,
                                  scale / 2 - icons.dot(relative, up) / depth * focal * scale / 2, depth))
            icons.rasterise(pixels, zbuffer, projected, colour)
    return Image.fromarray(pixels).resize((size, size), Image.LANCZOS)


def main():
    args = sys.argv[1:]
    cell, columns, angle = 220, 5, "three"
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--cell":
            cell = int(args.pop(0))
        elif flag == "--columns":
            columns = int(args.pop(0))
        elif flag == "--angle":
            angle = args.pop(0)
    output, specs = args[0], args[1:]
    table = rigs()
    columns = min(columns, len(specs))
    rows = math.ceil(len(specs) / columns)
    sheet = Image.new("RGB", (columns * (cell + 8) + 8, rows * (cell + 26) + 8), icons.BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, item in enumerate(specs):
        kind, _, rest = item.partition(":")
        hex_colour, _, tier = rest.partition(":")
        tint = tuple(int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)) if hex_colour else None
        tier = tier or "critter"
        x, y = 8 + index % columns * (cell + 8), 8 + index // columns * (cell + 26)
        sheet.paste(render(assemble(kind, table[kind], tint, tier), cell, angle), (x, y))
        draw.text((x + 4, y + cell + 6), kind + " (" + tier + ")", fill=(220, 230, 235), font=font)
    sheet.save(output)
    print("Rendered", len(specs), "creatures to", output)


if __name__ == "__main__":
    main()
